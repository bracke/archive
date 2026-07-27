with Archive.Archives.Errors;
with Archive.Archives.Entries;
with Archive.Archives.Formats;
with Archive.Archives.Index;
with Archive.Types;
with Zlib;

package Archive.Archives.Readers.Dispatch is
   type Open_Result is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Format : Archive.Archives.Formats.Format_Id := Archive.Archives.Formats.Unknown_Format;
      Index  : Archive.Archives.Index.Archive_Index;
      Backing_Path : Archive.Types.UString;
   end record;

   function Open_File
     (Path      : String;
      Max_Bytes : Positive := 256 * 1_024 * 1_024;
      Source_Name : String := "";
      Retain_Backing : Boolean := False)
      return Open_Result;

   function Verify_File
     (Path            : String;
      Expected_Format : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format;
      Max_Bytes       : Positive := 256 * 1_024 * 1_024;
      Source_Name     : String := "")
      return Archive.Archives.Errors.Error_Code;

   type Payload_Chunk_Consumer is access procedure
     (Bytes : Zlib.Byte_Array;
      Continue : in out Boolean);

   type Stream_Result is record
      Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
      Bytes_Written : Archive.Types.Uncompressed_Size := 0;
   end record;

   function Stream_Payload_File
     (Path        : String;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry;
      Consumer    : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean);
      Password    : String := "")
      return Stream_Result;
end Archive.Archives.Readers.Dispatch;
