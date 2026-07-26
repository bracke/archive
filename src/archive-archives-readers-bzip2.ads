with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Types;
with Zlib;

package Archive.Archives.Readers.BZip2 is
   type BZip2_Index_Result is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Item   : Archive.Archives.Entries.Archive_Entry;
   end record;

   function Index_File
     (Path        : String;
      Max_Bytes   : Positive := 256 * 1_024 * 1_024;
      Source_Name : String := "")
      return BZip2_Index_Result;

   type Stream_Result is record
      Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
      Bytes_Written : Archive.Types.Uncompressed_Size := 0;
   end record;

   function Stream_Payload_File
     (Path      : String;
      Max_Bytes : Positive;
      Item      : Archive.Archives.Entries.Archive_Entry;
      Consumer  : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result;
end Archive.Archives.Readers.BZip2;
