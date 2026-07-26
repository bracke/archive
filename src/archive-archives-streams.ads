with Archive.Archives.Errors;
with Zlib;

package Archive.Archives.Streams is
   Default_Chunk_Size : constant Positive := 32_768;

   type Buffered_Source (Length : Natural := 0) is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Bytes  : Zlib.Byte_Array (1 .. Length);
   end record;

   function Read_Bounded
     (Path       : String;
      Max_Bytes  : Positive;
      Chunk_Size : Positive := Default_Chunk_Size)
      return Buffered_Source;

   function Read_Prefix
     (Path      : String;
      Max_Bytes : Positive)
      return Buffered_Source;
end Archive.Archives.Streams;
