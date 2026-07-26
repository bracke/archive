with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

with Archive.Archives.Paths;

package body Archive.Archives.Readers.Cab is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Types.Archive_Ordinal;
   use type Archive.Types.Source_Offset;
   use type Archive.Types.Uncompressed_Size;

   Header_Size : constant Natural := 36;
   Folder_Size : constant Natural := 8;
   File_Record_Fixed_Size : constant Natural := 16;
   Data_Block_Header_Size : constant Natural := 8;
   Payload_Chunk_Size : constant Natural := 8_192;

   function Read_U16_LE
     (Bytes : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset)
      return Natural
   is
   begin
      return Natural (Bytes (First))
        + Natural (Bytes (First + 1)) * 256;
   end Read_U16_LE;

   function Read_U32_LE
     (Bytes : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset)
      return Natural
   is
   begin
      return Natural (Bytes (First))
        + Natural (Bytes (First + 1)) * 256
        + Natural (Bytes (First + 2)) * 65_536
        + Natural (Bytes (First + 3)) * 16_777_216;
   end Read_U32_LE;

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

   function Read_Nul_Terminated_Name
     (File       : in out Ada.Streams.Stream_IO.File_Type;
      Max_Length : Natural;
      Ok         : out Boolean)
      return String
   is
      Buffer : String (1 .. Max_Length);
      Count  : Natural := 0;
      Byte   : Ada.Streams.Stream_Element_Array (1 .. 1);
   begin
      Ok := False;
      while Count < Max_Length loop
         if not Read_Exact (File, 1, Byte) then
            return "";
         end if;
         if Byte (1) = 0 then
            Ok := Count > 0;
            if Count = 0 then
               return "";
            end if;
            return Buffer (1 .. Count);
         end if;
         Count := Count + 1;
         Buffer (Count) := Character'Val (Byte (1));
      end loop;
      return "";
   end Read_Nul_Terminated_Name;

   function Index_File (Path : String) return Cab_Index_Result is
      File    : Ada.Streams.Stream_IO.File_Type;
      Size    : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
      Header  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Header_Size));
      Folder  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Folder_Size));
      Data    : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data_Block_Header_Size));
      Result  : Cab_Index_Result;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
   begin
      if Size < Ada.Directories.File_Size (Header_Size + Folder_Size)
        or else Size > Ada.Directories.File_Size (Natural'Last)
      then
         return (Status => Archive.Archives.Errors.Invalid_Format,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      if not Read_Exact (File, Header_Size, Header)
        or else Bytes_To_String (Header, Header'First, 4) /= "MSCF"
      then
         Ada.Streams.Stream_IO.Close (File);
         return (Status => Archive.Archives.Errors.Invalid_Format,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      declare
         Cabinet_Size : constant Natural := Read_U32_LE (Header, Header'First + 8);
         Files_Offset : constant Natural := Read_U32_LE (Header, Header'First + 16);
         Folder_Count : constant Natural := Read_U16_LE (Header, Header'First + 26);
         File_Count   : constant Natural := Read_U16_LE (Header, Header'First + 28);
         Flags        : constant Natural := Read_U16_LE (Header, Header'First + 30);
      begin
         if Cabinet_Size = 0
           or else Cabinet_Size > Natural (Size)
           or else Folder_Count /= 1
           or else File_Count = 0
           or else Files_Offset < Header_Size + Folder_Size
           or else Files_Offset > Natural (Size)
           or else Flags /= 0
         then
            Ada.Streams.Stream_IO.Close (File);
            return (Status => Archive.Archives.Errors.Unsupported_Method,
                    Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
         end if;

         if not Read_Exact (File, Folder_Size, Folder) then
            Ada.Streams.Stream_IO.Close (File);
            return (Status => Archive.Archives.Errors.Read_Failed,
                    Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
         end if;

         declare
            Data_Offset : constant Natural := Read_U32_LE (Folder, Folder'First);
            Block_Count : constant Natural := Read_U16_LE (Folder, Folder'First + 4);
            Compression : constant Natural := Read_U16_LE (Folder, Folder'First + 6);
         begin
            if Compression /= 0 or else Block_Count /= 1
              or else Data_Offset > Natural (Size) - Data_Block_Header_Size
            then
               Ada.Streams.Stream_IO.Close (File);
               return (Status => Archive.Archives.Errors.Unsupported_Method,
                       Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
            end if;

            Ada.Streams.Stream_IO.Set_Index
              (File, Ada.Streams.Stream_IO.Count (Data_Offset + 1));
            if not Read_Exact (File, Data_Block_Header_Size, Data) then
               Ada.Streams.Stream_IO.Close (File);
               return (Status => Archive.Archives.Errors.Read_Failed,
                       Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
            end if;

            declare
               Block_Compressed   : constant Natural := Read_U16_LE (Data, Data'First + 4);
               Block_Uncompressed : constant Natural := Read_U16_LE (Data, Data'First + 6);
               Payload_Offset     : constant Natural := Data_Offset + Data_Block_Header_Size;
            begin
               if Block_Compressed /= Block_Uncompressed
                 or else Payload_Offset > Natural (Size)
                 or else Block_Compressed > Natural (Size) - Payload_Offset
               then
                  Ada.Streams.Stream_IO.Close (File);
                  return (Status => Archive.Archives.Errors.Invalid_Format,
                          Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
               end if;

               Ada.Streams.Stream_IO.Set_Index
                 (File, Ada.Streams.Stream_IO.Count (Files_Offset + 1));
               for Entry_Index in 1 .. File_Count loop
                  declare
                     Fixed : Ada.Streams.Stream_Element_Array
                       (1 .. Ada.Streams.Stream_Element_Offset (File_Record_Fixed_Size));
                     Name_Ok : Boolean;
                  begin
                     if not Read_Exact (File, File_Record_Fixed_Size, Fixed) then
                        Result.Status := Archive.Archives.Errors.Read_Failed;
                        exit;
                     end if;

                     declare
                        File_Size : constant Natural := Read_U32_LE (Fixed, Fixed'First);
                        File_Offset : constant Natural := Read_U32_LE (Fixed, Fixed'First + 4);
                        Folder_Index : constant Natural := Read_U16_LE (Fixed, Fixed'First + 8);
                        Date_Value : constant Natural := Read_U16_LE (Fixed, Fixed'First + 10);
                        Time_Value : constant Natural := Read_U16_LE (Fixed, Fixed'First + 12);
                        Attributes : constant Natural := Read_U16_LE (Fixed, Fixed'First + 14);
                        Name : constant String :=
                          Read_Nul_Terminated_Name
                            (File, Natural'Min (4_096, Natural (Size)), Name_Ok);
                     begin
                        if not Name_Ok
                          or else Folder_Index /= 0
                          or else File_Offset > Block_Uncompressed
                          or else File_Size > Block_Uncompressed - File_Offset
                        then
                           Result.Status := Archive.Archives.Errors.Invalid_Format;
                           exit;
                        end if;

                        declare
                           Item : Archive.Archives.Entries.Archive_Entry;
                        begin
                           Item.Ordinal := Ordinal;
                           Item.Original_Path := To_Unbounded_String (Name);
                           Item.Display_Name :=
                             To_Unbounded_String
                               (Archive.Archives.Paths.Safe_Display_Name (Name));
                           Item.Kind := Archive.Archives.Entries.Regular_File;
                           Item.Method := Archive.Archives.Entries.No_Compression;
                           Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
                           Item.Integrity := Archive.Archives.Entries.Not_Checked;
                           Item.Data_Offset :=
                             (Present => True,
                              Value => Archive.Types.Source_Offset (Payload_Offset + File_Offset));
                           Item.Compressed :=
                             (Present => True,
                              Value => Archive.Types.Uncompressed_Size (File_Size));
                           Item.Uncompressed :=
                             (Present => True,
                              Value => Archive.Types.Uncompressed_Size (File_Size));
                           Item.Modified_Time :=
                             To_Unbounded_String
                               ("cab.date=" & U64_Image (Interfaces.Unsigned_64 (Date_Value))
                                & ";cab.time=" & U64_Image (Interfaces.Unsigned_64 (Time_Value)));
                           Item.Permissions :=
                             To_Unbounded_String
                               ("cab.attrs=" & U64_Image (Interfaces.Unsigned_64 (Attributes)));
                           Item.Format_Metadata :=
                             To_Unbounded_String
                               ("cab.folder=0;cab.block_offset="
                                & U64_Image (Interfaces.Unsigned_64 (Data_Offset))
                                & ";cab.entry=" & U64_Image (Interfaces.Unsigned_64 (Entry_Index)));
                           Item.Safety := Archive.Archives.Paths.Normalize (Name).Safety;
                           Result.Entries.Append (Item);
                           Ordinal := Ordinal + 1;
                        end;
                     end;
                  end;
               end loop;
            end;
         end;
      end;

      if Ada.Streams.Stream_IO.Is_Open (File) then
         Ada.Streams.Stream_IO.Close (File);
      end if;
      return Result;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status => Archive.Archives.Errors.Limit_Exceeded,
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return (Status => Archive.Archives.Errors.Read_Failed,
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
end Archive.Archives.Readers.Cab;
