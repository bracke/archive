with Ada.Directories;
with Ada.Strings.Unbounded;

with Archive.Archives.Readers.Gzip;
with Archive.Archives.Readers.Seven_Zip;
with Archive.Archives.Readers.Tar;
with Archive.Archives.Readers.Zip;
with Archive.Writes.Execution;

package body Archive.Archives.Readers.Dispatch is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Formats.Detection_Status;
   use type Archive.Archives.Formats.Format_Id;

   Detection_Probe_Bytes : constant Positive := 32_774;

   function Lower (Value : String) return String is
      Result : String := Value;
   begin
      for C of Result loop
         if C in 'A' .. 'Z' then
            C := Character'Val (Character'Pos (C) + Character'Pos ('a') - Character'Pos ('A'));
         end if;
      end loop;
      return Result;
   end Lower;

   function Has_Suffix (Value : String; Suffix : String) return Boolean is
      L : constant String := Lower (Value);
   begin
      return L'Length >= Suffix'Length
        and then L (L'Last - Suffix'Length + 1 .. L'Last) = Suffix;
   end Has_Suffix;

   function Looks_Like_Tar_Gzip (Source_Name : String) return Boolean is
   begin
      return Has_Suffix (Source_Name, ".tar.gz")
        or else Has_Suffix (Source_Name, ".tgz");
   end Looks_Like_Tar_Gzip;

   function Tar_Backing_Path (Path : String) return String is
      Size_Image : constant String := Ada.Directories.File_Size'Image (Ada.Directories.Size (Path));
      Hash       : Natural := 0;
   begin
      for C of Path loop
         Hash := (Hash * 131 + Character'Pos (C)) mod 1_000_000_007;
      end loop;

      return "/tmp/archive-open-tar-"
        & (if Size_Image (Size_Image'First) = ' '
           then Size_Image (Size_Image'First + 1 .. Size_Image'Last)
           else Size_Image)
        & "-" & Natural'Image (Hash)
        & ".tmp";
   exception
      when others =>
         return "/tmp/archive-open-tar.tmp";
   end Tar_Backing_Path;

   function Open_File
     (Path      : String;
      Max_Bytes : Positive := 256 * 1_024 * 1_024;
      Source_Name : String := "";
      Retain_Backing : Boolean := False)
      return Open_Result
   is
      Detection : constant Archive.Archives.Formats.Detection_Result :=
        Archive.Archives.Formats.Detect_File (Path, Detection_Probe_Bytes);
      Result : Open_Result;
   begin
         Result.Format := Detection.Format;

         if Detection.Status = Archive.Archives.Formats.Recognized_Unsupported then
            Result.Status := Archive.Archives.Errors.Unsupported_Format;
            return Result;
         elsif Detection.Status /= Archive.Archives.Formats.Detected then
            Result.Status := Archive.Archives.Errors.Invalid_Format;
            return Result;
         end if;

         if Detection.Format = Archive.Archives.Formats.Tar_Format then
            declare
               Parsed : constant Archive.Archives.Readers.Tar.Tar_Index_Result :=
                 Archive.Archives.Readers.Tar.Index_File (Path);
            begin
               Result.Status := Parsed.Status;
               if Parsed.Status = Archive.Archives.Errors.Ok then
                  Result.Index := Archive.Archives.Index.Build (Parsed.Entries).Index;
               end if;
               return Result;
            end;
         elsif Detection.Format = Archive.Archives.Formats.GZip_Format
           and then Looks_Like_Tar_Gzip
             ((if Source_Name'Length > 0 then Source_Name else Path))
         then
            declare
               Backing : constant String := Tar_Backing_Path (Path);
               Inflate_Status : constant Archive.Archives.Errors.Error_Code :=
                 Archive.Writes.Execution.Stage_Gzip_As_Tar (Path, Backing);
            begin
               Result.Format := Archive.Archives.Formats.Tar_GZip_Format;
               if Inflate_Status /= Archive.Archives.Errors.Ok then
                  Result.Status := Inflate_Status;
                  if Ada.Directories.Exists (Backing) then
                     Ada.Directories.Delete_File (Backing);
                  end if;
                  return Result;
               end if;

               declare
                  Parsed : constant Archive.Archives.Readers.Tar.Tar_Index_Result :=
                    Archive.Archives.Readers.Tar.Index_File (Backing);
               begin
                  Result.Status := Parsed.Status;
                  if Parsed.Status = Archive.Archives.Errors.Ok then
                     Result.Index := Archive.Archives.Index.Build (Parsed.Entries).Index;
                     if Retain_Backing then
                        Result.Backing_Path := To_Unbounded_String (Backing);
                     end if;
                  end if;
               end;

               if (not Retain_Backing or else Result.Status /= Archive.Archives.Errors.Ok)
                 and then Ada.Directories.Exists (Backing)
               then
                  Ada.Directories.Delete_File (Backing);
               end if;
               return Result;
            exception
               when others =>
                  if Ada.Directories.Exists (Backing) then
                     Ada.Directories.Delete_File (Backing);
                  end if;
                  Result.Status := Archive.Archives.Errors.Read_Failed;
                  return Result;
            end;
         elsif Detection.Format = Archive.Archives.Formats.Zip_Format then
            declare
               Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
               Limit : constant Ada.Directories.File_Size :=
                 Ada.Directories.File_Size (Max_Bytes);
            begin
               if Size > Limit
                 or else Size > Ada.Directories.File_Size (Natural'Last)
               then
                  Result.Status := Archive.Archives.Errors.Limit_Exceeded;
                  return Result;
               end if;
            end;

            declare
               Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
                 Archive.Archives.Readers.Zip.Index_File (Path);
            begin
               Result.Status := Parsed.Status;
               if Parsed.Status = Archive.Archives.Errors.Ok then
                  Result.Index := Archive.Archives.Index.Build (Parsed.Entries).Index;
               end if;
               return Result;
            end;
         elsif Detection.Format = Archive.Archives.Formats.Seven_Zip_Format then
            declare
               Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
               Limit : constant Ada.Directories.File_Size :=
                 Ada.Directories.File_Size (Max_Bytes);
            begin
               if Size > Limit
                 or else Size > Ada.Directories.File_Size (Natural'Last)
               then
                  Result.Status := Archive.Archives.Errors.Limit_Exceeded;
                  return Result;
               end if;
            end;

            declare
               Parsed : constant Archive.Archives.Readers.Seven_Zip.Seven_Zip_Index_Result :=
                 Archive.Archives.Readers.Seven_Zip.Index_File (Path, Max_Bytes);
            begin
               Result.Status := Parsed.Status;
               if Parsed.Status = Archive.Archives.Errors.Ok then
                  Result.Index := Archive.Archives.Index.Build (Parsed.Entries).Index;
               end if;
               return Result;
            end;
         elsif Detection.Format = Archive.Archives.Formats.GZip_Format then
            declare
               Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
                 Archive.Archives.Readers.Gzip.Index_File
                   (Path,
                    Source_Name =>
                      (if Source_Name'Length > 0 then Source_Name else Path));
               Entries : Archive.Archives.Entries.Entry_Vectors.Vector;
            begin
               Result.Status := Parsed.Status;
               if Parsed.Status = Archive.Archives.Errors.Ok then
                  Entries.Append (Parsed.Item);
                  Result.Index := Archive.Archives.Index.Build (Entries).Index;
               end if;
               return Result;
            end;
         else
            Result.Status := Archive.Archives.Errors.Unsupported_Format;
            return Result;
         end if;
   end Open_File;

   function Verify_File
     (Path            : String;
      Expected_Format : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format;
      Max_Bytes       : Positive := 256 * 1_024 * 1_024;
      Source_Name     : String := "")
      return Archive.Archives.Errors.Error_Code
   is
      Opened : constant Open_Result := Open_File (Path, Max_Bytes, Source_Name);
   begin
      if Opened.Status /= Archive.Archives.Errors.Ok then
         return Opened.Status;
      elsif Expected_Format /= Archive.Archives.Formats.Unknown_Format
        and then Opened.Format /= Expected_Format
      then
         return Archive.Archives.Errors.Invalid_Format;
      else
         return Archive.Archives.Errors.Ok;
      end if;
   end Verify_File;

   function Stream_Payload_File
     (Path        : String;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry;
      Consumer    : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      Opened : constant Open_Result :=
        Open_File (Path, Source_Name => Source_Name, Retain_Backing => True);
   begin
      if Opened.Status /= Archive.Archives.Errors.Ok then
         return (Status => Opened.Status,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      end if;

      case Opened.Format is
         when Archive.Archives.Formats.Zip_Format =>
            declare
               procedure Forward
                 (Bytes : Zlib.Byte_Array;
                  Continue : in out Boolean) is
               begin
                  Consumer.all (Bytes, Continue);
               end Forward;

               Payload : constant Archive.Archives.Readers.Zip.Stream_Result :=
                 Archive.Archives.Readers.Zip.Stream_Payload_File
                   (Path, Item, Forward'Access);
            begin
               return (Status => Payload.Status,
                       Integrity => Payload.Integrity,
                       Bytes_Written => Payload.Bytes_Written);
            end;

         when Archive.Archives.Formats.Tar_Format =>
            declare
               procedure Forward
                 (Bytes : Zlib.Byte_Array;
                  Continue : in out Boolean) is
               begin
                  Consumer.all (Bytes, Continue);
               end Forward;

               Payload : constant Archive.Archives.Readers.Tar.Stream_Result :=
                 Archive.Archives.Readers.Tar.Stream_Payload_File
                   (Path, Item, Forward'Access);
            begin
               return (Status => Payload.Status,
                       Integrity => Payload.Integrity,
                       Bytes_Written => Payload.Bytes_Written);
            end;

         when Archive.Archives.Formats.Tar_GZip_Format =>
            declare
               procedure Forward
                 (Bytes : Zlib.Byte_Array;
                  Continue : in out Boolean) is
               begin
                  Consumer.all (Bytes, Continue);
               end Forward;

               Payload : constant Archive.Archives.Readers.Tar.Stream_Result :=
                 Archive.Archives.Readers.Tar.Stream_Payload_File
                   (To_String (Opened.Backing_Path), Item, Forward'Access);
            begin
               return (Status => Payload.Status,
                       Integrity => Payload.Integrity,
                       Bytes_Written => Payload.Bytes_Written);
            end;

         when Archive.Archives.Formats.GZip_Format =>
            declare
               procedure Forward
                 (Bytes : Zlib.Byte_Array;
                  Continue : in out Boolean) is
               begin
                  Consumer.all (Bytes, Continue);
               end Forward;

               Payload : constant Archive.Archives.Readers.Gzip.Stream_Result :=
                 Archive.Archives.Readers.Gzip.Stream_Payload_File
                   (Path, Item, Forward'Access);
            begin
               return (Status => Payload.Status,
                       Integrity => Payload.Integrity,
                       Bytes_Written => Payload.Bytes_Written);
            end;

         when Archive.Archives.Formats.Seven_Zip_Format =>
            declare
               procedure Forward
                 (Bytes : Zlib.Byte_Array;
                  Continue : in out Boolean) is
               begin
                  Consumer.all (Bytes, Continue);
               end Forward;

               Payload : constant Archive.Archives.Readers.Seven_Zip.Stream_Result :=
                 Archive.Archives.Readers.Seven_Zip.Stream_Payload_File
                   (Path, 256 * 1_024 * 1_024, Item, Forward'Access);
            begin
               return (Status => Payload.Status,
                       Integrity => Payload.Integrity,
                       Bytes_Written => Payload.Bytes_Written);
            end;

         when others =>
            return (Status => Archive.Archives.Errors.Unsupported_Format,
                    Integrity => Archive.Archives.Entries.Not_Available,
                    Bytes_Written => 0);
      end case;
   end Stream_Payload_File;
end Archive.Archives.Readers.Dispatch;
