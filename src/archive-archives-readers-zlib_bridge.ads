with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Types;
with Zlib;

--  Shared glue for the container readers that now delegate their parsing to
--  the zlib library (ar, cpio, ISO 9660, RAR, cab). It maps zlib's neutral
--  Status_Code / Archive_Entry onto the app's own Error_Code / Archive_Entry,
--  and reads the ";"-separated "key=value" attribute string zlib returns in
--  each entry's Metadata so a reader can restore the format-specific fields
--  (owner, mode, timestamps, ...) the neutral record has no column for.
package Archive.Archives.Readers.Zlib_Bridge is

   function To_Error
     (Status : Zlib.Status_Code)
      return Archive.Archives.Errors.Error_Code;
   --  Map a zlib Status_Code onto the app's Error_Code.
   --  @param Status the zlib status to translate
   --  @return the closest matching Error_Code

   function Meta_Value (Metadata : String; Key : String) return String;
   --  Return the value of the ";"-separated "Key=value" token in Metadata, or
   --  "" when the key is absent.
   --  @param Metadata a ";"-separated "key=value" attribute string
   --  @param Key the attribute name to look up (without the "=")
   --  @return the token's value, or "" when the key is absent

   function Base_Entry
     (Item    : Zlib.Archive_Entry;
      Ordinal : Archive.Types.Archive_Ordinal)
      return Archive.Archives.Entries.Archive_Entry;
   --  Build an Archive_Entry from a zlib listing entry, filling the fields
   --  every container reader shares: ordinal, paths, kind (from Is_Directory),
   --  uncompressed method, both size columns, CRC (when non-zero), the raw
   --  format metadata, and path safety. Callers refine format specifics.
   --  @param Item the zlib listing entry
   --  @param Ordinal the entry's position in the archive
   --  @return the populated Archive_Entry

end Archive.Archives.Readers.Zlib_Bridge;
