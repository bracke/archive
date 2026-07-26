with Ada.Streams;
with Ada.Strings.Unbounded;
with Interfaces;

with Tarlib;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Files;
with Tarlib.Inputs;
with Tarlib.Readers;

package body Archive.Archives.Readers.Tar is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Types.Archive_Ordinal;
   use type Archive.Types.Uncompressed_Size;
   use type Interfaces.Unsigned_64;
   use type Tarlib.Errors.Status_Code;

   Payload_Chunk_Size : constant := 8_192;

   function Map_Kind
     (Kind : Tarlib.Entries.Entry_Kind)
      return Archive.Archives.Entries.Entry_Kind
   is
   begin
      case Kind is
         when Tarlib.Entries.Regular_File =>
            return Archive.Archives.Entries.Regular_File;
         when Tarlib.Entries.Directory =>
            return Archive.Archives.Entries.Directory;
         when Tarlib.Entries.Symbolic_Link =>
            return Archive.Archives.Entries.Symbolic_Link;
         when Tarlib.Entries.Hard_Link =>
            return Archive.Archives.Entries.Hard_Link;
         when Tarlib.Entries.Character_Device =>
            return Archive.Archives.Entries.Character_Device;
         when Tarlib.Entries.Block_Device =>
            return Archive.Archives.Entries.Block_Device;
         when Tarlib.Entries.FIFO =>
            return Archive.Archives.Entries.FIFO;
         when Tarlib.Entries.PAX_Extended_Header | Tarlib.Entries.PAX_Global_Header
            | Tarlib.Entries.GNU_Long_Name | Tarlib.Entries.GNU_Long_Link
            | Tarlib.Entries.GNU_Sparse | Tarlib.Entries.Volume_Label
            | Tarlib.Entries.Multi_Volume | Tarlib.Entries.Incremental_Dump =>
            return Archive.Archives.Entries.Metadata_Record;
      end case;
   end Map_Kind;

   function Map_Error
     (Status : Tarlib.Errors.Status)
      return Archive.Archives.Errors.Error_Code
   is
   begin
      case Status.Code is
         when Tarlib.Errors.Success =>
            return Archive.Archives.Errors.Ok;
         when Tarlib.Errors.Input_Failure =>
            return Archive.Archives.Errors.Read_Failed;
         when Tarlib.Errors.Invalid_Archive | Tarlib.Errors.Invalid_Path
            | Tarlib.Errors.Path_Too_Long | Tarlib.Errors.Invalid_Metadata
            | Tarlib.Errors.Invalid_Size | Tarlib.Errors.Numeric_Field_Overflow =>
            return Archive.Archives.Errors.Invalid_Format;
         when others =>
            return Archive.Archives.Errors.Unsupported_Format;
      end case;
   end Map_Error;

   function Trim_Image (Value : String) return String is
   begin
      if Value'Length > 0 and then Value (Value'First) = ' ' then
         return Value (Value'First + 1 .. Value'Last);
      end if;
      return Value;
   end Trim_Image;

   function U64_Image (Value : Interfaces.Unsigned_64) return String is
     (Trim_Image (Interfaces.Unsigned_64'Image (Value)));

   function I64_Image (Value : Interfaces.Integer_64) return String is
     (Trim_Image (Interfaces.Integer_64'Image (Value)));

   function Natural_Image (Value : Natural) return String is
     (Trim_Image (Natural'Image (Value)));

   function Metadata_Text (Value : Tarlib.Entries.Metadata_Text) return String is
     (Tarlib.Entries.Text (Value));

   function TAR_Metadata (Info : Tarlib.Readers.Entry_Info) return String is
      Meta : constant Tarlib.Entries.Metadata := Tarlib.Readers.Metadata (Info);
      Dev  : constant Tarlib.Entries.Device_Numbers := Tarlib.Readers.Device (Info);
      Extended : constant Natural := Tarlib.Readers.Extended_Record_Count (Info);
      XAttrs   : constant Natural := Tarlib.Readers.XAttr_Count (Info);
      ACL_Access : constant Boolean := Tarlib.Readers.ACL_Access (Info) /= "";
      ACL_Default : constant Boolean := Tarlib.Readers.ACL_Default (Info) /= "";
      Flags : constant Boolean := Tarlib.Readers.File_Flags (Info) /= "";
      Multi_Offset : constant Tarlib.Entries.Archive_Offset :=
        Tarlib.Readers.Multi_Volume_Offset (Info);
      Sparse_Count : constant Natural := Tarlib.Readers.Sparse_Extent_Count (Info);
   begin
      return "tar.mode=" & U64_Image (Interfaces.Unsigned_64 (Meta.Mode))
        & ";tar.uid=" & U64_Image (Interfaces.Unsigned_64 (Meta.UID))
        & ";tar.gid=" & U64_Image (Interfaces.Unsigned_64 (Meta.GID))
        & ";tar.mtime=" & I64_Image (Meta.MTime)
        & ";tar.atime=" & I64_Image (Meta.ATime)
        & ";tar.ctime=" & I64_Image (Meta.CTime)
        & ";tar.device_major=" & U64_Image (Interfaces.Unsigned_64 (Dev.Major))
        & ";tar.device_minor=" & U64_Image (Interfaces.Unsigned_64 (Dev.Minor))
        & ";tar.multi_volume_offset=" & U64_Image (Interfaces.Unsigned_64 (Multi_Offset))
        & ";tar.sparse_extents=" & Natural_Image (Sparse_Count)
        & ";tar.sparse_logical_size="
        & U64_Image (Tarlib.Readers.Sparse_Logical_Size (Info))
        & ";tar.sparse_physical_size="
        & U64_Image (Tarlib.Readers.Sparse_Physical_Size (Info))
        & (if Sparse_Count > 0
           then ";tar.sparse_first_offset="
             & U64_Image (Tarlib.Readers.Sparse_Extent_Offset (Info, 1))
             & ";tar.sparse_first_length="
             & U64_Image (Tarlib.Readers.Sparse_Extent_Length (Info, 1))
           else "")
        & ";tar.pax_unknown_records=" & Natural_Image (Extended)
        & (if Extended > 0
           then ";tar.pax_first_key=" & Tarlib.Readers.Extended_Key (Info, 1)
           else "")
        & ";tar.xattrs=" & Natural_Image (XAttrs)
        & (if XAttrs > 0
           then ";tar.xattr_first_name=" & Tarlib.Readers.XAttr_Name (Info, 1)
           else "")
        & ";tar.acl_access=" & (if ACL_Access then "true" else "false")
        & ";tar.acl_default=" & (if ACL_Default then "true" else "false")
        & ";tar.file_flags=" & (if Flags then "true" else "false");
   end TAR_Metadata;

   function Index_Source
     (Source : not null access Tarlib.Inputs.Input_Source'Class)
      return Tar_Index_Result
   is
      Reader : Tarlib.Readers.Reader;
      Status : Tarlib.Errors.Status;
      Info   : Tarlib.Readers.Entry_Info;
      Has_Entry : Boolean := False;
      Result : Tar_Index_Result;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
   begin
      Tarlib.Readers.Initialize (Reader, Source.all, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Result.Status := Map_Error (Status);
         return Result;
      end if;

      loop
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Status);
         if Status.Code /= Tarlib.Errors.Success then
            Result.Status := Map_Error (Status);
            return Result;
         elsif not Has_Entry then
            return Result;
         end if;

         declare
            Path : constant String := Tarlib.Readers.Path (Info);
            Size : constant Tarlib.Byte_Count := Tarlib.Readers.Size (Info);
            Physical_Size : constant Tarlib.Byte_Count :=
              Tarlib.Readers.Sparse_Physical_Size (Info);
            Meta : constant Tarlib.Entries.Metadata := Tarlib.Readers.Metadata (Info);
            Item : Archive.Archives.Entries.Archive_Entry;
         begin
            Item.Ordinal := Ordinal;
            Item.Original_Path := To_Unbounded_String (Path);
            Item.Display_Name := To_Unbounded_String (Path);
            Item.Kind := Map_Kind (Tarlib.Readers.Kind (Info));
            Item.Owner_Name := To_Unbounded_String (Metadata_Text (Meta.User_Name));
            Item.Group_Name := To_Unbounded_String (Metadata_Text (Meta.Group_Name));
            Item.Permissions := To_Unbounded_String (U64_Image (Interfaces.Unsigned_64 (Meta.Mode)));
            Item.Modified_Time := To_Unbounded_String (I64_Image (Meta.MTime));
            Item.Link_Target := To_Unbounded_String (Tarlib.Readers.Link_Path (Info));
            Item.Format_Metadata := To_Unbounded_String (TAR_Metadata (Info));
            Item.Method := Archive.Archives.Entries.No_Compression;
            Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
            Item.Integrity := Archive.Archives.Entries.Not_Checked;
            Item.Compressed :=
              (Present => True,
               Value   => Archive.Types.Uncompressed_Size (Physical_Size));
            Item.Uncompressed :=
              (Present => True,
               Value   => Archive.Types.Uncompressed_Size (Size));
            Result.Entries.Append (Item);
            Ordinal := Ordinal + 1;
         end;

         Tarlib.Readers.Skip_Entry (Reader, Status);
         if Status.Code /= Tarlib.Errors.Success then
            Result.Status := Map_Error (Status);
            return Result;
         end if;
      end loop;
   end Index_Source;

   function Index_File (Path : String) return Tar_Index_Result is
      Source : aliased Tarlib.Files.File_Input_Source;
      Status : Tarlib.Errors.Status;
   begin
      Tarlib.Files.Open_Read (Source, Path, Status);
      if Status.Code /= Tarlib.Errors.Success then
         return (Status => Map_Error (Status),
                 Entries => Archive.Archives.Entries.Entry_Vectors.Empty_Vector);
      end if;

      declare
         Result : Tar_Index_Result := Index_Source (Source'Access);
         Close_Status : Tarlib.Errors.Status;
      begin
         Tarlib.Files.Close (Source, Close_Status);
         if Result.Status = Archive.Archives.Errors.Ok
           and then Close_Status.Code /= Tarlib.Errors.Success
         then
            Result.Status := Map_Error (Close_Status);
         end if;
         return Result;
      end;
   end Index_File;

   function Stream_Payload_Source
     (Source   : not null access Tarlib.Inputs.Input_Source'Class;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      use type Archive.Archives.Entries.Entry_Kind;
      Reader : Tarlib.Readers.Reader;
      Status : Tarlib.Errors.Status;
      Info   : Tarlib.Readers.Entry_Info;
      Has_Entry : Boolean := False;
      Ordinal : Archive.Types.Archive_Ordinal := 0;
      Written : Archive.Types.Uncompressed_Size := 0;
   begin
      if Item.Kind /= Archive.Archives.Entries.Regular_File then
         return (Status => Archive.Archives.Errors.Unsupported_Method,
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      end if;

      Tarlib.Readers.Initialize (Reader, Source.all, Status);
      if Status.Code /= Tarlib.Errors.Success then
         return (Status => Map_Error (Status),
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      end if;

      loop
         Tarlib.Readers.Next_Entry (Reader, Info, Has_Entry, Status);
         if Status.Code /= Tarlib.Errors.Success then
            return (Status => Map_Error (Status),
                    Integrity => Archive.Archives.Entries.Not_Available,
                    Bytes_Written => Written);
         elsif not Has_Entry then
            return (Status => Archive.Archives.Errors.Invalid_Format,
                    Integrity => Archive.Archives.Entries.Not_Available,
                    Bytes_Written => Written);
         end if;

         if Ordinal = Item.Ordinal then
            declare
               Size_U64 : constant Tarlib.Byte_Count := Tarlib.Readers.Size (Info);
               Size : Archive.Types.Uncompressed_Size;
            begin
               Size := Archive.Types.Uncompressed_Size (Size_U64);

               while Written < Size loop
                  declare
                     Buffer : Ada.Streams.Stream_Element_Array
                       (1 .. Ada.Streams.Stream_Element_Offset
                         (Natural'Min
                            (Payload_Chunk_Size,
                             Natural (Size - Written))));
                     Last : Ada.Streams.Stream_Element_Offset := 0;
                     Continue : Boolean := True;
                  begin
                     Tarlib.Readers.Read (Reader, Buffer, Last, Status);
                     if Status.Code /= Tarlib.Errors.Success then
                        return (Status => Map_Error (Status),
                                Integrity => Archive.Archives.Entries.Not_Available,
                                Bytes_Written => Written);
                     elsif Last < Buffer'First then
                        return (Status => Archive.Archives.Errors.Invalid_Format,
                                Integrity => Archive.Archives.Entries.Failed,
                                Bytes_Written => Written);
                     end if;

                     declare
                        Chunk : Zlib.Byte_Array (1 .. Natural (Last));
                     begin
                        for Pos in Chunk'Range loop
                           Chunk (Pos) := Zlib.Byte
                             (Buffer (Ada.Streams.Stream_Element_Offset (Pos)));
                        end loop;
                        Consumer.all (Chunk, Continue);
                        Written := Written + Archive.Types.Uncompressed_Size (Chunk'Length);
                     end;

                     if not Continue then
                        return (Status => Archive.Archives.Errors.Cancelled,
                                Integrity => Archive.Archives.Entries.Not_Available,
                                Bytes_Written => Written);
                     end if;
                  end;
               end loop;

               Tarlib.Readers.Skip_Entry (Reader, Status);
               if Status.Code /= Tarlib.Errors.Success then
                  return (Status => Map_Error (Status),
                          Integrity => Archive.Archives.Entries.Not_Available,
                          Bytes_Written => Written);
               end if;

               return (Status => Archive.Archives.Errors.Ok,
                       Integrity => Archive.Archives.Entries.Verified,
                       Bytes_Written => Written);
            end;
         end if;

         Tarlib.Readers.Skip_Entry (Reader, Status);
         if Status.Code /= Tarlib.Errors.Success then
            return (Status => Map_Error (Status),
                    Integrity => Archive.Archives.Entries.Not_Available,
                    Bytes_Written => Written);
         end if;
         Ordinal := Ordinal + 1;
      end loop;
   end Stream_Payload_Source;

   function Stream_Payload_File
     (Path     : String;
      Item     : Archive.Archives.Entries.Archive_Entry;
      Consumer : not null access procedure
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean))
      return Stream_Result
   is
      Source : aliased Tarlib.Files.File_Input_Source;
      Open_Status : Tarlib.Errors.Status;
   begin
      Tarlib.Files.Open_Read (Source, Path, Open_Status);
      if Open_Status.Code /= Tarlib.Errors.Success then
         return (Status => Map_Error (Open_Status),
                 Integrity => Archive.Archives.Entries.Not_Available,
                 Bytes_Written => 0);
      end if;

      declare
         Result : constant Stream_Result :=
           Stream_Payload_Source (Source'Access, Item, Consumer);
         Close_Status : Tarlib.Errors.Status;
      begin
         Tarlib.Files.Close (Source, Close_Status);
         if Result.Status = Archive.Archives.Errors.Ok
           and then Close_Status.Code /= Tarlib.Errors.Success
         then
            return (Status => Map_Error (Close_Status),
                    Integrity => Archive.Archives.Entries.Not_Available,
                    Bytes_Written => Result.Bytes_Written);
         end if;
         return Result;
      end;
   end Stream_Payload_File;
end Archive.Archives.Readers.Tar;
