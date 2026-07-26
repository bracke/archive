with Ada.Directories;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Streams;

package body Archive.Archives.Readers.Seven_Zip is
   use Ada.Strings.Unbounded;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Ada.Directories.File_Size;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Types.Archive_Ordinal;
   use type Zlib.Status_Code;

   function Map_Status
     (Status : Zlib.Status_Code)
      return Archive.Archives.Errors.Error_Code
   is
   begin
      case Status is
         when Zlib.Ok =>
            return Archive.Archives.Errors.Ok;
         when Zlib.Unsupported_Method =>
            return Archive.Archives.Errors.Unsupported_Method;
         when Zlib.Unexpected_End_Of_Input | Zlib.Invalid_Header
            | Zlib.Invalid_Block_Type | Zlib.Invalid_Checksum =>
            return Archive.Archives.Errors.Invalid_Format;
         when Zlib.Input_File_Error =>
            return Archive.Archives.Errors.Read_Failed;
         when Zlib.Output_File_Error =>
            return Archive.Archives.Errors.Write_Failed;
         when others =>
            return Archive.Archives.Errors.Zlib_Failed;
      end case;
   end Map_Status;

   function Size_Of (Value : Interfaces.Unsigned_64) return Archive.Types.Optional_Size is
   begin
      return
        (Present => True,
         Value   => Archive.Types.Uncompressed_Size (Value));
   end Size_Of;

   function CRC_Of (Value : Interfaces.Unsigned_32) return Archive.Types.Optional_CRC32 is
   begin
      return
        (Present => True,
         Value   => Archive.Types.CRC32_Value (Value));
   end CRC_Of;

   function Name_Looks_Directory (Name : String) return Boolean is
   begin
      return Name'Length > 0
        and then (Name (Name'Last) = '/' or else Name (Name'Last) = '\');
   end Name_Looks_Directory;

   function Effective_Read_Limit
     (Path      : String;
      Max_Bytes : Positive)
      return Positive
   is
      Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
   begin
      if Size = 0 then
         return 1;
      elsif Size > Ada.Directories.File_Size (Max_Bytes) then
         return Max_Bytes;
      elsif Size > Ada.Directories.File_Size (Positive'Last) then
         return Max_Bytes;
      else
         return Positive (Size);
      end if;
   exception
      when others =>
         return Max_Bytes;
   end Effective_Read_Limit;

   function Index_File
     (Path      : String;
      Max_Bytes : Positive := 256 * 1_024 * 1_024)
      return Seven_Zip_Index_Result
   is
      Source : constant Archive.Archives.Streams.Buffered_Source :=
        Archive.Archives.Streams.Read_Bounded
          (Path, Effective_Read_Limit (Path, Max_Bytes));
      Status : Zlib.Status_Code := Zlib.Ok;
      Result : Seven_Zip_Index_Result;
   begin
      if Source.Status /= Archive.Archives.Errors.Ok then
         Result.Status := Source.Status;
         return Result;
      end if;

      declare
         Listed : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Seven_Zip_Entries (Source.Bytes, Status);
         Ordinal : Archive.Types.Archive_Ordinal := 0;
      begin
         Result.Status := Map_Status (Status);
         if Result.Status /= Archive.Archives.Errors.Ok then
            return Result;
         end if;

         for Native of Listed loop
            Ordinal := Ordinal + 1;
            declare
               Name : constant String := To_String (Native.Name);
               Item : Archive.Archives.Entries.Archive_Entry;
            begin
               Item.Ordinal := Ordinal;
               Item.Original_Path := To_Unbounded_String (Name);
               Item.Display_Name := To_Unbounded_String (Name);
               Item.Kind :=
                 (if Native.Is_Directory and then Name_Looks_Directory (Name)
                  then Archive.Archives.Entries.Directory
                  else Archive.Archives.Entries.Regular_File);
               Item.Compressed := Size_Of (Native.Compressed_Size);
               Item.Uncompressed := Size_Of (Native.Uncompressed_Size);
               Item.CRC32 := CRC_Of (Native.CRC_32);
               Item.Method := Archive.Archives.Entries.Unknown_Compression;
               Item.Encryption := Archive.Archives.Entries.Unknown_Encryption;
               Item.Integrity := Archive.Archives.Entries.Not_Checked;
               Item.Format_Metadata :=
                 To_Unbounded_String
                   ("7z.compression=" & Interfaces.Unsigned_16'Image (Native.Compression));
               Result.Entries.Append (Item);
            end;
         end loop;
      end;

      return Result;
   end Index_File;

   function Stream_Payload_File
     (Path      : String;
      Max_Bytes : Positive;
      Item      : Archive.Archives.Entries.Archive_Entry;
      Consumer  : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      Source : constant Archive.Archives.Streams.Buffered_Source :=
        Archive.Archives.Streams.Read_Bounded
          (Path, Effective_Read_Limit (Path, Max_Bytes));
      Status : Zlib.Status_Code := Zlib.Ok;
      Continue : Boolean := True;
   begin
      if Source.Status /= Archive.Archives.Errors.Ok then
         return
           (Status        => Source.Status,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      elsif Item.Kind = Archive.Archives.Entries.Directory then
         return
           (Status        => Archive.Archives.Errors.Ok,
            Integrity     => Archive.Archives.Entries.Verified,
            Bytes_Written => 0);
      elsif To_String (Item.Original_Path) = "" then
         return
           (Status        => Archive.Archives.Errors.Invalid_Format,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      end if;

      declare
         Payload : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip
             (Source.Bytes, To_String (Item.Original_Path), Status);
      begin
         if Status /= Zlib.Ok then
            return
              (Status        => Map_Status (Status),
               Integrity     => Archive.Archives.Entries.Failed,
               Bytes_Written => 0);
         end if;

         Consumer.all (Payload, Continue);
         return
           (Status        =>
              (if Continue
               then Archive.Archives.Errors.Ok
               else Archive.Archives.Errors.Cancelled),
            Integrity     =>
              (if Continue
               then Archive.Archives.Entries.Verified
               else Archive.Archives.Entries.Not_Checked),
            Bytes_Written => Archive.Types.Uncompressed_Size (Payload'Length));
      end;
   exception
      when Storage_Error =>
         return
           (Status        => Archive.Archives.Errors.Limit_Exceeded,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      when others =>
         return
           (Status        => Archive.Archives.Errors.Zlib_Failed,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
   end Stream_Payload_File;
end Archive.Archives.Readers.Seven_Zip;
