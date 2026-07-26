with Ada.Streams;
with Ada.Streams.Stream_IO;

package body Archive.Archives.Streams is
   use type Ada.Streams.Stream_Element_Offset;

   function Read_Bounded
     (Path       : String;
      Max_Bytes  : Positive;
      Chunk_Size : Positive := Default_Chunk_Size)
      return Buffered_Source
   is
      File      : Ada.Streams.Stream_IO.File_Type;
      Output    : Zlib.Byte_Array (1 .. Max_Bytes);
      Written   : Natural := 0;
      Buffer    : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Positive'Min (Chunk_Size, Max_Bytes)));
      Last      : Ada.Streams.Stream_Element_Offset := 0;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         exit when Last < Buffer'First;

         declare
            Count : constant Natural := Natural (Last - Buffer'First + 1);
         begin
            if Written + Count > Max_Bytes then
               Ada.Streams.Stream_IO.Close (File);
               return
                 (Length => 0,
                  Status => Archive.Archives.Errors.Limit_Exceeded,
                  Bytes  => []);
            end if;

            for Index in 0 .. Count - 1 loop
               Output (Written + Index + 1) :=
                 Zlib.Byte (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            Written := Written + Count;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);

      declare
         Bytes : Zlib.Byte_Array (1 .. Written);
      begin
         for Index in Bytes'Range loop
            Bytes (Index) := Output (Index);
         end loop;
         return
           (Length => Written,
            Status => Archive.Archives.Errors.Ok,
            Bytes  => Bytes);
      end;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return
           (Length => 0,
            Status => Archive.Archives.Errors.Limit_Exceeded,
            Bytes  => []);
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return
           (Length => 0,
            Status => Archive.Archives.Errors.Read_Failed,
            Bytes  => []);
   end Read_Bounded;

   function Read_Prefix
     (Path      : String;
      Max_Bytes : Positive)
      return Buffered_Source
   is
      File    : Ada.Streams.Stream_IO.File_Type;
      Buffer  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Max_Bytes));
      Last    : Ada.Streams.Stream_Element_Offset := 0;
      Written : Natural := 0;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Read (File, Buffer, Last);
      Ada.Streams.Stream_IO.Close (File);

      if Last >= Buffer'First then
         Written := Natural (Last - Buffer'First + 1);
      end if;

      declare
         Bytes : Zlib.Byte_Array (1 .. Written);
      begin
         for Index in Bytes'Range loop
            Bytes (Index) :=
              Zlib.Byte
                (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index - 1)));
         end loop;
         return
           (Length => Written,
            Status => Archive.Archives.Errors.Ok,
            Bytes  => Bytes);
      end;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return
           (Length => 0,
            Status => Archive.Archives.Errors.Limit_Exceeded,
            Bytes  => []);
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return
           (Length => 0,
            Status => Archive.Archives.Errors.Read_Failed,
            Bytes  => []);
   end Read_Prefix;
end Archive.Archives.Streams;
