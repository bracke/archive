with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Paths;

package body Archive.Archives.Readers.Zlib_Bridge is
   use Ada.Strings.Unbounded;
   use type Interfaces.Unsigned_32;

   function To_Error
     (Status : Zlib.Status_Code)
      return Archive.Archives.Errors.Error_Code is
   begin
      case Status is
         when Zlib.Ok =>
            return Archive.Archives.Errors.Ok;
         when Zlib.Unsupported_Method
            | Zlib.Unsupported_Preset_Dictionary =>
            return Archive.Archives.Errors.Unsupported_Method;
         when Zlib.Insufficient_Memory =>
            return Archive.Archives.Errors.Limit_Exceeded;
         when Zlib.Input_File_Error | Zlib.Output_File_Error =>
            return Archive.Archives.Errors.Read_Failed;
         when others =>
            --  Invalid_Header, Invalid_Checksum, truncation, and the deflate
            --  failure codes all mean the input was not the well-formed archive
            --  it claimed to be.
            return Archive.Archives.Errors.Invalid_Format;
      end case;
   end To_Error;

   function Meta_Value (Metadata : String; Key : String) return String is
      Needle : constant String := Key & "=";
      Start  : Natural;
      Stop   : Natural;
   begin
      --  Match "Key=" either at the very start or just after a ";" separator,
      --  so "rar.method" does not match a "x.rar.method" suffix.
      Start := Ada.Strings.Fixed.Index (Metadata, Needle);
      while Start /= 0 loop
         if Start = Metadata'First
           or else Metadata (Start - 1) = ';'
         then
            Start := Start + Needle'Length;
            Stop := Ada.Strings.Fixed.Index (Metadata (Start .. Metadata'Last), ";");
            if Stop = 0 then
               return Metadata (Start .. Metadata'Last);
            end if;
            return Metadata (Start .. Stop - 1);
         end if;
         Start :=
           Ada.Strings.Fixed.Index (Metadata (Start + 1 .. Metadata'Last), Needle);
      end loop;
      return "";
   end Meta_Value;

   function Base_Entry
     (Item    : Zlib.Archive_Entry;
      Ordinal : Archive.Types.Archive_Ordinal)
      return Archive.Archives.Entries.Archive_Entry
   is
      Name : constant String := To_String (Item.Name);
      E    : Archive.Archives.Entries.Archive_Entry;
   begin
      E.Ordinal := Ordinal;
      E.Original_Path := To_Unbounded_String (Name);
      E.Display_Name :=
        To_Unbounded_String (Archive.Archives.Paths.Safe_Display_Name (Name));
      E.Kind :=
        (if Item.Is_Directory
         then Archive.Archives.Entries.Directory
         else Archive.Archives.Entries.Regular_File);
      E.Method := Archive.Archives.Entries.No_Compression;
      E.Encryption := Archive.Archives.Entries.Not_Encrypted;
      E.Integrity := Archive.Archives.Entries.Not_Checked;
      E.Format_Metadata := Item.Metadata;
      E.Uncompressed :=
        (Present => True,
         Value   => Archive.Types.Uncompressed_Size (Item.Uncompressed_Size));
      E.Compressed :=
        (Present => True,
         Value   => Archive.Types.Uncompressed_Size (Item.Compressed_Size));
      if Item.CRC_32 /= 0 then
         E.CRC32 :=
           (Present => True,
            Value   => Archive.Types.CRC32_Value (Item.CRC_32));
      end if;
      E.Safety := Archive.Archives.Paths.Normalize (Name).Safety;
      return E;
   end Base_Entry;

end Archive.Archives.Readers.Zlib_Bridge;
