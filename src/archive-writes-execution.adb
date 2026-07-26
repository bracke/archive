with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

with Archive.Archives.Entries;
with Archive.Archives.Index;
with Archive.Archives.Readers.Dispatch;
with Archive.Archives.Streams;
with Archive.Compression.Zlib;
with Archive.Resource_Limits;
with Archive.Temporary_Resources;
with Archive.Types;
with Archive.Writes.Tar;
with Archive.Writes.Zip;
with Tarlib.Errors;
with Tarlib.Outputs;
with Zlib;
with Zlib.BZip2_Encoder;
with Zlib.Zstd_Encoder;
package body Archive.Writes.Execution is
   use type Archive.Writes.Plans.Plan_Status;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Formats.Format_Id;
   use type Archive.Writes.Plans.Entry_Decision;
   use type Archive.Writes.Results.Write_Status;
   use type Archive.Writes.Plans.Write_Action;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Integrity_State;
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Uncompressed_Size;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Status_Code;

   Chunk_Size : constant Ada.Streams.Stream_Element_Count := 32_768;

   type File_Zip_Sink is limited new Archive.Writes.Zip.Output_Sink with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;

   type File_Tar_Sink is limited new Tarlib.Outputs.Output_Sink with record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;

   type File_Tar_Gzip_Sink is limited new Tarlib.Outputs.Output_Sink with record
      File   : Ada.Streams.Stream_IO.File_Type;
      Stream : Archive.Compression.Zlib.Deflate_Stream;
      Failed : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   end record;

   overriding procedure Write
     (Sink   : in out File_Zip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Status : out Archive.Archives.Errors.Error_Code);

   overriding procedure Write
     (Sink   : in out File_Tar_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   overriding procedure Write
     (Sink   : in out File_Tar_Gzip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   overriding procedure Write
     (Sink   : in out File_Zip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Status : out Archive.Archives.Errors.Error_Code)
   is
   begin
      Ada.Streams.Stream_IO.Write (Sink.File, Data);
      Status := Archive.Archives.Errors.Ok;
   exception
      when others =>
         Status := Archive.Archives.Errors.Write_Failed;
   end Write;

   procedure Write_Zlib_Bytes
     (File   : in out Ada.Streams.Stream_IO.File_Type;
      Bytes  : Zlib.Byte_Array;
      Status : out Archive.Archives.Errors.Error_Code)
   is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
   begin
      Status := Archive.Archives.Errors.Ok;
      if Bytes'Length = 0 then
         return;
      end if;

      for Index in Bytes'Range loop
         Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
           Ada.Streams.Stream_Element (Bytes (Index));
      end loop;
      Ada.Streams.Stream_IO.Write (File, Data);
   exception
      when others =>
         Status := Archive.Archives.Errors.Write_Failed;
   end Write_Zlib_Bytes;

   procedure Write_Text
     (File   : in out Ada.Streams.Stream_IO.File_Type;
      Text   : String;
      Status : out Archive.Archives.Errors.Error_Code)
   is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      Status := Archive.Archives.Errors.Ok;
      if Text'Length = 0 then
         return;
      end if;

      for Index in Text'Range loop
         Data
           (Ada.Streams.Stream_Element_Offset (Index - Text'First + 1)) :=
             Ada.Streams.Stream_Element (Character'Pos (Text (Index)));
      end loop;
      Ada.Streams.Stream_IO.Write (File, Data);
   exception
      when others =>
         Status := Archive.Archives.Errors.Write_Failed;
   end Write_Text;

   function U16_LE_Text (Value : Natural) return String is
   begin
      return [1 => Character'Val (Value mod 256),
              2 => Character'Val ((Value / 256) mod 256)];
   end U16_LE_Text;

   function U32_LE_Text (Value : Natural) return String is
   begin
      return [1 => Character'Val (Value mod 256),
              2 => Character'Val ((Value / 256) mod 256),
              3 => Character'Val ((Value / 65_536) mod 256),
              4 => Character'Val ((Value / 16_777_216) mod 256)];
   end U32_LE_Text;

   overriding procedure Write
     (Sink   : in out File_Tar_Gzip_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
      Input : Zlib.Byte_Array (1 .. Natural (Data'Length));
      Pos   : Natural := 1;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Sink.Failed /= Archive.Archives.Errors.Ok then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      end if;

      for Item of Data loop
         Input (Pos) := Zlib.Byte (Item);
         Pos := Pos + 1;
      end loop;

      declare
         Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
           Archive.Compression.Zlib.Append (Sink.Stream, Input);
      begin
         if Step.Status /= Archive.Archives.Errors.Ok then
            Sink.Failed := Step.Status;
            Result := (Code => Tarlib.Errors.Output_Failure);
            return;
         end if;

         Write_Zlib_Bytes (Sink.File, Step.Bytes, Write_Status);
         if Write_Status /= Archive.Archives.Errors.Ok then
            Sink.Failed := Write_Status;
            Result := (Code => Tarlib.Errors.Output_Failure);
         else
            Result := Tarlib.Errors.OK;
         end if;
      end;
   exception
      when others =>
         Sink.Failed := Archive.Archives.Errors.Write_Failed;
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Write;

   function Finish_Tar_Gzip_Sink
     (Sink : in out File_Tar_Gzip_Sink)
      return Archive.Archives.Errors.Error_Code
   is
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Sink.Failed /= Archive.Archives.Errors.Ok then
         return Sink.Failed;
      end if;

      declare
         Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
           Archive.Compression.Zlib.Finish (Sink.Stream);
         Closed : Archive.Compression.Zlib.Stream_Close_Result;
      begin
         if Final.Status /= Archive.Archives.Errors.Ok then
            return Final.Status;
         end if;

         Write_Zlib_Bytes (Sink.File, Final.Bytes, Write_Status);
         if Write_Status /= Archive.Archives.Errors.Ok then
            return Write_Status;
         end if;

         Closed := Archive.Compression.Zlib.Close (Sink.Stream);
         if Closed.Status /= Archive.Archives.Errors.Ok then
            return Closed.Status;
         end if;
      end;

      return Archive.Archives.Errors.Ok;
   exception
      when others =>
         return Archive.Archives.Errors.Write_Failed;
   end Finish_Tar_Gzip_Sink;

   overriding procedure Write
     (Sink   : in out File_Tar_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
   begin
      Ada.Streams.Stream_IO.Write (Sink.File, Data);
      Result := Tarlib.Errors.OK;
   exception
      when others =>
         Result := (Code => Tarlib.Errors.Output_Failure);
   end Write;

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

   function Fresh_Write_Sibling_Path
     (Root             : String;
      Destination_Path : String;
      Role             : String)
      return String
   is
   begin
      return Archive.Temporary_Resources.Fresh_Sibling_Path
        (Root, Destination_Path, Role);
   end Fresh_Write_Sibling_Path;

   function Verify_Staged_Archive
     (Path            : String;
      Expected_Format : Archive.Archives.Formats.Format_Id;
      Source_Name     : String)
      return Boolean
   is
      Status : constant Archive.Archives.Errors.Error_Code :=
        Archive.Archives.Readers.Dispatch.Verify_File
          (Path, Expected_Format, Source_Name => Source_Name);
   begin
      return Status = Archive.Archives.Errors.Ok;
   end Verify_Staged_Archive;

   function Preflight
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Root             : String;
      Overwrite        : Boolean;
      Cancelled        : Boolean)
      return Archive.Writes.Results.Write_Status
   is
   begin
      if Plan.Status /= Archive.Writes.Plans.Write_Plan_Ready then
         return Archive.Writes.Results.Write_Blocked_By_Plan;
      elsif Cancelled then
         return Archive.Writes.Results.Write_Cancelled;
      elsif not Archive.Temporary_Resources.Under_Root (Root, Destination_Path) then
         return Archive.Writes.Results.Write_Failed_Containment;
      elsif Ada.Directories.Exists (Destination_Path) and then not Overwrite then
         return Archive.Writes.Results.Write_Blocked_By_Plan;
      else
         return Archive.Writes.Results.Write_Completed;
      end if;
   end Preflight;

   procedure Copy_File_Chunked
     (Source_Path : String;
      Target_Path : String;
      OK          : out Boolean)
   is
      Input  : Ada.Streams.Stream_IO.File_Type;
      Output : Ada.Streams.Stream_IO.File_Type;
      Data   : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
      Last   : Ada.Streams.Stream_Element_Offset := 0;
   begin
      OK := False;
      Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Source_Path);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Target_Path);
      loop
         Ada.Streams.Stream_IO.Read (Input, Data, Last);
         exit when Last < Data'First;
         Ada.Streams.Stream_IO.Write (Output, Data (Data'First .. Last));
         exit when Last < Data'Last;
      end loop;
      Ada.Streams.Stream_IO.Close (Input);
      Ada.Streams.Stream_IO.Close (Output);
      OK := True;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Input) then
            Ada.Streams.Stream_IO.Close (Input);
         end if;
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         OK := False;
   end Copy_File_Chunked;

   function Finalize_Staged_Archive
     (Destination_Path : String;
      Temp             : String;
      Root             : String;
      Overwrite        : Boolean;
      Expected_Format  : Archive.Archives.Formats.Format_Id;
      Source_Name      : String;
      Cancelled        : Boolean)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      if Cancelled then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Cancelled);
      elsif not Verify_Staged_Archive (Temp, Expected_Format, Source_Name) then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Verification);
      end if;

      if not Archive.Temporary_Resources.Under_Root (Root, Destination_Path) then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Containment);
      end if;

      if Ada.Directories.Exists (Destination_Path) then
         if not Overwrite then
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
         end if;

         declare
            Backup : constant String :=
              Fresh_Write_Sibling_Path (Root, Destination_Path, "old");
         begin
            if Backup = "" then
               if Ada.Directories.Exists (Temp) then
                  Ada.Directories.Delete_File (Temp);
               end if;
               return (Status => Archive.Writes.Results.Write_Failed_Publish);
            end if;

            Ada.Directories.Rename (Destination_Path, Backup);
            begin
               Ada.Directories.Rename (Temp, Destination_Path);
               Ada.Directories.Delete_File (Backup);
            exception
               when others =>
                  if Ada.Directories.Exists (Destination_Path) then
                     Ada.Directories.Delete_File (Destination_Path);
                  end if;
                  if Ada.Directories.Exists (Backup) then
                     Ada.Directories.Rename (Backup, Destination_Path);
                  end if;
                  return (Status => Archive.Writes.Results.Write_Failed_Publish);
            end;
         end;
      else
         Ada.Directories.Rename (Temp, Destination_Path);
      end if;

      return (Status => Archive.Writes.Results.Write_Completed);
   exception
      when others =>
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Publish);
   end Finalize_Staged_Archive;

   function Zlib_Write_Status
     (Status : Zlib.Status_Code)
      return Archive.Writes.Results.Write_Status
   is
   begin
      case Status is
         when Zlib.Ok =>
            return Archive.Writes.Results.Write_Completed;
         when Zlib.Input_File_Error | Zlib.Output_File_Error =>
            return Archive.Writes.Results.Write_Failed_Staging;
         when Zlib.Unsupported_Method =>
            return Archive.Writes.Results.Write_Blocked_By_Plan;
         when others =>
            return Archive.Writes.Results.Write_Failed_Verification;
      end case;
   end Zlib_Write_Status;

   function Trimmed_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trimmed_Image;

   function Source_Change_For
     (Plan : Archive.Writes.Plans.Write_Plan;
      Id   : Archive.Types.Entry_Id)
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

   function Publish_Seven_Zip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      use Ada.Strings.Unbounded;

      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Stage_Dir : constant String :=
        Fresh_Write_Sibling_Path (Root, Destination_Path, "7z-stage");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);

      function Planned_Count return Natural is
         Count : Natural := 0;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
               begin
                  if not Item.Synthetic
                    and then not (Position > 0
                                  and then Plan.Changes.Element (Position).Request.Action =
                                    Archive.Writes.Plans.Remove_Entry)
                  then
                     Count := Count + 1;
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action in Archive.Writes.Plans.Add_File
                | Archive.Writes.Plans.Add_Directory
            then
               Count := Count + 1;
            end if;
         end loop;
         return Count;
      end Planned_Count;

      Count : constant Natural := Planned_Count;
      Z_Status : Zlib.Status_Code := Zlib.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else Stage_Dir = "" or else Count = 0 then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Directories.Create_Path (Stage_Dir);

      declare
         Input_Paths : Zlib.Text_Array (1 .. Count);
         Entry_Names : Zlib.Text_Array (1 .. Count);
         Next : Natural := 1;

         procedure Add_Path (Input_Path : String; Entry_Name : String) is
         begin
            Input_Paths (Next) := To_Unbounded_String (Input_Path);
            Entry_Names (Next) := To_Unbounded_String (Entry_Name);
            Next := Next + 1;
         end Add_Path;

         procedure Add_Existing
           (Item : Archive.Archives.Entries.Archive_Entry;
            Name : String)
         is
            Extracted : constant String :=
              Stage_Dir & "/entry-" & Trimmed_Image (Next);
         begin
            if Item.Kind = Archive.Archives.Entries.Directory then
               Ada.Directories.Create_Path (Extracted);
               Add_Path (Extracted, Name);
            elsif Item.Kind = Archive.Archives.Entries.Regular_File then
               Zlib.Extract_Seven_Zip_File
                 (Source_Path, Extracted, To_String (Item.Original_Path), Z_Status);
               if Z_Status = Zlib.Ok then
                  Add_Path (Extracted, Name);
               end if;
            else
               Z_Status := Zlib.Unsupported_Method;
            end if;
         end Add_Existing;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
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
                        Add_Path
                          (To_String (Plan.Changes.Element (Position).Request.Host_Source),
                           To_String (Plan.Changes.Element (Position).Request.Target_Path));
                     elsif Position > 0
                       and then Plan.Changes.Element (Position).Request.Action =
                         Archive.Writes.Plans.Rename_Entry
                     then
                        Add_Existing
                          (Item,
                           To_String (Plan.Changes.Element (Position).Request.Replacement_Path));
                     else
                        Add_Existing (Item, To_String (Item.Original_Path));
                     end if;
                  end if;
               end;
               exit when Z_Status /= Zlib.Ok;
            end loop;
         end if;

         if Z_Status = Zlib.Ok then
            for Change of Plan.Changes loop
               if Change.Decision /= Archive.Writes.Plans.Entry_Ready then
                  Z_Status := Zlib.Unsupported_Method;
               elsif Change.Request.Action = Archive.Writes.Plans.Add_File
                 or else Change.Request.Action = Archive.Writes.Plans.Add_Directory
               then
                  Add_Path
                    (To_String (Change.Request.Host_Source),
                     To_String (Change.Request.Target_Path));
               end if;
               exit when Z_Status /= Zlib.Ok;
            end loop;
         end if;

         if Z_Status = Zlib.Ok and then Next /= Count + 1 then
            Z_Status := Zlib.Unsupported_Method;
         end if;

         if Z_Status = Zlib.Ok then
            Zlib.Seven_Zip_Deflate_Files (Input_Paths, Temp, Entry_Names, Z_Status);
         end if;
      end;

      if Ada.Directories.Exists (Stage_Dir) then
         Ada.Directories.Delete_Tree (Stage_Dir);
      end if;

      if Z_Status /= Zlib.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Zlib_Write_Status (Z_Status));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Seven_Zip_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Directories.Exists (Stage_Dir) then
            begin
               Ada.Directories.Delete_Tree (Stage_Dir);
            exception
               when others =>
                  null;
            end;
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Seven_Zip;

   function Publish_Archive_From_File
     (Destination_Path    : String;
      Plan                : Archive.Writes.Plans.Write_Plan;
      Payload_Source_Path : String;
      Overwrite           : Boolean := False;
      Expected_Format     : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format;
      Source_Name         : String := "";
      Cancelled           : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      OK : Boolean := False;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      elsif not Ada.Directories.Exists (Payload_Source_Path) then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Copy_File_Chunked (Payload_Source_Path, Temp, OK);
      if not OK then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite, Expected_Format, Source_Name,
         Cancelled);
   exception
      when others =>
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Archive_From_File;

   function Publish_Zip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Deflate          : Boolean;
      External_Method  : String := "";
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Sink : File_Zip_Sink;
      Build_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Sink.File, Ada.Streams.Stream_IO.Out_File, Temp);
      Build_Status :=
        (if External_Method /= ""
         then Archive.Writes.Zip.Build_External_Stream
           (Plan, Sink, External_Method, Source_Path, Source_Name)
         elsif Deflate
         then
           (if Source_Path = ""
            then Archive.Writes.Zip.Build_Deflate_Stream (Plan, Sink)
            else Archive.Writes.Zip.Build_Deflate_Stream
              (Plan, Sink, Source_Path, Source_Name))
         else
           (if Source_Path = ""
            then Archive.Writes.Zip.Build_Stored_Stream (Plan, Sink)
            else Archive.Writes.Zip.Build_Stored_Stream
              (Plan, Sink, Source_Path, Source_Name)));
      Ada.Streams.Stream_IO.Close (Sink.File);

      if Build_Status /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return
           (Status =>
              (if Build_Status = Archive.Archives.Errors.Write_Failed
               then Archive.Writes.Results.Write_Failed_Staging
               else Archive.Writes.Results.Write_Blocked_By_Plan));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Zip_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
            Ada.Streams.Stream_IO.Close (Sink.File);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Zip;

   function Publish_Zip_Stored
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => False,
         Overwrite => Overwrite, Cancelled => Cancelled);
   end Publish_Zip_Stored;

   function Publish_Zip_Stored
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => False,
         Source_Path => Source_Path,
         Source_Name => Source_Name,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Zip_Stored;

   function Publish_Zip_Deflate
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => True,
         Overwrite => Overwrite, Cancelled => Cancelled);
   end Publish_Zip_Deflate;

   function Publish_Zip_Deflate
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip
        (Destination_Path, Plan, Deflate => True,
         Source_Path => Source_Path,
         Source_Name => Source_Name,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Zip_Deflate;

   function Publish_Zip_External
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Method_Name      : String;
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      use Ada.Strings.Unbounded;

      Root : constant String := Parent_Directory (Destination_Path);
      Stage_Dir : constant String :=
        Fresh_Write_Sibling_Path (Root, Destination_Path, "zip-external-stage");

      procedure Append_Add_File
        (Requests    : in out Archive.Writes.Plans.Write_Request_Vectors.Vector;
         Host_Source : String;
         Target_Path : String)
      is
      begin
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String (Host_Source),
               Target_Path      => To_Unbounded_String (Target_Path),
               Replacement_Path => To_Unbounded_String ("")));
      end Append_Add_File;

      procedure Append_Add_Directory
        (Requests    : in out Archive.Writes.Plans.Write_Request_Vectors.Vector;
         Host_Source : String;
         Target_Path : String)
      is
      begin
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_Directory,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String (Host_Source),
               Target_Path      => To_Unbounded_String (Target_Path),
               Replacement_Path => To_Unbounded_String ("")));
      end Append_Add_Directory;

      procedure Stage_Existing_File
        (Item        : Archive.Archives.Entries.Archive_Entry;
         Slot        : Natural;
         Target_Path : out Unbounded_String;
         Status      : out Archive.Archives.Errors.Error_Code)
      is
         Output : Ada.Streams.Stream_IO.File_Type;
         Path   : constant String :=
           Fresh_Write_Sibling_Path
             (Stage_Dir, Stage_Dir & "/entry-" & Trimmed_Image (Slot), "payload");

         procedure Consume
           (Bytes    : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
            Write_Status : Archive.Archives.Errors.Error_Code :=
              Archive.Archives.Errors.Ok;
         begin
            Continue := Status = Archive.Archives.Errors.Ok;
            if not Continue then
               return;
            end if;

            Write_Zlib_Bytes (Output, Bytes, Write_Status);
            if Write_Status /= Archive.Archives.Errors.Ok then
               Status := Write_Status;
               Continue := False;
            end if;
         end Consume;
      begin
         Status := Archive.Archives.Errors.Ok;
         Target_Path := Null_Unbounded_String;
         if Path = "" then
            Status := Archive.Archives.Errors.Write_Failed;
            return;
         end if;

         Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Path);
         declare
            Payload : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
              Archive.Archives.Readers.Dispatch.Stream_Payload_File
                (Source_Path, Source_Name, Item, Consume'Access);
         begin
            if Payload.Status /= Archive.Archives.Errors.Ok then
               Status := Payload.Status;
            elsif Payload.Integrity = Archive.Archives.Entries.Failed then
               Status := Archive.Archives.Errors.Read_Failed;
            end if;
         end;
         Ada.Streams.Stream_IO.Close (Output);

         if Status = Archive.Archives.Errors.Ok then
            Target_Path := To_Unbounded_String (Path);
         elsif Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Output) then
               Ada.Streams.Stream_IO.Close (Output);
            end if;
            if Path /= "" and then Ada.Directories.Exists (Path) then
               begin
                  Ada.Directories.Delete_File (Path);
               exception
                  when others =>
                     null;
               end;
            end if;
            Status := Archive.Archives.Errors.Write_Failed;
            Target_Path := Null_Unbounded_String;
      end Stage_Existing_File;

      function Build_Staged_Plan
        (Status : out Archive.Archives.Errors.Error_Code)
         return Archive.Writes.Plans.Write_Plan
      is
         Empty_Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
         Empty_Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Empty_Physical).Index;
         Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
         Slot : Natural := 0;

         procedure Add_Existing
           (Item : Archive.Archives.Entries.Archive_Entry;
            Name : String)
         is
            Staged : Unbounded_String;
         begin
            if Status /= Archive.Archives.Errors.Ok then
               return;
            elsif Item.Kind = Archive.Archives.Entries.Directory then
               Append_Add_Directory (Requests, Stage_Dir, Name);
            elsif Item.Kind = Archive.Archives.Entries.Regular_File then
               Slot := Slot + 1;
               Stage_Existing_File (Item, Slot, Staged, Status);
               if Status = Archive.Archives.Errors.Ok then
                  Append_Add_File (Requests, To_String (Staged), Name);
               end if;
            else
               Status := Archive.Archives.Errors.Unsupported_Method;
            end if;
         end Add_Existing;
      begin
         Status := Archive.Archives.Errors.Ok;

         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For (Plan, Id);
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
                     Append_Add_File
                       (Requests,
                        To_String (Plan.Changes.Element (Position).Request.Host_Source),
                        To_String (Plan.Changes.Element (Position).Request.Target_Path));
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Rename_Entry
                  then
                     Add_Existing
                       (Item,
                        To_String
                          (Plan.Changes.Element (Position).Request.Replacement_Path));
                  else
                     Add_Existing (Item, To_String (Item.Original_Path));
                  end if;
               end if;
            end;
            exit when Status /= Archive.Archives.Errors.Ok;
         end loop;

         if Status = Archive.Archives.Errors.Ok then
            for Change of Plan.Changes loop
               if Change.Decision /= Archive.Writes.Plans.Entry_Ready then
                  Status := Archive.Archives.Errors.Unsupported_Method;
               elsif Change.Request.Action = Archive.Writes.Plans.Add_File then
                  Append_Add_File
                    (Requests,
                     To_String (Change.Request.Host_Source),
                     To_String (Change.Request.Target_Path));
               elsif Change.Request.Action = Archive.Writes.Plans.Add_Directory then
                  Append_Add_Directory
                    (Requests,
                     To_String (Change.Request.Host_Source),
                     To_String (Change.Request.Target_Path));
               elsif Change.Request.Action in Archive.Writes.Plans.Replace_File
                 | Archive.Writes.Plans.Remove_Entry
                 | Archive.Writes.Plans.Rename_Entry
               then
                  null;
               else
                  Status := Archive.Archives.Errors.Unsupported_Method;
               end if;
               exit when Status /= Archive.Archives.Errors.Ok;
            end loop;
         end if;

         if Status /= Archive.Archives.Errors.Ok then
            return Archive.Writes.Plans.Build
              (Empty_Index, Requests, Archive.Types.No_Generation);
         end if;

         return Archive.Writes.Plans.Build (Empty_Index, Requests, Plan.Session);
      end Build_Staged_Plan;
   begin
      if Source_Path /= "" then
         declare
            Preflight_Status : constant Archive.Writes.Results.Write_Status :=
              Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
            Stage_Status : Archive.Archives.Errors.Error_Code :=
              Archive.Archives.Errors.Ok;
         begin
            if Preflight_Status /= Archive.Writes.Results.Write_Completed then
               return (Status => Preflight_Status);
            elsif Stage_Dir = "" then
               return (Status => Archive.Writes.Results.Write_Failed_Staging);
            end if;

            Ada.Directories.Create_Path (Root);
            Ada.Directories.Create_Path (Stage_Dir);

            declare
               Staged_Plan : constant Archive.Writes.Plans.Write_Plan :=
                 Build_Staged_Plan (Stage_Status);
               Result : Archive.Writes.Results.Publish_Result;
            begin
               if Stage_Status /= Archive.Archives.Errors.Ok
                 or else Staged_Plan.Status /= Archive.Writes.Plans.Write_Plan_Ready
               then
                  if Ada.Directories.Exists (Stage_Dir) then
                     Ada.Directories.Delete_Tree (Stage_Dir);
                  end if;
                  return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
               end if;

               Result :=
                 Publish_Zip
                   (Destination_Path, Staged_Plan, Deflate => False,
                    External_Method => Method_Name,
                    Overwrite => Overwrite,
                    Cancelled => Cancelled);

               if Ada.Directories.Exists (Stage_Dir) then
                  Ada.Directories.Delete_Tree (Stage_Dir);
               end if;
               return Result;
            end;
         exception
            when others =>
               if Ada.Directories.Exists (Stage_Dir) then
                  begin
                     Ada.Directories.Delete_Tree (Stage_Dir);
                  exception
                     when others =>
                        null;
                  end;
               end if;
               return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end;
      end if;

      return Publish_Zip
        (Destination_Path, Plan, Deflate => False,
         External_Method => Method_Name,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Zip_External;

   function Publish_Zip_BZip2
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip_External
        (Destination_Path, Plan, "BZip2",
         Source_Path => Source_Path,
         Source_Name => Source_Name,
         Overwrite => Overwrite, Cancelled => Cancelled);
   end Publish_Zip_BZip2;

   function Publish_Zip_LZMA
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip_External
        (Destination_Path, Plan, "LZMA",
         Source_Path => Source_Path,
         Source_Name => Source_Name,
         Overwrite => Overwrite, Cancelled => Cancelled);
   end Publish_Zip_LZMA;

   function Publish_Zip_Zstd
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Zip_External
        (Destination_Path, Plan, "ZSTD",
         Source_Path => Source_Path,
         Source_Name => Source_Name,
         Overwrite => Overwrite, Cancelled => Cancelled);
   end Publish_Zip_Zstd;

   function Publish_Tar_Internal
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Sink : File_Tar_Sink;
      Build_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Sink.File, Ada.Streams.Stream_IO.Out_File, Temp);
      Build_Status :=
        (if Source_Path = ""
         then Archive.Writes.Tar.Build_Stream (Plan, Sink)
         else Archive.Writes.Tar.Build_Stream (Plan, Sink, Source_Path));
      Ada.Streams.Stream_IO.Close (Sink.File);

      if Build_Status /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return
           (Status =>
              (if Build_Status = Archive.Archives.Errors.Write_Failed
               then Archive.Writes.Results.Write_Failed_Staging
               else Archive.Writes.Results.Write_Blocked_By_Plan));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Tar_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
            Ada.Streams.Stream_IO.Close (Sink.File);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Tar_Internal;

   function Publish_Tar
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Internal
        (Destination_Path, Plan,
         Source_Path => "",
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar;

   function Publish_Tar
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Internal
        (Destination_Path, Plan,
         Source_Path => Source_Path,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar;

   function Stage_Gzip_As_Tar
     (Source_Path : String;
      Target_Path : String)
      return Archive.Archives.Errors.Error_Code
   is
      Input  : Ada.Streams.Stream_IO.File_Type;
      Output : Ada.Streams.Stream_IO.File_Type;
      Stream : Archive.Compression.Zlib.Inflate_Stream;
      Data   : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
      Last   : Ada.Streams.Stream_Element_Offset := 0;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;

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

      procedure Write_Output (Bytes : Zlib.Byte_Array) is
      begin
         Write_Zlib_Bytes (Output, Bytes, Write_Status);
      end Write_Output;
   begin
      Archive.Compression.Zlib.Open
        (Stream,
         Archive.Compression.Zlib.Gzip_Wrapped,
         Limits =>
           (Max_Output_Bytes => Archive.Types.Uncompressed_Size
              (Archive.Resource_Limits.Default_Configured
                 (Archive.Resource_Limits.Temporary_Backing_Bytes)),
            Max_Ratio => 1_000));
      Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Source_Path);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Target_Path);

      loop
         Ada.Streams.Stream_IO.Read (Input, Data, Last);
         exit when Last < Data'First;
         declare
            Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append
                (Stream, To_Bytes (Data (Data'First .. Last)));
         begin
            if Step.Status /= Archive.Archives.Errors.Ok then
               Ada.Streams.Stream_IO.Close (Input);
               Ada.Streams.Stream_IO.Close (Output);
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               return Step.Status;
            end if;
            Write_Output (Step.Bytes);
            if Write_Status /= Archive.Archives.Errors.Ok then
               Ada.Streams.Stream_IO.Close (Input);
               Ada.Streams.Stream_IO.Close (Output);
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               return Write_Status;
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
         if Final.Status /= Archive.Archives.Errors.Ok then
            Ada.Streams.Stream_IO.Close (Output);
            Closed := Archive.Compression.Zlib.Close (Stream);
            return Final.Status;
         end if;
         Write_Output (Final.Bytes);
         Ada.Streams.Stream_IO.Close (Output);
         Closed := Archive.Compression.Zlib.Close (Stream);
         if Write_Status /= Archive.Archives.Errors.Ok then
            return Write_Status;
         elsif Closed.Status /= Archive.Archives.Errors.Ok then
            return Closed.Status;
         else
            return Archive.Archives.Errors.Ok;
         end if;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Input) then
            Ada.Streams.Stream_IO.Close (Input);
         end if;
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         return Archive.Archives.Errors.Read_Failed;
   end Stage_Gzip_As_Tar;

   function Publish_Tar_Gzip_Internal
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Sink : File_Tar_Gzip_Sink;
      Build_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Finish_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Source_Tar : constant String :=
        Fresh_Write_Sibling_Path (Root, Destination_Path, "source-tar");
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else (Source_Path /= "" and then Source_Tar = "") then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Sink.File, Ada.Streams.Stream_IO.Out_File, Temp);
      Archive.Compression.Zlib.Open
        (Sink.Stream,
         Archive.Compression.Zlib.Gzip_Wrapped,
         Max_Output_Bytes => Archive.Types.Compressed_Size'Last);

      if Source_Path /= "" then
         Build_Status := Stage_Gzip_As_Tar (Source_Path, Source_Tar);
      end if;

      if Build_Status = Archive.Archives.Errors.Ok then
         Build_Status :=
           (if Source_Path = ""
            then Archive.Writes.Tar.Build_Stream (Plan, Sink)
            else Archive.Writes.Tar.Build_Stream (Plan, Sink, Source_Tar));
         Finish_Status := Finish_Tar_Gzip_Sink (Sink);
      end if;
      Ada.Streams.Stream_IO.Close (Sink.File);

      if Ada.Directories.Exists (Source_Tar) then
         Ada.Directories.Delete_File (Source_Tar);
      end if;

      if Build_Status /= Archive.Archives.Errors.Ok
        or else Finish_Status /= Archive.Archives.Errors.Ok
      then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return
           (Status =>
              (if Build_Status = Archive.Archives.Errors.Write_Failed
                 or else Finish_Status = Archive.Archives.Errors.Write_Failed
               then Archive.Writes.Results.Write_Failed_Staging
               else Archive.Writes.Results.Write_Blocked_By_Plan));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Tar_GZip_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Sink.File) then
            Ada.Streams.Stream_IO.Close (Sink.File);
         end if;
         if Ada.Directories.Exists (Source_Tar) then
            begin
               Ada.Directories.Delete_File (Source_Tar);
            exception
               when others =>
                  null;
            end;
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Tar_Gzip_Internal;

   function Publish_Tar_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Gzip_Internal
        (Destination_Path, Plan,
         Source_Path => "",
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar_Gzip;

   function Publish_Tar_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
   begin
      return Publish_Tar_Gzip_Internal
        (Destination_Path, Plan,
         Source_Path => Source_Path,
         Overwrite => Overwrite,
         Cancelled => Cancelled);
   end Publish_Tar_Gzip;

   function Publish_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Input  : Ada.Streams.Stream_IO.File_Type;
      Output : Ada.Streams.Stream_IO.File_Type;
      Stream : Archive.Compression.Zlib.Deflate_Stream;
      Data   : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
      Last   : Ada.Streams.Stream_Element_Offset := 0;
      Source : Ada.Strings.Unbounded.Unbounded_String;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;

      function To_Bytes
        (Slice : Ada.Streams.Stream_Element_Array)
         return Zlib.Byte_Array
      is
         Result : Zlib.Byte_Array (1 .. Natural (Slice'Length));
         Pos    : Natural := 1;
      begin
         for Item of Slice loop
            Result (Pos) := Zlib.Byte (Item);
            Pos := Pos + 1;
         end loop;
         return Result;
      end To_Bytes;

      procedure Fail_Cleanup is
      begin
         if Ada.Streams.Stream_IO.Is_Open (Input) then
            Ada.Streams.Stream_IO.Close (Input);
         end if;
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
      exception
         when others =>
            null;
      end Fail_Cleanup;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      if Natural (Plan.Changes.Length) /= 1 then
         return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end if;

      declare
         Change : constant Archive.Writes.Plans.Planned_Change :=
           Plan.Changes.Element (Plan.Changes.First_Index);
      begin
         if Change.Decision /= Archive.Writes.Plans.Entry_Ready
           or else Change.Request.Action not in Archive.Writes.Plans.Add_File
             | Archive.Writes.Plans.Replace_File
           or else Ada.Strings.Unbounded.To_String (Change.Request.Host_Source) = ""
         then
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
         end if;

         Source := Change.Request.Host_Source;
      end;

      if not Ada.Directories.Exists (Ada.Strings.Unbounded.To_String (Source)) then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Open
        (Input, Ada.Streams.Stream_IO.In_File,
         Ada.Strings.Unbounded.To_String (Source));
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);
      Archive.Compression.Zlib.Open
        (Stream,
         Archive.Compression.Zlib.Gzip_Wrapped,
         Max_Output_Bytes => Archive.Types.Compressed_Size'Last);

      loop
         Ada.Streams.Stream_IO.Read (Input, Data, Last);
         exit when Last < Data'First;
         declare
            Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append
                (Stream, To_Bytes (Data (Data'First .. Last)));
         begin
            if Step.Status /= Archive.Archives.Errors.Ok then
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               Fail_Cleanup;
               return (Status => Archive.Writes.Results.Write_Failed_Staging);
            end if;

            Write_Zlib_Bytes (Output, Step.Bytes, Write_Status);
            if Write_Status /= Archive.Archives.Errors.Ok then
               declare
                  Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
                    Archive.Compression.Zlib.Close (Stream);
               begin
                  pragma Unreferenced (Closed);
               end;
               Fail_Cleanup;
               return (Status => Archive.Writes.Results.Write_Failed_Staging);
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
         if Final.Status /= Archive.Archives.Errors.Ok then
            Closed := Archive.Compression.Zlib.Close (Stream);
            Fail_Cleanup;
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;

         Write_Zlib_Bytes (Output, Final.Bytes, Write_Status);
         Ada.Streams.Stream_IO.Close (Output);
         Closed := Archive.Compression.Zlib.Close (Stream);
         if Write_Status /= Archive.Archives.Errors.Ok
           or else Closed.Status /= Archive.Archives.Errors.Ok
         then
            Fail_Cleanup;
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;
      end;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.GZip_Format, Destination_Path, Cancelled);
   exception
      when others =>
         Fail_Cleanup;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Gzip;

   function Publish_Zstd
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Source : Ada.Strings.Unbounded.Unbounded_String;
      Output : Ada.Streams.Stream_IO.File_Type;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Z_Status : Zlib.Status_Code := Zlib.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else Natural (Plan.Changes.Length) /= 1 then
         return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end if;

      declare
         Change : constant Archive.Writes.Plans.Planned_Change :=
           Plan.Changes.Element (Plan.Changes.First_Index);
      begin
         if Change.Decision /= Archive.Writes.Plans.Entry_Ready
           or else Change.Request.Action not in Archive.Writes.Plans.Add_File
             | Archive.Writes.Plans.Replace_File
           or else Ada.Strings.Unbounded.To_String (Change.Request.Host_Source) = ""
         then
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
         end if;

         Source := Change.Request.Host_Source;
      end;

      if not Ada.Directories.Exists (Ada.Strings.Unbounded.To_String (Source)) then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);

      declare
         Size : constant Ada.Directories.File_Size :=
           Ada.Directories.Size (Ada.Strings.Unbounded.To_String (Source));
         Limit : constant Ada.Directories.File_Size :=
           Ada.Directories.File_Size
             (Archive.Resource_Limits.Default_Configured
                (Archive.Resource_Limits.Preview_Input_Bytes));
      begin
         if Size > Limit or else Size > Ada.Directories.File_Size (Natural'Last) then
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;
      end;

      declare
         Plain : constant Archive.Archives.Streams.Buffered_Source :=
           Archive.Archives.Streams.Read_Bounded
             (Ada.Strings.Unbounded.To_String (Source),
              Positive'Max
                (1,
                 Positive
                   (Ada.Directories.Size
                      (Ada.Strings.Unbounded.To_String (Source)))));
      begin
         if Plain.Status /= Archive.Archives.Errors.Ok then
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;

         declare
            Encoded : constant Zlib.Byte_Array :=
              Zlib.Zstd_Encoder.Encode (Plain.Bytes, Z_Status);
         begin
            if Z_Status /= Zlib.Ok then
               return (Status => Zlib_Write_Status (Z_Status));
            end if;

            Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);
            Write_Zlib_Bytes (Output, Encoded, Write_Status);
            Ada.Streams.Stream_IO.Close (Output);
         end;
      end;

      if Write_Status /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Zstd_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Zstd;

   function Publish_Xz
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Source : Ada.Strings.Unbounded.Unbounded_String;
      Output : Ada.Streams.Stream_IO.File_Type;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Z_Status : Zlib.Status_Code := Zlib.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else Natural (Plan.Changes.Length) /= 1 then
         return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end if;

      declare
         Change : constant Archive.Writes.Plans.Planned_Change :=
           Plan.Changes.Element (Plan.Changes.First_Index);
      begin
         if Change.Decision /= Archive.Writes.Plans.Entry_Ready
           or else Change.Request.Action not in Archive.Writes.Plans.Add_File
             | Archive.Writes.Plans.Replace_File
           or else Ada.Strings.Unbounded.To_String (Change.Request.Host_Source) = ""
         then
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
         end if;

         Source := Change.Request.Host_Source;
      end;

      if not Ada.Directories.Exists (Ada.Strings.Unbounded.To_String (Source)) then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);

      declare
         Size : constant Ada.Directories.File_Size :=
           Ada.Directories.Size (Ada.Strings.Unbounded.To_String (Source));
         Limit : constant Ada.Directories.File_Size :=
           Ada.Directories.File_Size
             (Archive.Resource_Limits.Default_Configured
                (Archive.Resource_Limits.Preview_Input_Bytes));
      begin
         if Size > Limit or else Size > Ada.Directories.File_Size (Natural'Last) then
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;
      end;

      declare
         Plain : constant Archive.Archives.Streams.Buffered_Source :=
           Archive.Archives.Streams.Read_Bounded
             (Ada.Strings.Unbounded.To_String (Source),
              Positive'Max
                (1,
                 Positive
                   (Ada.Directories.Size
                      (Ada.Strings.Unbounded.To_String (Source)))));
      begin
         if Plain.Status /= Archive.Archives.Errors.Ok then
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;

         declare
            Encoded : constant Zlib.Byte_Array :=
              Zlib.XZ_LZMA2 (Plain.Bytes, Z_Status);
         begin
            if Z_Status /= Zlib.Ok then
               return (Status => Zlib_Write_Status (Z_Status));
            end if;

            Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);
            Write_Zlib_Bytes (Output, Encoded, Write_Status);
            Ada.Streams.Stream_IO.Close (Output);
         end;
      end;

      if Write_Status /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Xz_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Xz;

   function Publish_Ar
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      use Ada.Strings.Unbounded;

      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Output : Ada.Streams.Stream_IO.File_Type;
      Failed : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;

      function Field (Value : String; Width : Natural) return String is
      begin
         if Value'Length >= Width then
            return Value (Value'First .. Value'First + Width - 1);
         else
            return Value & (1 .. Width - Value'Length => ' ');
         end if;
      end Field;

      function Short_Name (Name : String) return Boolean is
      begin
         return Name'Length > 0
           and then Name'Length <= 15
           and then (for all C of Name => C /= '/' and then C /= ASCII.LF);
      end Short_Name;

      procedure Write_Member_Header
        (Name         : String;
         Payload_Size : Natural)
      is
         Header_Name : constant String :=
           (if Short_Name (Name)
            then Field (Name & "/", 16)
            else Field ("#1/" & Trimmed_Image (Name'Length), 16));
         Stored_Size : constant Natural :=
           Payload_Size + (if Short_Name (Name) then 0 else Name'Length);
         Header : constant String :=
           Header_Name
           & Field ("0", 12)
           & Field ("0", 6)
           & Field ("0", 6)
           & Field ("100644", 8)
           & Field (Trimmed_Image (Stored_Size), 10)
           & "`" & ASCII.LF;
      begin
         Write_Text (Output, Header, Failed);
         if Failed = Archive.Archives.Errors.Ok and then not Short_Name (Name) then
            Write_Text (Output, Name, Failed);
         end if;
      end Write_Member_Header;

      procedure Write_Pad_If_Odd (Size : Natural) is
      begin
         if Failed = Archive.Archives.Errors.Ok and then Size mod 2 = 1 then
            Write_Text (Output, ASCII.LF & "", Failed);
         end if;
      end Write_Pad_If_Odd;

      procedure Write_Host_File (Name : String; Path : String) is
         Input : Ada.Streams.Stream_IO.File_Type;
         Data : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
         Last : Ada.Streams.Stream_Element_Offset := 0;
         Size : constant Natural := Natural (Ada.Directories.Size (Path));
         Written : Natural := 0;
      begin
         if Size > Natural'Last - Name'Length then
            Failed := Archive.Archives.Errors.Limit_Exceeded;
            return;
         end if;

         Write_Member_Header (Name, Size);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         end if;

         Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Path);
         loop
            Ada.Streams.Stream_IO.Read (Input, Data, Last);
            exit when Last < Data'First;
            Ada.Streams.Stream_IO.Write (Output, Data (Data'First .. Last));
            Written := Written + Natural (Last - Data'First + 1);
            exit when Last < Data'Last;
         end loop;
         Ada.Streams.Stream_IO.Close (Input);
         if Written /= Size then
            Failed := Archive.Archives.Errors.Read_Failed;
            return;
         end if;
         Write_Pad_If_Odd (Size + (if Short_Name (Name) then 0 else Name'Length));
      exception
         when Storage_Error =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Failed := Archive.Archives.Errors.Limit_Exceeded;
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Failed := Archive.Archives.Errors.Read_Failed;
      end Write_Host_File;

      procedure Write_Existing
        (Item : Archive.Archives.Entries.Archive_Entry;
         Name : String)
      is
         Total : Natural := 0;
         Continue_Writing : Boolean := True;

         procedure Count_Chunk
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
         begin
            Total := Total + Bytes'Length;
            Continue := Continue_Writing;
         exception
            when Constraint_Error =>
               Continue := False;
               Continue_Writing := False;
               Failed := Archive.Archives.Errors.Limit_Exceeded;
         end Count_Chunk;

         procedure Emit_Chunk
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
            Local : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
         begin
            Write_Zlib_Bytes (Output, Bytes, Local);
            if Local /= Archive.Archives.Errors.Ok then
               Failed := Local;
               Continue_Writing := False;
            end if;
            Continue := Continue_Writing;
         end Emit_Chunk;

         Counted : Archive.Archives.Readers.Dispatch.Stream_Result;
         Emitted : Archive.Archives.Readers.Dispatch.Stream_Result;
      begin
         if Source_Path = "" then
            Failed := Archive.Archives.Errors.Unsupported_Method;
            return;
         elsif Item.Kind /= Archive.Archives.Entries.Regular_File then
            return;
         end if;

         Counted :=
           Archive.Archives.Readers.Dispatch.Stream_Payload_File
             (Source_Path, Source_Path, Item, Count_Chunk'Access);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         elsif Counted.Status /= Archive.Archives.Errors.Ok then
            Failed := Counted.Status;
            return;
         end if;

         Write_Member_Header (Name, Total);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         end if;

         Continue_Writing := True;
         Emitted :=
           Archive.Archives.Readers.Dispatch.Stream_Payload_File
             (Source_Path, Source_Path, Item, Emit_Chunk'Access);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         elsif Emitted.Status /= Archive.Archives.Errors.Ok then
            Failed := Emitted.Status;
            return;
         end if;
         Write_Pad_If_Odd (Total + (if Short_Name (Name) then 0 else Name'Length));
      end Write_Existing;

      function Source_Change_For_Path
        (Id : Archive.Types.Entry_Id)
         return Natural
      is
      begin
         return Source_Change_For (Plan, Id);
      end Source_Change_For_Path;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);
      Write_Text (Output, "!<arch>" & ASCII.LF, Failed);

      if Source_Path /= "" and then Failed = Archive.Archives.Errors.Ok then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For_Path (Id);
               Name : Unbounded_String := Item.Original_Path;
            begin
               if Failed /= Archive.Archives.Errors.Ok then
                  exit;
               elsif Item.Synthetic then
                  null;
               elsif Position > 0 then
                  declare
                     Change : constant Archive.Writes.Plans.Planned_Change :=
                       Plan.Changes.Element (Position);
                  begin
                     case Change.Request.Action is
                        when Archive.Writes.Plans.Remove_Entry =>
                           null;
                        when Archive.Writes.Plans.Rename_Entry =>
                           Name := Change.Request.Replacement_Path;
                           Write_Existing (Item, To_String (Name));
                        when Archive.Writes.Plans.Replace_File =>
                           Write_Host_File
                             (To_String (Change.Request.Target_Path),
                              To_String (Change.Request.Host_Source));
                        when others =>
                           Write_Existing (Item, To_String (Name));
                     end case;
                  end;
               else
                  Write_Existing (Item, To_String (Name));
               end if;
            end;
         end loop;
      end if;

      if Failed = Archive.Archives.Errors.Ok then
         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_File
            then
               Write_Host_File
                 (To_String (Change.Request.Target_Path),
                  To_String (Change.Request.Host_Source));
            elsif Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_Directory
            then
               Failed := Archive.Archives.Errors.Unsupported_Method;
            end if;
            exit when Failed /= Archive.Archives.Errors.Ok;
         end loop;
      end if;

      if Ada.Streams.Stream_IO.Is_Open (Output) then
         Ada.Streams.Stream_IO.Close (Output);
      end if;

      if Failed /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status =>
                   (if Failed = Archive.Archives.Errors.Limit_Exceeded
                    then Archive.Writes.Results.Write_Failed_Staging
                    elsif Failed = Archive.Archives.Errors.Unsupported_Method
                    then Archive.Writes.Results.Write_Blocked_By_Plan
                    else Archive.Writes.Results.Write_Failed_Staging));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Ar_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Ar;

   function Publish_Cpio
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      use Ada.Strings.Unbounded;

      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Output : Ada.Streams.Stream_IO.File_Type;
      Failed : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Written_Bytes : Natural := 0;
      Next_Inode : Natural := 1;

      function Hex8 (Value : Natural) return String is
         Hex_Digits : constant String := "0123456789ABCDEF";
         Current : Natural := Value;
         Result : String (1 .. 8);
      begin
         for Index in reverse Result'Range loop
            Result (Index) := Hex_Digits (Hex_Digits'First + Current mod 16);
            Current := Current / 16;
         end loop;
         return Result;
      end Hex8;

      procedure Write_Cpio_Text (Text : String) is
      begin
         if Failed = Archive.Archives.Errors.Ok then
            Write_Text (Output, Text, Failed);
            if Failed = Archive.Archives.Errors.Ok then
               Written_Bytes := Written_Bytes + Text'Length;
            end if;
         end if;
      end Write_Cpio_Text;

      procedure Pad_4 is
      begin
         while Failed = Archive.Archives.Errors.Ok and then Written_Bytes mod 4 /= 0 loop
            Write_Cpio_Text ([1 => Character'Val (0)]);
         end loop;
      end Pad_4;

      procedure Write_Header
        (Name : String;
         Mode : Natural;
         Size : Natural;
         Links : Natural := 1)
      is
         Name_Size : constant Natural := Name'Length + 1;
      begin
         if Name_Size > Natural'Last - 110 then
            Failed := Archive.Archives.Errors.Limit_Exceeded;
            return;
         end if;

         Write_Cpio_Text
           ("070701"
            & Hex8 (Next_Inode)
            & Hex8 (Mode)
            & Hex8 (0)
            & Hex8 (0)
            & Hex8 (Links)
            & Hex8 (0)
            & Hex8 (Size)
            & Hex8 (0)
            & Hex8 (0)
            & Hex8 (0)
            & Hex8 (0)
            & Hex8 (Name_Size)
            & Hex8 (0));
         Next_Inode := Next_Inode + 1;
         Write_Cpio_Text (Name);
         Write_Cpio_Text ([1 => Character'Val (0)]);
         Pad_4;
      end Write_Header;

      procedure Write_Host_File (Name : String; Path : String) is
         Input : Ada.Streams.Stream_IO.File_Type;
         Data : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
         Last : Ada.Streams.Stream_Element_Offset := 0;
         Size : constant Natural := Natural (Ada.Directories.Size (Path));
         Written : Natural := 0;
      begin
         Write_Header (Name, 16#81A4#, Size);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         end if;

         Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Path);
         loop
            Ada.Streams.Stream_IO.Read (Input, Data, Last);
            exit when Last < Data'First;
            Ada.Streams.Stream_IO.Write (Output, Data (Data'First .. Last));
            Written := Written + Natural (Last - Data'First + 1);
            Written_Bytes := Written_Bytes + Natural (Last - Data'First + 1);
            exit when Last < Data'Last;
         end loop;
         Ada.Streams.Stream_IO.Close (Input);
         if Written /= Size then
            Failed := Archive.Archives.Errors.Read_Failed;
            return;
         end if;
         Pad_4;
      exception
         when Storage_Error =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Failed := Archive.Archives.Errors.Limit_Exceeded;
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Failed := Archive.Archives.Errors.Read_Failed;
      end Write_Host_File;

      procedure Write_Directory (Name : String) is
      begin
         Write_Header (Name, 16#41ED#, 0, Links => 2);
      end Write_Directory;

      procedure Write_Existing
        (Item : Archive.Archives.Entries.Archive_Entry;
         Name : String)
      is
         Total : Natural := 0;
         Continue_Writing : Boolean := True;

         procedure Count_Chunk
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
         begin
            Total := Total + Bytes'Length;
            Continue := Continue_Writing;
         exception
            when Constraint_Error =>
               Continue := False;
               Continue_Writing := False;
               Failed := Archive.Archives.Errors.Limit_Exceeded;
         end Count_Chunk;

         procedure Emit_Chunk
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
            Local : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
         begin
            Write_Zlib_Bytes (Output, Bytes, Local);
            if Local /= Archive.Archives.Errors.Ok then
               Failed := Local;
               Continue_Writing := False;
            else
               Written_Bytes := Written_Bytes + Bytes'Length;
            end if;
            Continue := Continue_Writing;
         end Emit_Chunk;

         Counted : Archive.Archives.Readers.Dispatch.Stream_Result;
         Emitted : Archive.Archives.Readers.Dispatch.Stream_Result;
      begin
         if Item.Kind = Archive.Archives.Entries.Directory then
            Write_Directory (Name);
            return;
         elsif Item.Kind /= Archive.Archives.Entries.Regular_File then
            Failed := Archive.Archives.Errors.Unsupported_Method;
            return;
         elsif Source_Path = "" then
            Failed := Archive.Archives.Errors.Unsupported_Method;
            return;
         end if;

         Counted :=
           Archive.Archives.Readers.Dispatch.Stream_Payload_File
             (Source_Path, Source_Path, Item, Count_Chunk'Access);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         elsif Counted.Status /= Archive.Archives.Errors.Ok then
            Failed := Counted.Status;
            return;
         end if;

         Write_Header (Name, 16#81A4#, Total);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         end if;

         Continue_Writing := True;
         Emitted :=
           Archive.Archives.Readers.Dispatch.Stream_Payload_File
             (Source_Path, Source_Path, Item, Emit_Chunk'Access);
         if Failed /= Archive.Archives.Errors.Ok then
            return;
         elsif Emitted.Status /= Archive.Archives.Errors.Ok then
            Failed := Emitted.Status;
            return;
         end if;
         Pad_4;
      end Write_Existing;

      procedure Write_Trailer is
      begin
         Write_Header ("TRAILER!!!", 0, 0);
      end Write_Trailer;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);

      if Source_Path /= "" and then Failed = Archive.Archives.Errors.Ok then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For (Plan, Id);
               Name : Unbounded_String := Item.Original_Path;
            begin
               if Failed /= Archive.Archives.Errors.Ok then
                  exit;
               elsif Item.Synthetic then
                  null;
               elsif Position > 0 then
                  declare
                     Change : constant Archive.Writes.Plans.Planned_Change :=
                       Plan.Changes.Element (Position);
                  begin
                     case Change.Request.Action is
                        when Archive.Writes.Plans.Remove_Entry =>
                           null;
                        when Archive.Writes.Plans.Rename_Entry =>
                           Name := Change.Request.Replacement_Path;
                           Write_Existing (Item, To_String (Name));
                        when Archive.Writes.Plans.Replace_File =>
                           Write_Host_File
                             (To_String (Change.Request.Target_Path),
                              To_String (Change.Request.Host_Source));
                        when others =>
                           Write_Existing (Item, To_String (Name));
                     end case;
                  end;
               else
                  Write_Existing (Item, To_String (Name));
               end if;
            end;
         end loop;
      end if;

      if Failed = Archive.Archives.Errors.Ok then
         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_File
            then
               Write_Host_File
                 (To_String (Change.Request.Target_Path),
                  To_String (Change.Request.Host_Source));
            elsif Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_Directory
            then
               Write_Directory (To_String (Change.Request.Target_Path));
            end if;
            exit when Failed /= Archive.Archives.Errors.Ok;
         end loop;
      end if;

      if Failed = Archive.Archives.Errors.Ok then
         Write_Trailer;
      end if;

      if Ada.Streams.Stream_IO.Is_Open (Output) then
         Ada.Streams.Stream_IO.Close (Output);
      end if;

      if Failed /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status =>
                   (if Failed = Archive.Archives.Errors.Unsupported_Method
                    then Archive.Writes.Results.Write_Blocked_By_Plan
                    else Archive.Writes.Results.Write_Failed_Staging));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Cpio_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Cpio;

   function Publish_Cab
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      use Ada.Strings.Unbounded;

      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Output : Ada.Streams.Stream_IO.File_Type;
      Failed : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;

      function Host_Size (Path : String; Ok : out Boolean) return Natural is
         Size : Ada.Directories.File_Size;
      begin
         Ok := False;
         if Path = "" or else not Ada.Directories.Exists (Path) then
            return 0;
         end if;
         Size := Ada.Directories.Size (Path);
         if Size > Ada.Directories.File_Size (Natural'Last) then
            return 0;
         end if;
         Ok := True;
         return Natural (Size);
      exception
         when others =>
            Ok := False;
            return 0;
      end Host_Size;

      function Existing_Size
        (Item : Archive.Archives.Entries.Archive_Entry;
         Ok   : out Boolean)
         return Natural
      is
      begin
         Ok := Item.Uncompressed.Present
           and then Item.Uncompressed.Value <=
             Archive.Types.Uncompressed_Size (Natural'Last);
         return (if Ok then Natural (Item.Uncompressed.Value) else 0);
      end Existing_Size;

      function Planned_Name
        (Item     : Archive.Archives.Entries.Archive_Entry;
         Position : Natural)
         return String
      is
      begin
         if Position = 0 then
            return To_String (Item.Original_Path);
         end if;

         declare
            Change : constant Archive.Writes.Plans.Planned_Change :=
              Plan.Changes.Element (Position);
         begin
            case Change.Request.Action is
               when Archive.Writes.Plans.Rename_Entry =>
                  return To_String (Change.Request.Replacement_Path);
               when Archive.Writes.Plans.Replace_File =>
                  return To_String (Change.Request.Target_Path);
               when others =>
                  return To_String (Item.Original_Path);
            end case;
         end;
      end Planned_Name;

      function Planned_Count return Natural is
         Count : Natural := 0;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
               begin
                  if Item.Synthetic then
                     null;
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Remove_Entry
                  then
                     null;
                  elsif Item.Kind = Archive.Archives.Entries.Regular_File then
                     Count := Count + 1;
                  elsif Item.Kind /= Archive.Archives.Entries.Directory then
                     return Natural'Last;
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready then
               if Change.Request.Action = Archive.Writes.Plans.Add_File then
                  Count := Count + 1;
               elsif Change.Request.Action = Archive.Writes.Plans.Add_Directory then
                  return Natural'Last;
               end if;
            end if;
         end loop;
         return Count;
      exception
         when Constraint_Error =>
            return Natural'Last;
      end Planned_Count;

      function Planned_File_Table_Size return Natural is
         Total : Natural := 0;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
               begin
                  if Item.Synthetic
                    or else Item.Kind /= Archive.Archives.Entries.Regular_File
                    or else (Position > 0
                             and then Plan.Changes.Element (Position).Request.Action =
                               Archive.Writes.Plans.Remove_Entry)
                  then
                     null;
                  else
                     declare
                        Name : constant String := Planned_Name (Item, Position);
                     begin
                        Total := Total + 16 + Name'Length + 1;
                     end;
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_File
            then
               Total := Total + 16 + Length (Change.Request.Target_Path) + 1;
            end if;
         end loop;
         return Total;
      exception
         when Constraint_Error =>
            return Natural'Last;
      end Planned_File_Table_Size;

      function Planned_Payload_Size return Natural is
         Total : Natural := 0;
         Ok : Boolean;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
                  Size : Natural := 0;
               begin
                  if Item.Synthetic
                    or else Item.Kind /= Archive.Archives.Entries.Regular_File
                    or else (Position > 0
                             and then Plan.Changes.Element (Position).Request.Action =
                               Archive.Writes.Plans.Remove_Entry)
                  then
                     null;
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Replace_File
                  then
                     Size := Host_Size
                       (To_String
                          (Plan.Changes.Element (Position).Request.Host_Source),
                        Ok);
                     if not Ok then
                        return Natural'Last;
                     end if;
                     Total := Total + Size;
                  else
                     Size := Existing_Size (Item, Ok);
                     if not Ok then
                        return Natural'Last;
                     end if;
                     Total := Total + Size;
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_File
            then
               declare
                  Size : constant Natural :=
                    Host_Size (To_String (Change.Request.Host_Source), Ok);
               begin
                  if not Ok then
                     return Natural'Last;
                  end if;
                  Total := Total + Size;
               end;
            end if;
         end loop;
         return Total;
      exception
         when Constraint_Error =>
            return Natural'Last;
      end Planned_Payload_Size;

      procedure Write_Cab_Text (Text : String) is
      begin
         if Failed = Archive.Archives.Errors.Ok then
            Write_Text (Output, Text, Failed);
         end if;
      end Write_Cab_Text;

      procedure Write_File_Record
        (Name   : String;
         Size   : Natural;
         Offset : Natural)
      is
      begin
         Write_Cab_Text
           (U32_LE_Text (Size)
            & U32_LE_Text (Offset)
            & U16_LE_Text (0)
            & U16_LE_Text (0)
            & U16_LE_Text (0)
            & U16_LE_Text (16#20#)
            & Name
            & Character'Val (0));
      end Write_File_Record;

      procedure Write_Host_Payload (Path : String) is
         Input : Ada.Streams.Stream_IO.File_Type;
         Data : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
         Last : Ada.Streams.Stream_Element_Offset := 0;
      begin
         Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Path);
         loop
            Ada.Streams.Stream_IO.Read (Input, Data, Last);
            exit when Last < Data'First;
            Ada.Streams.Stream_IO.Write (Output, Data (Data'First .. Last));
            exit when Last < Data'Last;
         end loop;
         Ada.Streams.Stream_IO.Close (Input);
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Failed := Archive.Archives.Errors.Read_Failed;
      end Write_Host_Payload;

      procedure Write_Existing_Payload
        (Item : Archive.Archives.Entries.Archive_Entry)
      is
         Continue_Writing : Boolean := True;

         procedure Emit
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
            Local : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
         begin
            Write_Zlib_Bytes (Output, Bytes, Local);
            if Local /= Archive.Archives.Errors.Ok then
               Failed := Local;
               Continue_Writing := False;
            end if;
            Continue := Continue_Writing;
         end Emit;

         Streamed : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
           Archive.Archives.Readers.Dispatch.Stream_Payload_File
             (Source_Path, Source_Path, Item, Emit'Access);
      begin
         if Failed = Archive.Archives.Errors.Ok
           and then Streamed.Status /= Archive.Archives.Errors.Ok
         then
            Failed := Streamed.Status;
         end if;
      end Write_Existing_Payload;

      Count : constant Natural := Planned_Count;
      File_Table_Size : constant Natural := Planned_File_Table_Size;
      Payload_Size : constant Natural := Planned_Payload_Size;
      Files_Offset : constant Natural := 36 + 8;
      Data_Offset : constant Natural := Files_Offset + File_Table_Size;
      Cabinet_Size : constant Natural := Data_Offset + 8 + Payload_Size;
      Offset : Natural := 0;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else Count = 0 or else Count > 65_535
        or else File_Table_Size = Natural'Last
        or else Payload_Size = Natural'Last
        or else Payload_Size > 65_535
      then
         return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end if;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);

      Write_Cab_Text
        ("MSCF"
         & U32_LE_Text (0)
         & U32_LE_Text (Cabinet_Size)
         & U32_LE_Text (0)
         & U32_LE_Text (Files_Offset)
         & U32_LE_Text (0)
         & U16_LE_Text (16#0103#)
         & U16_LE_Text (1)
         & U16_LE_Text (Count)
         & U16_LE_Text (0)
         & U16_LE_Text (1)
         & U16_LE_Text (0));
      Write_Cab_Text
        (U32_LE_Text (Data_Offset)
         & U16_LE_Text (1)
         & U16_LE_Text (0));

      if Source_Path /= "" then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For (Plan, Id);
               Size_OK : Boolean;
               Size : Natural := 0;
            begin
               if Item.Synthetic
                 or else Item.Kind /= Archive.Archives.Entries.Regular_File
                 or else (Position > 0
                          and then Plan.Changes.Element (Position).Request.Action =
                            Archive.Writes.Plans.Remove_Entry)
               then
                  null;
               else
                  if Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Replace_File
                  then
                     Size := Host_Size
                       (To_String
                          (Plan.Changes.Element (Position).Request.Host_Source),
                        Size_OK);
                  else
                     Size := Existing_Size (Item, Size_OK);
                  end if;
                  if not Size_OK then
                     Failed := Archive.Archives.Errors.Read_Failed;
                     exit;
                  end if;
                  Write_File_Record (Planned_Name (Item, Position), Size, Offset);
                  Offset := Offset + Size;
               end if;
            end;
         end loop;
      end if;

      for Change of Plan.Changes loop
         if Change.Decision = Archive.Writes.Plans.Entry_Ready
           and then Change.Request.Action = Archive.Writes.Plans.Add_File
         then
            declare
               Size_OK : Boolean;
               Size : constant Natural :=
                 Host_Size (To_String (Change.Request.Host_Source), Size_OK);
            begin
               if not Size_OK then
                  Failed := Archive.Archives.Errors.Read_Failed;
                  exit;
               end if;
               Write_File_Record (To_String (Change.Request.Target_Path), Size, Offset);
               Offset := Offset + Size;
            end;
         elsif Change.Decision = Archive.Writes.Plans.Entry_Ready
           and then Change.Request.Action = Archive.Writes.Plans.Add_Directory
         then
            Failed := Archive.Archives.Errors.Unsupported_Method;
            exit;
         end if;
      end loop;

      Write_Cab_Text
        (U32_LE_Text (0)
         & U16_LE_Text (Payload_Size)
         & U16_LE_Text (Payload_Size));

      if Source_Path /= "" then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For (Plan, Id);
            begin
               exit when Failed /= Archive.Archives.Errors.Ok;
               if Item.Synthetic
                 or else Item.Kind /= Archive.Archives.Entries.Regular_File
                 or else (Position > 0
                          and then Plan.Changes.Element (Position).Request.Action =
                            Archive.Writes.Plans.Remove_Entry)
               then
                  null;
               elsif Position > 0
                 and then Plan.Changes.Element (Position).Request.Action =
                   Archive.Writes.Plans.Replace_File
               then
                  Write_Host_Payload
                    (To_String
                       (Plan.Changes.Element (Position).Request.Host_Source));
               else
                  Write_Existing_Payload (Item);
               end if;
            end;
         end loop;
      end if;

      for Change of Plan.Changes loop
         exit when Failed /= Archive.Archives.Errors.Ok;
         if Change.Decision = Archive.Writes.Plans.Entry_Ready
           and then Change.Request.Action = Archive.Writes.Plans.Add_File
         then
            Write_Host_Payload (To_String (Change.Request.Host_Source));
         end if;
      end loop;

      if Ada.Streams.Stream_IO.Is_Open (Output) then
         Ada.Streams.Stream_IO.Close (Output);
      end if;

      if Failed /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status =>
                   (if Failed = Archive.Archives.Errors.Unsupported_Method
                    then Archive.Writes.Results.Write_Blocked_By_Plan
                    else Archive.Writes.Results.Write_Failed_Staging));
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Cab_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Cab;

   function Publish_Iso
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      use Ada.Strings.Unbounded;

      Sector_Size : constant Natural := 2_048;
      Root_Sector : constant Natural := 18;
      First_File_Sector : constant Natural := 19;
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Output : Ada.Streams.Stream_IO.File_Type;
      Failed : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;

      function Sector_Count (Size : Natural) return Natural is
      begin
         return (Size + Sector_Size - 1) / Sector_Size;
      end Sector_Count;

      function Root_Name (Name : String; OK : out Boolean) return String is
      begin
         OK := Name'Length > 0
           and then Name'Length <= 64
           and then (for all C of Name => C /= '/' and then C /= Character'Val (0));
         return Name;
      end Root_Name;

      function Host_Size (Path : String; OK : out Boolean) return Natural is
         Size : Ada.Directories.File_Size;
      begin
         OK := False;
         if Path = "" or else not Ada.Directories.Exists (Path) then
            return 0;
         end if;
         Size := Ada.Directories.Size (Path);
         if Size > Ada.Directories.File_Size (Natural'Last) then
            return 0;
         end if;
         OK := True;
         return Natural (Size);
      exception
         when others =>
            OK := False;
            return 0;
      end Host_Size;

      function Entry_Size
        (Item : Archive.Archives.Entries.Archive_Entry;
         OK   : out Boolean)
         return Natural
      is
      begin
         OK := Item.Uncompressed.Present
           and then Item.Uncompressed.Value <=
             Archive.Types.Uncompressed_Size (Natural'Last);
         return (if OK then Natural (Item.Uncompressed.Value) else 0);
      end Entry_Size;

      function Planned_Name
        (Item     : Archive.Archives.Entries.Archive_Entry;
         Position : Natural)
         return String
      is
      begin
         if Position = 0 then
            return To_String (Item.Original_Path);
         end if;

         declare
            Change : constant Archive.Writes.Plans.Planned_Change :=
              Plan.Changes.Element (Position);
         begin
            case Change.Request.Action is
               when Archive.Writes.Plans.Rename_Entry =>
                  return To_String (Change.Request.Replacement_Path);
               when Archive.Writes.Plans.Replace_File =>
                  return To_String (Change.Request.Target_Path);
               when others =>
                  return To_String (Item.Original_Path);
            end case;
         end;
      end Planned_Name;

      function Planned_Count return Natural is
         Count : Natural := 0;
         OK : Boolean;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
               begin
                  if Item.Synthetic
                    or else (Position > 0
                             and then Plan.Changes.Element (Position).Request.Action =
                               Archive.Writes.Plans.Remove_Entry)
                  then
                     null;
                  elsif Item.Kind = Archive.Archives.Entries.Regular_File then
                     declare
                        Name : constant String := Root_Name (Planned_Name (Item, Position), OK);
                     begin
                        if not OK then
                           return Natural'Last;
                        end if;
                        Count := Count + 1;
                     end;
                  elsif Item.Kind /= Archive.Archives.Entries.Directory then
                     return Natural'Last;
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready then
               if Change.Request.Action = Archive.Writes.Plans.Add_File then
                  declare
                     Name : constant String :=
                       Root_Name (To_String (Change.Request.Target_Path), OK);
                  begin
                     if not OK then
                        return Natural'Last;
                     end if;
                     Count := Count + 1;
                  end;
               elsif Change.Request.Action = Archive.Writes.Plans.Add_Directory then
                  return Natural'Last;
               end if;
            end if;
         end loop;
         return Count;
      exception
         when Constraint_Error =>
            return Natural'Last;
      end Planned_Count;

      function Directory_Record_Length (Name_Length : Natural) return Natural is
         Base : constant Natural := 33 + Name_Length;
      begin
         return Base + (if Base mod 2 = 1 then 1 else 0);
      end Directory_Record_Length;

      function Directory_Size return Natural is
         Total : Natural := Directory_Record_Length (1) * 2;
         OK : Boolean;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
               begin
                  if Item.Synthetic
                    or else Item.Kind /= Archive.Archives.Entries.Regular_File
                    or else (Position > 0
                             and then Plan.Changes.Element (Position).Request.Action =
                               Archive.Writes.Plans.Remove_Entry)
                  then
                     null;
                  else
                     declare
                        Name : constant String := Root_Name (Planned_Name (Item, Position), OK);
                     begin
                        if not OK then
                           return Natural'Last;
                        end if;
                        Total := Total + Directory_Record_Length (Name'Length);
                     end;
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_File
            then
               declare
                  Name : constant String :=
                    Root_Name (To_String (Change.Request.Target_Path), OK);
               begin
                  if not OK then
                     return Natural'Last;
                  end if;
                  Total := Total + Directory_Record_Length (Name'Length);
               end;
            end if;
         end loop;
         return Total;
      exception
         when Constraint_Error =>
            return Natural'Last;
      end Directory_Size;

      function Payload_Sectors return Natural is
         Total : Natural := 0;
         OK : Boolean;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
                  Size : Natural := 0;
               begin
                  if Item.Synthetic
                    or else Item.Kind /= Archive.Archives.Entries.Regular_File
                    or else (Position > 0
                             and then Plan.Changes.Element (Position).Request.Action =
                               Archive.Writes.Plans.Remove_Entry)
                  then
                     null;
                  elsif Position > 0
                    and then Plan.Changes.Element (Position).Request.Action =
                      Archive.Writes.Plans.Replace_File
                  then
                     Size := Host_Size
                       (To_String
                          (Plan.Changes.Element (Position).Request.Host_Source),
                        OK);
                     if not OK then
                        return Natural'Last;
                     end if;
                     Total := Total + Sector_Count (Size);
                  else
                     Size := Entry_Size (Item, OK);
                     if not OK then
                        return Natural'Last;
                     end if;
                     Total := Total + Sector_Count (Size);
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_File
            then
               declare
                  Size : constant Natural :=
                    Host_Size (To_String (Change.Request.Host_Source), OK);
               begin
                  if not OK then
                     return Natural'Last;
                  end if;
                  Total := Total + Sector_Count (Size);
               end;
            end if;
         end loop;
         return Total;
      exception
         when Constraint_Error =>
            return Natural'Last;
      end Payload_Sectors;

      procedure Write_Iso_Text (Text : String) is
      begin
         if Failed = Archive.Archives.Errors.Ok then
            Write_Text (Output, Text, Failed);
         end if;
      end Write_Iso_Text;

      procedure Write_Zeroes (Count : Natural) is
      begin
         for Index in 1 .. Count loop
            Write_Iso_Text ([1 => Character'Val (0)]);
            exit when Failed /= Archive.Archives.Errors.Ok;
         end loop;
      end Write_Zeroes;

      function U32_BE_Text (Value : Natural) return String is
      begin
         return [1 => Character'Val ((Value / 16_777_216) mod 256),
                 2 => Character'Val ((Value / 65_536) mod 256),
                 3 => Character'Val ((Value / 256) mod 256),
                 4 => Character'Val (Value mod 256)];
      end U32_BE_Text;

      function U16_BE_Text (Value : Natural) return String is
      begin
         return [1 => Character'Val ((Value / 256) mod 256),
                 2 => Character'Val (Value mod 256)];
      end U16_BE_Text;

      function Directory_Record
        (Name   : String;
         Extent : Natural;
         Size   : Natural;
         Is_Dir : Boolean)
         return String
      is
         Length : constant Natural := Directory_Record_Length (Name'Length);
         Flags : constant Character := Character'Val ((if Is_Dir then 2 else 0));
         Padding : constant String :=
           (if (33 + Name'Length) mod 2 = 1 then [1 => Character'Val (0)] else "");
      begin
         return Character'Val (Length)
           & Character'Val (0)
           & U32_LE_Text (Extent) & U32_BE_Text (Extent)
           & U32_LE_Text (Size) & U32_BE_Text (Size)
           & [1 => Character'Val (126),
              2 => Character'Val (1),
              3 => Character'Val (1),
              4 => Character'Val (0),
              5 => Character'Val (0),
              6 => Character'Val (0),
              7 => Character'Val (0)]
           & Flags
           & Character'Val (0)
           & Character'Val (0)
           & U16_LE_Text (1) & U16_BE_Text (1)
           & Character'Val (Name'Length)
           & Name
           & Padding;
      end Directory_Record;

      procedure Write_Host_Payload (Path : String; Size : Natural) is
         Input : Ada.Streams.Stream_IO.File_Type;
         Data : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
         Last : Ada.Streams.Stream_Element_Offset := 0;
         Written : Natural := 0;
      begin
         Ada.Streams.Stream_IO.Open (Input, Ada.Streams.Stream_IO.In_File, Path);
         loop
            Ada.Streams.Stream_IO.Read (Input, Data, Last);
            exit when Last < Data'First;
            Ada.Streams.Stream_IO.Write (Output, Data (Data'First .. Last));
            Written := Written + Natural (Last - Data'First + 1);
            exit when Last < Data'Last;
         end loop;
         Ada.Streams.Stream_IO.Close (Input);
         if Written /= Size then
            Failed := Archive.Archives.Errors.Read_Failed;
         else
            Write_Zeroes (Sector_Count (Size) * Sector_Size - Size);
         end if;
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (Input) then
               Ada.Streams.Stream_IO.Close (Input);
            end if;
            Failed := Archive.Archives.Errors.Read_Failed;
      end Write_Host_Payload;

      procedure Write_Existing_Payload
        (Item : Archive.Archives.Entries.Archive_Entry;
         Size : Natural)
      is
         Written : Natural := 0;
         Continue_Writing : Boolean := True;

         procedure Emit
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean)
         is
            Local : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
         begin
            Write_Zlib_Bytes (Output, Bytes, Local);
            if Local /= Archive.Archives.Errors.Ok then
               Failed := Local;
               Continue_Writing := False;
            end if;
            Written := Written + Bytes'Length;
            Continue := Continue_Writing;
         end Emit;

         Streamed : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
           Archive.Archives.Readers.Dispatch.Stream_Payload_File
             (Source_Path, Source_Path, Item, Emit'Access);
      begin
         if Streamed.Status /= Archive.Archives.Errors.Ok then
            Failed := Streamed.Status;
         elsif Written /= Size then
            Failed := Archive.Archives.Errors.Read_Failed;
         else
            Write_Zeroes (Sector_Count (Size) * Sector_Size - Size);
         end if;
      end Write_Existing_Payload;

      Count : constant Natural := Planned_Count;
      Root_Dir_Size : constant Natural := Directory_Size;
      Data_Sectors : constant Natural := Payload_Sectors;
      Volume_Sectors : constant Natural := First_File_Sector + Data_Sectors;
      Current_Sector : Natural := First_File_Sector;
      Root_Dir : Unbounded_String;
      OK : Boolean;

      procedure Append_File_Record (Name : String; Size : Natural; Extent : Natural) is
      begin
         Root_Dir := Root_Dir & Directory_Record (Name, Extent, Size, Is_Dir => False);
      end Append_File_Record;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else Count = 0 or else Root_Dir_Size = Natural'Last
        or else Root_Dir_Size > Sector_Size or else Data_Sectors = Natural'Last
      then
         return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end if;

      Root_Dir := To_Unbounded_String
        (Directory_Record ([1 => Character'Val (0)], Root_Sector, Sector_Size, True)
         & Directory_Record ([1 => Character'Val (1)], Root_Sector, Sector_Size, True));

      declare
         Scan_Sector : Natural := First_File_Sector;
      begin
         if Source_Path /= "" then
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
               declare
                  Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Plan.Index, Id);
                  Position : constant Natural := Source_Change_For (Plan, Id);
                  Size : Natural := 0;
               begin
                  if Item.Synthetic
                    or else Item.Kind /= Archive.Archives.Entries.Regular_File
                    or else (Position > 0
                             and then Plan.Changes.Element (Position).Request.Action =
                               Archive.Writes.Plans.Remove_Entry)
                  then
                     null;
                  else
                     if Position > 0
                       and then Plan.Changes.Element (Position).Request.Action =
                         Archive.Writes.Plans.Replace_File
                     then
                        Size := Host_Size
                          (To_String
                             (Plan.Changes.Element (Position).Request.Host_Source),
                           OK);
                     else
                        Size := Entry_Size (Item, OK);
                     end if;
                     if not OK then
                        return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
                     end if;
                     Append_File_Record
                       (Root_Name (Planned_Name (Item, Position), OK),
                        Size, Scan_Sector);
                     if not OK then
                        return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
                     end if;
                     Scan_Sector := Scan_Sector + Sector_Count (Size);
                  end if;
               end;
            end loop;
         end if;

         for Change of Plan.Changes loop
            if Change.Decision = Archive.Writes.Plans.Entry_Ready
              and then Change.Request.Action = Archive.Writes.Plans.Add_File
            then
               declare
                  Size : constant Natural :=
                    Host_Size (To_String (Change.Request.Host_Source), OK);
                  Name : constant String :=
                    Root_Name (To_String (Change.Request.Target_Path), OK);
               begin
                  if not OK then
                     return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
                  end if;
                  Append_File_Record (Name, Size, Scan_Sector);
                  Scan_Sector := Scan_Sector + Sector_Count (Size);
               end;
            end if;
         end loop;
      end;

      Ada.Directories.Create_Path (Root);
      Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);
      Write_Zeroes (16 * Sector_Size);

      declare
         PVD : String (1 .. Sector_Size) := [others => Character'Val (0)];
         Root_Record : constant String :=
           Directory_Record ([1 => Character'Val (0)], Root_Sector, Sector_Size, True);
      begin
         PVD (1) := Character'Val (1);
         PVD (2 .. 6) := "CD001";
         PVD (7) := Character'Val (1);
         PVD (81 .. 112) := "ARCHIVE                         ";
         PVD (121 .. 124) := U32_LE_Text (Volume_Sectors);
         PVD (125 .. 128) := U32_BE_Text (Volume_Sectors);
         PVD (129 .. 132) := U16_LE_Text (1) & U16_BE_Text (1);
         PVD (133 .. 136) := U16_LE_Text (1) & U16_BE_Text (1);
         PVD (137 .. 140) := U16_LE_Text (Sector_Size) & U16_BE_Text (Sector_Size);
         PVD (157 .. 156 + Root_Record'Length) := Root_Record;
         Write_Iso_Text (PVD);
      end;

      declare
         TVD : String (1 .. Sector_Size) := [others => Character'Val (0)];
      begin
         TVD (1) := Character'Val (255);
         TVD (2 .. 6) := "CD001";
         TVD (7) := Character'Val (1);
         Write_Iso_Text (TVD);
      end;

      Write_Iso_Text (To_String (Root_Dir));
      Write_Zeroes (Sector_Size - Length (Root_Dir));

      if Source_Path /= "" then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Plan.Index) loop
            declare
               Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Plan.Index, Id);
               Position : constant Natural := Source_Change_For (Plan, Id);
               Size : Natural := 0;
            begin
               exit when Failed /= Archive.Archives.Errors.Ok;
               if Item.Synthetic
                 or else Item.Kind /= Archive.Archives.Entries.Regular_File
                 or else (Position > 0
                          and then Plan.Changes.Element (Position).Request.Action =
                            Archive.Writes.Plans.Remove_Entry)
               then
                  null;
               elsif Position > 0
                 and then Plan.Changes.Element (Position).Request.Action =
                   Archive.Writes.Plans.Replace_File
               then
                  Size := Host_Size
                    (To_String
                       (Plan.Changes.Element (Position).Request.Host_Source),
                     OK);
                  Write_Host_Payload
                    (To_String
                       (Plan.Changes.Element (Position).Request.Host_Source),
                     Size);
               else
                  Size := Entry_Size (Item, OK);
                  Write_Existing_Payload (Item, Size);
               end if;
            end;
         end loop;
      end if;

      for Change of Plan.Changes loop
         exit when Failed /= Archive.Archives.Errors.Ok;
         if Change.Decision = Archive.Writes.Plans.Entry_Ready
           and then Change.Request.Action = Archive.Writes.Plans.Add_File
         then
            declare
               Size : constant Natural :=
                 Host_Size (To_String (Change.Request.Host_Source), OK);
            begin
               Write_Host_Payload (To_String (Change.Request.Host_Source), Size);
            end;
         end if;
      end loop;

      if Ada.Streams.Stream_IO.Is_Open (Output) then
         Ada.Streams.Stream_IO.Close (Output);
      end if;

      if Failed /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.Iso_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_Iso;

   function Publish_BZip2
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result
   is
      Root : constant String := Parent_Directory (Destination_Path);
      Temp : constant String := Fresh_Write_Sibling_Path (Root, Destination_Path, "save");
      Status : constant Archive.Writes.Results.Write_Status :=
        Preflight (Destination_Path, Plan, Root, Overwrite, Cancelled);
      Source : Ada.Strings.Unbounded.Unbounded_String;
      Output : Ada.Streams.Stream_IO.File_Type;
      Write_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Z_Status : Zlib.Status_Code := Zlib.Ok;
   begin
      if Status /= Archive.Writes.Results.Write_Completed then
         return (Status => Status);
      elsif Temp = "" or else Natural (Plan.Changes.Length) /= 1 then
         return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
      end if;

      declare
         Change : constant Archive.Writes.Plans.Planned_Change :=
           Plan.Changes.Element (Plan.Changes.First_Index);
      begin
         if Change.Decision /= Archive.Writes.Plans.Entry_Ready
           or else Change.Request.Action not in Archive.Writes.Plans.Add_File
             | Archive.Writes.Plans.Replace_File
           or else Ada.Strings.Unbounded.To_String (Change.Request.Host_Source) = ""
         then
            return (Status => Archive.Writes.Results.Write_Blocked_By_Plan);
         end if;

         Source := Change.Request.Host_Source;
      end;

      if not Ada.Directories.Exists (Ada.Strings.Unbounded.To_String (Source)) then
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      Ada.Directories.Create_Path (Root);

      declare
         Size : constant Ada.Directories.File_Size :=
           Ada.Directories.Size (Ada.Strings.Unbounded.To_String (Source));
         Limit : constant Ada.Directories.File_Size :=
           Ada.Directories.File_Size
             (Archive.Resource_Limits.Default_Configured
                (Archive.Resource_Limits.Preview_Input_Bytes));
      begin
         if Size > Limit or else Size > Ada.Directories.File_Size (Natural'Last) then
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;
      end;

      declare
         Plain : constant Archive.Archives.Streams.Buffered_Source :=
           Archive.Archives.Streams.Read_Bounded
             (Ada.Strings.Unbounded.To_String (Source),
              Positive'Max
                (1,
                 Positive
                   (Ada.Directories.Size
                      (Ada.Strings.Unbounded.To_String (Source)))));
      begin
         if Plain.Status /= Archive.Archives.Errors.Ok then
            return (Status => Archive.Writes.Results.Write_Failed_Staging);
         end if;

         declare
            Encoded : constant Zlib.Byte_Array :=
              Zlib.BZip2_Encoder.Encode (Plain.Bytes, Status => Z_Status);
         begin
            if Z_Status /= Zlib.Ok then
               return (Status => Zlib_Write_Status (Z_Status));
            end if;

            Ada.Streams.Stream_IO.Create (Output, Ada.Streams.Stream_IO.Out_File, Temp);
            Write_Zlib_Bytes (Output, Encoded, Write_Status);
            Ada.Streams.Stream_IO.Close (Output);
         end;
      end;

      if Write_Status /= Archive.Archives.Errors.Ok then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
      end if;

      return Finalize_Staged_Archive
        (Destination_Path, Temp, Root, Overwrite,
         Archive.Archives.Formats.BZip2_Format, Destination_Path, Cancelled);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (Output) then
            Ada.Streams.Stream_IO.Close (Output);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Writes.Results.Write_Failed_Staging);
   end Publish_BZip2;
end Archive.Writes.Execution;
