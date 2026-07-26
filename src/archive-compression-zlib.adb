with Ada.Containers.Vectors;

package body Archive.Compression.Zlib is
   use type Archive.Types.Compressed_Size;
   use type Archive.Types.Uncompressed_Size;
   use type Standard.Zlib.Status_Code;
   use type Standard.Zlib.Byte;
   use type Ada.Streams.Stream_Element_Offset;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Standard.Zlib.Byte,
      "="          => Standard.Zlib."=");

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   function Header_For (Mode : Stream_Mode) return Standard.Zlib.Header_Type is
   begin
      case Mode is
         when Raw_Deflate =>
            return Standard.Zlib.Raw_Deflate;
         when Zlib_Wrapped =>
            return Standard.Zlib.Zlib_Header;
         when Gzip_Wrapped =>
            return Standard.Zlib.GZip;
         when Auto_Wrapped =>
            return Standard.Zlib.Default;
      end case;
   end Header_For;

   function To_Array (Bytes : Byte_Vectors.Vector) return Standard.Zlib.Byte_Array is
      Result : Standard.Zlib.Byte_Array (1 .. Natural (Bytes.Length));
      Pos    : Natural := 1;
   begin
      for B of Bytes loop
         Result (Pos) := B;
         Pos := Pos + 1;
      end loop;
      return Result;
   end To_Array;

   function Map_Status (Status : Standard.Zlib.Status_Code) return Archive.Archives.Errors.Error_Code is
   begin
      case Status is
         when Standard.Zlib.Ok =>
            return Archive.Archives.Errors.Ok;
         when Standard.Zlib.Invalid_Header
            | Standard.Zlib.Invalid_Checksum
            | Standard.Zlib.Invalid_Block_Type
            | Standard.Zlib.Invalid_Stored_Block
            | Standard.Zlib.Invalid_Huffman_Code
            | Standard.Zlib.Invalid_Distance
            | Standard.Zlib.Unexpected_End_Of_Input =>
            return Archive.Archives.Errors.Invalid_Format;
         when Standard.Zlib.Unsupported_Method | Standard.Zlib.Unsupported_Preset_Dictionary =>
            return Archive.Archives.Errors.Unsupported_Method;
         when Standard.Zlib.Input_File_Error =>
            return Archive.Archives.Errors.Read_Failed;
         when Standard.Zlib.Output_File_Error =>
            return Archive.Archives.Errors.Write_Failed;
      end case;
   end Map_Status;

   function Ratio_Exceeded
     (Compressed   : Archive.Types.Compressed_Size;
      Uncompressed : Archive.Types.Uncompressed_Size;
      Max_Ratio    : Positive)
      return Boolean
   is
   begin
      if Compressed = 0 then
         return Uncompressed > 0;
      end if;

      return Uncompressed / Archive.Types.Uncompressed_Size (Compressed) >
        Archive.Types.Uncompressed_Size (Max_Ratio);
   end Ratio_Exceeded;

   function Step_Result
     (Status             : Archive.Archives.Errors.Error_Code;
      Input_Bytes        : Natural;
      Output_Bytes       : Natural;
      Total_Input_Bytes  : Natural;
      Total_Output_Bytes : Natural;
      Stream_Ended       : Boolean;
      Output_Limited     : Boolean;
      Ratio_Limited      : Boolean;
      Cancelled          : Boolean;
      Bytes              : Byte_Vectors.Vector)
      return Stream_Step_Result
   is
   begin
      return
        (Length             => Natural (Bytes.Length),
         Status             => Status,
         Input_Bytes        => Input_Bytes,
         Output_Bytes       => Output_Bytes,
         Total_Input_Bytes  => Total_Input_Bytes,
         Total_Output_Bytes => Total_Output_Bytes,
         Stream_Ended       => Stream_Ended,
         Output_Limited     => Output_Limited,
         Ratio_Limited      => Ratio_Limited,
         Cancelled          => Cancelled,
         Bytes              => To_Array (Bytes));
   end Step_Result;

   procedure Open
     (Stream : in out Inflate_Stream;
      Mode   : Stream_Mode;
      Limits : Inflate_Limits := (others => <>);
      Output_Chunk_Bytes : Positive :=
        Positive
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Zlib_Output_Chunk_Bytes)))
   is
   begin
      if Stream.Opened and then not Stream.Closed then
         Standard.Zlib.Close (Stream.Filter, Ignore_Error => True);
      end if;

      Standard.Zlib.Inflate_Init
        (Stream.Filter,
         Header    => Header_For (Mode),
         GZip_Mode => Standard.Zlib.Multi_Member);
      Stream.Opened := True;
      Stream.Closed := False;
      Stream.Limits := Limits;
      Stream.Output_Chunk_Bytes := Output_Chunk_Bytes;
      Stream.Compressed := 0;
      Stream.Uncompressed := 0;
   exception
      when Standard.Zlib.Zlib_Error =>
         Stream.Opened := False;
         Stream.Closed := True;
   end Open;

   function Append
     (Stream : in out Inflate_Stream;
      Input  : Standard.Zlib.Byte_Array;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result
   is
      Output : Byte_Vectors.Vector;
      Consumed_Total : Natural := 0;
      Produced_Total : Natural := 0;

      procedure Append_Output
        (Data : Ada.Streams.Stream_Element_Array;
         Last : Ada.Streams.Stream_Element_Offset;
         Hit_Limit : out Boolean)
      is
      begin
         Hit_Limit := False;
         if Last = Before_First (Data) then
            return;
         end if;

         for Offset in Data'First .. Last loop
            if Stream.Uncompressed >= Stream.Limits.Max_Output_Bytes then
               Hit_Limit := True;
               return;
            end if;
            Output.Append (Standard.Zlib.Byte (Data (Offset)));
            Stream.Uncompressed := Stream.Uncompressed + 1;
            Produced_Total := Produced_Total + 1;
         end loop;
      end Append_Output;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return Step_Result
           (Archive.Archives.Errors.Cancelled, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, True, Output);
      elsif Stream.Closed or else not Stream.Opened then
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, False, Output);
      end if;

      declare
         In_Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
         Chunk_Pos : Ada.Streams.Stream_Element_Offset := 1;
      begin
         for Index in Input'Range loop
            In_Data (Ada.Streams.Stream_Element_Offset (Index - Input'First + 1)) :=
              Ada.Streams.Stream_Element (Input (Index));
         end loop;

         while Chunk_Pos <= In_Data'Last and then not Standard.Zlib.Stream_End (Stream.Filter) loop
            if Cancellation /= null and then Cancellation.Cancelled then
               return Step_Result
                 (Archive.Archives.Errors.Cancelled, Consumed_Total, Produced_Total,
                  Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                  False, False, False, True, Output);
            end if;

            declare
               Out_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Stream.Output_Chunk_Bytes));
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
               Hit_Limit : Boolean := False;
            begin
               Standard.Zlib.Translate
                 (Stream.Filter,
                  In_Data (Chunk_Pos .. In_Data'Last),
                  In_Last,
                  Out_Data,
                  Out_Last,
                  Standard.Zlib.No_Flush);

               declare
                  Produced : constant Boolean := Out_Last /= Before_First (Out_Data);
                  Consumed : constant Boolean := In_Last >= Chunk_Pos;
               begin
                  if Consumed then
                     declare
                        Amount : constant Natural :=
                          Natural (In_Last - Chunk_Pos + 1);
                     begin
                        Consumed_Total := Consumed_Total + Amount;
                        Stream.Compressed := Stream.Compressed + Archive.Types.Compressed_Size (Amount);
                     end;
                     Chunk_Pos := In_Last + 1;
                  end if;

                  Append_Output (Out_Data, Out_Last, Hit_Limit);
                  if Hit_Limit then
                     return Step_Result
                       (Archive.Archives.Errors.Limit_Exceeded,
                        Consumed_Total, Produced_Total, Natural (Stream.Compressed),
                        Natural (Stream.Uncompressed), Standard.Zlib.Stream_End (Stream.Filter),
                        True, False, False, Output);
                  elsif Ratio_Exceeded
                    (Stream.Compressed, Stream.Uncompressed, Stream.Limits.Max_Ratio)
                  then
                     return Step_Result
                       (Archive.Archives.Errors.Limit_Exceeded,
                        Consumed_Total, Produced_Total, Natural (Stream.Compressed),
                        Natural (Stream.Uncompressed), Standard.Zlib.Stream_End (Stream.Filter),
                        False, True, False, Output);
                  elsif not Produced and then not Consumed then
                     return Step_Result
                       (Archive.Archives.Errors.Zlib_Failed,
                        Consumed_Total, Produced_Total, Natural (Stream.Compressed),
                        Natural (Stream.Uncompressed), False, False, False, False, Output);
                  end if;
               end;
            end;
         end loop;
      end;

      return Step_Result
        (Archive.Archives.Errors.Ok, Consumed_Total, Produced_Total,
         Natural (Stream.Compressed), Natural (Stream.Uncompressed),
         Standard.Zlib.Stream_End (Stream.Filter), False, False, False, Output);
   exception
      when Standard.Zlib.Zlib_Error =>
         return Step_Result
           (Archive.Archives.Errors.Invalid_Format, Consumed_Total, Produced_Total,
            Natural (Stream.Compressed), Natural (Stream.Uncompressed),
            False, False, False, False, Output);
      when Standard.Zlib.Status_Error =>
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, Consumed_Total, Produced_Total,
            Natural (Stream.Compressed), Natural (Stream.Uncompressed),
           False, False, False, False, Output);
   end Append;

   function Append_Chunks
     (Stream : in out Inflate_Stream;
      Input  : Standard.Zlib.Byte_Array;
      Consumer : not null access procedure
        (Bytes : Standard.Zlib.Byte_Array;
         Continue : in out Boolean);
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result
   is
      Empty : Byte_Vectors.Vector;
      Consumed_Total : Natural := 0;
      Produced_Total : Natural := 0;

      procedure Emit_Output
        (Data : Ada.Streams.Stream_Element_Array;
         Last : Ada.Streams.Stream_Element_Offset;
         Hit_Limit : out Boolean;
         Stopped : out Boolean)
      is
      begin
         Hit_Limit := False;
         Stopped := False;
         if Last = Before_First (Data) then
            return;
         end if;

         declare
            Chunk : Standard.Zlib.Byte_Array (1 .. Natural (Last));
            Continue : Boolean := True;
         begin
            for Offset in Data'First .. Last loop
               if Stream.Uncompressed >= Stream.Limits.Max_Output_Bytes then
                  Hit_Limit := True;
                  return;
               end if;
               Chunk (Natural (Offset)) := Standard.Zlib.Byte (Data (Offset));
               Stream.Uncompressed := Stream.Uncompressed + 1;
               Produced_Total := Produced_Total + 1;
            end loop;

            Consumer.all (Chunk, Continue);
            Stopped := not Continue;
         end;
      end Emit_Output;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return Step_Result
           (Archive.Archives.Errors.Cancelled, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, True, Empty);
      elsif Stream.Closed or else not Stream.Opened then
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, False, Empty);
      end if;

      declare
         In_Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
         Chunk_Pos : Ada.Streams.Stream_Element_Offset := 1;
      begin
         for Index in Input'Range loop
            In_Data (Ada.Streams.Stream_Element_Offset (Index - Input'First + 1)) :=
              Ada.Streams.Stream_Element (Input (Index));
         end loop;

         while Chunk_Pos <= In_Data'Last and then not Standard.Zlib.Stream_End (Stream.Filter) loop
            if Cancellation /= null and then Cancellation.Cancelled then
               return Step_Result
                 (Archive.Archives.Errors.Cancelled, Consumed_Total, Produced_Total,
                  Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                  False, False, False, True, Empty);
            end if;

            declare
               Out_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Stream.Output_Chunk_Bytes));
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
               Hit_Limit : Boolean := False;
               Stopped : Boolean := False;
            begin
               Standard.Zlib.Translate
                 (Stream.Filter,
                  In_Data (Chunk_Pos .. In_Data'Last),
                  In_Last,
                  Out_Data,
                  Out_Last,
                  Standard.Zlib.No_Flush);

               declare
                  Produced : constant Boolean := Out_Last /= Before_First (Out_Data);
                  Consumed : constant Boolean := In_Last >= Chunk_Pos;
               begin
                  if Consumed then
                     declare
                        Amount : constant Natural := Natural (In_Last - Chunk_Pos + 1);
                     begin
                        Consumed_Total := Consumed_Total + Amount;
                        Stream.Compressed := Stream.Compressed + Archive.Types.Compressed_Size (Amount);
                     end;
                     Chunk_Pos := In_Last + 1;
                  end if;

                  Emit_Output (Out_Data, Out_Last, Hit_Limit, Stopped);
                  if Stopped then
                     return Step_Result
                       (Archive.Archives.Errors.Cancelled, Consumed_Total, Produced_Total,
                        Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                        Standard.Zlib.Stream_End (Stream.Filter), False, False, True, Empty);
                  elsif Hit_Limit then
                     return Step_Result
                       (Archive.Archives.Errors.Limit_Exceeded, Consumed_Total, Produced_Total,
                        Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                        Standard.Zlib.Stream_End (Stream.Filter), True, False, False, Empty);
                  elsif Ratio_Exceeded
                    (Stream.Compressed, Stream.Uncompressed, Stream.Limits.Max_Ratio)
                  then
                     return Step_Result
                       (Archive.Archives.Errors.Limit_Exceeded, Consumed_Total, Produced_Total,
                        Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                        Standard.Zlib.Stream_End (Stream.Filter), False, True, False, Empty);
                  elsif not Produced and then not Consumed then
                     return Step_Result
                       (Archive.Archives.Errors.Zlib_Failed, Consumed_Total, Produced_Total,
                        Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                        False, False, False, False, Empty);
                  end if;
               end;
            end;
         end loop;
      end;

      return Step_Result
        (Archive.Archives.Errors.Ok, Consumed_Total, Produced_Total,
         Natural (Stream.Compressed), Natural (Stream.Uncompressed),
         Standard.Zlib.Stream_End (Stream.Filter), False, False, False, Empty);
   exception
      when Standard.Zlib.Zlib_Error =>
         return Step_Result
           (Archive.Archives.Errors.Invalid_Format, Consumed_Total, Produced_Total,
            Natural (Stream.Compressed), Natural (Stream.Uncompressed),
            False, False, False, False, Empty);
      when Standard.Zlib.Status_Error =>
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, Consumed_Total, Produced_Total,
            Natural (Stream.Compressed), Natural (Stream.Uncompressed),
            False, False, False, False, Empty);
   end Append_Chunks;

   function Finish
     (Stream : in out Inflate_Stream;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result
   is
      Output : Byte_Vectors.Vector;
      Produced_Total : Natural := 0;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return Step_Result
           (Archive.Archives.Errors.Cancelled, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, True, Output);
      elsif Stream.Closed or else not Stream.Opened then
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, False, Output);
      end if;

      while not Standard.Zlib.Stream_End (Stream.Filter) loop
         declare
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Stream.Output_Chunk_Bytes));
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Standard.Zlib.Flush (Stream.Filter, Out_Data, Out_Last, Standard.Zlib.Finish);
            if Out_Last = Before_First (Out_Data) then
               exit;
            end if;
            for Offset in Out_Data'First .. Out_Last loop
               if Stream.Uncompressed >= Stream.Limits.Max_Output_Bytes then
                  return Step_Result
                    (Archive.Archives.Errors.Limit_Exceeded, 0, Produced_Total,
                     Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                     Standard.Zlib.Stream_End (Stream.Filter), True, False, False, Output);
               end if;
               Output.Append (Standard.Zlib.Byte (Out_Data (Offset)));
               Stream.Uncompressed := Stream.Uncompressed + 1;
               Produced_Total := Produced_Total + 1;
            end loop;
         end;
      end loop;

      return Step_Result
        (Archive.Archives.Errors.Ok, 0, Produced_Total, Natural (Stream.Compressed),
         Natural (Stream.Uncompressed), Standard.Zlib.Stream_End (Stream.Filter),
         False, False, False, Output);
   exception
      when Standard.Zlib.Zlib_Error =>
         return Step_Result
           (Archive.Archives.Errors.Invalid_Format, 0, Produced_Total,
            Natural (Stream.Compressed), Natural (Stream.Uncompressed),
            False, False, False, False, Output);
      when Standard.Zlib.Status_Error =>
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, Produced_Total,
           Natural (Stream.Compressed), Natural (Stream.Uncompressed),
            False, False, False, False, Output);
   end Finish;

   function Finish_Chunks
     (Stream : in out Inflate_Stream;
      Consumer : not null access procedure
        (Bytes : Standard.Zlib.Byte_Array;
         Continue : in out Boolean);
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result
   is
      Empty : Byte_Vectors.Vector;
      Produced_Total : Natural := 0;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return Step_Result
           (Archive.Archives.Errors.Cancelled, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, True, Empty);
      elsif Stream.Closed or else not Stream.Opened then
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, 0, Natural (Stream.Compressed),
            Natural (Stream.Uncompressed), False, False, False, False, Empty);
      end if;

      while not Standard.Zlib.Stream_End (Stream.Filter) loop
         declare
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Stream.Output_Chunk_Bytes));
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Standard.Zlib.Flush (Stream.Filter, Out_Data, Out_Last, Standard.Zlib.Finish);
            if Out_Last = Before_First (Out_Data) then
               exit;
            end if;

            declare
               Chunk : Standard.Zlib.Byte_Array (1 .. Natural (Out_Last));
               Continue : Boolean := True;
            begin
               for Offset in Out_Data'First .. Out_Last loop
                  if Stream.Uncompressed >= Stream.Limits.Max_Output_Bytes then
                     return Step_Result
                       (Archive.Archives.Errors.Limit_Exceeded, 0, Produced_Total,
                        Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                        Standard.Zlib.Stream_End (Stream.Filter), True, False, False, Empty);
                  end if;
                  Chunk (Natural (Offset)) := Standard.Zlib.Byte (Out_Data (Offset));
                  Stream.Uncompressed := Stream.Uncompressed + 1;
                  Produced_Total := Produced_Total + 1;
               end loop;

               Consumer.all (Chunk, Continue);
               if not Continue then
                  return Step_Result
                    (Archive.Archives.Errors.Cancelled, 0, Produced_Total,
                     Natural (Stream.Compressed), Natural (Stream.Uncompressed),
                     Standard.Zlib.Stream_End (Stream.Filter), False, False, True, Empty);
               end if;
            end;
         end;
      end loop;

      return Step_Result
        (Archive.Archives.Errors.Ok, 0, Produced_Total, Natural (Stream.Compressed),
         Natural (Stream.Uncompressed), Standard.Zlib.Stream_End (Stream.Filter),
         False, False, False, Empty);
   exception
      when Standard.Zlib.Zlib_Error =>
         return Step_Result
           (Archive.Archives.Errors.Invalid_Format, 0, Produced_Total,
            Natural (Stream.Compressed), Natural (Stream.Uncompressed),
            False, False, False, False, Empty);
      when Standard.Zlib.Status_Error =>
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, Produced_Total,
            Natural (Stream.Compressed), Natural (Stream.Uncompressed),
            False, False, False, False, Empty);
   end Finish_Chunks;

   function Close (Stream : in out Inflate_Stream) return Stream_Close_Result is
      Ended : constant Boolean :=
        Stream.Opened and then not Stream.Closed and then Standard.Zlib.Stream_End (Stream.Filter);
   begin
      if Stream.Closed or else not Stream.Opened then
         return
           (Status       => Archive.Archives.Errors.Zlib_Failed,
            Close_Status => Close_Already_Closed,
            Stream_Ended => False);
      end if;

      Standard.Zlib.Close (Stream.Filter);
      Stream.Closed := True;
      return
        (Status       => Archive.Archives.Errors.Ok,
         Close_Status => Close_Ok,
         Stream_Ended => Ended);
   exception
      when Standard.Zlib.Zlib_Error =>
         Stream.Closed := True;
         return
           (Status       => Archive.Archives.Errors.Invalid_Format,
            Close_Status => Close_Incomplete,
            Stream_Ended => False);
      when Standard.Zlib.Status_Error =>
         Stream.Closed := True;
         return
           (Status       => Archive.Archives.Errors.Zlib_Failed,
            Close_Status => Close_Already_Closed,
            Stream_Ended => False);
   end Close;

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
             (Archive.Resource_Limits.Zlib_Output_Chunk_Bytes)))
   is
   begin
      if Stream.Opened and then not Stream.Closed then
         Standard.Zlib.Compress_Close (Stream.Filter, Ignore_Error => True);
      end if;

      Standard.Zlib.Deflate_Init
        (Stream.Filter, Header => Header_For (Mode), Mode => Standard.Zlib.Auto);
      Stream.Opened := True;
      Stream.Closed := False;
      Stream.Max_Output_Bytes := Max_Output_Bytes;
      Stream.Output_Chunk_Bytes := Output_Chunk_Bytes;
      Stream.Input_Count := 0;
      Stream.Output_Count := 0;
   exception
      when Standard.Zlib.Zlib_Error =>
         Stream.Opened := False;
         Stream.Closed := True;
   end Open;

   function Append
     (Stream : in out Deflate_Stream;
      Input  : Standard.Zlib.Byte_Array;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result
   is
      Output : Byte_Vectors.Vector;
      Consumed_Total : Natural := 0;
      Produced_Total : Natural := 0;

      procedure Append_Output
        (Data : Ada.Streams.Stream_Element_Array;
         Last : Ada.Streams.Stream_Element_Offset;
         Hit_Limit : out Boolean)
      is
      begin
         Hit_Limit := False;
         if Last = Before_First (Data) then
            return;
         end if;

         for Offset in Data'First .. Last loop
            if Stream.Output_Count >= Stream.Max_Output_Bytes then
               Hit_Limit := True;
               return;
            end if;
            Output.Append (Standard.Zlib.Byte (Data (Offset)));
            Stream.Output_Count := Stream.Output_Count + 1;
            Produced_Total := Produced_Total + 1;
         end loop;
      end Append_Output;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return Step_Result
           (Archive.Archives.Errors.Cancelled, 0, 0, Natural (Stream.Input_Count),
            Natural (Stream.Output_Count), False,
            False, False, True, Output);
      elsif Stream.Closed or else not Stream.Opened then
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, 0, Natural (Stream.Input_Count),
            Natural (Stream.Output_Count), False,
            False, False, False, Output);
      end if;

      declare
         In_Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
         Chunk_Pos : Ada.Streams.Stream_Element_Offset := 1;
      begin
         for Index in Input'Range loop
            In_Data (Ada.Streams.Stream_Element_Offset (Index - Input'First + 1)) :=
              Ada.Streams.Stream_Element (Input (Index));
         end loop;

         while Chunk_Pos <= In_Data'Last
           and then not Standard.Zlib.Compress_Stream_End (Stream.Filter)
         loop
            if Cancellation /= null and then Cancellation.Cancelled then
               return Step_Result
                 (Archive.Archives.Errors.Cancelled, Consumed_Total, Produced_Total,
                  Natural (Stream.Input_Count), Natural (Stream.Output_Count),
                  False, False, False, True, Output);
            end if;

            declare
               Out_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Stream.Output_Chunk_Bytes));
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
               Hit_Limit : Boolean := False;
            begin
               Standard.Zlib.Compress
                 (Stream.Filter,
                  In_Data (Chunk_Pos .. In_Data'Last),
                  In_Last,
                  Out_Data,
                  Out_Last,
                  Standard.Zlib.No_Flush);

               declare
                  Produced : constant Boolean := Out_Last /= Before_First (Out_Data);
                  Consumed : constant Boolean := In_Last >= Chunk_Pos;
               begin
                  if Consumed then
                     declare
                        Amount : constant Natural := Natural (In_Last - Chunk_Pos + 1);
                     begin
                        Consumed_Total := Consumed_Total + Amount;
                        Stream.Input_Count := Stream.Input_Count
                          + Archive.Types.Uncompressed_Size (Amount);
                     end;
                     Chunk_Pos := In_Last + 1;
                  end if;

                  Append_Output (Out_Data, Out_Last, Hit_Limit);
                  if Hit_Limit then
                     return Step_Result
                       (Archive.Archives.Errors.Limit_Exceeded,
                        Consumed_Total, Produced_Total, Natural (Stream.Input_Count),
                        Natural (Stream.Output_Count),
                        Standard.Zlib.Compress_Stream_End (Stream.Filter),
                        True, False, False, Output);
                  elsif not Produced and then not Consumed then
                     return Step_Result
                       (Archive.Archives.Errors.Zlib_Failed,
                        Consumed_Total, Produced_Total, Natural (Stream.Input_Count),
                        Natural (Stream.Output_Count),
                        False, False, False, False, Output);
                  end if;
               end;
            end;
         end loop;
      end;

      return Step_Result
        (Archive.Archives.Errors.Ok, Consumed_Total, Produced_Total,
         Natural (Stream.Input_Count), Natural (Stream.Output_Count),
         Standard.Zlib.Compress_Stream_End (Stream.Filter), False, False, False, Output);
   exception
      when Standard.Zlib.Zlib_Error | Standard.Zlib.Status_Error =>
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, Consumed_Total, Produced_Total,
            Natural (Stream.Input_Count), Natural (Stream.Output_Count),
            False, False, False, False, Output);
   end Append;

   function Finish
     (Stream : in out Deflate_Stream;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Stream_Step_Result
   is
      Output : Byte_Vectors.Vector;
      Produced_Total : Natural := 0;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return Step_Result
           (Archive.Archives.Errors.Cancelled, 0, 0, Natural (Stream.Input_Count),
            Natural (Stream.Output_Count), False,
            False, False, True, Output);
      elsif Stream.Closed or else not Stream.Opened then
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, 0, Natural (Stream.Input_Count),
            Natural (Stream.Output_Count), False,
            False, False, False, Output);
      end if;

      while not Standard.Zlib.Compress_Stream_End (Stream.Filter) loop
         declare
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Stream.Output_Chunk_Bytes));
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Standard.Zlib.Compress_Flush
              (Stream.Filter, Out_Data, Out_Last, Standard.Zlib.Finish);
            if Out_Last = Before_First (Out_Data) then
               exit;
            end if;
            for Offset in Out_Data'First .. Out_Last loop
               if Stream.Output_Count >= Stream.Max_Output_Bytes then
                  return Step_Result
                    (Archive.Archives.Errors.Limit_Exceeded, 0, Produced_Total,
                     Natural (Stream.Input_Count), Natural (Stream.Output_Count),
                     Standard.Zlib.Compress_Stream_End (Stream.Filter), True, False, False,
                     Output);
               end if;
               Output.Append (Standard.Zlib.Byte (Out_Data (Offset)));
               Stream.Output_Count := Stream.Output_Count + 1;
               Produced_Total := Produced_Total + 1;
            end loop;
         end;
      end loop;

      return Step_Result
        (Archive.Archives.Errors.Ok, 0, Produced_Total, Natural (Stream.Input_Count),
         Natural (Stream.Output_Count),
         Standard.Zlib.Compress_Stream_End (Stream.Filter), False, False, False, Output);
   exception
      when Standard.Zlib.Zlib_Error | Standard.Zlib.Status_Error =>
         return Step_Result
           (Archive.Archives.Errors.Zlib_Failed, 0, Produced_Total,
            Natural (Stream.Input_Count), Natural (Stream.Output_Count),
            False, False, False, False, Output);
   end Finish;

   function Close (Stream : in out Deflate_Stream) return Stream_Close_Result is
      Ended : constant Boolean :=
        Stream.Opened and then not Stream.Closed
        and then Standard.Zlib.Compress_Stream_End (Stream.Filter);
   begin
      if Stream.Closed or else not Stream.Opened then
         return
           (Status       => Archive.Archives.Errors.Zlib_Failed,
            Close_Status => Close_Already_Closed,
            Stream_Ended => False);
      end if;

      Standard.Zlib.Compress_Close (Stream.Filter);
      Stream.Closed := True;
      return
        (Status       => Archive.Archives.Errors.Ok,
         Close_Status => Close_Ok,
         Stream_Ended => Ended);
   exception
      when Standard.Zlib.Zlib_Error =>
         Stream.Closed := True;
         return
           (Status       => Archive.Archives.Errors.Invalid_Format,
            Close_Status => Close_Incomplete,
            Stream_Ended => False);
      when Standard.Zlib.Status_Error =>
         Stream.Closed := True;
         return
           (Status       => Archive.Archives.Errors.Zlib_Failed,
            Close_Status => Close_Already_Closed,
            Stream_Ended => False);
   end Close;

end Archive.Compression.Zlib;
