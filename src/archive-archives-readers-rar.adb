with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Readers.Zlib_Bridge;

package body Archive.Archives.Readers.Rar is
   use Ada.Strings.Unbounded;
   use type Archive.Types.Archive_Ordinal;
   use type Archive.Types.Uncompressed_Size;
   use type Interfaces.Unsigned_16;
   use type Zlib.Status_Code;

   package Bridge renames Archive.Archives.Readers.Zlib_Bridge;

   --  Parsing lives in Zlib.Rar_Reader; this body maps zlib's neutral listing
   --  onto the app's Archive_Entry (restoring the compression and encryption
   --  state) and streams a stored member by name. zlib reports Compression 0
   --  for a stored member and the raw RAR method id otherwise.

   function Index_File (Path : String) return Rar_Index_Result is
      Status  : Zlib.Status_Code := Zlib.Invalid_Header;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
      Result  : Rar_Index_Result;
   begin
      declare
         Items : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Rar_File_Entries (Path, Status);
      begin
         Result.Status := Bridge.To_Error (Status);
         if Status /= Zlib.Ok then
            return Result;
         end if;

         for Item of Items loop
            declare
               E    : Archive.Archives.Entries.Archive_Entry :=
                 Bridge.Base_Entry (Item, Ordinal);
               Meta : constant String := To_String (E.Format_Metadata);
            begin
               E.Method :=
                 (if Item.Compression = 0
                  then Archive.Archives.Entries.No_Compression
                  else Archive.Archives.Entries.Unsupported_Compression);
               if Bridge.Meta_Value (Meta, "rar.encrypted") = "1" then
                  E.Encryption := Archive.Archives.Entries.Encrypted;
               end if;
               Result.Entries.Append (E);
               Ordinal := Ordinal + 1;
            end;
         end loop;
      end;
      return Result;
   end Index_File;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      Status    : Zlib.Status_Code := Zlib.Invalid_Header;
      Written   : Archive.Types.Uncompressed_Size := 0;
      Cancelled : Boolean := False;

      procedure Counting
        (Bytes    : Zlib.Byte_Array;
         Continue : in out Boolean) is
      begin
         Consumer.all (Bytes, Continue);
         Written := Written + Archive.Types.Uncompressed_Size (Bytes'Length);
         if not Continue then
            Cancelled := True;
         end if;
      end Counting;
   begin
      Zlib.Extract_Rar_File_Entry
        (Path, To_String (Item.Original_Path), Counting'Access, Status);

      if Status = Zlib.Invalid_Checksum then
         return (Status        => Archive.Archives.Errors.Invalid_Format,
                 Integrity      => Archive.Archives.Entries.Failed,
                 Bytes_Written  => Written);
      elsif Status /= Zlib.Ok then
         return (Status        => Bridge.To_Error (Status),
                 Integrity      => Archive.Archives.Entries.Not_Available,
                 Bytes_Written  => Written);
      elsif Cancelled then
         return (Status        => Archive.Archives.Errors.Cancelled,
                 Integrity      => Archive.Archives.Entries.Not_Available,
                 Bytes_Written  => Written);
      else
         return (Status        => Archive.Archives.Errors.Ok,
                 Integrity      => Archive.Archives.Entries.Verified,
                 Bytes_Written  => Written);
      end if;
   end Stream_Payload_File;

end Archive.Archives.Readers.Rar;
