with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Paths;
with Archive.Archives.Streams;
with Archive.Compression.Zlib;
with Archive.Resource_Limits;
with Archive.Verification.CRC32;

package body Archive.Archives.Readers.Zip is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Entries.Compression_Method;
   use type Archive.Archives.Entries.Encryption_State;
   use type Archive.Types.Uncompressed_Size;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   EOCD_Min_Size : constant Natural := 22;
   Max_EOCD_Search : constant Natural := EOCD_Min_Size + 65_535;
   Max_Zip_Record_Metadata : constant Natural :=
     Natural
       (Archive.Resource_Limits.Hard_Ceiling
          (Archive.Resource_Limits.Metadata_Bytes_Per_Entry));

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

   function Within_Metadata_Limit (Count : Natural) return Boolean is
   begin
      return Count <= Max_Zip_Record_Metadata;
   end Within_Metadata_Limit;

   function Octet (Bytes : Zlib.Byte_Array; Offset : Natural) return Zlib.Byte is
   begin
      return Bytes (Bytes'First + Offset);
   end Octet;

   function U16 (Bytes : Zlib.Byte_Array; Offset : Natural) return Interfaces.Unsigned_16 is
   begin
      return Interfaces.Unsigned_16 (Octet (Bytes, Offset))
        or Interfaces.Shift_Left (Interfaces.Unsigned_16 (Octet (Bytes, Offset + 1)), 8);
   end U16;

   function U32 (Bytes : Zlib.Byte_Array; Offset : Natural) return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Octet (Bytes, Offset))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Bytes, Offset + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Bytes, Offset + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Octet (Bytes, Offset + 3)), 24);
   end U32;

   function U64 (Bytes : Zlib.Byte_Array; Offset : Natural) return Interfaces.Unsigned_64 is
   begin
      return Interfaces.Unsigned_64 (U32 (Bytes, Offset))
        or Interfaces.Shift_Left (Interfaces.Unsigned_64 (U32 (Bytes, Offset + 4)), 32);
   end U64;

   function Signature (Bytes : Zlib.Byte_Array; Offset : Natural) return Interfaces.Unsigned_32 is
   begin
      if not In_Range (Bytes, Offset, 4) then
         return 0;
      end if;
      return U32 (Bytes, Offset);
   end Signature;

   function Find_EOCD (Bytes : Zlib.Byte_Array) return Natural is
      Max_Comment : constant Natural := 65_535;
      First       : Natural := 0;
   begin
      if Bytes'Length < EOCD_Min_Size then
         return Natural'Last;
      end if;

      if Bytes'Length > EOCD_Min_Size + Max_Comment then
         First := Bytes'Length - (EOCD_Min_Size + Max_Comment);
      end if;

      for Offset in reverse First .. Bytes'Length - EOCD_Min_Size loop
         if Signature (Bytes, Offset) = 16#0605_4B50# then
            declare
               Comment_Length : constant Natural := Natural (U16 (Bytes, Offset + 20));
            begin
               if Offset + EOCD_Min_Size + Comment_Length = Bytes'Length then
                  return Offset;
               end if;
            end;
         end if;
      end loop;

      return Natural'Last;
   end Find_EOCD;

   function Name_At
     (Bytes  : Zlib.Byte_Array;
      Offset : Natural;
      Length : Natural)
      return String
   is
      Result : String (1 .. Length);
   begin
      for Index in Result'Range loop
         Result (Index) := Character'Val (Octet (Bytes, Offset + Index - 1));
      end loop;
      return Result;
   end Name_At;

   function Image_Trimmed (Value : Natural) return String is
      Raw : constant String := Natural'Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Image_Trimmed;

   function ZIP_Metadata
     (Flags       : Interfaces.Unsigned_16;
      Extra_Len   : Natural;
      Comment_Len : Natural;
      Unicode_Path : Boolean;
      UTF8_Name    : Boolean;
      Uses_ZIP64   : Boolean;
      Data_Descriptor : Boolean;
      Descriptor_ZIP64 : Boolean;
      Encrypted    : Boolean;
      Method       : Interfaces.Unsigned_16)
      return String
   is
   begin
      return "zip.flags=" & Image_Trimmed (Natural (Flags))
        & ";zip.method=" & Image_Trimmed (Natural (Method))
        & ";zip.extra_len=" & Image_Trimmed (Extra_Len)
        & ";zip.comment_len=" & Image_Trimmed (Comment_Len)
        & ";zip.data_descriptor=" & (if Data_Descriptor then "true" else "false")
        & ";zip.descriptor_zip64=" & (if Descriptor_ZIP64 then "true" else "false")
        & ";zip.zip64=" & (if Uses_ZIP64 then "true" else "false")
        & ";zip.encrypted=" & (if Encrypted then "true" else "false")
        & ";zip.unicode_path=" & (if Unicode_Path then "true" else "false")
        & ";zip.utf8_name=" & (if UTF8_Name then "true" else "false")
        & ";zip.legacy_name=" & (if UTF8_Name or else Unicode_Path then "false" else "true");
   end ZIP_Metadata;

   type Unicode_Path_Result is record
      Present : Boolean := False;
      Valid   : Boolean := True;
      Path    : Unbounded_String;
   end record;

   type ZIP64_Extra_Result is record
      Present       : Boolean := False;
      Valid         : Boolean := True;
      Uncompressed  : Interfaces.Unsigned_64 := 0;
      Compressed    : Interfaces.Unsigned_64 := 0;
      Local_Offset  : Interfaces.Unsigned_64 := 0;
   end record;

   type Descriptor_Result is record
      Valid : Boolean := False;
      ZIP64 : Boolean := False;
      Length : Natural := 0;
   end record;

   function Fits_Natural (Value : Interfaces.Unsigned_64) return Boolean is
   begin
      return Value <= Interfaces.Unsigned_64 (Natural'Last);
   end Fits_Natural;

   function Unicode_Path_From_Extra
     (Bytes  : Zlib.Byte_Array;
      Offset : Natural;
      Length : Natural;
      Name   : String)
      return Unicode_Path_Result
   is
      Cursor : Natural := Offset;
      Result : Unicode_Path_Result;
   begin
      while Cursor < Offset + Length loop
         if not In_Range (Bytes, Cursor, 4) then
            Result.Valid := False;
            return Result;
         end if;

         declare
            Header_Id : constant Interfaces.Unsigned_16 := U16 (Bytes, Cursor);
            Data_Len  : constant Natural := Natural (U16 (Bytes, Cursor + 2));
            Data_Off  : constant Natural := Cursor + 4;
         begin
            if Data_Off > Offset + Length
              or else Data_Len > Offset + Length - Data_Off
            then
               Result.Valid := False;
               return Result;
            elsif Header_Id = 16#7075# then
               if Data_Len < 5 or else Octet (Bytes, Data_Off) /= 1 then
                  Result.Valid := False;
                  return Result;
               end if;

               declare
                  Name_Bytes : Zlib.Byte_Array (1 .. Name'Length);
                  State      : Archive.Verification.CRC32.CRC32_State :=
                    Archive.Verification.CRC32.Initial;
               begin
                  for Index in Name'Range loop
                     Name_Bytes (Index - Name'First + 1) :=
                       Zlib.Byte (Character'Pos (Name (Index)));
                  end loop;
                  Archive.Verification.CRC32.Update (State, Name_Bytes);

                  if U32 (Bytes, Data_Off + 1) /=
                    Interfaces.Unsigned_32
                      (Archive.Verification.CRC32.Final (State))
                  then
                     Result.Valid := False;
                     return Result;
                  end if;
               end;
               Result.Present := True;
               Result.Path := To_Unbounded_String
                 (Name_At (Bytes, Data_Off + 5, Data_Len - 5));
               return Result;
            end if;
            Cursor := Data_Off + Data_Len;
         end;
      end loop;
      return Result;
   end Unicode_Path_From_Extra;

   function ZIP64_From_Extra
     (Bytes        : Zlib.Byte_Array;
      Offset       : Natural;
      Length       : Natural;
      Need_Uncomp  : Boolean;
      Need_Comp    : Boolean;
      Need_Local   : Boolean)
      return ZIP64_Extra_Result
   is
      Cursor : Natural := Offset;
      Result : ZIP64_Extra_Result;
   begin
      while Cursor < Offset + Length loop
         if not In_Range (Bytes, Cursor, 4) then
            Result.Valid := False;
            return Result;
         end if;

         declare
            Header_Id : constant Interfaces.Unsigned_16 := U16 (Bytes, Cursor);
            Data_Len  : constant Natural := Natural (U16 (Bytes, Cursor + 2));
            Data_Off  : constant Natural := Cursor + 4;
            Pos       : Natural := Data_Off;
         begin
            if Data_Off > Offset + Length
              or else Data_Len > Offset + Length - Data_Off
            then
               Result.Valid := False;
               return Result;
            elsif Header_Id = 16#0001# then
               Result.Present := True;
               if Need_Uncomp then
                  if Pos > Data_Off + Data_Len or else Data_Off + Data_Len - Pos < 8 then
                     Result.Valid := False;
                     return Result;
                  end if;
                  Result.Uncompressed := U64 (Bytes, Pos);
                  Pos := Pos + 8;
               end if;
               if Need_Comp then
                  if Pos > Data_Off + Data_Len or else Data_Off + Data_Len - Pos < 8 then
                     Result.Valid := False;
                     return Result;
                  end if;
                  Result.Compressed := U64 (Bytes, Pos);
                  Pos := Pos + 8;
               end if;
               if Need_Local then
                  if Pos > Data_Off + Data_Len or else Data_Off + Data_Len - Pos < 8 then
                     Result.Valid := False;
                     return Result;
                  end if;
                  Result.Local_Offset := U64 (Bytes, Pos);
               end if;
               return Result;
            end if;
            Cursor := Data_Off + Data_Len;
         end;
      end loop;
      if Need_Uncomp or else Need_Comp or else Need_Local then
         Result.Valid := False;
      end if;
      return Result;
   end ZIP64_From_Extra;

   function Name_Equals
     (Bytes  : Zlib.Byte_Array;
      Offset : Natural;
      Name   : String)
      return Boolean
   is
   begin
      if not In_Range (Bytes, Offset, Name'Length) then
         return False;
      end if;

      for Index in Name'Range loop
         if Character'Val (Octet (Bytes, Offset + Index - Name'First)) /= Name (Index) then
            return False;
         end if;
      end loop;
      return True;
   end Name_Equals;

   function Descriptor_At
     (Bytes       : Zlib.Byte_Array;
      Offset      : Natural;
      CRC         : Interfaces.Unsigned_32;
      Compressed  : Interfaces.Unsigned_64;
      Uncompressed : Interfaces.Unsigned_64)
      return Descriptor_Result
   is
   begin
      if Fits_Natural (Compressed)
        and then Fits_Natural (Uncompressed)
      then
         if In_Range (Bytes, Offset, 16)
           and then Signature (Bytes, Offset) = 16#0807_4B50#
           and then U32 (Bytes, Offset + 4) = CRC
           and then Interfaces.Unsigned_64 (U32 (Bytes, Offset + 8)) = Compressed
           and then Interfaces.Unsigned_64 (U32 (Bytes, Offset + 12)) = Uncompressed
         then
            return (Valid => True, ZIP64 => False, Length => 16);
         elsif In_Range (Bytes, Offset, 12)
           and then U32 (Bytes, Offset) = CRC
           and then Interfaces.Unsigned_64 (U32 (Bytes, Offset + 4)) = Compressed
           and then Interfaces.Unsigned_64 (U32 (Bytes, Offset + 8)) = Uncompressed
         then
            return (Valid => True, ZIP64 => False, Length => 12);
         end if;
      end if;

      if In_Range (Bytes, Offset, 24)
        and then Signature (Bytes, Offset) = 16#0807_4B50#
        and then U32 (Bytes, Offset + 4) = CRC
        and then U64 (Bytes, Offset + 8) = Compressed
        and then U64 (Bytes, Offset + 16) = Uncompressed
      then
         return (Valid => True, ZIP64 => True, Length => 24);
      elsif In_Range (Bytes, Offset, 20)
        and then U32 (Bytes, Offset) = CRC
        and then U64 (Bytes, Offset + 4) = Compressed
        and then U64 (Bytes, Offset + 12) = Uncompressed
      then
         return (Valid => True, ZIP64 => True, Length => 20);
      end if;

      return (Valid => False, ZIP64 => False, Length => 0);
   end Descriptor_At;

   function Is_Directory_Name (Name : String) return Boolean is
   begin
      return Name'Length > 0 and then Name (Name'Last) = '/';
   end Is_Directory_Name;

   function Compression_For
     (Method : Interfaces.Unsigned_16)
      return Archive.Archives.Entries.Compression_Method
   is
   begin
      case Method is
         when 0 =>
            return Archive.Archives.Entries.Zip_Stored;
         when 8 =>
            return Archive.Archives.Entries.Zip_Deflate;
         when 12 =>
            return Archive.Archives.Entries.BZip2_Compression;
         when 14 =>
            return Archive.Archives.Entries.LZMA_Compression;
         when 20 | 93 =>
            return Archive.Archives.Entries.Zstd_Compression;
         when others =>
            return Archive.Archives.Entries.Unsupported_Compression;
      end case;
   end Compression_For;

   function Map_Zlib_Status
     (Status : Zlib.Status_Code)
      return Archive.Archives.Errors.Error_Code
   is
   begin
      case Status is
         when Zlib.Ok =>
            return Archive.Archives.Errors.Ok;
         when Zlib.Unsupported_Method | Zlib.Unsupported_Preset_Dictionary =>
            return Archive.Archives.Errors.Unsupported_Method;
         when Zlib.Unexpected_End_Of_Input | Zlib.Invalid_Header
            | Zlib.Invalid_Block_Type | Zlib.Invalid_Checksum
            | Zlib.Invalid_Stored_Block | Zlib.Invalid_Huffman_Code
            | Zlib.Invalid_Distance =>
            return Archive.Archives.Errors.Invalid_Format;
         when Zlib.Input_File_Error =>
            return Archive.Archives.Errors.Read_Failed;
         when Zlib.Output_File_Error =>
            return Archive.Archives.Errors.Write_Failed;
      end case;
   end Map_Zlib_Status;

   function Index_File (Path : String) return Zip_Index_Result is
      Size      : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
      Size_N    : Natural;
      Tail_Size : Natural;
   begin
      if Size > Ada.Directories.File_Size (Natural'Last) then
         return
           (Status  => Archive.Archives.Errors.Limit_Exceeded,
            Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      Size_N := Natural (Size);
      if Size_N < EOCD_Min_Size then
         return
           (Status  => Archive.Archives.Errors.Invalid_Format,
            Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      Tail_Size := Natural'Min (Size_N, Max_EOCD_Search);

      declare
         Tail_Offset : constant Natural := Size_N - Tail_Size;
         Tail        : constant File_Slice_Result :=
           Read_File_Slice (Path, Tail_Offset, Tail_Size);
         Tail_Bytes  : constant Zlib.Byte_Array := Slice_Bytes (Tail);
         EOCD_Rel    : Natural;
         EOCD_Abs    : Natural;
      begin
         if Tail.Status /= Archive.Archives.Errors.Ok then
            return
              (Status  => Tail.Status,
               Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
         end if;

         EOCD_Rel := Find_EOCD (Tail_Bytes);
         if EOCD_Rel = Natural'Last then
            return
              (Status  => Archive.Archives.Errors.Invalid_Format,
               Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
         end if;

         EOCD_Abs := Tail_Offset + EOCD_Rel;

         if EOCD_Abs >= 20 then
            declare
               Locator : constant File_Slice_Result :=
                 Read_File_Slice (Path, EOCD_Abs - 20, 4);
               Locator_Bytes : constant Zlib.Byte_Array := Slice_Bytes (Locator);
            begin
               if Locator.Status = Archive.Archives.Errors.Ok
                 and then Signature (Locator_Bytes, 0) = 16#0706_4B50#
               then
                  return
                    (Status  => Archive.Archives.Errors.Unsupported_Format,
                     Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
               end if;
            end;
         end if;

         if U16 (Tail_Bytes, EOCD_Rel + 4) /= 0
           or else U16 (Tail_Bytes, EOCD_Rel + 6) /= 0
         then
            return
              (Status  => Archive.Archives.Errors.Unsupported_Format,
               Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
         end if;

         declare
            Entries_On_Disk_Raw : constant Interfaces.Unsigned_16 :=
              U16 (Tail_Bytes, EOCD_Rel + 8);
            Entries_Total_Raw   : constant Interfaces.Unsigned_16 :=
              U16 (Tail_Bytes, EOCD_Rel + 10);
            Directory_Size_Raw  : constant Interfaces.Unsigned_32 :=
              U32 (Tail_Bytes, EOCD_Rel + 12);
            Directory_Off_Raw   : constant Interfaces.Unsigned_32 :=
              U32 (Tail_Bytes, EOCD_Rel + 16);
            Archive_Comment     : constant Natural :=
              Natural (U16 (Tail_Bytes, EOCD_Rel + 20));
            Result              : Zip_Index_Result;
         begin
            if Entries_On_Disk_Raw = 16#FFFF#
              or else Entries_Total_Raw = 16#FFFF#
              or else Directory_Size_Raw = 16#FFFF_FFFF#
              or else Directory_Off_Raw = 16#FFFF_FFFF#
            then
               return
                 (Status  => Archive.Archives.Errors.Unsupported_Format,
                  Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
            end if;

            declare
               Entries_On_Disk : constant Natural := Natural (Entries_On_Disk_Raw);
               Entries_Total   : constant Natural := Natural (Entries_Total_Raw);
               Directory_Size  : constant Natural := Natural (Directory_Size_Raw);
               Directory_Off   : constant Natural := Natural (Directory_Off_Raw);
               Directory       : File_Slice_Result;
            begin
               if Entries_On_Disk /= Entries_Total then
                  return
                    (Status  => Archive.Archives.Errors.Unsupported_Format,
                     Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
               elsif Directory_Off > EOCD_Abs
                 or else Directory_Size > EOCD_Abs - Directory_Off
                 or else Directory_Off + Directory_Size /= EOCD_Abs
                 or else EOCD_Abs + EOCD_Min_Size + Archive_Comment /= Size_N
               then
                  return
                    (Status  => Archive.Archives.Errors.Invalid_Format,
                     Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
               end if;

               Directory := Read_File_Slice (Path, Directory_Off, Directory_Size);
               if Directory.Status /= Archive.Archives.Errors.Ok then
                  return
                    (Status  => Directory.Status,
                     Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
               end if;

               declare
                  Directory_Bytes : constant Zlib.Byte_Array := Slice_Bytes (Directory);
                  Cursor          : Natural := 0;
               begin
                  for Ordinal in 0 .. Entries_Total - 1 loop
                     if not In_Range (Directory_Bytes, Cursor, 46)
                       or else Signature (Directory_Bytes, Cursor) /= 16#0201_4B50#
                     then
                        return
                          (Status  => Archive.Archives.Errors.Invalid_Format,
                           Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                     end if;

                     declare
                        Flags      : constant Interfaces.Unsigned_16 :=
                          U16 (Directory_Bytes, Cursor + 8);
                        Method     : constant Interfaces.Unsigned_16 :=
                          U16 (Directory_Bytes, Cursor + 10);
                        CRC        : constant Interfaces.Unsigned_32 :=
                          U32 (Directory_Bytes, Cursor + 16);
                        Comp_Size_Raw : constant Interfaces.Unsigned_32 :=
                          U32 (Directory_Bytes, Cursor + 20);
                        Uncomp_Raw    : constant Interfaces.Unsigned_32 :=
                          U32 (Directory_Bytes, Cursor + 24);
                        Name_Len   : constant Natural :=
                          Natural (U16 (Directory_Bytes, Cursor + 28));
                        Extra_Len  : constant Natural :=
                          Natural (U16 (Directory_Bytes, Cursor + 30));
                        Comment_Len : constant Natural :=
                          Natural (U16 (Directory_Bytes, Cursor + 32));
                        Local_Off_Raw : constant Interfaces.Unsigned_32 :=
                          U32 (Directory_Bytes, Cursor + 42);
                        Header_End : constant Natural := Cursor + 46;
                     begin
                        if not Within_Metadata_Limit
                          (Name_Len + Extra_Len + Comment_Len)
                        then
                           return
                             (Status  => Archive.Archives.Errors.Limit_Exceeded,
                              Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                        elsif not In_Range
                          (Directory_Bytes,
                           Header_End,
                           Name_Len + Extra_Len + Comment_Len)
                        then
                           return
                             (Status  => Archive.Archives.Errors.Invalid_Format,
                              Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                        end if;

                        declare
                           Name : constant String :=
                             Name_At (Directory_Bytes, Header_End, Name_Len);
                           Extra_Offset : constant Natural := Header_End + Name_Len;
                           Comment_Offset : constant Natural := Extra_Offset + Extra_Len;
                           Unicode_Name : constant Unicode_Path_Result :=
                             Unicode_Path_From_Extra
                               (Directory_Bytes, Extra_Offset, Extra_Len, Name);
                           ZIP64 : constant ZIP64_Extra_Result :=
                             ZIP64_From_Extra
                               (Directory_Bytes,
                                Extra_Offset,
                                Extra_Len,
                                Need_Uncomp => Uncomp_Raw = 16#FFFF_FFFF#,
                                Need_Comp   => Comp_Size_Raw = 16#FFFF_FFFF#,
                                Need_Local  => Local_Off_Raw = 16#FFFF_FFFF#);
                           Comp_Size_64 : constant Interfaces.Unsigned_64 :=
                             (if Comp_Size_Raw = 16#FFFF_FFFF#
                              then ZIP64.Compressed
                              else Interfaces.Unsigned_64 (Comp_Size_Raw));
                           Uncomp_64 : constant Interfaces.Unsigned_64 :=
                             (if Uncomp_Raw = 16#FFFF_FFFF#
                              then ZIP64.Uncompressed
                              else Interfaces.Unsigned_64 (Uncomp_Raw));
                           Local_Off_64 : constant Interfaces.Unsigned_64 :=
                             (if Local_Off_Raw = 16#FFFF_FFFF#
                              then ZIP64.Local_Offset
                              else Interfaces.Unsigned_64 (Local_Off_Raw));
                           Item : Archive.Archives.Entries.Archive_Entry;
                        begin
                           if not Unicode_Name.Valid
                             or else not ZIP64.Valid
                             or else not Fits_Natural (Comp_Size_64)
                             or else not Fits_Natural (Uncomp_64)
                             or else not Fits_Natural (Local_Off_64)
                           then
                              return
                                (Status  => Archive.Archives.Errors.Invalid_Format,
                                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                           end if;

                           declare
                              Comp_Size : constant Natural := Natural (Comp_Size_64);
                              Local_Off : constant Natural := Natural (Local_Off_64);
                              Local_Header : constant File_Slice_Result :=
                                Read_File_Slice (Path, Local_Off, 30);
                              Local_Header_Bytes : constant Zlib.Byte_Array :=
                                Slice_Bytes (Local_Header);
                           begin
                              if Local_Header.Status /= Archive.Archives.Errors.Ok then
                                 return
                                   (Status  => Local_Header.Status,
                                    Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                              elsif Signature (Local_Header_Bytes, 0) /= 16#0403_4B50#
                                or else U16 (Local_Header_Bytes, 6) /= Flags
                                or else U16 (Local_Header_Bytes, 8) /= Method
                              then
                                 return
                                   (Status  => Archive.Archives.Errors.Invalid_Format,
                                    Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                              end if;

                              declare
                                 Local_Name_Len : constant Natural :=
                                   Natural (U16 (Local_Header_Bytes, 26));
                                 Local_Extra_Len : constant Natural :=
                                   Natural (U16 (Local_Header_Bytes, 28));
                              begin
                                 if not Within_Metadata_Limit
                                   (Local_Name_Len + Local_Extra_Len)
                                 then
                                    return
                                      (Status  => Archive.Archives.Errors.Limit_Exceeded,
                                       Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                 elsif Local_Name_Len /= Name_Len then
                                    return
                                      (Status  => Archive.Archives.Errors.Invalid_Format,
                                       Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                 end if;

                                 declare
                                    Local_Name_Extra : constant File_Slice_Result :=
                                      Read_File_Slice
                                        (Path,
                                         Local_Off + 30,
                                         Local_Name_Len + Local_Extra_Len);
                                    Local_Name_Extra_Bytes : constant Zlib.Byte_Array :=
                                      Slice_Bytes (Local_Name_Extra);
                                 begin
                                    if Local_Name_Extra.Status /= Archive.Archives.Errors.Ok
                                      or else not Name_Equals
                                        (Local_Name_Extra_Bytes, 0, Name)
                                    then
                                       return
                                         (Status  => Archive.Archives.Errors.Invalid_Format,
                                          Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                    end if;

                                    declare
                                       Uses_Data_Descriptor : constant Boolean := (Flags and 8) /= 0;
                                       Local_Comp_Size : constant Interfaces.Unsigned_32 :=
                                         U32 (Local_Header_Bytes, 18);
                                       Local_Uncomp_Size : constant Interfaces.Unsigned_32 :=
                                         U32 (Local_Header_Bytes, 22);
                                       Local_ZIP64 : constant ZIP64_Extra_Result :=
                                         ZIP64_From_Extra
                                           (Local_Name_Extra_Bytes,
                                            Local_Name_Len,
                                            Local_Extra_Len,
                                            Need_Uncomp => Local_Uncomp_Size = 16#FFFF_FFFF#,
                                            Need_Comp   => Local_Comp_Size = 16#FFFF_FFFF#,
                                            Need_Local  => False);
                                       Effective_Local_Comp : constant Interfaces.Unsigned_64 :=
                                         (if Local_Comp_Size = 16#FFFF_FFFF#
                                          then Local_ZIP64.Compressed
                                          else Interfaces.Unsigned_64 (Local_Comp_Size));
                                       Effective_Local_Uncomp : constant Interfaces.Unsigned_64 :=
                                         (if Local_Uncomp_Size = 16#FFFF_FFFF#
                                          then Local_ZIP64.Uncompressed
                                          else Interfaces.Unsigned_64 (Local_Uncomp_Size));
                                       Data_Start : constant Natural :=
                                         Local_Off + 30 + Local_Name_Len + Local_Extra_Len;
                                       Descriptor_Start : constant Natural := Data_Start + Comp_Size;
                                       Descriptor : Descriptor_Result := (others => <>);
                                    begin
                                       if not Local_ZIP64.Valid then
                                          return
                                            (Status  => Archive.Archives.Errors.Invalid_Format,
                                             Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                       elsif not Uses_Data_Descriptor
                                         and then
                                           (Effective_Local_Comp /= Comp_Size_64
                                            or else Effective_Local_Uncomp /= Uncomp_64)
                                       then
                                          return
                                            (Status  => Archive.Archives.Errors.Invalid_Format,
                                             Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                       elsif Data_Start > Directory_Off
                                         or else Comp_Size > Directory_Off - Data_Start
                                         or else Descriptor_Start > Directory_Off
                                       then
                                          return
                                            (Status  => Archive.Archives.Errors.Invalid_Format,
                                             Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                       elsif Uses_Data_Descriptor then
                                          declare
                                             Descriptor_Bytes : constant File_Slice_Result :=
                                               Read_File_Slice
                                                 (Path,
                                                  Descriptor_Start,
                                                  Natural'Min (24, Directory_Off - Descriptor_Start));
                                             Descriptor_Array : constant Zlib.Byte_Array :=
                                               Slice_Bytes (Descriptor_Bytes);
                                          begin
                                             if Descriptor_Bytes.Status /= Archive.Archives.Errors.Ok then
                                                return
                                                  (Status  => Descriptor_Bytes.Status,
                                                   Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                             end if;
                                             Descriptor :=
                                               Descriptor_At
                                                 (Descriptor_Array,
                                                  0,
                                                  CRC,
                                                  Comp_Size_64,
                                                  Uncomp_64);
                                          end;
                                          if not Descriptor.Valid
                                            or else Descriptor_Start + Descriptor.Length > Directory_Off
                                          then
                                             return
                                               (Status  => Archive.Archives.Errors.Invalid_Format,
                                                Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
                                          end if;
                                       end if;

                                       Item.Format_Metadata :=
                                         To_Unbounded_String
                                           (ZIP_Metadata
                                              (Flags, Extra_Len, Comment_Len, Unicode_Name.Present,
                                               (Flags and 2048) /= 0,
                                               ZIP64.Present or else Local_ZIP64.Present,
                                               Uses_Data_Descriptor,
                                               Uses_Data_Descriptor and then Descriptor.ZIP64,
                                               (Flags and 1) /= 0,
                                               Method));
                                       Item.Data_Offset :=
                                         (Present => True,
                                          Value => Archive.Types.Source_Offset (Data_Start));
                                    end;
                                 end;
                              end;
                           end;

                           Item.Id := Archive.Types.No_Entry;
                           Item.Ordinal := Archive.Types.Archive_Ordinal (Ordinal);
                           Item.Original_Path := To_Unbounded_String (Name);
                           Item.Display_Name :=
                             To_Unbounded_String
                               (Archive.Archives.Paths.Safe_Display_Name
                                  ((if Unicode_Name.Present
                                    then To_String (Unicode_Name.Path)
                                    else Name)));
                           if Comment_Len > 0 then
                              Item.Comment := To_Unbounded_String
                                (Name_At (Directory_Bytes, Comment_Offset, Comment_Len));
                           end if;
                           Item.CRC32 := (Present => True, Value => Archive.Types.CRC32_Value (CRC));
                           Item.Kind :=
                             (if Is_Directory_Name (Name)
                              then Archive.Archives.Entries.Directory
                              else Archive.Archives.Entries.Regular_File);
                           Item.Compressed :=
                             (Present => True, Value => Archive.Types.Uncompressed_Size (Comp_Size_64));
                           Item.Uncompressed :=
                             (Present => True, Value => Archive.Types.Uncompressed_Size (Uncomp_64));
                           Item.Method := Compression_For (Method);
                           Item.Encryption :=
                             (if (Flags and 1) /= 0
                              then Archive.Archives.Entries.Encrypted
                              else Archive.Archives.Entries.Not_Encrypted);
                           Item.Integrity :=
                             (if CRC = 0 and then Uncomp_64 = 0
                              then Archive.Archives.Entries.Not_Available
                              else Archive.Archives.Entries.Not_Checked);
                           Item.Safety := Archive.Archives.Paths.Normalize (Name).Safety;
                           Result.Entries.Append (Item);
                        end;

                        Cursor := Header_End + Name_Len + Extra_Len + Comment_Len;
                     end;
                  end loop;

                  if Cursor /= Directory_Size then
                     Result.Status := Archive.Archives.Errors.Invalid_Format;
                  end if;
               end;
            end;

            return Result;
         end;
      end;
   exception
      when others =>
         return
           (Status  => Archive.Archives.Errors.Read_Failed,
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
      use type Archive.Types.CRC32_Value;
      File : Ada.Streams.Stream_IO.File_Type;
      Chunk_Size : constant Natural := 32_768;
   begin
      if Item.Encryption = Archive.Archives.Entries.Encrypted then
         return (Status => Archive.Archives.Errors.Unsupported_Method,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      elsif Item.Method not in Archive.Archives.Entries.Zip_Stored
        | Archive.Archives.Entries.Zip_Deflate
        | Archive.Archives.Entries.BZip2_Compression
        | Archive.Archives.Entries.LZMA_Compression
        | Archive.Archives.Entries.Zstd_Compression
      then
         return (Status => Archive.Archives.Errors.Unsupported_Method,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      elsif not Item.Data_Offset.Present or else not Item.Compressed.Present then
         return (Status => Archive.Archives.Errors.Invalid_Format,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      elsif Item.Compressed.Value > Archive.Types.Uncompressed_Size (Natural'Last) then
         return (Status => Archive.Archives.Errors.Limit_Exceeded,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      end if;

      if Item.Method = Archive.Archives.Entries.Zip_Deflate then
         declare
            Offset : constant Natural := Natural (Item.Data_Offset.Value);
            Count  : constant Natural := Natural (Item.Compressed.Value);
            Source_Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
            Remaining : Natural := Count;
            Written : Archive.Types.Uncompressed_Size := 0;
            CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
            Stream : Archive.Compression.Zlib.Inflate_Stream;
            Close_Status : Archive.Compression.Zlib.Stream_Close_Result;

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

            function Emit
              (Step : Archive.Compression.Zlib.Stream_Step_Result)
               return Stream_Result
            is
               Continue : Boolean := True;
            begin
               if Step.Status /= Archive.Archives.Errors.Ok then
                  return
                    (Status => Step.Status,
                     Integrity =>
                       (if Step.Status = Archive.Archives.Errors.Limit_Exceeded
                        then Archive.Archives.Entries.Not_Available
                        else Archive.Archives.Entries.Failed),
                     Bytes_Written => Written);
               elsif Step.Bytes'Length > 0 then
                  Archive.Verification.CRC32.Update (CRC, Step.Bytes);
                  Consumer.all (Step.Bytes, Continue);
                  Written := Written + Archive.Types.Uncompressed_Size (Step.Bytes'Length);
                  if not Continue then
                     return
                       (Status => Archive.Archives.Errors.Cancelled,
                        Integrity => Archive.Archives.Entries.Not_Available,
                        Bytes_Written => Written);
                  end if;
               end if;

               return
                 (Status => Archive.Archives.Errors.Ok,
                  Integrity => Archive.Archives.Entries.Not_Checked,
                  Bytes_Written => Written);
            end Emit;
         begin
            if Ada.Directories.File_Size (Offset) > Source_Size
              or else Ada.Directories.File_Size (Count) >
                Source_Size - Ada.Directories.File_Size (Offset)
            then
               return (Status => Archive.Archives.Errors.Invalid_Format,
                       Integrity => Archive.Archives.Entries.Not_Available,
                       Bytes_Written => 0);
            end if;

            Archive.Compression.Zlib.Open
              (Stream,
               Archive.Compression.Zlib.Raw_Deflate,
               Limits =>
                 (Max_Output_Bytes =>
                    (if Item.Uncompressed.Present
                     then Item.Uncompressed.Value
                     else Archive.Types.Uncompressed_Size
                       (Archive.Resource_Limits.Default_Configured
                          (Archive.Resource_Limits.Preview_Output_Bytes))),
                  Max_Ratio => 1_000));

            Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
            Ada.Streams.Stream_IO.Set_Index
              (File, Ada.Streams.Stream_IO.Positive_Count (Offset + 1));

            while Remaining > 0 loop
               declare
                  This_Count : constant Natural := Natural'Min (Chunk_Size, Remaining);
                  Raw : Ada.Streams.Stream_Element_Array
                    (1 .. Ada.Streams.Stream_Element_Offset (This_Count));
                  Last : Ada.Streams.Stream_Element_Offset := 0;
                  Chunk : Zlib.Byte_Array (1 .. This_Count);
               begin
                  Ada.Streams.Stream_IO.Read (File, Raw, Last);
                  if Natural (Last) /= This_Count then
                     Ada.Streams.Stream_IO.Close (File);
                     Close_Status := Archive.Compression.Zlib.Close (Stream);
                     return (Status => Archive.Archives.Errors.Read_Failed,
                             Integrity => Archive.Archives.Entries.Not_Available,
                             Bytes_Written => Written);
                  end if;

                  for Index in Chunk'Range loop
                     Chunk (Index) := Zlib.Byte
                       (Raw (Ada.Streams.Stream_Element_Offset (Index)));
                  end loop;

                  declare
                     Emitted : constant Stream_Result := Emit
                       (Archive.Compression.Zlib.Append_Chunks
                          (Stream, Chunk, Forward_Output'Access));
                  begin
                     if Emitted.Status /= Archive.Archives.Errors.Ok then
                        Ada.Streams.Stream_IO.Close (File);
                        Close_Status := Archive.Compression.Zlib.Close (Stream);
                        return Emitted;
                     end if;
                  end;

                  Remaining := Remaining - This_Count;
               end;
            end loop;

            Ada.Streams.Stream_IO.Close (File);

            declare
               Finished : constant Stream_Result := Emit
                 (Archive.Compression.Zlib.Finish_Chunks (Stream, Forward_Output'Access));
            begin
               if Finished.Status /= Archive.Archives.Errors.Ok then
                  Close_Status := Archive.Compression.Zlib.Close (Stream);
                  return Finished;
               end if;
            end;

            Close_Status := Archive.Compression.Zlib.Close (Stream);
            if Close_Status.Status /= Archive.Archives.Errors.Ok
              or else not Close_Status.Stream_Ended
            then
               return (Status => Archive.Archives.Errors.Invalid_Format,
                       Integrity => Archive.Archives.Entries.Failed,
                       Bytes_Written => Written);
            elsif Item.Uncompressed.Present
              and then Written /= Item.Uncompressed.Value
            then
               return (Status => Archive.Archives.Errors.Invalid_Format,
                       Integrity => Archive.Archives.Entries.Failed,
                       Bytes_Written => Written);
            elsif Item.CRC32.Present
              and then Archive.Verification.CRC32.Final (CRC) /= Item.CRC32.Value
            then
               return (Status => Archive.Archives.Errors.Invalid_Format,
                       Integrity => Archive.Archives.Entries.Failed,
                       Bytes_Written => Written);
            end if;

            return (Status => Archive.Archives.Errors.Ok,
                    Integrity => Archive.Archives.Entries.Verified,
                    Bytes_Written => Written);
         end;
      end if;

      if Item.Method /= Archive.Archives.Entries.Zip_Stored then
         declare
            Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
         begin
            if Size > Ada.Directories.File_Size (Natural'Last)
              or else Size > Ada.Directories.File_Size
                (Archive.Resource_Limits.Default_Configured
                   (Archive.Resource_Limits.Temporary_Backing_Bytes))
            then
               return (Status => Archive.Archives.Errors.Limit_Exceeded,
                       Integrity => Archive.Archives.Entries.Not_Available,
                       Bytes_Written => 0);
            end if;
         end;

         declare
            Source : constant Archive.Archives.Streams.Buffered_Source :=
              Archive.Archives.Streams.Read_Bounded
                (Path, Positive'Max (1, Positive (Ada.Directories.Size (Path))));
            Status : Zlib.Status_Code := Zlib.Ok;
         begin
            if Source.Status /= Archive.Archives.Errors.Ok then
               return (Status => Source.Status,
                       Integrity => Archive.Archives.Entries.Not_Available,
                       Bytes_Written => 0);
            end if;

            declare
               Payload : constant Zlib.Byte_Array :=
                 Zlib.Extract_ZIP_External_Entry
                   (Source.Bytes, To_String (Item.Original_Path), "", Status);
               Continue : Boolean := True;
               CRC : Archive.Verification.CRC32.CRC32_State :=
                 Archive.Verification.CRC32.Initial;
            begin
               if Status /= Zlib.Ok then
                  return (Status => Map_Zlib_Status (Status),
                          Integrity => Archive.Archives.Entries.Failed,
                          Bytes_Written => 0);
               elsif Item.Uncompressed.Present
                 and then Archive.Types.Uncompressed_Size (Payload'Length) /=
                   Item.Uncompressed.Value
               then
                  return (Status => Archive.Archives.Errors.Invalid_Format,
                          Integrity => Archive.Archives.Entries.Failed,
                          Bytes_Written => Archive.Types.Uncompressed_Size (Payload'Length));
               end if;

               Archive.Verification.CRC32.Update (CRC, Payload);
               if Item.CRC32.Present
                 and then Archive.Verification.CRC32.Final (CRC) /= Item.CRC32.Value
               then
                  return (Status => Archive.Archives.Errors.Invalid_Format,
                          Integrity => Archive.Archives.Entries.Failed,
                          Bytes_Written => Archive.Types.Uncompressed_Size (Payload'Length));
               end if;

               Consumer.all (Payload, Continue);
               return
                 (Status =>
                    (if Continue then Archive.Archives.Errors.Ok else Archive.Archives.Errors.Cancelled),
                  Integrity =>
                    (if Continue
                     then Archive.Archives.Entries.Verified
                     else Archive.Archives.Entries.Not_Available),
                  Bytes_Written => Archive.Types.Uncompressed_Size (Payload'Length));
            end;
         end;
      end if;

      declare
         Offset : constant Natural := Natural (Item.Data_Offset.Value);
         Count  : constant Natural := Natural (Item.Compressed.Value);
         Source_Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
         Remaining : Natural := Count;
         Written : Archive.Types.Uncompressed_Size := 0;
         CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
      begin
         if Ada.Directories.File_Size (Offset) > Source_Size
           or else Ada.Directories.File_Size (Count) >
             Source_Size - Ada.Directories.File_Size (Offset)
         then
            return (Status => Archive.Archives.Errors.Invalid_Format,
                    Integrity => Archive.Archives.Entries.Not_Available,
                    Bytes_Written => 0);
         end if;

         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Set_Index
           (File, Ada.Streams.Stream_IO.Positive_Count (Offset + 1));

         while Remaining > 0 loop
            declare
               This_Count : constant Natural := Natural'Min (Chunk_Size, Remaining);
               Raw : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (This_Count));
               Last : Ada.Streams.Stream_Element_Offset := 0;
               Chunk : Zlib.Byte_Array (1 .. This_Count);
               Continue : Boolean := True;
            begin
               Ada.Streams.Stream_IO.Read (File, Raw, Last);
               if Natural (Last) /= This_Count then
                  Ada.Streams.Stream_IO.Close (File);
                  return (Status => Archive.Archives.Errors.Read_Failed,
                          Integrity => Archive.Archives.Entries.Not_Available,
                          Bytes_Written => Written);
               end if;

               for Index in Chunk'Range loop
                  Chunk (Index) := Zlib.Byte
                    (Raw (Ada.Streams.Stream_Element_Offset (Index)));
               end loop;

               Archive.Verification.CRC32.Update (CRC, Chunk);
               Consumer.all (Chunk, Continue);
               Written := Written + Archive.Types.Uncompressed_Size (Chunk'Length);
               Remaining := Remaining - This_Count;

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
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status => Archive.Archives.Errors.Read_Failed,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
   end Stream_Payload_File;
end Archive.Archives.Readers.Zip;
