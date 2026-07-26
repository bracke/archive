with Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Paths;
with Archive.Compression.Zlib;
with Archive.Resource_Limits;
with Archive.Verification.CRC32;

package body Archive.Archives.Readers.Gzip is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Compression.Zlib.Stream_Close_Status;
   use type Archive.Types.CRC32_Value;
   use type Archive.Types.Uncompressed_Size;
   use type Zlib.Byte;

   Max_Header_Probe : constant Natural := 16_384;
   Max_Gzip_Field_Metadata : constant Natural := 4_096;

   package Slice_Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Zlib.Byte);

   type File_Slice_Result is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Bytes  : Slice_Byte_Vectors.Vector;
   end record;

   function Read_File_Slice
     (Path   : String;
      Offset : Natural;
      Count  : Natural)
      return File_Slice_Result
   is
      File : Ada.Streams.Stream_IO.File_Type;
      Last : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Count = 0 then
         return
           (Status => Archive.Archives.Errors.Ok,
            Bytes  => Slice_Byte_Vectors.Empty_Vector);
      end if;

      declare
         Raw  : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Count));
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Set_Index
           (File, Ada.Streams.Stream_IO.Count (Offset + 1));
         Ada.Streams.Stream_IO.Read (File, Raw, Last);
         Ada.Streams.Stream_IO.Close (File);

         if Last < Raw'First or else Natural (Last - Raw'First + 1) /= Count then
            return
              (Status => Archive.Archives.Errors.Read_Failed,
               Bytes  => []);
         end if;

         return Result : File_Slice_Result do
            Result.Status := Archive.Archives.Errors.Ok;
            for Index in 1 .. Count loop
               Result.Bytes.Append
                 (Zlib.Byte
                    (Raw (Raw'First + Ada.Streams.Stream_Element_Offset (Index - 1))));
            end loop;
         end return;
      end;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return
           (Status => Archive.Archives.Errors.Limit_Exceeded,
            Bytes  => Slice_Byte_Vectors.Empty_Vector);
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return
           (Status => Archive.Archives.Errors.Read_Failed,
            Bytes  => Slice_Byte_Vectors.Empty_Vector);
   end Read_File_Slice;

   function Slice_Bytes (Slice : File_Slice_Result) return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. Natural (Slice.Bytes.Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Slice.Bytes.Element (Index);
      end loop;
      return Result;
   end Slice_Bytes;

   function In_Range
     (Bytes  : Zlib.Byte_Array;
      Offset : Natural;
      Count  : Natural)
      return Boolean
   is
   begin
      return Count <= Bytes'Length
        and then Offset <= Bytes'Length - Count;
   end In_Range;

   function Octet (Bytes : Zlib.Byte_Array; Offset : Natural) return Zlib.Byte is
   begin
      return Bytes (Bytes'First + Offset);
   end Octet;

   function U32 (Bytes : Zlib.Byte_Array; Offset : Natural) return Archive.Types.CRC32_Value is
   begin
      return Archive.Types.CRC32_Value (Octet (Bytes, Offset))
        or Archive.Types.CRC32_Value (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Bytes, Offset + 1)), 8))
        or Archive.Types.CRC32_Value (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Bytes, Offset + 2)), 16))
        or Archive.Types.CRC32_Value (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Bytes, Offset + 3)), 24));
   end U32;

   function U16 (Bytes : Zlib.Byte_Array; Offset : Natural) return Natural is
   begin
      return Natural (Octet (Bytes, Offset))
        + Natural (Octet (Bytes, Offset + 1)) * 256;
   end U16;

   function Has_Suffix (Value : String; Suffix : String) return Boolean is
   begin
      return Value'Length >= Suffix'Length
        and then Ada.Characters.Handling.To_Lower
          (Value (Value'Last - Suffix'Length + 1 .. Value'Last)) = Suffix;
   end Has_Suffix;

   function Strip_Gz (Source_Name : String) return String is
   begin
      if Has_Suffix (Source_Name, ".gz") and then Source_Name'Length > 3 then
         return Source_Name (Source_Name'First .. Source_Name'Last - 3);
      end if;
      return "";
   end Strip_Gz;

   function Safe_Name (Candidate : String) return String is
      Norm : constant Archive.Archives.Paths.Normalization_Result :=
        Archive.Archives.Paths.Normalize (Candidate);
   begin
      if Candidate /= ""
        and then Norm.Safety = Archive.Archives.Entries.Safe_Path
        and then Natural (Norm.Components.Length) = 1
      then
         return Candidate;
      end if;
      return "";
   end Safe_Name;

   type Parsed_Header (Name_Length : Natural := 0) is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Info   : Gzip_Header_Info;
      Name   : String (1 .. Name_Length);
   end record;

   function Parse_Header (Bytes : Zlib.Byte_Array) return Parsed_Header is
      FTEXT    : constant Zlib.Byte := 16#01#;
      FHCRC    : constant Zlib.Byte := 16#02#;
      FEXTRA   : constant Zlib.Byte := 16#04#;
      FNAME    : constant Zlib.Byte := 16#08#;
      FCOMMENT : constant Zlib.Byte := 16#10#;
      Reserved : constant Zlib.Byte := 16#E0#;
      Pos      : Natural := 10;
      FLG      : Zlib.Byte;
      Info     : Gzip_Header_Info;
      pragma Unreferenced (FTEXT);
   begin
      if Bytes'Length < 18
        or else Octet (Bytes, 0) /= 16#1F#
        or else Octet (Bytes, 1) /= 16#8B#
        or else Octet (Bytes, 2) /= 16#08#
      then
         return (Name_Length => 0,
                 Status => Archive.Archives.Errors.Invalid_Format,
                 Info => <>,
                 Name => "");
      end if;

      FLG := Octet (Bytes, 3);
      if (FLG and Reserved) /= 0 then
         return (Name_Length => 0,
                 Status => Archive.Archives.Errors.Invalid_Format,
                 Info => <>,
                 Name => "");
      end if;

      if (FLG and FEXTRA) /= 0 then
         if not In_Range (Bytes, Pos, 2) then
            return (Name_Length => 0,
                    Status => Archive.Archives.Errors.Invalid_Format,
                    Info => <>,
                    Name => "");
         end if;

         declare
            Len : constant Natural := U16 (Bytes, Pos);
         begin
            if Len > Max_Gzip_Field_Metadata then
               return (Name_Length => 0,
                       Status => Archive.Archives.Errors.Limit_Exceeded,
                       Info => <>,
                       Name => "");
            elsif not In_Range (Bytes, Pos + 2, Len) then
               return (Name_Length => 0,
                       Status => Archive.Archives.Errors.Invalid_Format,
                       Info => <>,
                       Name => "");
            end if;
            Info.Extra_Length := Len;
            Pos := Pos + 2 + Len;
         end;
      end if;

      declare
         Raw_Name : Unbounded_String;
      begin
         if (FLG and FNAME) /= 0 then
            declare
               Start : constant Natural := Pos;
            begin
               while Pos < Bytes'Length and then Octet (Bytes, Pos) /= 0 loop
                  if Pos - Start >= Max_Gzip_Field_Metadata then
                     return (Name_Length => 0,
                             Status => Archive.Archives.Errors.Limit_Exceeded,
                             Info => <>,
                             Name => "");
                  end if;
                  Append (Raw_Name, Character'Val (Octet (Bytes, Pos)));
                  Pos := Pos + 1;
               end loop;
               if Pos >= Bytes'Length then
                  return (Name_Length => 0,
                          Status => Archive.Archives.Errors.Invalid_Format,
                          Info => <>,
                          Name => "");
               end if;
               Info.Has_Name := True;
               Pos := Pos + 1;
            end;
         end if;

         if (FLG and FCOMMENT) /= 0 then
            declare
               Start : constant Natural := Pos;
            begin
               while Pos < Bytes'Length and then Octet (Bytes, Pos) /= 0 loop
                  if Pos - Start >= Max_Gzip_Field_Metadata then
                     return (Name_Length => 0,
                             Status => Archive.Archives.Errors.Limit_Exceeded,
                             Info => <>,
                             Name => "");
                  end if;
                  Pos := Pos + 1;
               end loop;
               if Pos >= Bytes'Length then
                  return (Name_Length => 0,
                          Status => Archive.Archives.Errors.Invalid_Format,
                          Info => <>,
                          Name => "");
               end if;
               Info.Has_Comment := True;
               Pos := Pos + 1;
            end;
         end if;

         if (FLG and FHCRC) /= 0 then
            if not In_Range (Bytes, Pos, 2) then
               return (Name_Length => 0,
                       Status => Archive.Archives.Errors.Invalid_Format,
                       Info => <>,
                       Name => "");
            end if;

            declare
               Header_Bytes : Zlib.Byte_Array (1 .. Pos);
               Expected     : constant Natural := U16 (Bytes, Pos);
               State        : Archive.Verification.CRC32.CRC32_State :=
                 Archive.Verification.CRC32.Initial;
               Actual       : Archive.Types.CRC32_Value;
            begin
               for Index in Header_Bytes'Range loop
                  Header_Bytes (Index) := Octet (Bytes, Index - 1);
               end loop;
               Archive.Verification.CRC32.Update (State, Header_Bytes);
               Actual := Archive.Verification.CRC32.Final (State);
               if Natural (Actual mod 65_536) /= Expected then
                  return (Name_Length => 0,
                          Status => Archive.Archives.Errors.Invalid_Format,
                          Info => <>,
                          Name => "");
               end if;
            end;
            Info.Has_Header_CRC := True;
            Pos := Pos + 2;
         end if;

         if Pos > Bytes'Length - 8 then
            return (Name_Length => 0,
                    Status => Archive.Archives.Errors.Invalid_Format,
                    Info => <>,
                    Name => "");
         end if;

         Info.Header_Length := Pos;
         declare
            Safe : constant String := Safe_Name (To_String (Raw_Name));
         begin
            return (Name_Length => Safe'Length,
                    Status => Archive.Archives.Errors.Ok,
                    Info => Info,
                    Name => Safe);
         end;
      end;
   end Parse_Header;

   function Logical_Name
     (Header     : Parsed_Header;
      Source_Name : String)
      return String
   is
      From_Source : constant String := Safe_Name (Strip_Gz (Source_Name));
   begin
      if Header.Name /= "" then
         return Header.Name;
      elsif From_Source /= "" then
         return From_Source;
      else
         return "gzip-payload";
      end if;
   end Logical_Name;

   function Index_File
     (Path        : String;
      Source_Name : String := "")
      return Gzip_Index_Result
   is
      Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
      Size_N : Natural;
   begin
      if Size > Ada.Directories.File_Size (Natural'Last) then
         return
           (Status => Archive.Archives.Errors.Limit_Exceeded,
            Item   => <>,
            Header => <>);
      elsif Size < 18 then
         return
           (Status => Archive.Archives.Errors.Invalid_Format,
            Item   => <>,
            Header => <>);
      end if;

      Size_N := Natural (Size);

      declare
         Header_Probe : constant File_Slice_Result :=
           Read_File_Slice (Path, 0, Natural'Min (Size_N, Max_Header_Probe));
         Trailer      : constant File_Slice_Result :=
           Read_File_Slice (Path, Size_N - 8, 8);
         Header_Bytes : constant Zlib.Byte_Array := Slice_Bytes (Header_Probe);
         Trailer_Bytes : constant Zlib.Byte_Array := Slice_Bytes (Trailer);
      begin
         if Header_Probe.Status /= Archive.Archives.Errors.Ok then
            return (Status => Header_Probe.Status, Item => <>, Header => <>);
         elsif Trailer.Status /= Archive.Archives.Errors.Ok then
            return (Status => Trailer.Status, Item => <>, Header => <>);
         end if;

         declare
            Header : constant Parsed_Header := Parse_Header (Header_Bytes);
            Result : Gzip_Index_Result;
            Name   : constant String :=
              Logical_Name
                (Header,
                 (if Source_Name'Length > 0 then Source_Name else Path));
         begin
            if Header.Status /= Archive.Archives.Errors.Ok then
               Result.Status := Header.Status;
               return Result;
            end if;

            Result.Item.Original_Path := To_Unbounded_String (Name);
            Result.Item.Display_Name := To_Unbounded_String (Name);
            Result.Item.Kind := Archive.Archives.Entries.Regular_File;
            Result.Item.Method := Archive.Archives.Entries.GZip_Deflate;
            Result.Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
            Result.Item.Integrity := Archive.Archives.Entries.Not_Checked;
            Result.Item.Safety := Archive.Archives.Paths.Normalize (Name).Safety;
            Result.Item.CRC32 := (Present => True, Value => U32 (Trailer_Bytes, 0));
            Result.Item.Uncompressed :=
              (Present => True,
               Value => Archive.Types.Uncompressed_Size (U32 (Trailer_Bytes, 4)));
            Result.Item.Compressed :=
              (Present => True,
               Value => Archive.Types.Uncompressed_Size (Size_N));
            Result.Header := Header.Info;
            return Result;
         end;
      end;
   exception
      when others =>
         return
           (Status => Archive.Archives.Errors.Read_Failed,
            Item   => <>,
            Header => <>);
   end Index_File;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      File        : Ada.Streams.Stream_IO.File_Type;
      Stream      : Archive.Compression.Zlib.Inflate_Stream;
      Chunk_Size  : constant Positive :=
        Positive
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Zlib_Input_Chunk_Bytes));
      Limit       : constant Archive.Types.Uncompressed_Size :=
        (if Item.Uncompressed.Present
         then Item.Uncompressed.Value
         else Archive.Types.Uncompressed_Size
           (Archive.Resource_Limits.Default_Configured
              (Archive.Resource_Limits.Preview_Output_Bytes)));
      Written     : Archive.Types.Uncompressed_Size := 0;
      CRC         : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
      Closed_File : Boolean := True;

      procedure Close_File_Quietly is
      begin
         if not Closed_File and then Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Closed_File := True;
      exception
         when others =>
            Closed_File := True;
      end Close_File_Quietly;

      function Fail
        (Status    : Archive.Archives.Errors.Error_Code;
         Integrity : Archive.Archives.Entries.Integrity_State)
         return Stream_Result
      is
         Close_Result : Archive.Compression.Zlib.Stream_Close_Result;
         pragma Unreferenced (Close_Result);
      begin
         Close_Result := Archive.Compression.Zlib.Close (Stream);
         Close_File_Quietly;
         return (Status => Status, Integrity => Integrity, Bytes_Written => Written);
      end Fail;

      procedure Forward_Output
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean) is
      begin
         Consumer.all (Bytes, Continue);
         if Continue then
            Archive.Verification.CRC32.Update (CRC, Bytes);
            Written := Written + Archive.Types.Uncompressed_Size (Bytes'Length);
         end if;
      end Forward_Output;
   begin
      Archive.Compression.Zlib.Open
        (Stream,
         Archive.Compression.Zlib.Gzip_Wrapped,
         Limits => (Max_Output_Bytes => Limit, Max_Ratio => 1_000));

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Closed_File := False;

      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         declare
            Raw  : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Chunk_Size));
            Last : Ada.Streams.Stream_Element_Offset;
         begin
            Ada.Streams.Stream_IO.Read (File, Raw, Last);
            exit when Last < Raw'First;

            declare
               Chunk : Zlib.Byte_Array (1 .. Natural (Last - Raw'First + 1));
            begin
               for Offset in Raw'First .. Last loop
                  Chunk (Natural (Offset - Raw'First + 1)) := Zlib.Byte (Raw (Offset));
               end loop;

               declare
                  Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
                    Archive.Compression.Zlib.Append_Chunks
                      (Stream, Chunk, Forward_Output'Access);
               begin
                  if Step.Status = Archive.Archives.Errors.Cancelled then
                     return Fail (Step.Status, Archive.Archives.Entries.Not_Available);
                  elsif Step.Status /= Archive.Archives.Errors.Ok then
                     return Fail (Step.Status, Archive.Archives.Entries.Failed);
                  end if;
               end;
            end;
         end;
      end loop;

      declare
         Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
           Archive.Compression.Zlib.Finish_Chunks (Stream, Forward_Output'Access);
      begin
         if Final.Status = Archive.Archives.Errors.Cancelled then
            return Fail (Final.Status, Archive.Archives.Entries.Not_Available);
         elsif Final.Status /= Archive.Archives.Errors.Ok then
            return Fail (Final.Status, Archive.Archives.Entries.Failed);
         end if;
      end;

      declare
         Close_Result : constant Archive.Compression.Zlib.Stream_Close_Result :=
           Archive.Compression.Zlib.Close (Stream);
      begin
         Close_File_Quietly;
         if Close_Result.Status /= Archive.Archives.Errors.Ok
           or else Close_Result.Close_Status /= Archive.Compression.Zlib.Close_Ok
           or else not Close_Result.Stream_Ended
         then
            return
              (Status => Archive.Archives.Errors.Invalid_Format,
               Integrity => Archive.Archives.Entries.Failed,
               Bytes_Written => Written);
         end if;
      end;

      if Item.Uncompressed.Present and then Written /= Item.Uncompressed.Value then
         return
           (Status => Archive.Archives.Errors.Invalid_Format,
            Integrity => Archive.Archives.Entries.Failed,
            Bytes_Written => Written);
      elsif Item.CRC32.Present
        and then Archive.Verification.CRC32.Final (CRC) /= Item.CRC32.Value
      then
         return
           (Status => Archive.Archives.Errors.Invalid_Format,
            Integrity => Archive.Archives.Entries.Failed,
            Bytes_Written => Written);
      end if;

      return
        (Status => Archive.Archives.Errors.Ok,
         Integrity => Archive.Archives.Entries.Verified,
         Bytes_Written => Written);
   exception
      when Ada.Streams.Stream_IO.Name_Error | Ada.Streams.Stream_IO.Use_Error =>
         Close_File_Quietly;
         return
           (Status => Archive.Archives.Errors.Read_Failed,
            Integrity => Archive.Archives.Entries.Not_Available,
            Bytes_Written => Written);
      when others =>
         Close_File_Quietly;
         return
           (Status => Archive.Archives.Errors.Read_Failed,
            Integrity => Archive.Archives.Entries.Not_Available,
            Bytes_Written => Written);
   end Stream_Payload_File;
end Archive.Archives.Readers.Gzip;
