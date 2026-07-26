with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

with Archive.Archives.Paths;

package body Archive.Archives.Readers.Iso is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Types.Uncompressed_Size;
   use type Zlib.Byte;

   Sector_Size : constant Natural := 2_048;
   PVD_Offset  : constant Natural := 16 * Sector_Size;

   function Read_U32_LE (Bytes : Zlib.Byte_Array; Offset : Natural) return Natural is
      Base : constant Natural := Bytes'First + Offset;
   begin
      return Natural (Bytes (Base))
        + Natural (Bytes (Base + 1)) * 256
        + Natural (Bytes (Base + 2)) * 65_536
        + Natural (Bytes (Base + 3)) * 16_777_216;
   end Read_U32_LE;

   function Read_At
     (Path   : String;
      Offset : Natural;
      Count  : Natural)
      return Zlib.Byte_Array
   is
      File   : Ada.Streams.Stream_IO.File_Type;
      Buffer : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Count = 0 then
         return [];
      end if;

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Set_Index
        (File, Ada.Streams.Stream_IO.Positive_Count (Offset + 1));
      Ada.Streams.Stream_IO.Read (File, Buffer, Last);
      Ada.Streams.Stream_IO.Close (File);

      if Last < Buffer'First then
         return [];
      end if;

      declare
         Length : constant Natural := Natural (Last - Buffer'First + 1);
         Result : Zlib.Byte_Array (1 .. Length);
      begin
         for Index in Result'Range loop
            Result (Index) :=
              Zlib.Byte
                (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index - 1)));
         end loop;
         return Result;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return [];
   end Read_At;

   function Clean_Name (Raw : String) return String is
      Last : Natural := Raw'Last;
   begin
      while Last >= Raw'First and then Raw (Last) = ' ' loop
         Last := Last - 1;
      end loop;

      for Index in Raw'First .. Last loop
         if Raw (Index) = ';' then
            if Index = Raw'First then
               return "";
            end if;
            return Raw (Raw'First .. Index - 1);
         end if;
      end loop;

      if Last < Raw'First then
         return "";
      end if;
      return Raw (Raw'First .. Last);
   end Clean_Name;

   function Read_Record_Name
     (Bytes       : Zlib.Byte_Array;
      Offset      : Natural;
      Name_Length : Natural)
      return String
   is
      Start : constant Natural := Bytes'First + Offset + 33;
      Raw   : String (1 .. Name_Length);
   begin
      for Index in Raw'Range loop
         Raw (Index) := Character'Val (Bytes (Start + Index - 1));
      end loop;
      return Clean_Name (Raw);
   end Read_Record_Name;

   procedure Append_Record
     (Entries : in out Archive.Archives.Entries.Entry_Vectors.Vector;
      Path    : String;
      Kind    : Archive.Archives.Entries.Entry_Kind;
      Extent  : Natural;
      Size    : Natural)
   is
      Norm : constant Archive.Archives.Paths.Normalization_Result :=
        Archive.Archives.Paths.Normalize (Path);
      Item : Archive.Archives.Entries.Archive_Entry;
   begin
      Item.Original_Path := To_Unbounded_String (Path);
      Item.Display_Name :=
        To_Unbounded_String (Archive.Archives.Paths.Safe_Display_Name (Path));
      Item.Kind := Kind;
      Item.Method := Archive.Archives.Entries.No_Compression;
      Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
      Item.Integrity := Archive.Archives.Entries.Not_Checked;
      Item.Safety := Norm.Safety;
      Item.Data_Offset :=
        (Present => True,
         Value => Archive.Types.Source_Offset (Extent * Sector_Size));
      Item.Compressed :=
        (Present => True,
         Value => Archive.Types.Uncompressed_Size (Size));
      Item.Uncompressed :=
        (Present => True,
         Value => Archive.Types.Uncompressed_Size (Size));
      Item.Format_Metadata := To_Unbounded_String ("iso9660");
      Entries.Append (Item);
   end Append_Record;

   procedure Walk_Directory
     (Path    : String;
      Prefix  : String;
      Extent  : Natural;
      Size    : Natural;
      Entries : in out Archive.Archives.Entries.Entry_Vectors.Vector;
      Status  : in out Archive.Archives.Errors.Error_Code)
   is
      Directory : constant Zlib.Byte_Array := Read_At (Path, Extent * Sector_Size, Size);
      Position  : Natural := 0;
   begin
      if Directory'Length < Size then
         Status := Archive.Archives.Errors.Read_Failed;
         return;
      end if;

      while Position < Directory'Length loop
         declare
            Record_Length : constant Natural := Natural (Directory (Directory'First + Position));
         begin
            if Record_Length = 0 then
               Position := ((Position / Sector_Size) + 1) * Sector_Size;
            elsif Position + Record_Length > Directory'Length
              or else Record_Length < 34
            then
               Status := Archive.Archives.Errors.Invalid_Format;
               return;
            else
               declare
                  Entry_Extent : constant Natural := Read_U32_LE (Directory, Position + 2);
                  Entry_Size   : constant Natural := Read_U32_LE (Directory, Position + 10);
                  Flags        : constant Zlib.Byte := Directory (Directory'First + Position + 25);
                  Name_Length  : constant Natural := Natural (Directory (Directory'First + Position + 32));
               begin
                  if Name_Length = 1
                    and then (Directory (Directory'First + Position + 33) = 0
                              or else Directory (Directory'First + Position + 33) = 1)
                  then
                     null;
                  elsif Name_Length = 0 or else 33 + Name_Length > Record_Length then
                     Status := Archive.Archives.Errors.Invalid_Format;
                     return;
                  else
                     declare
                        Name : constant String :=
                          Read_Record_Name (Directory, Position, Name_Length);
                        Full : constant String :=
                          (if Prefix'Length = 0 then Name else Prefix & "/" & Name);
                        Is_Dir : constant Boolean := (Natural (Flags) mod 4) >= 2;
                     begin
                        if Name'Length > 0 then
                           Append_Record
                             (Entries, Full,
                              (if Is_Dir
                               then Archive.Archives.Entries.Directory
                               else Archive.Archives.Entries.Regular_File),
                              Entry_Extent, Entry_Size);
                           if Is_Dir and then Entry_Size > 0 then
                              Walk_Directory (Path, Full, Entry_Extent, Entry_Size, Entries, Status);
                              if Status /= Archive.Archives.Errors.Ok then
                                 return;
                              end if;
                           end if;
                        end if;
                     end;
                  end if;
               end;
               Position := Position + Record_Length;
            end if;
         end;
      end loop;
   end Walk_Directory;

   function Index_File (Path : String) return Iso_Index_Result is
      Header : constant Zlib.Byte_Array := Read_At (Path, PVD_Offset, Sector_Size);
      Result : Iso_Index_Result;
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Header'Length < Sector_Size
        or else Header (Header'First) /= 1
        or else Header (Header'First + 1) /= Character'Pos ('C')
        or else Header (Header'First + 2) /= Character'Pos ('D')
        or else Header (Header'First + 3) /= Character'Pos ('0')
        or else Header (Header'First + 4) /= Character'Pos ('0')
        or else Header (Header'First + 5) /= Character'Pos ('1')
      then
         return (Status => Archive.Archives.Errors.Invalid_Format, Entries => <>);
      end if;

      declare
         Root_Length : constant Natural := Natural (Header (Header'First + 156));
         Root_Extent : constant Natural := Read_U32_LE (Header, 156 + 2);
         Root_Size   : constant Natural := Read_U32_LE (Header, 156 + 10);
      begin
         if Root_Length < 34 or else Root_Extent = 0 then
            return (Status => Archive.Archives.Errors.Invalid_Format, Entries => <>);
         end if;
         Walk_Directory (Path, "", Root_Extent, Root_Size, Result.Entries, Status);
         Result.Status := Status;
         return Result;
      end;
   exception
      when Storage_Error =>
         return (Status => Archive.Archives.Errors.Limit_Exceeded, Entries => <>);
      when others =>
         return (Status => Archive.Archives.Errors.Read_Failed, Entries => <>);
   end Index_File;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      File      : Ada.Streams.Stream_IO.File_Type;
      Remaining : Natural :=
        (if Item.Uncompressed.Present then Natural (Item.Uncompressed.Value) else 0);
      Offset    : constant Natural :=
        (if Item.Data_Offset.Present then Natural (Item.Data_Offset.Value) else 0);
      Continue  : Boolean := True;
      Written   : Archive.Types.Uncompressed_Size := 0;
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (32_768));
      Last      : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Item.Kind /= Archive.Archives.Entries.Regular_File
        or else not Item.Data_Offset.Present
      then
         return
           (Status => Archive.Archives.Errors.Unsupported_Method,
            Integrity => Archive.Archives.Entries.Not_Available,
            Bytes_Written => 0);
      end if;

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Set_Index
        (File, Ada.Streams.Stream_IO.Positive_Count (Offset + 1));
      while Remaining > 0 loop
         declare
            Wanted : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset
                (Natural'Min (Remaining, Natural (Buffer'Length)));
         begin
            Ada.Streams.Stream_IO.Read (File, Buffer (1 .. Wanted), Last);
            if Last < Buffer'First then
               Ada.Streams.Stream_IO.Close (File);
               return
                 (Status => Archive.Archives.Errors.Read_Failed,
                  Integrity => Archive.Archives.Entries.Failed,
                  Bytes_Written => Written);
            end if;

            declare
               Count : constant Natural := Natural (Last - Buffer'First + 1);
               Chunk : Zlib.Byte_Array (1 .. Count);
            begin
               for Index in Chunk'Range loop
                  Chunk (Index) :=
                    Zlib.Byte
                      (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index - 1)));
               end loop;
               Consumer.all (Chunk, Continue);
               Written := Written + Archive.Types.Uncompressed_Size (Count);
               Remaining := Remaining - Count;
               exit when not Continue;
            end;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
      return
        (Status =>
           (if Continue then Archive.Archives.Errors.Ok else Archive.Archives.Errors.Cancelled),
         Integrity =>
           (if Continue then Archive.Archives.Entries.Verified else Archive.Archives.Entries.Not_Checked),
         Bytes_Written => Written);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return
           (Status => Archive.Archives.Errors.Read_Failed,
            Integrity => Archive.Archives.Entries.Not_Available,
            Bytes_Written => Written);
   end Stream_Payload_File;
end Archive.Archives.Readers.Iso;
