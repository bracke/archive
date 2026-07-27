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

   function Is_First_Volume_Path (Path : String) return Boolean is
   begin
      return Path'Length >= 4
        and then Path (Path'Last - 3 .. Path'Last) = ".001";
   end Is_First_Volume_Path;

   function Volume_Suffix (N : Positive) return String is
      Hundreds : constant Natural := (N / 100) mod 10;
      Tens     : constant Natural := (N / 10) mod 10;
      Ones     : constant Natural := N mod 10;
   begin
      return
        Character'Val (Character'Pos ('0') + Hundreds)
        & Character'Val (Character'Pos ('0') + Tens)
        & Character'Val (Character'Pos ('0') + Ones);
   end Volume_Suffix;

   function Volume_Path (First_Volume_Path : String; N : Positive) return String is
   begin
      if N = 1 or else not Is_First_Volume_Path (First_Volume_Path) then
         return First_Volume_Path;
      end if;

      return First_Volume_Path (First_Volume_Path'First .. First_Volume_Path'Last - 3)
        & Volume_Suffix (N);
   end Volume_Path;

   function Volumes_Within_Limit
     (First_Volume_Path : String;
      Max_Bytes         : Positive)
      return Boolean
   is
      Limit : constant Ada.Directories.File_Size :=
        Ada.Directories.File_Size (Max_Bytes);
      Total : Ada.Directories.File_Size := 0;
   begin
      for N in 1 .. 999 loop
         declare
            Path : constant String := Volume_Path (First_Volume_Path, N);
         begin
            exit when N > 1 and then not Ada.Directories.Exists (Path);
            if not Ada.Directories.Exists (Path) then
               return False;
            end if;

            declare
               Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
            begin
               if Size > Limit or else Total > Limit - Size then
                  return False;
               end if;
               Total := Total + Size;
            end;
         end;
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Volumes_Within_Limit;

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

   function Load_File_Image
     (Path      : String;
      Max_Bytes : Positive;
      Status    : out Archive.Archives.Errors.Error_Code)
      return Zlib.Byte_Array
   is
      Source : constant Archive.Archives.Streams.Buffered_Source :=
        Archive.Archives.Streams.Read_Bounded
          (Path, Effective_Read_Limit (Path, Max_Bytes));
   begin
      Status := Source.Status;
      return Source.Bytes;
   end Load_File_Image;

   function Load_Volume_Image
     (First_Volume_Path : String;
      Max_Bytes         : Positive;
      Status            : out Archive.Archives.Errors.Error_Code)
      return Zlib.Byte_Array
   is
      Z_Status : Zlib.Status_Code := Zlib.Ok;
   begin
      if not Volumes_Within_Limit (First_Volume_Path, Max_Bytes) then
         Status := Archive.Archives.Errors.Limit_Exceeded;
         return [1 .. 0 => 0];
      end if;

      declare
         Image : constant Zlib.Byte_Array :=
           Zlib.Read_Seven_Zip_Volumes (First_Volume_Path, Z_Status);
      begin
         Status := Map_Status (Z_Status);
         if Status = Archive.Archives.Errors.Ok
           and then Image'Length > Max_Bytes
         then
            Status := Archive.Archives.Errors.Limit_Exceeded;
            return [1 .. 0 => 0];
         end if;
         return Image;
      end;
   exception
      when Storage_Error =>
         Status := Archive.Archives.Errors.Limit_Exceeded;
         return [1 .. 0 => 0];
      when others =>
         Status := Archive.Archives.Errors.Read_Failed;
         return [1 .. 0 => 0];
   end Load_Volume_Image;

   function Index_Image (Archive_Image : Zlib.Byte_Array) return Seven_Zip_Index_Result is
      Status : Zlib.Status_Code := Zlib.Ok;
      Result : Seven_Zip_Index_Result;
   begin
      declare
         Listed : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Seven_Zip_Entries (Archive_Image, Status);
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
   end Index_Image;

   function Index_File
     (Path      : String;
      Max_Bytes : Positive := 256 * 1_024 * 1_024)
      return Seven_Zip_Index_Result
   is
      Load_Status : Archive.Archives.Errors.Error_Code;
      Image       : constant Zlib.Byte_Array :=
        Load_File_Image (Path, Max_Bytes, Load_Status);
   begin
      if Load_Status /= Archive.Archives.Errors.Ok then
         return (Status => Load_Status,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      return Index_Image (Image);
   end Index_File;

   function Index_Volume_File
     (First_Volume_Path : String;
      Max_Bytes         : Positive := 256 * 1_024 * 1_024)
      return Seven_Zip_Index_Result
   is
      Load_Status : Archive.Archives.Errors.Error_Code;
      Image       : constant Zlib.Byte_Array :=
        Load_Volume_Image (First_Volume_Path, Max_Bytes, Load_Status);
   begin
      if Load_Status /= Archive.Archives.Errors.Ok then
         return (Status => Load_Status,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      return Index_Image (Image);
   end Index_Volume_File;

   function Stream_Payload_Image
     (Archive_Image : Zlib.Byte_Array;
      Item          : Archive.Archives.Entries.Archive_Entry;
      Consumer      : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean);
      Password      : String := "")
      return Stream_Result
   is
      Status : Zlib.Status_Code := Zlib.Ok;
      Continue : Boolean := True;
   begin
      if Item.Kind = Archive.Archives.Entries.Directory then
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
           (if Password'Length > 0
            then Zlib.Extract_Seven_Zip
              (Archive_Image, To_String (Item.Original_Path), Password, Status)
            else Zlib.Extract_Seven_Zip
              (Archive_Image, To_String (Item.Original_Path), Status));
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
   end Stream_Payload_Image;

   function Stream_Payload_File
     (Path      : String;
      Max_Bytes : Positive;
      Item      : Archive.Archives.Entries.Archive_Entry;
      Consumer  : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean);
      Password  : String := "")
      return Stream_Result
   is
      Load_Status : Archive.Archives.Errors.Error_Code;
      Image       : constant Zlib.Byte_Array :=
        Load_File_Image (Path, Max_Bytes, Load_Status);
   begin
      if Load_Status /= Archive.Archives.Errors.Ok then
         return
           (Status        => Load_Status,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      end if;

      return Stream_Payload_Image (Image, Item, Consumer, Password => Password);
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

   function Stream_Payload_Volume_File
     (First_Volume_Path : String;
      Max_Bytes         : Positive;
      Item              : Archive.Archives.Entries.Archive_Entry;
      Consumer          : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean);
      Password          : String := "")
      return Stream_Result
   is
      Load_Status : Archive.Archives.Errors.Error_Code;
      Image       : constant Zlib.Byte_Array :=
        Load_Volume_Image (First_Volume_Path, Max_Bytes, Load_Status);
   begin
      if Load_Status /= Archive.Archives.Errors.Ok then
         return
           (Status        => Load_Status,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      end if;

      return Stream_Payload_Image (Image, Item, Consumer, Password => Password);
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
   end Stream_Payload_Volume_File;
end Archive.Archives.Readers.Seven_Zip;
