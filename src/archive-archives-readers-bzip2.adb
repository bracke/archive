with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Unbounded;

with Archive.Archives.Paths;
with Archive.Archives.Streams;
with Zlib.BZip2_Decoder;

package body Archive.Archives.Readers.BZip2 is
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
      Name : constant String := (if Source_Name'Length > 0 then Source_Name else "payload.bz2");
   begin
      if Has_Suffix (Name, ".bzip2") and then Name'Length > 6 then
         declare
            Candidate : constant String := Name (Name'First .. Name'Last - 6);
         begin
            if Safe_Name (Candidate) /= "" then
               return Candidate;
            end if;
         end;
      elsif Has_Suffix (Name, ".bz2") and then Name'Length > 4 then
         declare
            Candidate : constant String := Name (Name'First .. Name'Last - 4);
         begin
            if Safe_Name (Candidate) /= "" then
               return Candidate;
            end if;
         end;
      end if;
      return "bzip2-payload";
   end Logical_Name;

   function Decode_File
     (Path      : String;
      Max_Bytes : Positive;
      Status    : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      Source : constant Archive.Archives.Streams.Buffered_Source :=
        Archive.Archives.Streams.Read_Bounded
          (Path, Effective_Read_Limit (Path, Max_Bytes));
   begin
      if Source.Status /= Archive.Archives.Errors.Ok then
         Status := Zlib.Input_File_Error;
         return [];
      end if;

      return Zlib.BZip2_Decoder.Decode (Source.Bytes, Status);
   end Decode_File;

   function Index_File
     (Path        : String;
      Max_Bytes   : Positive := 256 * 1_024 * 1_024;
      Source_Name : String := "")
      return BZip2_Index_Result
   is
      Status : Zlib.Status_Code := Zlib.Ok;
      Payload : constant Zlib.Byte_Array := Decode_File (Path, Max_Bytes, Status);
      Name : constant String :=
        Logical_Name ((if Source_Name'Length > 0 then Source_Name else Path));
      Result : BZip2_Index_Result;
   begin
      Result.Status := Map_Status (Status);
      if Result.Status /= Archive.Archives.Errors.Ok then
         return Result;
      end if;

      Result.Item.Original_Path := To_Unbounded_String (Name);
      Result.Item.Display_Name := To_Unbounded_String (Name);
      Result.Item.Kind := Archive.Archives.Entries.Regular_File;
      Result.Item.Method := Archive.Archives.Entries.BZip2_Compression;
      Result.Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
      Result.Item.Integrity := Archive.Archives.Entries.Not_Checked;
      Result.Item.Safety := Archive.Archives.Paths.Normalize (Name).Safety;
      Result.Item.Uncompressed :=
        (Present => True,
         Value => Archive.Types.Uncompressed_Size (Payload'Length));
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
      Status : Zlib.Status_Code := Zlib.Ok;
      Payload : constant Zlib.Byte_Array := Decode_File (Path, Max_Bytes, Status);
      Continue : Boolean := True;
   begin
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
          Archive.Types.Uncompressed_Size (Payload'Length)
      then
         return
           (Status        => Archive.Archives.Errors.Invalid_Format,
            Integrity     => Archive.Archives.Entries.Failed,
            Bytes_Written => 0);
      end if;

      Consumer.all (Payload, Continue);
      return
        (Status        =>
           (if Continue then Archive.Archives.Errors.Ok else Archive.Archives.Errors.Cancelled),
         Integrity     =>
           (if Continue then Archive.Archives.Entries.Verified else Archive.Archives.Entries.Not_Checked),
         Bytes_Written => Archive.Types.Uncompressed_Size (Payload'Length));
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
end Archive.Archives.Readers.BZip2;
