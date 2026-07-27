with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Types;
with Zlib;

package Archive.Archives.Readers.Rar is
   type Rar_Index_Result is record
      Status  : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Entries : Archive.Archives.Entries.Entry_Vectors.Vector;
   end record;

   function Index_File (Path : String) return Rar_Index_Result;

   type Stream_Result is record
      Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
      Bytes_Written : Archive.Types.Uncompressed_Size := 0;
   end record;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result;
end Archive.Archives.Readers.Rar;
