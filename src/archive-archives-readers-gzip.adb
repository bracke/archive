with Ada.Characters.Handling;
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
   use type Zlib.Status_Code;

   Max_Header_Probe : constant Natural := 16_384;
   Max_Gzip_Field_Metadata : constant Natural := 4_096;

   --  The gzip header is parsed by Zlib.Read_GZip_Header; this body keeps the
   --  app-domain glue: the ISIZE/CRC trailer, the ".gz" name derivation, and
   --  the streaming gunzip that verifies the payload.

   procedure Read_File_Slice
     (Path   : String;
      Offset : Natural;
      Bytes  : out Zlib.Byte_Array;
      Status : out Archive.Archives.Errors.Error_Code)
   is
      File : Ada.Streams.Stream_IO.File_Type;
      Last : Ada.Streams.Stream_Element_Offset := 0;
   begin
      Status := Archive.Archives.Errors.Ok;
      if Bytes'Length = 0 then
         return;
      end if;

      declare
         Raw  : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Set_Index
           (File, Ada.Streams.Stream_IO.Count (Offset + 1));
         Ada.Streams.Stream_IO.Read (File, Raw, Last);
         Ada.Streams.Stream_IO.Close (File);

         if Last < Raw'First
           or else Natural (Last - Raw'First + 1) /= Bytes'Length
         then
            Status := Archive.Archives.Errors.Read_Failed;
            return;
         end if;

         for Index in Bytes'Range loop
            Bytes (Index) :=
              Zlib.Byte
                (Raw
                   (Raw'First
                    + Ada.Streams.Stream_Element_Offset (Index - Bytes'First)));
         end loop;
      end;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Status := Archive.Archives.Errors.Limit_Exceeded;
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Status := Archive.Archives.Errors.Read_Failed;
   end Read_File_Slice;

   function U32 (Bytes : Zlib.Byte_Array; Offset : Natural)
      return Archive.Types.CRC32_Value
   is
      function Octet (K : Natural) return Archive.Types.CRC32_Value is
        (Archive.Types.CRC32_Value (Bytes (Bytes'First + K)));
   begin
      return Octet (Offset)
        or Archive.Types.CRC32_Value
             (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Offset + 1)), 8))
        or Archive.Types.CRC32_Value
             (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Offset + 2)), 16))
        or Archive.Types.CRC32_Value
             (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Offset + 3)), 24));
   end U32;

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

   function Logical_Name
     (Embedded    : String;
      Source_Name : String)
      return String
   is
      From_Source : constant String := Safe_Name (Strip_Gz (Source_Name));
   begin
      if Embedded'Length > 0 then
         return Embedded;
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
         Header_Bytes  : Zlib.Byte_Array
           (1 .. Natural'Min (Size_N, Max_Header_Probe));
         Trailer_Bytes : Zlib.Byte_Array (1 .. 8);
         Header_Status : Archive.Archives.Errors.Error_Code;
         Trailer_Status : Archive.Archives.Errors.Error_Code;
      begin
         Read_File_Slice (Path, 0, Header_Bytes, Header_Status);
         Read_File_Slice (Path, Size_N - 8, Trailer_Bytes, Trailer_Status);
         if Header_Status /= Archive.Archives.Errors.Ok then
            return (Status => Header_Status, Item => <>, Header => <>);
         elsif Trailer_Status /= Archive.Archives.Errors.Ok then
            return (Status => Trailer_Status, Item => <>, Header => <>);
         end if;

         declare
            Md      : Zlib.GZip_Metadata;
            HStatus : Zlib.Status_Code;
            Result  : Gzip_Index_Result;
         begin
            Zlib.Read_GZip_Header (Header_Bytes, Md, HStatus);
            if HStatus /= Zlib.Ok then
               Result.Status :=
                 (if HStatus = Zlib.Insufficient_Memory
                  then Archive.Archives.Errors.Limit_Exceeded
                  else Archive.Archives.Errors.Invalid_Format);
               return Result;
            end if;

            declare
               Embedded : constant String :=
                 (if Zlib.Has_Name (Md) then Safe_Name (Zlib.Name (Md)) else "");
               Extra_Len : constant Natural := Zlib.Extra (Md)'Length;
            begin
               --  Preserve the app's field-size ceiling: an oversized FEXTRA,
               --  FNAME, or FCOMMENT is refused rather than surfaced.
               if Extra_Len > Max_Gzip_Field_Metadata
                 or else (Zlib.Has_Name (Md)
                          and then Zlib.Name (Md)'Length > Max_Gzip_Field_Metadata)
                 or else (Zlib.Has_Comment (Md)
                          and then Zlib.Comment (Md)'Length
                                   > Max_Gzip_Field_Metadata)
               then
                  Result.Status := Archive.Archives.Errors.Limit_Exceeded;
                  return Result;
               end if;

               declare
                  Name : constant String :=
                    Logical_Name
                      (Embedded,
                       (if Source_Name'Length > 0 then Source_Name else Path));
               begin
                  Result.Item.Original_Path := To_Unbounded_String (Name);
                  Result.Item.Display_Name := To_Unbounded_String (Name);
                  Result.Item.Kind := Archive.Archives.Entries.Regular_File;
                  Result.Item.Method := Archive.Archives.Entries.GZip_Deflate;
                  Result.Item.Encryption :=
                    Archive.Archives.Entries.Not_Encrypted;
                  Result.Item.Integrity := Archive.Archives.Entries.Not_Checked;
                  Result.Item.Safety :=
                    Archive.Archives.Paths.Normalize (Name).Safety;
                  Result.Item.CRC32 :=
                    (Present => True, Value => U32 (Trailer_Bytes, 0));
                  Result.Item.Uncompressed :=
                    (Present => True,
                     Value =>
                       Archive.Types.Uncompressed_Size (U32 (Trailer_Bytes, 4)));
                  Result.Item.Compressed :=
                    (Present => True,
                     Value => Archive.Types.Uncompressed_Size (Size_N));
                  Result.Header :=
                    (Header_Length  => Zlib.Header_Length (Md),
                     Extra_Length   => Extra_Len,
                     Has_Name       => Zlib.Has_Name (Md),
                     Has_Comment    => Zlib.Has_Comment (Md),
                     Has_Header_CRC => Zlib.Has_Header_CRC (Md));
                  return Result;
               end;
            end;
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
