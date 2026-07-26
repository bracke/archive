with Ada.Containers.Vectors;
with Archive.Types;

package Archive.Archives.Entries is
   subtype UString is Archive.Types.UString;

   type Entry_Kind is
     (Regular_File,
      Directory,
      Symbolic_Link,
      Hard_Link,
      Character_Device,
      Block_Device,
      FIFO,
      Socket,
      Metadata_Record,
      Unknown);

   type Compression_Method is
     (No_Compression,
      GZip_Deflate,
      Zip_Stored,
      Zip_Deflate,
      BZip2_Compression,
      Zstd_Compression,
      Unsupported_Compression,
      Unknown_Compression);

   type Encryption_State is (Not_Encrypted, Encrypted, Unknown_Encryption);
   type Integrity_State is (Not_Checked, Verified, Failed, Not_Available);
   type Path_Safety is
     (Safe_Path,
      Empty_Path,
      Absolute_Path,
      Parent_Traversal,
      Windows_Drive_Path,
      Windows_UNC_Path,
      Alternate_Data_Stream,
      Reserved_Name,
      Invalid_Component,
      Too_Long,
      Unsafe_Encoding);

   type Archive_Entry is record
      Id                : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Ordinal           : Archive.Types.Archive_Ordinal := 0;
      Original_Path     : UString;
      Display_Name      : UString;
      Comment           : UString;
      Format_Metadata   : UString;
      Owner_Name        : UString;
      Group_Name        : UString;
      Permissions       : UString;
      Modified_Time     : UString;
      Link_Target       : UString;
      Parent            : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Synthetic         : Boolean := False;
      Data_Offset       : Archive.Types.Optional_Offset;
      CRC32             : Archive.Types.Optional_CRC32;
      Kind              : Entry_Kind := Unknown;
      Compressed        : Archive.Types.Optional_Size;
      Uncompressed      : Archive.Types.Optional_Size;
      Method            : Compression_Method := Unknown_Compression;
      Encryption        : Encryption_State := Unknown_Encryption;
      Integrity         : Integrity_State := Not_Checked;
      Safety            : Path_Safety := Unsafe_Encoding;
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Archive_Entry);
end Archive.Archives.Entries;
