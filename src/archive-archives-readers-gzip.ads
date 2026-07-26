with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Types;
with Zlib;

package Archive.Archives.Readers.Gzip is
   type Gzip_Header_Info is record
      Header_Length  : Natural := 0;
      Extra_Length   : Natural := 0;
      Has_Name       : Boolean := False;
      Has_Comment    : Boolean := False;
      Has_Header_CRC : Boolean := False;
   end record;

   type Gzip_Index_Result is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Item   : Archive.Archives.Entries.Archive_Entry;
      Header : Gzip_Header_Info;
   end record;

   type Stream_Result is record
     Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
      Bytes_Written : Archive.Types.Uncompressed_Size := 0;
   end record;

   function Index_File
     (Path        : String;
      Source_Name : String := "")
      return Gzip_Index_Result;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result;
end Archive.Archives.Readers.Gzip;
