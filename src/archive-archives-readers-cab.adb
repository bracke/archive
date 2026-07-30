with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Readers.Zlib_Bridge;

package body Archive.Archives.Readers.Cab is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Types.Archive_Ordinal;
   use type Archive.Types.Uncompressed_Size;
   use type Interfaces.Unsigned_16;
   use type Zlib.Status_Code;

   package Bridge renames Archive.Archives.Readers.Zlib_Bridge;

   Stream_Chunk : constant := 8_192;

   --  Parsing and MSZIP decompression live in Zlib.Cab_Reader. A cabinet is
   --  small, so this body reads the whole file into memory and calls zlib's
   --  in-memory catalogue/extract; an MSZIP member is reported as Zip_Deflate to
   --  match the app's earlier behaviour (zlib decodes it on extract).

   --  Read the whole file at Path into a Byte_Array. Ok is False on any error.
   function Read_All (Path : String; Ok : out Boolean) return Zlib.Byte_Array is
      File : Ada.Streams.Stream_IO.File_Type;
      Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
   begin
      Ok := False;
      if Size > Ada.Directories.File_Size (Natural'Last) then
         return [1 .. 0 => 0];
      end if;

      declare
         Count  : constant Natural := Natural (Size);
         Buffer : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Count));
         Last   : Ada.Streams.Stream_Element_Offset := 0;
         Result : Zlib.Byte_Array (0 .. (if Count = 0 then -1 else Count - 1));
      begin
         if Count = 0 then
            Ok := True;
            return Result;
         end if;
         Ada.Streams.Stream_IO.Open
           (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         Ada.Streams.Stream_IO.Close (File);
         if Natural (Last - Buffer'First + 1) /= Count then
            return [1 .. 0 => 0];
         end if;
         for I in Result'Range loop
            Result (I) :=
              Zlib.Byte
                (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (I)));
         end loop;
         Ok := True;
         return Result;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Ok := False;
         return [1 .. 0 => 0];
   end Read_All;

   function Index_File (Path : String) return Cab_Index_Result is
      Read_Ok : Boolean;
      Image   : constant Zlib.Byte_Array := Read_All (Path, Read_Ok);
      Status  : Zlib.Status_Code := Zlib.Invalid_Header;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
      Result  : Cab_Index_Result;
   begin
      if not Read_Ok then
         return (Status  => Archive.Archives.Errors.Read_Failed,
                 Entries => <>);
      end if;

      declare
         Items : constant Zlib.Archive_Entry_Array :=
           Zlib.List_CAB_Entries (Image, Status);
      begin
         Result.Status := Bridge.To_Error (Status);
         if Status /= Zlib.Ok then
            return Result;
         end if;

         for Item of Items loop
            declare
               E : Archive.Archives.Entries.Archive_Entry :=
                 Bridge.Base_Entry (Item, Ordinal);
            begin
               --  zlib reports Compression 8 for an MSZIP member; the app
               --  surfaces that as Zip_Deflate.
               if Item.Compression = 8 then
                  E.Method := Archive.Archives.Entries.Zip_Deflate;
               end if;
               Result.Entries.Append (E);
               Ordinal := Ordinal + 1;
            end;
         end loop;
      end;
      return Result;
   end Index_File;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      Read_Ok : Boolean;
      Image   : constant Zlib.Byte_Array := Read_All (Path, Read_Ok);
      Status  : Zlib.Status_Code := Zlib.Invalid_Header;
      Written : Archive.Types.Uncompressed_Size := 0;
   begin
      if Item.Kind /= Archive.Archives.Entries.Regular_File then
         return (Status        => Archive.Archives.Errors.Unsupported_Method,
                 Integrity      => Archive.Archives.Entries.Not_Available,
                 Bytes_Written  => 0);
      elsif not Read_Ok then
         return (Status        => Archive.Archives.Errors.Read_Failed,
                 Integrity      => Archive.Archives.Entries.Not_Available,
                 Bytes_Written  => 0);
      end if;

      declare
         Payload  : constant Zlib.Byte_Array :=
           Zlib.Extract_CAB (Image, To_String (Item.Original_Path), Status);
         Pos      : Natural := Payload'First;
         Continue : Boolean := True;
      begin
         if Status /= Zlib.Ok then
            return (Status        => Bridge.To_Error (Status),
                    Integrity      => Archive.Archives.Entries.Not_Available,
                    Bytes_Written  => 0);
         end if;

         while Pos <= Payload'Last loop
            declare
               Stop : constant Natural :=
                 Natural'Min (Payload'Last, Pos + Stream_Chunk - 1);
            begin
               Consumer.all (Payload (Pos .. Stop), Continue);
               Written :=
                 Written + Archive.Types.Uncompressed_Size (Stop - Pos + 1);
               exit when not Continue;
               Pos := Stop + 1;
            end;
         end loop;

         if not Continue then
            return (Status        => Archive.Archives.Errors.Cancelled,
                    Integrity      => Archive.Archives.Entries.Not_Available,
                    Bytes_Written  => Written);
         end if;
         return (Status        => Archive.Archives.Errors.Ok,
                 Integrity      => Archive.Archives.Entries.Verified,
                 Bytes_Written  => Written);
      end;
   end Stream_Payload_File;

end Archive.Archives.Readers.Cab;
