with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Paths;
with Archive.Verification.CRC32;

package body Archive.Archives.Readers.Rar is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Entries.Compression_Method;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Types.Archive_Ordinal;
   use type Archive.Types.CRC32_Value;
   use type Archive.Types.Source_Offset;
   use type Archive.Types.Uncompressed_Size;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_64;
   use type Zlib.Byte;

   Marker_Size : constant Natural := 7;
   Base_Header_Size : constant Natural := 7;
   File_Header_Payload_Size : constant Natural := 25;
   Payload_Chunk_Size : constant Natural := 8_192;

   Block_Main : constant Zlib.Byte := 16#73#;
   Block_File : constant Zlib.Byte := 16#74#;
   Block_End  : constant Zlib.Byte := 16#7B#;

   No_Flags : constant Interfaces.Unsigned_16 := 0;
   Flag_Add_Size : constant Interfaces.Unsigned_16 := 16#8000#;
   Flag_Large    : constant Interfaces.Unsigned_16 := 16#0100#;
   Flag_Directory : constant Interfaces.Unsigned_16 := 16#00E0#;
   Flag_Encrypted : constant Interfaces.Unsigned_16 := 16#0004#;

   Method_Store : constant Natural := 16#30#;

   function Byte_At
     (Bytes : Ada.Streams.Stream_Element_Array;
      Index : Natural)
      return Natural
   is
   begin
      return Natural (Bytes (Bytes'First + Ada.Streams.Stream_Element_Offset (Index)));
   end Byte_At;

   function U16_LE
     (Bytes : Ada.Streams.Stream_Element_Array;
      Index : Natural)
      return Natural
   is
   begin
      return Byte_At (Bytes, Index) + Byte_At (Bytes, Index + 1) * 256;
   end U16_LE;

   function U32_LE
     (Bytes : Ada.Streams.Stream_Element_Array;
      Index : Natural)
      return Interfaces.Unsigned_64
   is
   begin
      return Interfaces.Unsigned_64 (Byte_At (Bytes, Index))
        + Interfaces.Unsigned_64 (Byte_At (Bytes, Index + 1))
          * Interfaces.Unsigned_64'(16#100#)
        + Interfaces.Unsigned_64 (Byte_At (Bytes, Index + 2))
          * Interfaces.Unsigned_64'(16#1_0000#)
        + Interfaces.Unsigned_64 (Byte_At (Bytes, Index + 3))
          * Interfaces.Unsigned_64'(16#100_0000#);
   end U32_LE;

   function U64_From_High_Low
     (High : Interfaces.Unsigned_64;
      Low  : Interfaces.Unsigned_64)
      return Interfaces.Unsigned_64
   is
   begin
      return High * Interfaces.Unsigned_64'(16#1_0000_0000#) + Low;
   end U64_From_High_Low;

   function Bytes_To_String
     (Bytes : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset;
      Count : Natural)
      return String
   is
      Result : String (1 .. Count);
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Character'Val
             (Bytes (First + Ada.Streams.Stream_Element_Offset (Index - 1)));
      end loop;
      return Result;
   end Bytes_To_String;

   function Read_Exact
     (File  : in out Ada.Streams.Stream_IO.File_Type;
      Count : Natural;
      Bytes : out Ada.Streams.Stream_Element_Array)
      return Boolean
   is
      Last : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Count = 0 then
         return True;
      end if;
      Ada.Streams.Stream_IO.Read (File, Bytes, Last);
      return Last >= Bytes'First
        and then Natural (Last - Bytes'First + 1) = Count;
   end Read_Exact;

   function Hex2 (Value : Natural) return String is
      Hex_Digits : constant String := "0123456789ABCDEF";
   begin
      return
        Hex_Digits (Hex_Digits'First + (Value / 16) mod 16)
        & Hex_Digits (Hex_Digits'First + Value mod 16);
   end Hex2;

   function U64_Image (Value : Interfaces.Unsigned_64) return String is
      Image : constant String := Interfaces.Unsigned_64'Image (Value);
   begin
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end U64_Image;

   function Is_Rar4_Marker
     (Bytes : Ada.Streams.Stream_Element_Array)
      return Boolean
   is
   begin
      return Bytes'Length = Marker_Size
        and then Byte_At (Bytes, 0) = 16#52#
        and then Byte_At (Bytes, 1) = 16#61#
        and then Byte_At (Bytes, 2) = 16#72#
        and then Byte_At (Bytes, 3) = 16#21#
        and then Byte_At (Bytes, 4) = 16#1A#
        and then Byte_At (Bytes, 5) = 16#07#
        and then Byte_At (Bytes, 6) = 16#00#;
   end Is_Rar4_Marker;

   function Index_File (Path : String) return Rar_Index_Result is
      File    : Ada.Streams.Stream_IO.File_Type;
      Size    : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
      Offset  : Natural := Marker_Size;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
      Result  : Rar_Index_Result;
      Saw_End : Boolean := False;
   begin
      if Size < Ada.Directories.File_Size (Marker_Size + Base_Header_Size)
        or else Size > Ada.Directories.File_Size (Natural'Last)
      then
         return (Status  => Archive.Archives.Errors.Invalid_Format,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      declare
         Marker : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Marker_Size));
      begin
         if not Read_Exact (File, Marker_Size, Marker) then
            Ada.Streams.Stream_IO.Close (File);
            return (Status  => Archive.Archives.Errors.Read_Failed,
                    Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
         elsif not Is_Rar4_Marker (Marker) then
            Ada.Streams.Stream_IO.Close (File);
            return (Status  => Archive.Archives.Errors.Unsupported_Format,
                    Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
         end if;
      end;

      while Offset < Natural (Size) loop
         declare
            Header : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Base_Header_Size));
            Header_Type : Zlib.Byte;
            Flags       : Interfaces.Unsigned_16;
            Header_Size : Natural;
            Add_Size    : Interfaces.Unsigned_64 := 0;
            Header_Start : constant Natural := Offset;
         begin
            if Natural (Size) - Offset < Base_Header_Size then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;

            Ada.Streams.Stream_IO.Set_Index
              (File, Ada.Streams.Stream_IO.Count (Offset + 1));
            if not Read_Exact (File, Base_Header_Size, Header) then
               Result.Status := Archive.Archives.Errors.Read_Failed;
               exit;
            end if;

            Header_Type := Zlib.Byte (Byte_At (Header, 2));
            Flags := Interfaces.Unsigned_16 (U16_LE (Header, 3));
            Header_Size := U16_LE (Header, 5);
            if Header_Size < Base_Header_Size
              or else Header_Size > Natural (Size) - Offset
            then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;

            if (Flags and Flag_Add_Size) /= No_Flags then
               declare
                  Add : Ada.Streams.Stream_Element_Array (1 .. 4);
               begin
                  if not Read_Exact (File, 4, Add) then
                     Result.Status := Archive.Archives.Errors.Read_Failed;
                     exit;
                  end if;
                  Add_Size := U32_LE (Add, 0);
               end;
            end if;

            if Header_Type = Block_End then
               Saw_End := True;
               exit;
            elsif Header_Type = Block_File then
               declare
                  Body_Size : constant Natural := Header_Size - Base_Header_Size;
                  Pack_Size_Low : Interfaces.Unsigned_64;
                  Unpack_Size_Low : Interfaces.Unsigned_64;
                  Pack_Size : Interfaces.Unsigned_64;
                  Unpack_Size : Interfaces.Unsigned_64;
                  File_CRC : Interfaces.Unsigned_64;
                  Method : Natural;
                  Name_Size : Natural;
                  Extra_Offset : Natural := File_Header_Payload_Size;
                  Data_Offset : constant Natural := Header_Start + Header_Size;
               begin
                  if Body_Size < File_Header_Payload_Size then
                     Result.Status := Archive.Archives.Errors.Invalid_Format;
                     exit;
                  end if;

                  declare
                     Header_Body : Ada.Streams.Stream_Element_Array
                       (1 .. Ada.Streams.Stream_Element_Offset (Body_Size));
                  begin
                     if not Read_Exact (File, Body_Size, Header_Body) then
                        Result.Status := Archive.Archives.Errors.Read_Failed;
                        exit;
                     end if;

                     Pack_Size_Low := U32_LE (Header_Body, 0);
                     Unpack_Size_Low := U32_LE (Header_Body, 4);
                     File_CRC := U32_LE (Header_Body, 9);
                     Method := Byte_At (Header_Body, 18);
                     Name_Size := U16_LE (Header_Body, 19);

                     if (Flags and Flag_Large) /= No_Flags then
                        if Body_Size < File_Header_Payload_Size + 8 then
                           Result.Status := Archive.Archives.Errors.Invalid_Format;
                           exit;
                        end if;
                        Pack_Size :=
                          U64_From_High_Low (U32_LE (Header_Body, 25), Pack_Size_Low);
                        Unpack_Size :=
                          U64_From_High_Low (U32_LE (Header_Body, 29), Unpack_Size_Low);
                        Extra_Offset := Extra_Offset + 8;
                     else
                        Pack_Size := Pack_Size_Low;
                        Unpack_Size := Unpack_Size_Low;
                     end if;

                     if Name_Size = 0
                       or else Name_Size > Body_Size - Extra_Offset
                       or else Pack_Size > Interfaces.Unsigned_64 (Natural'Last)
                       or else Unpack_Size > Interfaces.Unsigned_64 (Natural'Last)
                       or else Natural (Pack_Size) > Natural (Size) - Data_Offset
                     then
                        Result.Status := Archive.Archives.Errors.Invalid_Format;
                        exit;
                     end if;

                     declare
                        Name : constant String :=
                          Bytes_To_String
                            (Header_Body,
                             Header_Body'First + Ada.Streams.Stream_Element_Offset (Extra_Offset),
                             Name_Size);
                        Item : Archive.Archives.Entries.Archive_Entry;
                        Stored : constant Boolean := Method = Method_Store;
                     begin
                        Item.Ordinal := Ordinal;
                        Item.Original_Path := To_Unbounded_String (Name);
                        Item.Display_Name := To_Unbounded_String (Name);
                        Item.Kind :=
                          (if (Flags and Flag_Directory) = Flag_Directory
                           then Archive.Archives.Entries.Directory
                           else Archive.Archives.Entries.Regular_File);
                        Item.Method :=
                          (if Stored
                           then Archive.Archives.Entries.No_Compression
                           else Archive.Archives.Entries.Unsupported_Compression);
                        Item.Encryption :=
                          (if (Flags and Flag_Encrypted) /= No_Flags
                           then Archive.Archives.Entries.Encrypted
                           else Archive.Archives.Entries.Not_Encrypted);
                        Item.Integrity := Archive.Archives.Entries.Not_Checked;
                        if Item.Kind = Archive.Archives.Entries.Regular_File
                          and then Stored
                        then
                           Item.Data_Offset :=
                             (Present => True,
                              Value   => Archive.Types.Source_Offset (Data_Offset));
                        end if;
                        Item.CRC32 :=
                          (Present => True,
                           Value   => Archive.Types.CRC32_Value (File_CRC));
                        Item.Compressed :=
                          (Present => True,
                           Value   => Archive.Types.Uncompressed_Size (Pack_Size));
                        Item.Uncompressed :=
                          (Present => True,
                           Value   => Archive.Types.Uncompressed_Size (Unpack_Size));
                        Item.Format_Metadata :=
                          To_Unbounded_String
                            ("rar.version=4;rar.method=0x" & Hex2 (Method)
                             & ";rar.header_offset="
                             & U64_Image (Interfaces.Unsigned_64 (Header_Start)));
                        Item.Safety := Archive.Archives.Paths.Normalize (Name).Safety;
                        Result.Entries.Append (Item);
                        Ordinal := Ordinal + 1;
                     end;
                  end;

                  Offset := Data_Offset + Natural (Pack_Size);
               end;
            else
               if Add_Size > Interfaces.Unsigned_64 (Natural'Last)
                 or else Natural (Add_Size) > Natural (Size) - (Offset + Header_Size)
               then
                  Result.Status := Archive.Archives.Errors.Invalid_Format;
                  exit;
               end if;
               Offset := Offset + Header_Size + Natural (Add_Size);
            end if;
         end;
      end loop;

      if Ada.Streams.Stream_IO.Is_Open (File) then
         Ada.Streams.Stream_IO.Close (File);
      end if;
      if Result.Status = Archive.Archives.Errors.Ok and then not Saw_End then
         Result.Status := Archive.Archives.Errors.Invalid_Format;
      end if;
      return Result;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status  => Archive.Archives.Errors.Limit_Exceeded,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status  => Archive.Archives.Errors.Read_Failed,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
   end Index_File;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      File : Ada.Streams.Stream_IO.File_Type;
      Remaining : Natural;
      Written : Archive.Types.Uncompressed_Size := 0;
      CRC : Archive.Verification.CRC32.CRC32_State :=
        Archive.Verification.CRC32.Initial;
   begin
      if Item.Kind /= Archive.Archives.Entries.Regular_File
        or else Item.Method /= Archive.Archives.Entries.No_Compression
        or else not Item.Data_Offset.Present
        or else not Item.Uncompressed.Present
      then
         return (Status => Archive.Archives.Errors.Unsupported_Method,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      elsif Item.Data_Offset.Value > Archive.Types.Source_Offset (Natural'Last)
        or else Item.Uncompressed.Value > Archive.Types.Uncompressed_Size (Natural'Last)
      then
         return (Status => Archive.Archives.Errors.Limit_Exceeded,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      end if;

      Remaining := Natural (Item.Uncompressed.Value);
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Set_Index
        (File, Ada.Streams.Stream_IO.Count (Natural (Item.Data_Offset.Value) + 1));

      while Remaining > 0 loop
         declare
            Count : constant Natural := Natural'Min (Payload_Chunk_Size, Remaining);
            Raw   : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Last  : Ada.Streams.Stream_Element_Offset := 0;
            Continue : Boolean := True;
         begin
            Ada.Streams.Stream_IO.Read (File, Raw, Last);
            if Last < Raw'First or else Natural (Last - Raw'First + 1) /= Count then
               Ada.Streams.Stream_IO.Close (File);
               return (Status => Archive.Archives.Errors.Read_Failed,
                       Integrity => Archive.Archives.Entries.Not_Available,
                       Bytes_Written => Written);
            end if;

            declare
               Chunk : Zlib.Byte_Array (1 .. Count);
            begin
               for Index in Chunk'Range loop
                  Chunk (Index) :=
                    Zlib.Byte
                      (Raw (Raw'First + Ada.Streams.Stream_Element_Offset (Index - 1)));
               end loop;
               Archive.Verification.CRC32.Update (CRC, Chunk);
               Consumer.all (Chunk, Continue);
            end;

            Written := Written + Archive.Types.Uncompressed_Size (Count);
            Remaining := Remaining - Count;
            if not Continue then
               Ada.Streams.Stream_IO.Close (File);
               return (Status => Archive.Archives.Errors.Cancelled,
                       Integrity => Archive.Archives.Entries.Not_Available,
                       Bytes_Written => Written);
            end if;
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      if Item.CRC32.Present
        and then Archive.Verification.CRC32.Final (CRC) /= Item.CRC32.Value
      then
         return (Status => Archive.Archives.Errors.Invalid_Format,
                 Integrity => Archive.Archives.Entries.Failed,
                 Bytes_Written => Written);
      end if;

      return (Status => Archive.Archives.Errors.Ok,
              Integrity => Archive.Archives.Entries.Verified,
              Bytes_Written => Written);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status => Archive.Archives.Errors.Read_Failed,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => Written);
   end Stream_Payload_File;
end Archive.Archives.Readers.Rar;
