with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;
with CryptoLib.Checksums;
with Zlib;

with Archive.Archives.Entries;
with Archive.Archives.Index;
with Archive.Archives.Readers.Dispatch;
with Archive.Compression.Zlib;
with Archive.Temporary_Resources;
with Archive.Verification.CRC32;
with Archive.Types;

package body Archive.Writes.Zip is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Integrity_State;
   use type Archive.Types.Entry_Id;
   use type Archive.Writes.Plans.Entry_Decision;
   use type Archive.Writes.Plans.Plan_Status;
   use type Archive.Writes.Plans.Write_Action;
   use type Archive.Archives.Errors.Error_Code;
   use type Zlib.Status_Code;

   Max_Zip_Metadata : constant Natural := 8192;
   File_Chunk_Size : constant Ada.Streams.Stream_Element_Count := 32_768;

   type Byte_Buffer is record
      Data   : Zlib.Byte_Array (1 .. Max_Zip_Metadata) := [others => 0];
      Length : Natural := 0;
   end record;

   procedure Append_Byte (Buffer : in out Byte_Buffer; Value : Natural; OK : in out Boolean) is
   begin
      if Buffer.Length = Buffer.Data'Last then
         OK := False;
      else
         Buffer.Length := Buffer.Length + 1;
         Buffer.Data (Buffer.Length) := Zlib.Byte (Value mod 256);
      end if;
   end Append_Byte;

   procedure Append_U16 (Buffer : in out Byte_Buffer; Value : Natural; OK : in out Boolean) is
   begin
      Append_Byte (Buffer, Value, OK);
      Append_Byte (Buffer, Value / 256, OK);
   end Append_U16;

   procedure Append_U32 (Buffer : in out Byte_Buffer; Value : Interfaces.Unsigned_32; OK : in out Boolean) is
      V : Interfaces.Unsigned_32 := Value;
   begin
      for Index in 1 .. 4 loop
         pragma Unreferenced (Index);
         Append_Byte (Buffer, Natural (V and Interfaces.Unsigned_32 (16#FF#)), OK);
         V := Interfaces.Shift_Right (V, 8);
      end loop;
   end Append_U32;

   procedure Append_Text (Buffer : in out Byte_Buffer; Value : String; OK : in out Boolean) is
   begin
      for C of Value loop
         Append_Byte (Buffer, Character'Pos (C), OK);
      end loop;
   end Append_Text;

   function Build_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Output_Sink'Class;
      Deflate : Boolean;
      External_Method : String := "";
      Source_Path : String := "";
      Source_Name : String := "")
      return Archive.Archives.Errors.Error_Code
   is
      Central : Byte_Buffer;
      OK      : Boolean := True;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Entry_Count : Natural := 0;
      Offset  : Interfaces.Unsigned_32 := 0;
      External : constant Boolean := External_Method /= "";

      procedure Write_Buffer (Buffer : Byte_Buffer) is
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Buffer.Length));
      begin
         for Index in 1 .. Buffer.Length loop
            Data (Ada.Streams.Stream_Element_Offset (Index)) :=
              Ada.Streams.Stream_Element (Buffer.Data (Index));
         end loop;
         Write (Sink, Data, Write_Status);
         if Write_Status = Archive.Archives.Errors.Ok then
            Offset := Offset + Interfaces.Unsigned_32 (Buffer.Length);
         else
            OK := False;
         end if;
      end Write_Buffer;

      procedure Write_U32_Data (Value : Interfaces.Unsigned_32) is
         Buffer : Byte_Buffer;
      begin
         Append_U32 (Buffer, Value, OK);
         Write_Buffer (Buffer);
      end Write_U32_Data;

      procedure Write_Bytes (Bytes : Zlib.Byte_Array; Good : out Boolean) is
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
      begin
         Good := False;
         if Bytes'Length = 0 then
            Good := True;
            return;
         end if;

         for Index in Bytes'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
              Ada.Streams.Stream_Element (Bytes (Index));
         end loop;
         Write (Sink, Data, Write_Status);
         if Write_Status = Archive.Archives.Errors.Ok then
            Offset := Offset + Interfaces.Unsigned_32 (Bytes'Length);
            Good := True;
         else
            OK := False;
         end if;
      end Write_Bytes;

      function Directory_Name (Name : String) return String is
      begin
         if Name'Length > 0 and then Name (Name'Last) = '/' then
            return Name;
         end if;
         return Name & "/";
      end Directory_Name;

      function Parent_Directory (Path : String) return String is
      begin
         for Index in reverse Path'Range loop
            if Path (Index) = '/' then
               if Index = Path'First then
                  return "/";
               end if;
               return Path (Path'First .. Index - 1);
            end if;
         end loop;
         return ".";
      end Parent_Directory;

      function Has_Source_Mutations return Boolean is
      begin
         for Change of Plan.Changes loop
            if Change.Request.Action in Archive.Writes.Plans.Replace_File
              | Archive.Writes.Plans.Remove_Entry
              | Archive.Writes.Plans.Rename_Entry
            then
               return True;
            end if;
         end loop;
         return False;
      end Has_Source_Mutations;

      function Source_Change_For
        (Id : Archive.Types.Entry_Id)
         return Natural
      is
         Position : Natural := 0;
      begin
         for Change of Plan.Changes loop
            Position := Position + 1;
            if Change.Request.Source_Entry = Id
              and then Change.Request.Action in Archive.Writes.Plans.Replace_File
                | Archive.Writes.Plans.Remove_Entry
                | Archive.Writes.Plans.Rename_Entry
            then
               return Position;
            end if;
         end loop;
         return 0;
      end Source_Change_For;

      procedure Measure_File
        (Path : String;
         Size : out Interfaces.Unsigned_32;
         CRC  : out Archive.Types.CRC32_Value;
         Good : out Boolean)
      is
         Input : Ada.Streams.Stream_IO.File_Type;
         Data  : Ada.Streams.Stream_Element_Array (1 .. File_Chunk_Size);
         Last  : Ada.Streams.Stream_Element_Offset := 0;
         State : CryptoLib.Checksums.CRC32_State;
         Total : Interfaces.Unsigned_32 := 0;
      begin
         Good := False;
         Size := 0;
         CRC := 0;
         CryptoLib.Checksums.CRC32_Reset (State);
         Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Path);
         loop
            Ada.Streams.Stream_IO.Read (Input, Data, Last);
            exit when Last < Data'First;
            declare
               Count : constant Natural := Natural (Last - Data'First + 1);
            begin
               if Interfaces.Unsigned_32'Last - Total < Interfaces.Unsigned_32 (Count) then
                  Ada.Streams.Stream_IO.Close (Input);
                  return;
               end if;
               CryptoLib.Checksums.CRC32_Update (State, Data (Data'First .. Last));
               Total := Total + Interfaces.Unsigned_32 (Count);
            end;
            exit when Last < Data'Last;
         end loop;
         Ada.Streams.Stream_IO.Close (Input);
         Size := Total;
         CRC := Archive.Types.CRC32_Value (CryptoLib.Checksums.CRC32_Value (State));
         Good := True;
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Good := False;
      end Measure_File;

      procedure Copy_File (Path : String; Good : out Boolean) is
         Input : Ada.Streams.Stream_IO.File_Type;
         Data  : Ada.Streams.Stream_Element_Array (1 .. File_Chunk_Size);
         Last  : Ada.Streams.Stream_Element_Offset := 0;
      begin
         Good := False;
         Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Path);
         loop
            Ada.Streams.Stream_IO.Read (Input, Data, Last);
            exit when Last < Data'First;
            Write (Sink, Data (Data'First .. Last), Write_Status);
            if Write_Status /= Archive.Archives.Errors.Ok then
               Ada.Streams.Stream_IO.Close (Input);
               return;
            end if;
            Offset := Offset + Interfaces.Unsigned_32 (Last - Data'First + 1);
            exit when Last < Data'Last;
         end loop;
         Ada.Streams.Stream_IO.Close (Input);
         Good := True;
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Good := False;
      end Copy_File;

      procedure Append_Central
        (Name         : String;
         CRC          : Archive.Types.CRC32_Value;
         Plain_Size   : Interfaces.Unsigned_32;
         Payload_Size : Interfaces.Unsigned_32;
         Method       : Natural;
         Flags        : Natural;
         Local_Offset : Interfaces.Unsigned_32)
      is
      begin
         Append_U32 (Central, 16#0201_4B50#, OK);
         Append_U16 (Central, 20, OK);
         Append_U16 (Central, 20, OK);
         Append_U16 (Central, Flags, OK);
         Append_U16 (Central, Method, OK);
         Append_U16 (Central, 0, OK);
         Append_U16 (Central, 0, OK);
         Append_U32 (Central, Interfaces.Unsigned_32 (CRC), OK);
         Append_U32 (Central, Payload_Size, OK);
         Append_U32 (Central, Plain_Size, OK);
         Append_U16 (Central, Name'Length, OK);
         Append_U16 (Central, 0, OK);
         Append_U16 (Central, 0, OK);
         Append_U16 (Central, 0, OK);
         Append_U16 (Central, 0, OK);
         Append_U32 (Central, 0, OK);
         Append_U32 (Central, Local_Offset, OK);
         Append_Text (Central, Name, OK);
      end Append_Central;

      procedure Write_Local_Header
        (Name : String;
         CRC  : Archive.Types.CRC32_Value;
         Plain_Size   : Interfaces.Unsigned_32;
         Payload_Size : Interfaces.Unsigned_32;
         Method       : Natural;
         Flags        : Natural)
      is
         Header : Byte_Buffer;
      begin
         Append_U32 (Header, 16#0403_4B50#, OK);
         Append_U16 (Header, 20, OK);
         Append_U16 (Header, Flags, OK);
         Append_U16 (Header, Method, OK);
         Append_U16 (Header, 0, OK);
         Append_U16 (Header, 0, OK);
         Append_U32 (Header, Interfaces.Unsigned_32 (CRC), OK);
         Append_U32 (Header, Payload_Size, OK);
         Append_U32 (Header, Plain_Size, OK);
         Append_U16 (Header, Name'Length, OK);
         Append_U16 (Header, 0, OK);
         Append_Text (Header, Name, OK);
         Write_Buffer (Header);
      end Write_Local_Header;

      procedure Write_Directory (Name : String) is
         Directory : constant String := Directory_Name (Name);
         Local_Offset : constant Interfaces.Unsigned_32 := Offset;
      begin
         Write_Local_Header (Directory, 0, 0, 0, 0, 0);
         Append_Central (Directory, 0, 0, 0, 0, 0, Local_Offset);
         Entry_Count := Entry_Count + 1;
      end Write_Directory;

      procedure Write_Data_Descriptor
        (CRC             : Archive.Types.CRC32_Value;
         Compressed_Size : Interfaces.Unsigned_32;
         Plain_Size      : Interfaces.Unsigned_32)
      is
         Descriptor : Byte_Buffer;
      begin
         Append_U32 (Descriptor, 16#0807_4B50#, OK);
         Append_U32 (Descriptor, Interfaces.Unsigned_32 (CRC), OK);
         Append_U32 (Descriptor, Compressed_Size, OK);
         Append_U32 (Descriptor, Plain_Size, OK);
         Write_Buffer (Descriptor);
      end Write_Data_Descriptor;

      procedure Deflate_File
        (Path : String;
         Compressed_Size : out Interfaces.Unsigned_32;
         Good : out Boolean)
      is
         Input : Ada.Streams.Stream_IO.File_Type;
         Data  : Ada.Streams.Stream_Element_Array (1 .. File_Chunk_Size);
         Last  : Ada.Streams.Stream_Element_Offset := 0;
         Stream : Archive.Compression.Zlib.Deflate_Stream;
         Start_Offset : constant Interfaces.Unsigned_32 := Offset;

         function To_Bytes
           (Slice : Ada.Streams.Stream_Element_Array)
            return Zlib.Byte_Array
         is
            Result : Zlib.Byte_Array (1 .. Natural (Slice'Length));
            Pos : Natural := 1;
         begin
            for Item of Slice loop
               Result (Pos) := Zlib.Byte (Item);
               Pos := Pos + 1;
            end loop;
            return Result;
         end To_Bytes;

         procedure Emit (Step : Archive.Compression.Zlib.Stream_Step_Result) is
            Emitted : Boolean := False;
         begin
            if Step.Status /= Archive.Archives.Errors.Ok then
               OK := False;
               Good := False;
               Write_Status := Step.Status;
               return;
            end if;
            Write_Bytes (Step.Bytes, Emitted);
            if not Emitted then
               Good := False;
            end if;
         end Emit;
      begin
         Good := False;
         Compressed_Size := 0;
         Archive.Compression.Zlib.Open
           (Stream,
            Archive.Compression.Zlib.Raw_Deflate,
            Max_Output_Bytes => Archive.Types.Compressed_Size (Interfaces.Unsigned_32'Last));

         Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Path);
         loop
            Ada.Streams.Stream_IO.Read (Input, Data, Last);
            exit when Last < Data'First;
            declare
               Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
                 Archive.Compression.Zlib.Append
                   (Stream, To_Bytes (Data (Data'First .. Last)));
            begin
               Emit (Step);
               if not OK then
                  Ada.Streams.Stream_IO.Close (Input);
                  declare
                     Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                       Archive.Compression.Zlib.Close (Stream);
                  begin
                     pragma Unreferenced (Closed);
                  end;
                  return;
               end if;
            end;
            exit when Last < Data'Last;
         end loop;
         Ada.Streams.Stream_IO.Close (Input);

         declare
            Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Finish (Stream);
            Closed : Archive.Compression.Zlib.Stream_Close_Result;
         begin
            Emit (Final);
            Closed := Archive.Compression.Zlib.Close (Stream);
            if Closed.Status /= Archive.Archives.Errors.Ok then
               OK := False;
               Good := False;
               Write_Status := Closed.Status;
               return;
            end if;
         end;

         Compressed_Size := Offset - Start_Offset;
         Good := OK;
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            declare
               Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                 Archive.Compression.Zlib.Close (Stream);
            begin
               pragma Unreferenced (Closed);
            exception
               when others =>
                  null;
            end;
            Good := False;
            OK := False;
      end Deflate_File;

      procedure Stage_External_Compressed_File
        (Path              : String;
         Method            : out Interfaces.Unsigned_16;
         CRC               : out Archive.Types.CRC32_Value;
         Uncompressed_Size : out Interfaces.Unsigned_64;
         Compressed_Size   : out Interfaces.Unsigned_32;
         Staged_Path       : out Ada.Strings.Unbounded.Unbounded_String;
         Good              : out Boolean)
      is
         Root    : constant String := Parent_Directory (Path);
         Staged  : constant String :=
           Archive.Temporary_Resources.Fresh_Sibling_Path
             (Root, Path, "zip-external-payload");
         Status  : Zlib.Status_Code := Zlib.Ok;
         Raw_CRC : Interfaces.Unsigned_32 := 0;
         Raw_Compressed_Size : Interfaces.Unsigned_64 := 0;
      begin
         Good := False;
         Method := 0;
         CRC := 0;
         Uncompressed_Size := 0;
         Compressed_Size := 0;
         Staged_Path := Null_Unbounded_String;

         if Staged = "" then
            Write_Status := Archive.Archives.Errors.Write_Failed;
            return;
         end if;

         Zlib.Compress_ZIP_External_File_To_File
           (Path, Staged, External_Method, Method, Raw_CRC, Uncompressed_Size,
            Raw_Compressed_Size, Status);

         if Status /= Zlib.Ok
           or else Uncompressed_Size > Interfaces.Unsigned_64 (Interfaces.Unsigned_32'Last)
           or else Raw_Compressed_Size > Interfaces.Unsigned_64 (Interfaces.Unsigned_32'Last)
         then
            if Ada.Directories.Exists (Staged) then
               Ada.Directories.Delete_File (Staged);
            end if;
            Write_Status :=
              (if Status = Zlib.Unsupported_Method
               then Archive.Archives.Errors.Unsupported_Method
               else Archive.Archives.Errors.Write_Failed);
            return;
         end if;

         Compressed_Size := Interfaces.Unsigned_32 (Raw_Compressed_Size);
         CRC := Archive.Types.CRC32_Value (Raw_CRC);
         Staged_Path := To_Unbounded_String (Staged);
         Good := True;
      exception
         when others =>
            if Staged /= "" and then Ada.Directories.Exists (Staged) then
               begin
                  Ada.Directories.Delete_File (Staged);
               exception
                  when others =>
                     null;
               end;
            end if;
            Write_Status := Archive.Archives.Errors.Write_Failed;
            Good := False;
      end Stage_External_Compressed_File;

      procedure Write_File_Record (Name : String; Path : String) is
         Size : Interfaces.Unsigned_32 := 0;
         Compressed_Size : Interfaces.Unsigned_32 := 0;
         CRC  : Archive.Types.CRC32_Value := 0;
         Good : Boolean := False;
         Local_Offset : Interfaces.Unsigned_32;
      begin
         Local_Offset := Offset;

         if External then
            declare
               Method : Interfaces.Unsigned_16 := 0;
               Uncompressed_Size : Interfaces.Unsigned_64 := 0;
               Staged : Ada.Strings.Unbounded.Unbounded_String;
            begin
               Stage_External_Compressed_File
                 (Path, Method, CRC, Uncompressed_Size, Compressed_Size, Staged, Good);
               if not Good then
                  OK := False;
                  return;
               end if;

               Size := Interfaces.Unsigned_32 (Uncompressed_Size);
               Write_Local_Header
                 (Name, CRC, Size, Compressed_Size, Natural (Method), 0);
               Copy_File (To_String (Staged), Good);
               if Ada.Directories.Exists (To_String (Staged)) then
                  Ada.Directories.Delete_File (To_String (Staged));
               end if;
               if not Good then
                  OK := False;
                  return;
               end if;
               Append_Central
                 (Name, CRC, Size, Compressed_Size, Natural (Method), 0, Local_Offset);
            end;
         else
            Measure_File (Path, Size, CRC, Good);
            if not Good then
               OK := False;
               return;
            end if;
         end if;

         if not External and then Deflate then
            Write_Local_Header (Name, 0, 0, 0, 8, 8);
            Deflate_File (Path, Compressed_Size, Good);
            if not Good then
               OK := False;
               return;
            end if;
            Write_Data_Descriptor (CRC, Compressed_Size, Size);
            Append_Central (Name, CRC, Size, Compressed_Size, 8, 8, Local_Offset);
         elsif not External then
            Write_Local_Header (Name, CRC, Size, Size, 0, 0);
            Copy_File (Path, Good);
            if not Good then
               OK := False;
               return;
            end if;
            Append_Central (Name, CRC, Size, Size, 0, 0, Local_Offset);
         end if;
         Entry_Count := Entry_Count + 1;
      end Write_File_Record;

      procedure Write_Streamed_Record
        (Name : String;
         Item : Archive.Archives.Entries.Archive_Entry)
      is
         Local_Offset : constant Interfaces.Unsigned_32 := Offset;
         CRC          : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
         Plain_Size   : Interfaces.Unsigned_32 := 0;
         Payload_Size : Interfaces.Unsigned_32 := 0;
         Start_Data   : Interfaces.Unsigned_32 := 0;
         Stream       : Archive.Compression.Zlib.Deflate_Stream;
         Stream_Open  : Boolean := False;

         procedure Add_Size (Count : Natural) is
         begin
            if Interfaces.Unsigned_32'Last - Plain_Size < Interfaces.Unsigned_32 (Count) then
               OK := False;
               Write_Status := Archive.Archives.Errors.Limit_Exceeded;
            else
               Plain_Size := Plain_Size + Interfaces.Unsigned_32 (Count);
            end if;
         end Add_Size;

         procedure Emit_Deflated (Step : Archive.Compression.Zlib.Stream_Step_Result) is
            Good : Boolean := False;
         begin
            if Step.Status /= Archive.Archives.Errors.Ok then
               OK := False;
               Write_Status := Step.Status;
            else
               Write_Bytes (Step.Bytes, Good);
               if not Good then
                  OK := False;
               end if;
            end if;
         end Emit_Deflated;

         procedure Consume
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
            Good : Boolean := False;
         begin
            Continue := OK;
            if not OK then
               return;
            end if;

            Archive.Verification.CRC32.Update (CRC, Bytes);
            Add_Size (Bytes'Length);
            if not OK then
               Continue := False;
               return;
            end if;

            if Deflate then
               Emit_Deflated (Archive.Compression.Zlib.Append (Stream, Bytes));
            else
               Write_Bytes (Bytes, Good);
               if not Good then
                  OK := False;
               end if;
            end if;

            Continue := OK;
         end Consume;
      begin
         if External then
            OK := False;
            Write_Status := Archive.Archives.Errors.Unsupported_Method;
            return;
         end if;

         Write_Local_Header (Name, 0, 0, 0, (if Deflate then 8 else 0), 8);
         Start_Data := Offset;

         if Deflate then
            Archive.Compression.Zlib.Open
              (Stream,
               Archive.Compression.Zlib.Raw_Deflate,
               Max_Output_Bytes => Archive.Types.Compressed_Size (Interfaces.Unsigned_32'Last));
            Stream_Open := True;
         end if;

         declare
            Payload : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
              Archive.Archives.Readers.Dispatch.Stream_Payload_File
                (Source_Path, Source_Name, Item, Consume'Access);
         begin
            if Payload.Status /= Archive.Archives.Errors.Ok
              or else Payload.Integrity = Archive.Archives.Entries.Failed
            then
               OK := False;
               Write_Status := Payload.Status;
            end if;
         end;

         if OK and then Deflate then
            Emit_Deflated (Archive.Compression.Zlib.Finish (Stream));
         end if;

         if Stream_Open then
            declare
               Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                 Archive.Compression.Zlib.Close (Stream);
            begin
               if OK and then Closed.Status /= Archive.Archives.Errors.Ok then
                  OK := False;
                  Write_Status := Closed.Status;
               end if;
            end;
         end if;

         if OK then
            Payload_Size := Offset - Start_Data;
            Write_Data_Descriptor
              (Archive.Verification.CRC32.Final (CRC), Payload_Size, Plain_Size);
            Append_Central
              (Name, Archive.Verification.CRC32.Final (CRC), Plain_Size,
               Payload_Size, (if Deflate then 8 else 0), 8, Local_Offset);
            Entry_Count := Entry_Count + 1;
         end if;
      exception
         when others =>
            if Stream_Open then
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               exception
                  when others =>
                     null;
               end;
            end if;
            OK := False;
            Write_Status := Archive.Archives.Errors.Write_Failed;
      end Write_Streamed_Record;

      procedure Write_Existing_Record
        (Item : Archive.Archives.Entries.Archive_Entry;
         Name : String)
      is
      begin
         if Item.Kind = Archive.Archives.Entries.Directory then
            Write_Directory (Name);
         elsif Item.Kind = Archive.Archives.Entries.Regular_File then
            Write_Streamed_Record (Name, Item);
         else
            OK := False;
            Write_Status := Archive.Archives.Errors.Unsupported_Method;
         end if;
      end Write_Existing_Record;
   begin
      if Plan.Status /= Archive.Writes.Plans.Write_Plan_Ready then
         return Archive.Archives.Errors.Unsupported_Method;
      elsif Has_Source_Mutations and then Source_Path = "" then
         return Archive.Archives.Errors.Unsupported_Method;
      end if;

      if Source_Path /= "" then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id       : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item     : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For (Id);
            begin
               if not Item.Synthetic then
                  if Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Remove_Entry
                  then
                     null;
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Replace_File
                  then
                     Write_File_Record
                       (To_String (Plan.Changes.Element (Position).Request.Target_Path),
                        To_String (Plan.Changes.Element (Position).Request.Host_Source));
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Rename_Entry
                  then
                     Write_Existing_Record
                       (Item,
                        To_String (Plan.Changes.Element (Position).Request.Replacement_Path));
                  else
                     Write_Existing_Record (Item, To_String (Item.Original_Path));
                  end if;
               end if;
            end;
            exit when not OK;
         end loop;
      end if;

      for Change of Plan.Changes loop
         if Change.Decision /= Archive.Writes.Plans.Entry_Ready then
            OK := False;
         elsif Change.Request.Action = Archive.Writes.Plans.Add_Directory then
            Write_Directory (To_String (Change.Request.Target_Path));
         elsif Change.Request.Action = Archive.Writes.Plans.Add_File then
            Write_File_Record
              (To_String (Change.Request.Target_Path),
               To_String (Change.Request.Host_Source));
         elsif Change.Request.Action in Archive.Writes.Plans.Replace_File
           | Archive.Writes.Plans.Remove_Entry
           | Archive.Writes.Plans.Rename_Entry
         then
            null;
         else
            OK := False;
         end if;
         exit when not OK;
      end loop;

      if OK then
         declare
            Central_Offset : constant Interfaces.Unsigned_32 := Offset;
            Central_Size   : constant Interfaces.Unsigned_32 :=
              Interfaces.Unsigned_32 (Central.Length);
            Trailer : Byte_Buffer;
         begin
            Write_Buffer (Central);
            Append_U32 (Trailer, 16#0605_4B50#, OK);
            Append_U16 (Trailer, 0, OK);
            Append_U16 (Trailer, 0, OK);
            Append_U16 (Trailer, Entry_Count, OK);
            Append_U16 (Trailer, Entry_Count, OK);
            Append_U32 (Trailer, Central_Size, OK);
            Append_U32 (Trailer, Central_Offset, OK);
            Append_U16 (Trailer, 0, OK);
            Write_Buffer (Trailer);
         end;
      end if;

      if OK then
         return Archive.Archives.Errors.Ok;
      else
         return
           (if Write_Status /= Archive.Archives.Errors.Ok
            then Write_Status
            else Archive.Archives.Errors.Write_Failed);
      end if;
   exception
      when others =>
         return Archive.Archives.Errors.Write_Failed;
   end Build_Stream;

   function Build_Stored_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Output_Sink'Class)
      return Archive.Archives.Errors.Error_Code
   is
   begin
      return Build_Stream (Plan, Sink, Deflate => False);
   end Build_Stored_Stream;

   function Build_Stored_Stream
     (Plan        : Archive.Writes.Plans.Write_Plan;
      Sink        : in out Output_Sink'Class;
      Source_Path : String;
      Source_Name : String := "")
      return Archive.Archives.Errors.Error_Code
   is
   begin
      return Build_Stream
        (Plan, Sink, Deflate => False,
         Source_Path => Source_Path, Source_Name => Source_Name);
   end Build_Stored_Stream;

   function Build_Deflate_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Output_Sink'Class)
      return Archive.Archives.Errors.Error_Code
   is
   begin
      return Build_Stream (Plan, Sink, Deflate => True);
   end Build_Deflate_Stream;

   function Build_Deflate_Stream
     (Plan        : Archive.Writes.Plans.Write_Plan;
      Sink        : in out Output_Sink'Class;
      Source_Path : String;
      Source_Name : String := "")
      return Archive.Archives.Errors.Error_Code
   is
   begin
      return Build_Stream
        (Plan, Sink, Deflate => True,
         Source_Path => Source_Path, Source_Name => Source_Name);
   end Build_Deflate_Stream;

   function Build_External_Stream
     (Plan        : Archive.Writes.Plans.Write_Plan;
      Sink        : in out Output_Sink'Class;
      Method_Name : String;
      Source_Path : String := "";
      Source_Name : String := "")
      return Archive.Archives.Errors.Error_Code
   is
   begin
      return Build_Stream
        (Plan, Sink, Deflate => False, External_Method => Method_Name,
         Source_Path => Source_Path, Source_Name => Source_Name);
   end Build_External_Stream;

end Archive.Writes.Zip;
