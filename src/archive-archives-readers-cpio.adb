with Ada.Strings.Unbounded;

with Archive.Archives.Readers.Zlib_Bridge;

package body Archive.Archives.Readers.Cpio is
   use Ada.Strings.Unbounded;
   use type Archive.Types.Archive_Ordinal;
   use type Archive.Types.Uncompressed_Size;
   use type Zlib.Status_Code;

   package Bridge renames Archive.Archives.Readers.Zlib_Bridge;

   --  Parsing lives in Zlib.Cpio_Reader; this body maps zlib's neutral listing
   --  onto the app's Archive_Entry (restoring the file-type taxonomy from the
   --  member mode) and streams a regular member by name.

   function Kind_From_Mode
     (Mode : Natural)
      return Archive.Archives.Entries.Entry_Kind
   is
      Kind_Bits : constant Natural := Mode - (Mode mod 16#1000#);
   begin
      case Kind_Bits is
         when 16#4000# => return Archive.Archives.Entries.Directory;
         when 16#A000# => return Archive.Archives.Entries.Symbolic_Link;
         when 16#2000# => return Archive.Archives.Entries.Character_Device;
         when 16#6000# => return Archive.Archives.Entries.Block_Device;
         when 16#1000# => return Archive.Archives.Entries.FIFO;
         when 16#C000# => return Archive.Archives.Entries.Socket;
         when 16#8000# => return Archive.Archives.Entries.Regular_File;
         when others   => return Archive.Archives.Entries.Unknown;
      end case;
   end Kind_From_Mode;

   function Mode_Of (Meta : String) return Natural is
   begin
      return Natural'Value (Bridge.Meta_Value (Meta, "cpio.mode"));
   exception
      when others =>
         return 0;
   end Mode_Of;

   function Index_File (Path : String) return Cpio_Index_Result is
      Status  : Zlib.Status_Code := Zlib.Invalid_Header;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
      Result  : Cpio_Index_Result;
   begin
      declare
         Items : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Cpio_File_Entries (Path, Status);
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
               E.Kind := Kind_From_Mode (Mode_Of (Meta));
               E.Owner_Name :=
                 To_Unbounded_String (Bridge.Meta_Value (Meta, "cpio.uid"));
               E.Group_Name :=
                 To_Unbounded_String (Bridge.Meta_Value (Meta, "cpio.gid"));
               E.Modified_Time :=
                 To_Unbounded_String (Bridge.Meta_Value (Meta, "cpio.mtime"));
               E.Permissions :=
                 To_Unbounded_String (Bridge.Meta_Value (Meta, "cpio.mode"));
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
      Zlib.Extract_Cpio_File_Entry
        (Path, To_String (Item.Original_Path), Counting'Access, Status);

      if Status /= Zlib.Ok then
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

end Archive.Archives.Readers.Cpio;
