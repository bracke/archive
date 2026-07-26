with Ada.Streams;
with Zlib;
with Archive.Archives.Errors;
with Archive.Resource_Limits;
with Archive.Tasking.Cancellation;
with Archive.Types;

package Archive.Compression.Zlib is
   type Stream_Mode is (Raw_Deflate, Zlib_Wrapped, Gzip_Wrapped, Auto_Wrapped);
   type Stream_Close_Status is
     (Close_Ok,
      Close_Incomplete,
      Close_Already_Closed);

   type Inflate_Limits is record
      Max_Output_Bytes : Archive.Types.Uncompressed_Size :=
        Archive.Types.Uncompressed_Size
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Preview_Output_Bytes));
      Max_Ratio        : Positive := 1_000;
   end record;

   type Stream_Step_Result (Length : Natural := 0) is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Input_Bytes        : Natural := 0;
      Output_Bytes       : Natural := 0;
      Total_Input_Bytes  : Natural := 0;
      Total_Output_Bytes : Natural := 0;
      Stream_Ended       : Boolean := False;
      Output_Limited     : Boolean := False;
      Ratio_Limited      : Boolean := False;
      Cancelled          : Boolean := False;
      Bytes              : Standard.Zlib.Byte_Array (1 .. Length);
   end record;

   type Stream_Close_Result is record
      Status       : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Close_Status : Stream_Close_Status := Close_Ok;
      Stream_Ended : Boolean := False;
   end record;

   type Inflate_Stream is limited private;
   type Deflate_Stream is limited private;

   function Map_Status (Status : Standard.Zlib.Status_Code) return Archive.Archives.Errors.Error_Code;
   procedure Open
     (Stream : in out Inflate_Stream;
      Mode   : Stream_Mode;
      Limits : Inflate_Limits := (others => <>);
      Output_Chunk_Bytes : Positive :=
        Positive
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Zlib_Output_Chunk_Bytes)));
   function Append
     (Stream : in out Inflate_Stream;
      Input  : Standard.Zlib.Byte_Array;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result;
   function Append_Chunks
     (Stream : in out Inflate_Stream;
      Input  : Standard.Zlib.Byte_Array;
      Consumer : not null access procedure
        (Bytes : Standard.Zlib.Byte_Array;
         Continue : in out Boolean);
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result;
   function Finish
     (Stream : in out Inflate_Stream;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result;
   function Finish_Chunks
     (Stream : in out Inflate_Stream;
      Consumer : not null access procedure
        (Bytes : Standard.Zlib.Byte_Array;
         Continue : in out Boolean);
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result;
   function Close (Stream : in out Inflate_Stream) return Stream_Close_Result;

   procedure Open
     (Stream : in out Deflate_Stream;
      Mode   : Stream_Mode;
      Max_Output_Bytes : Archive.Types.Compressed_Size :=
        Archive.Types.Compressed_Size
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Temporary_Backing_Bytes));
      Output_Chunk_Bytes : Positive :=
        Positive
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Zlib_Output_Chunk_Bytes)));
   function Append
     (Stream : in out Deflate_Stream;
      Input  : Standard.Zlib.Byte_Array;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result;
   function Finish
     (Stream : in out Deflate_Stream;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result;
   function Close (Stream : in out Deflate_Stream) return Stream_Close_Result;
private
   type Inflate_Stream is limited record
      Filter             : Standard.Zlib.Filter_Type;
      Opened             : Boolean := False;
      Closed             : Boolean := True;
      Limits             : Inflate_Limits;
      Output_Chunk_Bytes : Positive := 1;
      Compressed         : Archive.Types.Compressed_Size := 0;
      Uncompressed       : Archive.Types.Uncompressed_Size := 0;
   end record;

   type Deflate_Stream is limited record
      Filter             : Standard.Zlib.Compression_Filter_Type;
      Opened             : Boolean := False;
      Closed             : Boolean := True;
      Max_Output_Bytes   : Archive.Types.Compressed_Size := 0;
      Output_Chunk_Bytes : Positive := 1;
      Input_Count        : Archive.Types.Uncompressed_Size := 0;
      Output_Count       : Archive.Types.Compressed_Size := 0;
   end record;
end Archive.Compression.Zlib;
