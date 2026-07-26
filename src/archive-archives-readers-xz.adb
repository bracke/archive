with Ada.Characters.Handling;
with Ada.Directories;
with Interfaces;
with Ada.Strings.Unbounded;

with Archive.Archives.Paths;

package body Archive.Archives.Readers.Xz is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Types.Uncompressed_Size;
   use type Zlib.Status_Code;

   function Map_Status
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
   end Map_Status;

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
      else
         return Positive (Size);
      end if;
   exception
      when others =>
         return Max_Bytes;
   end Effective_Read_Limit;

   function Has_Suffix (Value : String; Suffix : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Value);
   begin
      return Lower'Length >= Suffix'Length
        and then Lower (Lower'Last - Suffix'Length + 1 .. Lower'Last) = Suffix;
   end Has_Suffix;

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

   function Logical_Name (Source_Name : String) return String is
      Name : constant String := (if Source_Name'Length > 0 then Source_Name else "payload.xz");
   begin
      if Has_Suffix (Name, ".xz") and then Name'Length > 3 then
         declare
            Candidate : constant String := Name (Name'First .. Name'Last - 3);
         begin
            if Safe_Name (Candidate) /= "" then
               return Candidate;
            end if;
         end;
      end if;
      return "xz-payload";
   end Logical_Name;

   procedure Count_Decoded_File
     (Path      : String;
      Max_Bytes : Positive;
      Size      : out Interfaces.Unsigned_64;
      Status    : out Zlib.Status_Code)
   is
      procedure Ignore
        (Bytes    : Zlib.Byte_Array;
         Continue : in out Boolean)
      is
         pragma Unreferenced (Bytes);
      begin
         Continue := True;
      end Ignore;
   begin
      Zlib.XZ_File_To_Consumer
        (Path, Effective_Read_Limit (Path, Max_Bytes), Ignore'Access, Size, Status);
   end Count_Decoded_File;

   function Index_File
     (Path        : String;
      Max_Bytes   : Positive := 256 * 1_024 * 1_024;
      Source_Name : String := "")
      return Xz_Index_Result
   is
      Status       : Zlib.Status_Code := Zlib.Ok;
      Payload_Size : Interfaces.Unsigned_64 := 0;
      Name         : constant String :=
        Logical_Name ((if Source_Name'Length > 0 then Source_Name else Path));
      Result       : Xz_Index_Result;
   begin
      Count_Decoded_File (Path, Max_Bytes, Payload_Size, Status);
      Result.Status := Map_Status (Status);
      if Result.Status /= Archive.Archives.Errors.Ok then
         return Result;
      end if;

      Result.Item.Original_Path := To_Unbounded_String (Name);
      Result.Item.Display_Name := To_Unbounded_String (Name);
      Result.Item.Kind := Archive.Archives.Entries.Regular_File;
      Result.Item.Method := Archive.Archives.Entries.LZMA_Compression;
      Result.Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
      Result.Item.Integrity := Archive.Archives.Entries.Not_Checked;
      Result.Item.Safety := Archive.Archives.Paths.Normalize (Name).Safety;
      Result.Item.Uncompressed :=
        (Present => True,
         Value => Archive.Types.Uncompressed_Size (Payload_Size));
      Result.Item.Compressed :=
        (Present => True,
         Value => Archive.Types.Uncompressed_Size (Ada.Directories.Size (Path)));
      return Result;
   exception
      when Storage_Error =>
         return (Status => Archive.Archives.Errors.Limit_Exceeded, Item => <>);
      when others =>
         return (Status => Archive.Archives.Errors.Read_Failed, Item => <>);
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
      Status       : Zlib.Status_Code := Zlib.Ok;
      Continue     : Boolean := True;
      Payload_Size : Interfaces.Unsigned_64 := 0;

      procedure Forward
        (Bytes      : Zlib.Byte_Array;
         Keep_Going : in out Boolean) is
      begin
         if Continue then
            Consumer.all (Bytes, Continue);
         end if;
         Keep_Going := Continue;
      end Forward;
   begin
      Count_Decoded_File (Path, Max_Bytes, Payload_Size, Status);
      if Status /= Zlib.Ok then
         return
           (Status        => Map_Status (Status),
            Integrity     => Archive.Archives.Entries.Failed,
            Bytes_Written => 0);
      elsif Item.Kind /= Archive.Archives.Entries.Regular_File then
         return
           (Status        => Archive.Archives.Errors.Unsupported_Method,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      elsif Item.Uncompressed.Present
        and then Item.Uncompressed.Value /=
          Archive.Types.Uncompressed_Size (Payload_Size)
      then
         return
           (Status        => Archive.Archives.Errors.Invalid_Format,
            Integrity     => Archive.Archives.Entries.Failed,
            Bytes_Written => 0);
      end if;

      Zlib.XZ_File_To_Consumer
        (Path, Effective_Read_Limit (Path, Max_Bytes), Forward'Access,
         Payload_Size, Status);
      if Status /= Zlib.Ok then
         return
           (Status        => Map_Status (Status),
            Integrity     => Archive.Archives.Entries.Failed,
            Bytes_Written => 0);
      end if;

      return
        (Status        =>
           (if Continue then Archive.Archives.Errors.Ok else Archive.Archives.Errors.Cancelled),
         Integrity     =>
           (if Continue then Archive.Archives.Entries.Verified else Archive.Archives.Entries.Not_Checked),
         Bytes_Written => Archive.Types.Uncompressed_Size (Payload_Size));
   exception
      when Storage_Error =>
         return
           (Status        => Archive.Archives.Errors.Limit_Exceeded,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      when others =>
         return
           (Status        => Archive.Archives.Errors.Read_Failed,
            Integrity     => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
   end Stream_Payload_File;
end Archive.Archives.Readers.Xz;
