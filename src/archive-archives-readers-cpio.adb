with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Paths;

package body Archive.Archives.Readers.Cpio is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Types.Archive_Ordinal;
   use type Archive.Types.Source_Offset;
   use type Archive.Types.Uncompressed_Size;

   Header_Size : constant Natural := 110;
   Payload_Chunk_Size : constant Natural := 8_192;

   function Align_4 (Value : Natural) return Natural is
   begin
      if Value > Natural'Last - 3 then
         return Natural'Last;
      end if;
      return ((Value + 3) / 4) * 4;
   end Align_4;

   function Hex_Value (Value : String; Ok : out Boolean) return Natural is
      Result : Natural := 0;
      Digit  : Natural;
   begin
      Ok := False;
      for C of Value loop
         if C in '0' .. '9' then
            Digit := Character'Pos (C) - Character'Pos ('0');
         elsif C in 'A' .. 'F' then
            Digit := 10 + Character'Pos (C) - Character'Pos ('A');
         elsif C in 'a' .. 'f' then
            Digit := 10 + Character'Pos (C) - Character'Pos ('a');
         else
            return 0;
         end if;

         if Result > (Natural'Last - Digit) / 16 then
            return 0;
         end if;
         Result := Result * 16 + Digit;
      end loop;
      Ok := True;
      return Result;
   end Hex_Value;

   function U64_Image (Value : Interfaces.Unsigned_64) return String is
      Image : constant String := Interfaces.Unsigned_64'Image (Value);
   begin
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end U64_Image;

   function Bytes_To_String
     (Bytes : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset;
      Count : Natural)
      return String
   is
      Result : String (1 .. Count);
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Character'Val
             (Bytes (First + Ada.Streams.Stream_Element_Offset (Index - 1)));
      end loop;
      return Result;
   end Bytes_To_String;

   function Read_Exact
     (File  : in out Ada.Streams.Stream_IO.File_Type;
      Count : Natural;
      Bytes : out Ada.Streams.Stream_Element_Array)
      return Boolean
   is
      Last : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Count = 0 then
         return True;
      end if;
      Ada.Streams.Stream_IO.Read (File, Bytes, Last);
      return Last >= Bytes'First
        and then Natural (Last - Bytes'First + 1) = Count;
   end Read_Exact;

   function Kind_From_Mode (Mode : Natural) return Archive.Archives.Entries.Entry_Kind is
      Kind_Bits : constant Natural := Mode - (Mode mod 16#1000#);
   begin
      case Kind_Bits is
         when 16#4000# => return Archive.Archives.Entries.Directory;
         when 16#A000# => return Archive.Archives.Entries.Symbolic_Link;
         when 16#2000# => return Archive.Archives.Entries.Character_Device;
         when 16#6000# => return Archive.Archives.Entries.Block_Device;
         when 16#1000# => return Archive.Archives.Entries.FIFO;
         when 16#C000# => return Archive.Archives.Entries.Socket;
         when 16#8000# => return Archive.Archives.Entries.Regular_File;
         when others   => return Archive.Archives.Entries.Unknown;
      end case;
   end Kind_From_Mode;

   function Index_File (Path : String) return Cpio_Index_Result is
      File    : Ada.Streams.Stream_IO.File_Type;
      Size    : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
      Offset  : Natural := 0;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
      Result  : Cpio_Index_Result;
   begin
      if Size < Ada.Directories.File_Size (Header_Size)
        or else Size > Ada.Directories.File_Size (Natural'Last)
      then
         return (Status  => Archive.Archives.Errors.Invalid_Format,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      while Offset < Natural (Size) loop
         declare
            Header : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Header_Size));
            Text : String (1 .. Header_Size);
            Ok : Boolean;
            Mode : Natural;
            UID : Natural;
            GID : Natural;
            Links : Natural;
            MTime : Natural;
            File_Size : Natural;
            Name_Size : Natural;
            Check : Natural;
            Data_Offset : Natural;
            Next_Offset : Natural;
         begin
            if Natural (Size) - Offset < Header_Size then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;

            Ada.Streams.Stream_IO.Set_Index
              (File, Ada.Streams.Stream_IO.Count (Offset + 1));
            if not Read_Exact (File, Header_Size, Header) then
               Result.Status := Archive.Archives.Errors.Read_Failed;
               exit;
            end if;

            Text := Bytes_To_String (Header, Header'First, Header_Size);
            if Text (1 .. 6) /= "070701" and then Text (1 .. 6) /= "070702" then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;

            Mode := Hex_Value (Text (15 .. 22), Ok);
            if not Ok then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;
            UID := Hex_Value (Text (23 .. 30), Ok);
            if not Ok then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;
            GID := Hex_Value (Text (31 .. 38), Ok);
            if not Ok then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;
            Links := Hex_Value (Text (39 .. 46), Ok);
            if not Ok then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;
            MTime := Hex_Value (Text (47 .. 54), Ok);
            if not Ok then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;
            File_Size := Hex_Value (Text (55 .. 62), Ok);
            if not Ok then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;
            Name_Size := Hex_Value (Text (95 .. 102), Ok);
            if not Ok or else Name_Size = 0 then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;
            Check := Hex_Value (Text (103 .. 110), Ok);
            if not Ok then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;

            if Header_Size > Natural (Size) - Offset
              or else Name_Size > Natural (Size) - Offset - Header_Size
            then
               Result.Status := Archive.Archives.Errors.Invalid_Format;
               exit;
            end if;

            declare
               Name_Bytes : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Name_Size));
               Name_Text : String (1 .. Name_Size);
               Name : Unbounded_String;
               Kind : constant Archive.Archives.Entries.Entry_Kind := Kind_From_Mode (Mode);
            begin
               if not Read_Exact (File, Name_Size, Name_Bytes) then
                  Result.Status := Archive.Archives.Errors.Read_Failed;
                  exit;
               end if;

               Name_Text := Bytes_To_String (Name_Bytes, Name_Bytes'First, Name_Size);
               if Name_Text (Name_Text'Last) /= Character'Val (0) then
                  Result.Status := Archive.Archives.Errors.Invalid_Format;
                  exit;
               end if;
               Name := To_Unbounded_String (Name_Text (Name_Text'First .. Name_Text'Last - 1));
               exit when To_String (Name) = "TRAILER!!!";

               Data_Offset := Align_4 (Offset + Header_Size + Name_Size);
               if Data_Offset > Natural (Size) or else File_Size > Natural (Size) - Data_Offset then
                  Result.Status := Archive.Archives.Errors.Invalid_Format;
                  exit;
               end if;
               Next_Offset := Align_4 (Data_Offset + File_Size);
               if Next_Offset > Natural (Size) then
                  Result.Status := Archive.Archives.Errors.Invalid_Format;
                  exit;
               end if;

               declare
                  Item : Archive.Archives.Entries.Archive_Entry;
                  Display : constant String := To_String (Name);
               begin
                  Item.Ordinal := Ordinal;
                  Item.Original_Path := Name;
                  Item.Display_Name := Name;
                  Item.Kind := Kind;
                  Item.Method := Archive.Archives.Entries.No_Compression;
                  Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
                  Item.Integrity := Archive.Archives.Entries.Not_Checked;
                  if Kind = Archive.Archives.Entries.Regular_File then
                     Item.Data_Offset :=
                       (Present => True,
                        Value   => Archive.Types.Source_Offset (Data_Offset));
                  end if;
                  Item.Compressed :=
                    (Present => True,
                     Value   => Archive.Types.Uncompressed_Size (File_Size));
                  Item.Uncompressed :=
                    (Present => True,
                     Value   => Archive.Types.Uncompressed_Size (File_Size));
                  Item.Owner_Name := To_Unbounded_String (U64_Image (Interfaces.Unsigned_64 (UID)));
                  Item.Group_Name := To_Unbounded_String (U64_Image (Interfaces.Unsigned_64 (GID)));
                  Item.Permissions := To_Unbounded_String ("16#" & Text (15 .. 22) & "#");
                  Item.Modified_Time := To_Unbounded_String (U64_Image (Interfaces.Unsigned_64 (MTime)));
                  Item.Format_Metadata :=
                    To_Unbounded_String
                      ("cpio.links=" & U64_Image (Interfaces.Unsigned_64 (Links))
                       & ";cpio.check=" & U64_Image (Interfaces.Unsigned_64 (Check))
                       & ";cpio.header_offset=" & U64_Image (Interfaces.Unsigned_64 (Offset)));
                  Item.Safety := Archive.Archives.Paths.Normalize (Display).Safety;
                  Result.Entries.Append (Item);
                  Ordinal := Ordinal + 1;
               end;

               Offset := Next_Offset;
            end;
         end;
      end loop;

      if Ada.Streams.Stream_IO.Is_Open (File) then
         Ada.Streams.Stream_IO.Close (File);
      end if;
      return Result;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status  => Archive.Archives.Errors.Limit_Exceeded,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status  => Archive.Archives.Errors.Read_Failed,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
   end Index_File;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      File : Ada.Streams.Stream_IO.File_Type;
      Remaining : Natural;
      Written : Archive.Types.Uncompressed_Size := 0;
   begin
      if Item.Kind /= Archive.Archives.Entries.Regular_File
        or else not Item.Data_Offset.Present
        or else not Item.Uncompressed.Present
      then
         return (Status => Archive.Archives.Errors.Unsupported_Method,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      elsif Item.Data_Offset.Value > Archive.Types.Source_Offset (Natural'Last)
        or else Item.Uncompressed.Value > Archive.Types.Uncompressed_Size (Natural'Last)
      then
         return (Status => Archive.Archives.Errors.Limit_Exceeded,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      end if;

      Remaining := Natural (Item.Uncompressed.Value);
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Set_Index
        (File, Ada.Streams.Stream_IO.Count (Natural (Item.Data_Offset.Value) + 1));

      while Remaining > 0 loop
         declare
            Count : constant Natural := Natural'Min (Payload_Chunk_Size, Remaining);
            Raw   : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Last  : Ada.Streams.Stream_Element_Offset := 0;
            Continue : Boolean := True;
         begin
            Ada.Streams.Stream_IO.Read (File, Raw, Last);
            if Last < Raw'First or else Natural (Last - Raw'First + 1) /= Count then
               Ada.Streams.Stream_IO.Close (File);
               return (Status => Archive.Archives.Errors.Read_Failed,
                       Integrity => Archive.Archives.Entries.Not_Available,
                       Bytes_Written => Written);
            end if;

            declare
               Chunk : Zlib.Byte_Array (1 .. Count);
            begin
               for Index in Chunk'Range loop
                  Chunk (Index) :=
                    Zlib.Byte
                      (Raw (Raw'First + Ada.Streams.Stream_Element_Offset (Index - 1)));
               end loop;
               Consumer.all (Chunk, Continue);
            end;

            Written := Written + Archive.Types.Uncompressed_Size (Count);
            Remaining := Remaining - Count;
            if not Continue then
               Ada.Streams.Stream_IO.Close (File);
               return (Status => Archive.Archives.Errors.Cancelled,
                       Integrity => Archive.Archives.Entries.Not_Available,
                       Bytes_Written => Written);
            end if;
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      return (Status => Archive.Archives.Errors.Ok,
              Integrity => Archive.Archives.Entries.Verified,
              Bytes_Written => Written);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status => Archive.Archives.Errors.Read_Failed,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => Written);
   end Stream_Payload_File;
end Archive.Archives.Readers.Cpio;
