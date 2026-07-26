with Ada.Command_Line;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with GNAT.OS_Lib;

with Archive.Commands;
with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Archives.Index;
with Archive.Archives.Readers.Dispatch;
with Archive.Types;
with Archive.Archives.Formats;
with Archive.Extraction.Paths;
with Archive.Verification.CRC32;

with Project_Tools.Processes;
with Project_Tools.Text;
with Tarlib;
with Tarlib.Errors;
with Tarlib.Outputs;
with Tarlib.Writers;
with Zlib;

procedure Check_All is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Project_Tools.Text;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Formats.Detection_Status;
   use type Archive.Archives.Formats.Format_Id;
   use type Tarlib.Errors.Status_Code;
   use type Zlib.Status_Code;
   use type Archive.Extraction.Paths.Path_Decision;
   use type Archive.Types.CRC32_Value;
   use type Ada.Directories.File_Kind;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   function Tests_Root return String is
      Here : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists (Here & "/archive_tests.gpr") then
         return Here;
      elsif Ada.Directories.Exists (Here & "/../archive_tests.gpr") then
         return Ada.Directories.Full_Name (Here & "/..");
      elsif Ada.Directories.Exists (Here & "/tests/archive_tests.gpr") then
         return Ada.Directories.Full_Name (Here & "/tests");
      else
         return Here;
      end if;
   end Tests_Root;

   Tests : constant String := Tests_Root;
   Root  : constant String := Ada.Directories.Full_Name (Tests & "/..");
   Alr   : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Gnatprove : constant String := Project_Tools.Processes.Locate_Command ("gnatprove");

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List;
      Quiet   : Boolean := False) renames Project_Tools.Processes.Run;

   function Is_Generated_Directory_Name (Name : String) return Boolean is
   begin
      return Name = "bin"
        or else Name = "obj"
        or else Name = "proof"
        or else Name = "alire"
        or else Name = ".git";
   end Is_Generated_Directory_Name;

   function Is_Release_Temporary_Artifact_Name (Name : String) return Boolean is
   begin
      return Ends_With (Name, ".archive-tmp")
        or else Ends_With (Name, ".archive-old")
        or else Ends_With (Name, ".tmp")
        or else Name = "release-staging"
        or else Name = "package-staging";
   end Is_Release_Temporary_Artifact_Name;

   function Is_Ada_File (Name : String) return Boolean is
   begin
      return Ends_With (Name, ".adb") or else Ends_With (Name, ".ads");
   end Is_Ada_File;

   function Is_Script_Name (Name : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      return Ends_With (Lower, ".sh")
        or else Ends_With (Lower, ".bash")
        or else Ends_With (Lower, ".py")
        or else Ends_With (Lower, ".ps1")
        or else Ends_With (Lower, ".rb")
        or else Ends_With (Lower, ".pl");
   end Is_Script_Name;

   procedure Fail (Message : String) is
   begin
      Put_Line (Standard_Error, Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise Program_Error;
   end Fail;

   function Has_Shebang (Path : String) return Boolean is
      File   : Ada.Text_IO.File_Type;
      Buffer : String (1 .. 2);
      Last   : Natural := 0;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      if not Ada.Text_IO.End_Of_File (File) then
         Ada.Text_IO.Get_Line (File, Buffer, Last);
      end if;
      Ada.Text_IO.Close (File);
      return Last = 2 and then Buffer = "#!";
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end Has_Shebang;

   procedure Check_Ada_Source_File (Path : String) is
      Content : constant String := To_String (Read_Text_File (Path));
   begin
      if Ends_With (Path, "/tests/src/check_all.adb") then
         return;
      end if;

      if Contains (Path, "/archive/src/") then
         if Contains (Content, "GNAT.OS_Lib.Spawn")
           or else Contains (Content, "Run_Shell")
         then
            Fail (Path & ": external archive/tool process use is not allowed");
         end if;
      end if;

      if Contains (Content, "with Zlib.Raw_Inflate")
        or else Contains (Content, "with Zlib.Stream_Inflate")
        or else Contains (Content, "with Zlib.Wrapper")
      then
         Fail (Path & ": direct internal zlib package import is not allowed");
      end if;

      if Contains (Path, "/archive/src/")
        and then not Ends_With (Path, "/archive-compression-zlib.adb")
        and then
          (Contains (Content, " Zlib.Inflate")
           or else Contains (Content, "Inflate_With_Header")
           or else Contains (Content, "Inflate_Raw"))
      then
         Fail (Path & ": inflate operations must go through Archive.Compression.Zlib");
      end if;

      if Contains (Path, "/archive/src/")
        and then not Ends_With (Path, "/archive-compression-zlib.adb")
        and then
          (Contains (Content, " Zlib.GZip")
           or else Contains (Content, " Zlib.Deflate")
           or else Contains (Content, "Deflate_Raw"))
      then
         Fail (Path & ": deflate/gzip output must go through Archive.Compression.Zlib");
      end if;

      if Contains (Content, "with Tarlib.Internal") then
         Fail (Path & ": archive must use only public tarlib packages");
      end if;

      if Contains (Content, "Original_Path") and then Contains (Content, "Destination_Root &") then
         Fail (Path & ": raw archive path joining to extraction root is not allowed");
      end if;

      if Contains (Path, "/archive/src/")
        and then Contains (Content, "Ada.Streams.Stream_IO.Create")
        and then not Ends_With (Path, "/archive-extraction-execution.adb")
        and then not Ends_With (Path, "/archive-writes-execution.adb")
      then
         Fail (Path & ": file publication must stay in extraction/write execution packages");
      end if;

      if Contains (Path, "/archive/src/")
        and then not Ends_With (Path, "/archive-resource_limits.adb")
        and then
          (Contains (Content, "1024 * 1024")
           or else Contains (Content, "64 * 1024")
           or else Contains (Content, "16 * 1024"))
      then
         Fail (Path & ": resource ceilings must be centralized in Archive.Resource_Limits");
      end if;

      if Ends_With (Path, "/archive-view_snapshots-entry_properties.adb")
        and then not Contains (Content, "Archive.Archives.Capabilities.For_Entry")
      then
         Fail (Path & ": entry property snapshots must consume Archive.Archives.Capabilities");
      end if;

      if Ends_With (Path, "/archive-commands.adb")
        and then not Contains (Content, "Archive.Archives.Formats.Capabilities")
      then
         Fail (Path & ": command availability must consume the format capability registry");
      end if;

      if Ends_With (Path, "/archive-application.adb")
        and then
          (not Contains (Content, "Archive.Application.Windows.Run")
           or else not Contains (Content, "First_Path_Or_Empty"))
      then
         Fail
           (Path
            & ": desktop mode must enter the live window runtime with startup archive paths");
      end if;

      if Ends_With (Path, "/archive-application-windows.adb")
        and then
          (not Contains (Content, "Glfw.Windows.Init")
           or else not Contains (Content, "Guikit.Vulkan.Ensure_Ready")
           or else not Contains (Content, "Guikit.Vulkan.Present_Frame")
           or else not Contains (Content, "Guikit.Vulkan.Wait_For_Events")
           or else not Contains (Content, "Archive.GUI_Runtime.Drain_Operations")
           or else not Contains (Content, "Archive.GUI_Runtime.Start_Open_Archive"))
      then
         Fail
           (Path
            & ": live runtime must own GLFW windowing, guikit Vulkan presentation,"
            & " and operation draining");
      end if;

      if Ends_With (Path, "/archive-tasking-services.ads")
        and then
          (not Contains (Content, "protected type Event_Bridge")
           or else not Contains (Content, "Take_Latest_Progress")
           or else not Contains (Content, "Acknowledge_Wakeup"))
      then
         Fail (Path & ": tasking services must expose the protected event bridge boundary");
      end if;

      if Ends_With (Path, "/archive-tasking-services.adb")
        and then
          (not Contains (Content, "Archive.Tasking.Events.Classify")
           or else not Contains (Content, "Latest_Progress")
           or else not Contains (Content, "Has_Latest_Progress")
           or else not Contains (Content, "Wakeup"))
      then
         Fail (Path & ": tasking services must reject stale events and coalesce progress/wakeups");
      end if;

      if Ends_With (Path, "/archive-archives-opening.adb")
        and then
          (not Contains (Content, "Archive.Model.Begin_Open")
           or else not Contains (Content, "Archive.Source_Monitoring.Fingerprint")
           or else not Contains (Content, "Archive.Archives.Readers.Dispatch.Open_File")
           or else not Contains (Content, "Archive.Model.Publish_Open_Result"))
      then
         Fail (Path & ": archive opening must own source validation, reader dispatch, and model publication");
      end if;

      if Ends_With (Path, "/archive-archives-opening.adb")
        and then Contains (Content, "Ada.Streams.Stream_IO")
      then
         Fail (Path & ": archive opening must use Archive.Archives.Streams instead of direct file reads");
      end if;

      if Ends_With (Path, "/archive-archives-streams.adb")
        and then
          (not Contains (Content, "Ada.Streams.Stream_IO.Read")
           or else not Contains (Content, "Chunk_Size")
           or else not Contains (Content, "Read_Prefix")
           or else not Contains (Content, "Limit_Exceeded"))
      then
         Fail (Path & ": source stream boundary must perform bounded chunked reads and prefix probes");
      end if;

      if Ends_With (Path, "/archive-archives-readers-gzip.adb")
        and then
          (not Contains (Content, "Max_Gzip_Field_Metadata")
           or else not Contains (Content, "Max_Header_Probe")
           or else not Contains (Content, "Archive.Archives.Errors.Limit_Exceeded"))
      then
         Fail (Path & ": gzip reader must expose bounded optional-header metadata limits");
      end if;

      if (Ends_With (Path, "/archive-archives-readers-gzip.adb")
          or else Ends_With (Path, "/archive-archives-readers-zip.adb"))
        and then
          (Contains (Content, "Byte_Array_Access")
           or else Contains (Content, "new Zlib.Byte_Array")
           or else Contains (Content, ".Bytes.all"))
      then
         Fail (Path & ": runtime readers must not use heap-backed metadata slice buffers");
      end if;

      if Ends_With (Path, "/archive-archives-opening-tasks.adb")
        and then
          (not Contains (Content, "task body Open_Worker")
           or else not Contains (Content, "Archive.Archives.Opening.Prepare_Path")
           or else not Contains (Content, "Target_Results.Store")
           or else not Contains (Content, "Target_Bridge.Publish")
           or else not Contains (Content, "Open_Completed"))
      then
         Fail (Path & ": open worker must prepare off-thread and publish through the event bridge");
      end if;

      if Ends_With (Path, "/archive-archives-opening-tasks.adb")
        and then Contains (Content, "Archive.Model")
      then
         Fail (Path & ": open worker must not mutate the application model");
      end if;

      if Ends_With (Path, "/archive-operations-opening.adb")
        and then
          (not Contains (Content, "Archive.Model.Begin_Open")
           or else not Contains (Content, "Self.Bridge.Configure")
           or else not Contains (Content, "new Archive.Archives.Opening.Tasks.Open_Worker")
           or else not Contains (Content, "Archive.Archives.Opening.Publish_Prepared")
           or else not Contains (Content, "Self.Bridge.Acknowledge_Wakeup"))
      then
         Fail (Path & ": open operation coordinator must own start, drain, publish, and wakeup lifecycle");
      end if;

      if Ends_With (Path, "/archive-gui_runtime.adb")
        and then
          (not Contains (Content, "Archive.Operations.Opening.Start_Open")
           or else not Contains (Content, "Archive.Operations.Opening.Drain_Events"))
      then
         Fail (Path & ": GUI runtime must route background archive opens through the operation coordinator");
      end if;

      if Ends_With (Path, "/archive-gui_frame.adb")
        and then
          (not Contains (Content, "Guikit.Item_Grid.Calculate_Layout")
           or else not Contains (Content, "Guikit.Item_Grid.Draw_Name_Field")
           or else not Contains (Content, "Guikit.Command_Palette.Build_Frame")
           or else not Contains (Content, "Guikit.Settings_Panel.Build_Frame")
           or else not Contains (Content, "Guikit.List_Panel.Draw_Frame"))
      then
         Fail (Path & ": GUI frame must render primary surfaces through guikit widgets");
      end if;

      if Ends_With (Path, "/archive-settings.adb")
        and then
          (not Contains (Content, "recent_archives=")
           or else not Contains (Content, "Remember_Recent_Archive")
           or else not Contains (Content, "Max_Recent_Items"))
      then
         Fail (Path & ": settings must persist bounded recent archive path data");
      end if;

      if Ends_With (Path, "/archive-ui.ads")
        and then
          (not Contains (Content, "Recent_Archives")
           or else not Contains (Content, "Recent_Count"))
      then
         Fail (Path & ": shell settings snapshot must expose recent archive state");
      end if;

      if Ends_With (Path, "/archive-extraction-plans.adb")
        and then not Contains (Content, "Plan_Relative_Path (Item, Platform)")
      then
         Fail (Path & ": extraction planning must use platform-aware path keys");
      end if;

      if Ends_With (Path, "/archive-writes-plans.adb")
        and then not Contains (Content, "Platform_Key")
      then
         Fail (Path & ": write planning must use platform-aware path keys");
      end if;
   end Check_Ada_Source_File;

   procedure Check_Tree (Path : String) is
      Search    : Ada.Directories.Search_Type;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
      Started   : Boolean := False;
   begin
      if not Ada.Directories.Exists (Path) then
         return;
      end if;

      Ada.Directories.Start_Search
        (Search,
         Directory => Path,
         Pattern   => "*",
         Filter    =>
           [Ada.Directories.Ordinary_File => True,
            Ada.Directories.Directory     => True,
            Ada.Directories.Special_File  => False]);
      Started := True;

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
            Full : constant String := Ada.Directories.Full_Name (Dir_Entry);
         begin
            if Name = "." or else Name = ".." then
               null;
            elsif Ada.Directories.Kind (Dir_Entry) = Ada.Directories.Directory then
               if not Is_Generated_Directory_Name (Name) then
                  Check_Tree (Full);
               end if;
            elsif Is_Script_Name (Name) then
               Fail (Full & ": script tooling is not allowed");
            elsif Has_Shebang (Full) then
               Fail (Full & ": shebang tooling is not allowed");
            elsif Is_Ada_File (Name) then
               Check_Ada_Source_File (Full);
            end if;
         end;
      end loop;

      Ada.Directories.End_Search (Search);
      Started := False;
   exception
      when others =>
         if Started then
            Ada.Directories.End_Search (Search);
         end if;
         raise;
   end Check_Tree;

   procedure Check_Release_Cleanliness_Tree (Path : String) is
      Search    : Ada.Directories.Search_Type;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
      Started   : Boolean := False;
   begin
      if not Ada.Directories.Exists (Path) then
         return;
      end if;

      Ada.Directories.Start_Search
        (Search,
         Directory => Path,
         Pattern   => "*",
         Filter    =>
           [Ada.Directories.Ordinary_File => True,
            Ada.Directories.Directory     => True,
            Ada.Directories.Special_File  => False]);
      Started := True;

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
            Full : constant String := Ada.Directories.Full_Name (Dir_Entry);
         begin
            if Name = "." or else Name = ".." then
               null;
            elsif Is_Generated_Directory_Name (Name) then
               null;
            elsif Is_Release_Temporary_Artifact_Name (Name) then
               Fail (Full & ": release temporary/staging artifact must not remain in the repository tree");
            elsif Ada.Directories.Kind (Dir_Entry) = Ada.Directories.Directory then
               Check_Release_Cleanliness_Tree (Full);
            end if;
         end;
      end loop;

      Ada.Directories.End_Search (Search);
      Started := False;
   exception
      when others =>
         if Started then
            Ada.Directories.End_Search (Search);
         end if;
         raise;
   end Check_Release_Cleanliness_Tree;

   procedure Check_Release_Cleanliness is
   begin
      Check_Release_Cleanliness_Tree (Root);
   end Check_Release_Cleanliness;

   procedure Check_Architecture is
   begin
      if not Ada.Directories.Exists (Root & "/src/archive-archives-capabilities.ads")
        or else not Ada.Directories.Exists (Root & "/src/archive-archives-capabilities.adb")
      then
         Fail (Root & "/src/archive-archives-capabilities: required capability boundary is missing");
      end if;

      Check_Tree (Root & "/src");
      Check_Tree (Root & "/tests/src");

      declare
         Suite : constant String := To_String (Read_Text_File (Root & "/tests/src/archive_suite-core.adb"));
      begin
         if not Contains (Suite, "extraction security gate") then
            Fail (Root & "/tests/src/archive_suite-core.adb: extraction security gate test is missing");
         elsif not Contains (Suite, "deterministic mutation gate") then
            Fail (Root & "/tests/src/archive_suite-core.adb: deterministic mutation gate test is missing");
         elsif not Contains (Suite, "completion gate format workflows") then
            Fail (Root & "/tests/src/archive_suite-core.adb: completion gate workflow test is missing");
         end if;
      end;

      declare
         CI_Path : constant String := Root & "/.github/workflows/check.yml";
         CI      : constant String := To_String (Read_Text_File (CI_Path));
      begin
         if CI'Length = 0 then
            Fail (CI_Path & ": CI workflow is missing or empty");
         elsif not Contains (CI, "tests/bin/check_all") then
            Fail (CI_Path & ": CI must delegate to the Ada check_all workflow");
         end if;
      end;
   end Check_Architecture;

   function Catalog_Has_Key (Catalog : String; Key : String) return Boolean is
      Localized_Key : constant String := "en." & Key & " =";
   begin
      return Starts_With (Catalog, Key & "=")
        or else Contains (Catalog, ASCII.LF & Key & "=")
        or else Starts_With (Catalog, Localized_Key)
        or else Contains (Catalog, ASCII.LF & Localized_Key);
   end Catalog_Has_Key;

   procedure Require_Catalog_Key (Catalog : String; Key : String) is
   begin
      if not Catalog_Has_Key (Catalog, Key) then
         Fail (Root & "/share/archive.catalog: missing required key " & Key);
      end if;
   end Require_Catalog_Key;

   procedure Check_Catalogs is
      Catalog_Path : constant String := Root & "/share/archive.catalog";
      Catalog      : constant String := To_String (Read_Text_File (Catalog_Path));
   begin
      if Catalog'Length = 0 then
         Fail (Catalog_Path & ": catalog is missing or empty");
      end if;

      Require_Catalog_Key (Catalog, "application.title");
      Require_Catalog_Key (Catalog, "application.version");
      Require_Catalog_Key (Catalog, "help.summary");
      Require_Catalog_Key (Catalog, "runtime.backend.headless");
      Require_Catalog_Key (Catalog, "format.tar.name");
      Require_Catalog_Key (Catalog, "format.tar.description");
      Require_Catalog_Key (Catalog, "format.tar.gz.name");
      Require_Catalog_Key (Catalog, "format.tar.gz.description");
      Require_Catalog_Key (Catalog, "format.zip.name");
      Require_Catalog_Key (Catalog, "format.zip.description");
      Require_Catalog_Key (Catalog, "format.gzip.name");
      Require_Catalog_Key (Catalog, "format.gzip.description");
      Require_Catalog_Key (Catalog, "format.7z.name");
      Require_Catalog_Key (Catalog, "format.7z.description");
      Require_Catalog_Key (Catalog, "format.rar.name");
      Require_Catalog_Key (Catalog, "format.rar.description");
      Require_Catalog_Key (Catalog, "format.xz.name");
      Require_Catalog_Key (Catalog, "format.xz.description");
      Require_Catalog_Key (Catalog, "format.bzip2.name");
      Require_Catalog_Key (Catalog, "format.bzip2.description");
      Require_Catalog_Key (Catalog, "format.zstd.name");
      Require_Catalog_Key (Catalog, "format.zstd.description");
      Require_Catalog_Key (Catalog, "format.cab.name");
      Require_Catalog_Key (Catalog, "format.cab.description");
      Require_Catalog_Key (Catalog, "format.cpio.name");
      Require_Catalog_Key (Catalog, "format.cpio.description");
      Require_Catalog_Key (Catalog, "format.iso.name");
      Require_Catalog_Key (Catalog, "format.iso.description");
      Require_Catalog_Key (Catalog, "format.ar.name");
      Require_Catalog_Key (Catalog, "format.ar.description");
      Require_Catalog_Key (Catalog, "format.split_zip.name");
      Require_Catalog_Key (Catalog, "format.split_zip.description");
      Require_Catalog_Key (Catalog, "unavailable.encrypted");
      Require_Catalog_Key (Catalog, "unavailable.unsupported_method");
      Require_Catalog_Key (Catalog, "unavailable.unsafe_path");
      Require_Catalog_Key (Catalog, "unavailable.unsupported_entry_kind");
      Require_Catalog_Key (Catalog, "column.name");
      Require_Catalog_Key (Catalog, "column.type");
      Require_Catalog_Key (Catalog, "column.uncompressed_size");
      Require_Catalog_Key (Catalog, "column.compressed_size");
      Require_Catalog_Key (Catalog, "column.compression_ratio");
      Require_Catalog_Key (Catalog, "column.modified_time");
      Require_Catalog_Key (Catalog, "column.compression_method");
      Require_Catalog_Key (Catalog, "column.archive_position");
      Require_Catalog_Key (Catalog, "column.original_path");
      Require_Catalog_Key (Catalog, "column.owner");
      Require_Catalog_Key (Catalog, "column.group");
      Require_Catalog_Key (Catalog, "column.permissions");
      Require_Catalog_Key (Catalog, "column.integrity");
      Require_Catalog_Key (Catalog, "column.path_safety");
      Require_Catalog_Key (Catalog, "column.link_target");

      for Id in Archive.Commands.Registered_Command_Id loop
         Require_Catalog_Key (Catalog, Archive.Commands.Name_Key (Id));
         Require_Catalog_Key (Catalog, Archive.Commands.Description_Key (Id));
      end loop;
      Require_Catalog_Key (Catalog, "command.unavailable.none");
      Require_Catalog_Key (Catalog, "command.unavailable.no_archive");
      Require_Catalog_Key (Catalog, "command.unavailable.no_selection");
      Require_Catalog_Key (Catalog, "command.unavailable.no_filter");
      Require_Catalog_Key (Catalog, "command.unavailable.no_pending_changes");
      Require_Catalog_Key (Catalog, "command.unavailable.not_ready");
      Require_Catalog_Key (Catalog, "command.unavailable.no_recent_archives");
      Require_Catalog_Key (Catalog, "command.unavailable.read_only_archive");
      Require_Catalog_Key (Catalog, "menu.file");
      Require_Catalog_Key (Catalog, "menu.edit");
      Require_Catalog_Key (Catalog, "menu.view");
      Require_Catalog_Key (Catalog, "menu.navigate");
      Require_Catalog_Key (Catalog, "menu.tools");
      Require_Catalog_Key (Catalog, "menu.settings");
      Require_Catalog_Key (Catalog, "menu.application");
      Require_Catalog_Key (Catalog, "ui.region.content");
      Require_Catalog_Key (Catalog, "ui.region.breadcrumb");
      Require_Catalog_Key (Catalog, "ui.region.preview");
      Require_Catalog_Key (Catalog, "ui.region.command_palette");
      Require_Catalog_Key (Catalog, "ui.preview.accessible");
      Require_Catalog_Key (Catalog, "ui.preview.state.none");
      Require_Catalog_Key (Catalog, "ui.preview.state.loading");
      Require_Catalog_Key (Catalog, "ui.preview.state.ready");
      Require_Catalog_Key (Catalog, "ui.preview.state.failed");
      Require_Catalog_Key (Catalog, "ui.preview.truncated");
      Require_Catalog_Key (Catalog, "settings.title");
      Require_Catalog_Key (Catalog, "settings.section.general");
      Require_Catalog_Key (Catalog, "settings.section.layout");
      Require_Catalog_Key (Catalog, "settings.view");
      Require_Catalog_Key (Catalog, "settings.directories_first");
      Require_Catalog_Key (Catalog, "settings.preview_visible");
      Require_Catalog_Key (Catalog, "settings.preview_limit");
      Require_Catalog_Key (Catalog, "settings.toolbar_visible");
      Require_Catalog_Key (Catalog, "settings.status_bar_visible");
      Require_Catalog_Key (Catalog, "settings.status.ready");
      Require_Catalog_Key (Catalog, "ui.view.grid");
      Require_Catalog_Key (Catalog, "ui.view.compact");
      Require_Catalog_Key (Catalog, "ui.view.details");
      Require_Catalog_Key (Catalog, "ui.accessible.grid");
      Require_Catalog_Key (Catalog, "ui.accessible.compact");
      Require_Catalog_Key (Catalog, "ui.accessible.details");
      Require_Catalog_Key (Catalog, "ui.focus.content");
      Require_Catalog_Key (Catalog, "ui.focus.toolbar");
      Require_Catalog_Key (Catalog, "ui.focus.breadcrumb");
      Require_Catalog_Key (Catalog, "ui.focus.preview");
      Require_Catalog_Key (Catalog, "ui.focus.command_palette");
      Require_Catalog_Key (Catalog, "ui.focus.settings");
      Require_Catalog_Key (Catalog, "ui.overlay.none");
      Require_Catalog_Key (Catalog, "ui.overlay.command_palette");
      Require_Catalog_Key (Catalog, "ui.overlay.settings");
      Require_Catalog_Key (Catalog, "entry.kind.file");
      Require_Catalog_Key (Catalog, "entry.kind.directory");
      Require_Catalog_Key (Catalog, "entry.kind.symlink");
      Require_Catalog_Key (Catalog, "entry.kind.hardlink");
      Require_Catalog_Key (Catalog, "entry.kind.unknown");
      Require_Catalog_Key (Catalog, "ui.dialog.none");
      Require_Catalog_Key (Catalog, "ui.dialog.open_archive");
      Require_Catalog_Key (Catalog, "ui.dialog.add_files");
      Require_Catalog_Key (Catalog, "ui.dialog.add_directory");
      Require_Catalog_Key (Catalog, "ui.dialog.replace_file");
      Require_Catalog_Key (Catalog, "ui.dialog.rename_entry");
      Require_Catalog_Key (Catalog, "ui.dialog.extract_destination");
      Require_Catalog_Key (Catalog, "ui.dialog.save_as");
      Require_Catalog_Key (Catalog, "ui.dialog.confirm_close");
      Require_Catalog_Key (Catalog, "ui.dialog.archive_properties");
      Require_Catalog_Key (Catalog, "ui.dialog.entry_properties");
      Require_Catalog_Key (Catalog, "ui.notification.command_unavailable");
      Require_Catalog_Key (Catalog, "ui.notification.open_complete");
      Require_Catalog_Key (Catalog, "ui.notification.open_failed");
      Require_Catalog_Key (Catalog, "ui.notification.save_complete");
      Require_Catalog_Key (Catalog, "ui.notification.save_failed");
      Require_Catalog_Key (Catalog, "ui.notification.copy_complete");
      Require_Catalog_Key (Catalog, "ui.status_bar.accessible");
      Require_Catalog_Key (Catalog, "ui.status.starting");
      Require_Catalog_Key (Catalog, "ui.status.no_archive");
      Require_Catalog_Key (Catalog, "ui.status.opening");
      Require_Catalog_Key (Catalog, "ui.status.ready");
      Require_Catalog_Key (Catalog, "ui.status.dirty");
      Require_Catalog_Key (Catalog, "ui.status.saving");
      Require_Catalog_Key (Catalog, "ui.status.save_failed");
      Require_Catalog_Key (Catalog, "ui.status.warnings");
      Require_Catalog_Key (Catalog, "ui.status.failed");
      Require_Catalog_Key (Catalog, "ui.status.shutting_down");
      Require_Catalog_Key (Catalog, "settings.title");
      Require_Catalog_Key (Catalog, "settings.section.general");
      Require_Catalog_Key (Catalog, "settings.section.layout");
      Require_Catalog_Key (Catalog, "settings.view");
      Require_Catalog_Key (Catalog, "settings.directories_first");
      Require_Catalog_Key (Catalog, "settings.preview_visible");
      Require_Catalog_Key (Catalog, "settings.preview_limit");
      Require_Catalog_Key (Catalog, "settings.per_entry_extraction_limit");
      Require_Catalog_Key (Catalog, "settings.total_extraction_limit");
      Require_Catalog_Key (Catalog, "settings.conflict_policy");
      Require_Catalog_Key (Catalog, "settings.write_conflict_policy");
      Require_Catalog_Key (Catalog, "settings.conflict.ask");
      Require_Catalog_Key (Catalog, "settings.conflict.skip");
      Require_Catalog_Key (Catalog, "settings.conflict.overwrite");
      Require_Catalog_Key (Catalog, "settings.conflict.rename");
      Require_Catalog_Key (Catalog, "settings.link_policy");
      Require_Catalog_Key (Catalog, "settings.link.skip");
      Require_Catalog_Key (Catalog, "settings.link.safe_internal");
      Require_Catalog_Key (Catalog, "settings.show_unsafe_entries");
      Require_Catalog_Key (Catalog, "settings.startup_reopen_recent");
      Require_Catalog_Key (Catalog, "settings.toolbar_visible");
      Require_Catalog_Key (Catalog, "settings.status_bar_visible");
      Require_Catalog_Key (Catalog, "settings.window_maximized");
      Require_Catalog_Key (Catalog, "settings.status.ready");
   end Check_Catalogs;

   procedure Require_Document_Text
     (Relative_Path : String;
      Text          : String)
   is
      Path    : constant String := Root & "/" & Relative_Path;
      Content : constant String := To_String (Read_Text_File (Path));
   begin
      if Content'Length = 0 then
         Fail (Path & ": required documentation is missing or empty");
      elsif not Contains (Content, Text) then
         Fail (Path & ": missing required text: " & Text);
      end if;
   end Require_Document_Text;

   procedure Forbid_Document_Text
     (Relative_Path : String;
      Text          : String)
   is
      Path    : constant String := Root & "/" & Relative_Path;
      Content : constant String := To_String (Read_Text_File (Path));
   begin
      if Contains (Content, Text) then
         Fail (Path & ": stale forbidden text remains: " & Text);
      end if;
   end Forbid_Document_Text;

   procedure Check_Documentation is
      GUI_Runtime_AI_Marker : constant String :=
        "`Archive.GUI_Runtime`: initialized model/config owner and open-operation owner";
      GUI_Runtime_Scope_Marker : constant String :=
        "`Archive.GUI_Runtime` owns the initialized application model, shell configuration, "
        & "and open operation coordinator";
   begin
      Require_Document_Text
        ("README.md", "docs/PRODUCT_SCOPE.md");
      Require_Document_Text
        ("README.md", "docs/IMPLEMENTATION_PLAN.md");
      Require_Document_Text
        ("README.md", "docs/FORMAT_SUPPORT.md");
      Require_Document_Text
        ("README.md", "docs/testing-guide.md");
      Require_Document_Text
        ("README.md", "docs/settings-architecture.md");
      Require_Document_Text
        ("README.md", "docs/package-contracts.md");
      Require_Document_Text
        ("README.md", "tests/bin/check_all");
      Require_Document_Text
        ("README.md", "bin/archive --live-smoke");
      Require_Document_Text
        ("docs/release-guide.md", "tests/bin/release_report --write");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "graphical desktop archive manager");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "current product direction supersedes that limitation");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Required V1 write workflows");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Per-entry command availability is owned by `Archive.Archives.Capabilities`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.Resource_Limits`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "platform path models to derive deterministic destination keys");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.UI`");
      Forbid_Document_Text
        ("share/archive.catalog", "read-only archive browser");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "`Archive.Commands` is the central registry and executor");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "safe archive write planning");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "Startup and shutdown mapping");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "`Files.Model` maps to `Archive.Model`");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "`Files.Settings` maps to `Archive.Settings`");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "`Files.Localization` maps to `Archive.Localization`");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "`Guikit.Settings_Panel`");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "No private `files` package");
      Require_Document_Text
        ("docs/FORMAT_SUPPORT.md", "TAR.GZ / TGZ");
      Require_Document_Text
        ("docs/FORMAT_SUPPORT.md", "ZIP DEFLATE");
      Require_Document_Text
        ("docs/FORMAT_SUPPORT.md", "In-place archive mutation is");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "TAR parsing, traversal");
      Require_Document_Text
        ("docs/IMPLEMENTATION_PLAN.md", "Phase 4: TAR Adapter Integration");
      Require_Document_Text
        ("docs/IMPLEMENTATION_PLAN.md", "Phase 9: Archive Write Planner And Publisher");
      Require_Document_Text
        ("docs/IMPLEMENTATION_PLAN.md", "Completion Gate");
      Require_Document_Text
        ("docs/IMPLEMENTATION_PLAN.md", "Phase Status Snapshot");
      Require_Document_Text
        ("docs/IMPLEMENTATION_PLAN.md", "`completion gate format workflows`");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Do not write TAR outside `tarlib`");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Do not scatter hard-coded resource ceilings");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.UI`: GUI shell snapshots");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Application.Windows`: live GLFW/Vulkan desktop runtime");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Tasking.Services`: protected worker-to-main-thread event bridge");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Route them through `Archive.Tasking.Services.Event_Bridge`");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Archives.Capabilities`: authoritative per-entry");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Archives.Opening`: source validation");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Archives.Streams`: bounded compatibility helper");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Production readers should prefer file-backed metadata");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Archives.Opening.Tasks`: native Ada open worker");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Operations.Opening`: application operation coordinator");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Use `Archive.Archives.Opening.Open_Path` for path-based archive opening");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "workers must call `Prepare_Path` and must not mutate `Archive.Model`");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Use `Archive.Operations.Opening.Start_Open` and `Drain_Events`");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.Extraction.Paths`: safe extraction-relative path planning");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "`Archive.GUI_Frame`: converts shell snapshots");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", GUI_Runtime_AI_Marker);
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Runtime callers should use `Archive.GUI_Runtime.Start_Open_Archive`");
      Require_Document_Text
        ("docs/ai-implementation-guide.md",
         "Desktop startup paths must enter through `Archive.Application.Windows.Run`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "focus and overlay snapshots");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", GUI_Runtime_Scope_Marker);
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.GUI_Frame` renders shell snapshots into concrete `guikit` draw");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "content rows are rendered through `Guikit.Item_Grid`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "command palette overlays are rendered through `Guikit.Command_Palette`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "settings overlays are rendered through `Guikit.Settings_Panel`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "preview panels are rendered through `Guikit.List_Panel`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.Application.Windows` owns the live desktop boundary");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "bounded `--live-smoke` mode validates the same boundary");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md",
         "Desktop startup archive paths are forwarded into `Archive.GUI_Runtime.Start_Open_Archive`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.Tasking.Services.Event_Bridge` is the main-thread event boundary");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "coalesces extraction progress through a latest-value slot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.Archives.Opening` owns the source-to-model archive open workflow");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "enters the file-backed reader dispatch boundary");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "metadata slices, and payload streams rather than whole-archive reads");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.Archives.Opening.Tasks.Open_Worker` is the native Ada task boundary");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.Operations.Opening` coordinates the open operation lifecycle");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Failed replacement opens retain the previous active archive session");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Dialog and notification snapshots are also model-owned");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Keyboard handling is also centralized through `Archive.UI`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "model-owned breadcrumb snapshot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "content projection snapshot containing stable entry IDs");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "model-owned filter and sorting state");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "command palette snapshot with localized command rows");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "focused-entry property snapshots");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "entry-ID selection");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "preview panel snapshot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Navigation commands use model-owned history");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "directory activation navigates");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "actionable focused selection");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "model-owned copy results");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "shell settings snapshot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Settings schema 2 persists stable tokens");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "configured details-column IDs");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "shell verification snapshot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "shell extraction snapshot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "shell write snapshot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Write commands gather required payloads through");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "ready, dirty, saving, and save-failed archive states");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "apply-to-all flag before");
      Require_Document_Text
        ("docs/ai-implementation-guide.md",
         "Application-level write dialog completion must call model-owned typed planning operations");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Settings schema 2 owns write conflict policy");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "resolution records");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "`Archive.Writes.Service` owns app-level save-as publication");
      Require_Document_Text
        ("docs/ai-implementation-guide.md", "Use `Archive.Writes.Service` for save-as publication");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Property commands open model-owned archive and entry property dialogs");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "shell source snapshot");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Lifecycle commands mutate model-owned session/request state");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "duplicate promotion and bounded retention");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Recent archive paths are persisted as stable data, not localized display labels");
      Require_Document_Text
        ("docs/FILES_MAPPING.md", "recent archives persist stable source paths");
      Require_Document_Text
        ("docs/settings-architecture.md", "`Archive.Settings` is the only settings subsystem");
      Require_Document_Text
        ("docs/settings-architecture.md", "Schema 0 and schema 1 inputs migrate");
      Require_Document_Text
        ("docs/settings-architecture.md", "Loading an invalid settings file returns compiled defaults");
      Require_Document_Text
        ("docs/settings-architecture.md", "`tests/fixtures/settings/`");
      Require_Document_Text
        ("docs/package-contracts.md", "`Archive.Commands` is the only user-action executor");
      Require_Document_Text
        ("docs/package-contracts.md", "`Archive.Archives.Readers.Tar` consumes public `tarlib` reader APIs only");
      Require_Document_Text
        ("docs/package-contracts.md", "`Archive.Tasking.Services.Event_Bridge` is the protected worker-to-main");
      Require_Document_Text
        ("docs/package-contracts.md", "Do not parse TAR outside `tarlib`");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "Open Recent availability");
      Require_Document_Text
        ("docs/PRODUCT_SCOPE.md", "status bar snapshot carries localized lifecycle text");
      Require_Document_Text
        ("docs/phase-0-dependency-audit.md", "public TAR reading and writing surfaces");
      Require_Document_Text
        ("docs/phase-0-dependency-audit.md", "`Tarlib.Readers`");
      Require_Document_Text
        ("docs/phase-0-dependency-audit.md", "`Tarlib.Writers`");
      Require_Document_Text
        ("docs/phase-0-dependency-audit.md", "`Guikit.Item_Grid`");
      Require_Document_Text
        ("docs/phase-0-dependency-audit.md", "Messages.Runtime.Initialize");
      Require_Document_Text
        ("docs/phase-0-dependency-audit.md", "`Project_Tools.Processes`");
      Require_Document_Text
        ("docs/phase-0-dependency-audit.md", "Exact Build And Test Commands");
      Require_Document_Text
        ("docs/check-all-workflow.md", "product-scope documentation validation");
      Require_Document_Text
        ("docs/check-all-workflow.md", "fixture manifest and CRC32 validation");
      Require_Document_Text
        ("docs/check-all-workflow.md", "completion gate format workflow gates");
      Require_Document_Text
        ("docs/check-all-workflow.md", "output publication gating");
      Require_Document_Text
        ("docs/check-all-workflow.md", "malformed/security corpus validation");
      Require_Document_Text
        ("docs/check-all-workflow.md", "release report JSON contract validation");
      Require_Document_Text
        ("docs/release-guide.md", "`packaging/manifest.txt` is the package contents contract");
      Require_Document_Text
        ("docs/release-guide.md", "aggregate package CRC32 checksum");
      Require_Document_Text
        ("docs/release-guide.md", "Every required release gate from the product scope is represented");
      Require_Document_Text
        ("docs/release-guide.md", "The malformed-input corpus gate is enforced by Ada tooling");
      Require_Document_Text
        ("docs/release-guide.md", "release builds are enforced by Ada tooling");
      Require_Document_Text
        ("docs/release-guide.md", "integration tests are enforced by Ada tooling");
      Require_Document_Text
        ("docs/release-guide.md", "GNATprove is enforced by Ada tooling");
      Require_Document_Text
        ("docs/release-guide.md", "per-format completion gate workflow");
      Require_Document_Text
        ("docs/release-guide.md", "progress coalescing count invariants");
      Require_Document_Text
        ("docs/release-guide.md", "packaged smoke tests are enforced by Ada tooling");
      Require_Document_Text
        ("docs/release-guide.md", "release cleanliness is enforced by Ada tooling");
      Require_Document_Text
        ("docs/testing-guide.md", "Tests must not require public network access");
      Require_Document_Text
        ("docs/fixture-guide.md", "`tests/fixtures/manifest.txt` is the fixture manifest");
      Require_Document_Text
        ("docs/fixture-guide.md", "`tests/fixtures/corpus.txt` is the malformed/security corpus manifest");
      Require_Document_Text
        ("docs/fixture-guide.md", "zip-unsupported-method");
      Require_Document_Text
        ("docs/fixture-guide.md", "zip-encrypted");
      Require_Document_Text
        ("docs/fixture-guide.md", "gzip-bad-trailer");
      Require_Document_Text
        ("docs/fixture-guide.md", "unsupported ZIP compression methods");
      Require_Document_Text
        ("docs/release-guide.md", "CI must delegate to the Ada `tests/bin/check_all` workflow");
      Require_Document_Text
        ("CONTRIBUTING.md", "use `tarlib` for TAR reading and writing");
      Require_Document_Text
        ("CHANGELOG.md", "0.1.0-dev");

      Forbid_Document_Text
        ("README.md", "read-only graphical desktop archive browser");
      Forbid_Document_Text
        ("README.md", "write-only POSIX USTAR library");
      Forbid_Document_Text
        ("docs/ai-implementation-guide.md", "has no public reader API");
      Forbid_Document_Text
        ("docs/phase-0-dependency-audit.md", "deterministic USTAR writing only");
   end Check_Documentation;

   function Has_Prefix (Value : String; Prefix : String) return Boolean is
   begin
      return Value'Length >= Prefix'Length
        and then Value (Value'First .. Value'First + Prefix'Length - 1) = Prefix;
   end Has_Prefix;

   function Field_Value (Line : String; Name : String) return String is
      Prefix : constant String := Name & "=";
      Start  : Positive := Line'First;
   begin
      while Start <= Line'Last loop
         while Start <= Line'Last and then Line (Start) = ' ' loop
            Start := Start + 1;
         end loop;

         exit when Start > Line'Last;

         declare
            Finish : Natural := Start;
         begin
            while Finish <= Line'Last and then Line (Finish) /= ' ' loop
               Finish := Finish + 1;
            end loop;

            if Finish > Start
              and then Finish - Start >= Prefix'Length
              and then Line (Start .. Start + Prefix'Length - 1) = Prefix
            then
               return Line (Start + Prefix'Length .. Finish - 1);
            end if;

            Start := Finish + 1;
         end;
      end loop;

      return "";
   end Field_Value;

   function To_Hex8 (Value : Archive.Types.CRC32_Value) return String is
      Hex_Digit : constant String := "0123456789ABCDEF";
      V         : Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Value);
      Result    : String (1 .. 8);
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Hex_Digit (Integer (V mod 16) + 1);
         V := V / 16;
      end loop;

      return Result;
   end To_Hex8;

   function Read_Bytes (Path : String) return Zlib.Byte_Array is
      File : Ada.Streams.Stream_IO.File_Type;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
   begin
      if Size = 0 then
         return Result : Zlib.Byte_Array (1 .. 0);
      end if;

      declare
         Raw    : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last   : Ada.Streams.Stream_Element_Offset;
         Result : Zlib.Byte_Array (1 .. Size);
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Read (File, Raw, Last);
         Ada.Streams.Stream_IO.Close (File);

         if Natural (Last) /= Size then
            Fail (Path & ": fixture read length mismatch");
         end if;

         for Index in Result'Range loop
            Result (Index) :=
              Zlib.Byte (Raw (Ada.Streams.Stream_Element_Offset (Index)));
         end loop;

         return Result;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Read_Bytes;

   procedure Write_Bytes (Path : String; Bytes : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
   begin
      Ada.Directories.Create_Path (Ada.Directories.Containing_Directory (Path));
      for Index in Bytes'Range loop
         Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
           Ada.Streams.Stream_Element (Bytes (Index));
      end loop;
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Data);
      Ada.Streams.Stream_IO.Close (File);
   end Write_Bytes;

   function CRC32_Compute (Bytes : Zlib.Byte_Array) return Archive.Types.CRC32_Value is
      State : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
   begin
      Archive.Verification.CRC32.Update (State, Bytes);
      return Archive.Verification.CRC32.Final (State);
   end CRC32_Compute;

   type File_CRC_Result is record
      Bytes : Natural := 0;
      CRC   : Archive.Types.CRC32_Value := 0;
   end record;

   function Compute_File_CRC32 (Path : String) return File_CRC_Result is
      Chunk_Size : constant Ada.Streams.Stream_Element_Count := 8_192;
      File       : Ada.Streams.Stream_IO.File_Type;
      State      : Archive.Verification.CRC32.CRC32_State :=
        Archive.Verification.CRC32.Initial;
      Total      : Natural := 0;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         declare
            Raw  : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
            Last : Ada.Streams.Stream_Element_Offset;
         begin
            Ada.Streams.Stream_IO.Read (File, Raw, Last);
            if Last >= Raw'First then
               declare
                  Count : constant Natural := Natural (Last - Raw'First + 1);
                  Chunk : Zlib.Byte_Array (1 .. Count);
               begin
                  for Index in Chunk'Range loop
                     Chunk (Index) :=
                       Zlib.Byte
                         (Raw
                            (Raw'First
                             + Ada.Streams.Stream_Element_Offset (Index - 1)));
                  end loop;

                  Archive.Verification.CRC32.Update (State, Chunk);
                  Total := Total + Count;
               end;
            end if;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);

      return (Bytes => Total, CRC => Archive.Verification.CRC32.Final (State));
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Compute_File_CRC32;

   function Fixture_Path
     (Name  : String;
      Bytes : Zlib.Byte_Array)
      return String
   is
      Path : constant String := Root & "/obj/check-all-byte-api/" & Name;
   begin
      Write_Bytes (Path, Bytes);
      return Path;
   end Fixture_Path;

   function Detect_Bytes
     (Bytes : Zlib.Byte_Array)
      return Archive.Archives.Formats.Detection_Result
   is
   begin
      return Archive.Archives.Formats.Detect_File
        (Fixture_Path ("detect.bin", Bytes));
   end Detect_Bytes;

   function Open_Dispatch
     (Bytes       : Zlib.Byte_Array;
      Source_Name : String := "")
      return Archive.Archives.Readers.Dispatch.Open_Result
   is
      Path : constant String := Fixture_Path
        ((if Source_Name'Length > 0 then Source_Name else "dispatch.bin"), Bytes);
   begin
      return Archive.Archives.Readers.Dispatch.Open_File
        (Path, Source_Name => Source_Name);
   end Open_Dispatch;

   type Memory_Tar_Sink is limited new Tarlib.Outputs.Output_Sink with record
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 8_192) := [others => 0];
      Length : Ada.Streams.Stream_Element_Offset := 0;
   end record;

   overriding procedure Write
     (Sink   : in out Memory_Tar_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
   begin
      if Sink.Length + Ada.Streams.Stream_Element_Offset (Data'Length) > Sink.Buffer'Last then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      end if;

      for Index in Data'Range loop
         Sink.Length := Sink.Length + Ada.Streams.Stream_Element_Offset (1);
         Sink.Buffer (Sink.Length) := Data (Index);
      end loop;
      Result := Tarlib.Errors.OK;
   end Write;

   function Tar_Sink_Bytes (Sink : Memory_Tar_Sink) return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. Natural (Sink.Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Zlib.Byte (Sink.Buffer (Ada.Streams.Stream_Element_Offset (Index)));
      end loop;
      return Result;
   end Tar_Sink_Bytes;

   procedure Put16 (Bytes : in out Zlib.Byte_Array; Offset : Natural; Value : Natural) is
   begin
      Bytes (Bytes'First + Offset) := Zlib.Byte (Value mod 256);
      Bytes (Bytes'First + Offset + 1) := Zlib.Byte ((Value / 256) mod 256);
   end Put16;

   procedure Put32_U
     (Bytes  : in out Zlib.Byte_Array;
      Offset : Natural;
      Value  : Interfaces.Unsigned_32)
   is
      V : Interfaces.Unsigned_32 := Value;
   begin
      for I in 0 .. 3 loop
         Bytes (Bytes'First + Offset + I) := Zlib.Byte (V mod 256);
         V := V / 256;
      end loop;
   end Put32_U;

   procedure Put32 (Bytes : in out Zlib.Byte_Array; Offset : Natural; Value : Natural) is
   begin
      Put32_U (Bytes, Offset, Interfaces.Unsigned_32 (Value));
   end Put32;

   procedure Put64_U
     (Bytes  : in out Zlib.Byte_Array;
      Offset : Natural;
      Value  : Interfaces.Unsigned_64)
   is
      V : Interfaces.Unsigned_64 := Value;
   begin
      for I in 0 .. 7 loop
         Bytes (Bytes'First + Offset + I) := Zlib.Byte (V mod 256);
         V := V / 256;
      end loop;
   end Put64_U;

   procedure Put_Text (Bytes : in out Zlib.Byte_Array; Offset : Natural; Text : String) is
   begin
      for Index in Text'Range loop
         Bytes (Bytes'First + Offset + Index - Text'First) :=
           Zlib.Byte (Character'Pos (Text (Index)));
      end loop;
   end Put_Text;

   function Payload_ABC return Zlib.Byte_Array is
     ([1 => Zlib.Byte (Character'Pos ('a')),
       2 => Zlib.Byte (Character'Pos ('b')),
       3 => Zlib.Byte (Character'Pos ('c'))]);

   function CRC32_String (Text : String) return Interfaces.Unsigned_32 is
      Bytes : Zlib.Byte_Array (1 .. Text'Length);
      State : Archive.Verification.CRC32.CRC32_State :=
        Archive.Verification.CRC32.Initial;
   begin
      for Index in Text'Range loop
         Bytes (Bytes'First + Index - Text'First) :=
           Zlib.Byte (Character'Pos (Text (Index)));
      end loop;
      Archive.Verification.CRC32.Update (State, Bytes);
      return Interfaces.Unsigned_32 (Archive.Verification.CRC32.Final (State));
   end CRC32_String;

   function Generated_Tar return Zlib.Byte_Array is
      Sink   : aliased Memory_Tar_Sink;
      Writer : Tarlib.Writers.Writer;
      Status : Tarlib.Errors.Status;
      Data   : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('o')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('k'))];
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated TAR fixture writer initialization failed");
      end if;
      Tarlib.Writers.Begin_File
        (Writer, "docs/readme.txt", Tarlib.Byte_Count (Data'Length), Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated TAR fixture entry start failed");
      end if;
      Tarlib.Writers.Write (Writer, Data, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated TAR fixture payload write failed");
      end if;
      Tarlib.Writers.End_Entry (Writer, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated TAR fixture entry end failed");
      end if;
      Tarlib.Writers.Finish (Writer, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated TAR fixture finish failed");
      end if;
      return Tar_Sink_Bytes (Sink);
   end Generated_Tar;

   function Generated_Tar_Duplicate_Path return Zlib.Byte_Array is
      Sink   : aliased Memory_Tar_Sink;
      Writer : Tarlib.Writers.Writer;
      Status : Tarlib.Errors.Status;
      One    : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('1'))];
      Two    : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('2'))];
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR fixture writer initialization failed");
      end if;

      Tarlib.Writers.Begin_File
        (Writer, "dup.txt", Tarlib.Byte_Count (One'Length), Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR first entry start failed");
      end if;
      Tarlib.Writers.Write (Writer, One, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR first payload write failed");
      end if;
      Tarlib.Writers.End_Entry (Writer, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR first entry end failed");
      end if;

      Tarlib.Writers.Begin_File
        (Writer, "dup.txt", Tarlib.Byte_Count (Two'Length), Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR second entry start failed");
      end if;
      Tarlib.Writers.Write (Writer, Two, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR second payload write failed");
      end if;
      Tarlib.Writers.End_Entry (Writer, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR second entry end failed");
      end if;

      Tarlib.Writers.Finish (Writer, Status);
      if Status.Code /= Tarlib.Errors.Success then
         Fail ("generated duplicate TAR fixture finish failed");
      end if;
      return Tar_Sink_Bytes (Sink);
   end Generated_Tar_Duplicate_Path;

   function Generated_Gzip return Zlib.Byte_Array is
      Status : Zlib.Status_Code;
      Result : constant Zlib.Byte_Array := Zlib.GZip (Payload_ABC, Zlib.Fixed, Status);
   begin
      if Status /= Zlib.Ok then
         Fail ("generated gzip fixture failed");
      end if;
      return Result;
   end Generated_Gzip;

   function Generated_Gzip_Empty return Zlib.Byte_Array is
      Status : Zlib.Status_Code;
      Empty  : constant Zlib.Byte_Array (1 .. 0) := [];
      Result : constant Zlib.Byte_Array := Zlib.GZip (Empty, Zlib.Fixed, Status);
   begin
      if Status /= Zlib.Ok then
         Fail ("generated empty gzip fixture failed");
      end if;
      return Result;
   end Generated_Gzip_Empty;

   function Generated_Gzip_Bad_Header_CRC return Zlib.Byte_Array is
      Base   : constant Zlib.Byte_Array := Generated_Gzip;
      Result : Zlib.Byte_Array (1 .. Base'Length + 2);
   begin
      for Offset in 0 .. 9 loop
         Result (Result'First + Offset) := Base (Base'First + Offset);
      end loop;
      Result (Result'First + 3) :=
        Zlib.Byte (Natural (Result (Result'First + 3)) + 16#02#);
      Result (Result'First + 10) := 0;
      Result (Result'First + 11) := 0;
      for Offset in 10 .. Base'Length - 1 loop
         Result (Result'First + Offset + 2) := Base (Base'First + Offset);
      end loop;
      return Result;
   end Generated_Gzip_Bad_Header_CRC;

   function Generated_Gzip_Bad_Trailer return Zlib.Byte_Array is
      Result : Zlib.Byte_Array := Generated_Gzip;
   begin
      if Result'Length >= 8 then
         Result (Result'Last - 7) := 0;
         Result (Result'Last - 6) := 0;
         Result (Result'Last - 5) := 0;
         Result (Result'Last - 4) := 0;
      end if;
      return Result;
   end Generated_Gzip_Bad_Trailer;

   function Generated_Tar_Gzip return Zlib.Byte_Array is
      Status : Zlib.Status_Code;
      Tar    : constant Zlib.Byte_Array := Generated_Tar;
      Result : constant Zlib.Byte_Array := Zlib.GZip (Tar, Zlib.Fixed, Status);
   begin
      if Status /= Zlib.Ok then
         Fail ("generated tar.gz fixture failed");
      end if;
      return Result;
   end Generated_Tar_Gzip;

   function Generated_Zip
     (Method    : Natural := 0;
      Bad_CRC   : Boolean := False;
      Encrypted : Boolean := False)
      return Zlib.Byte_Array
   is
      Name  : constant String := "a.txt";
      Plain : constant Zlib.Byte_Array := Payload_ABC;
      Status : Zlib.Status_Code;
      Payload : constant Zlib.Byte_Array :=
        (if Method = 8 then Zlib.Deflate_Raw (Plain, Zlib.Fixed, Status) else Plain);
      Local_Offset : constant Natural := 0;
      Central_Offset : constant Natural := 30 + Name'Length + Payload'Length;
      Central_Size : constant Natural := 46 + Name'Length;
      EOCD_Offset : constant Natural := Central_Offset + Central_Size;
      Total : constant Natural := EOCD_Offset + 22;
      Bytes : Zlib.Byte_Array (1 .. Total) := [others => 0];
      CRC : constant Natural := (if Bad_CRC then 0 else 16#3524_41C2#);
      Flags : constant Natural := (if Encrypted then 1 else 0);
   begin
      if Method = 8 and then Status /= Zlib.Ok then
         Fail ("generated zip deflate fixture failed");
      end if;
      Put32 (Bytes, Local_Offset, 16#0403_4B50#);
      Put16 (Bytes, Local_Offset + 6, Flags);
      Put16 (Bytes, Local_Offset + 8, Method);
      Put32 (Bytes, Local_Offset + 14, CRC);
      Put32 (Bytes, Local_Offset + 18, Payload'Length);
      Put32 (Bytes, Local_Offset + 22, Plain'Length);
      Put16 (Bytes, Local_Offset + 26, Name'Length);
      Put_Text (Bytes, Local_Offset + 30, Name);
      for Index in Payload'Range loop
         Bytes (Bytes'First + Local_Offset + 30 + Name'Length + Index - Payload'First) :=
           Payload (Index);
      end loop;

      Put32 (Bytes, Central_Offset, 16#0201_4B50#);
      Put16 (Bytes, Central_Offset + 8, Flags);
      Put16 (Bytes, Central_Offset + 10, Method);
      Put32 (Bytes, Central_Offset + 16, CRC);
      Put32 (Bytes, Central_Offset + 20, Payload'Length);
      Put32 (Bytes, Central_Offset + 24, Plain'Length);
      Put16 (Bytes, Central_Offset + 28, Name'Length);
      Put32 (Bytes, Central_Offset + 42, Local_Offset);
      Put_Text (Bytes, Central_Offset + 46, Name);

      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 1);
      Put16 (Bytes, EOCD_Offset + 10, 1);
      Put32 (Bytes, EOCD_Offset + 12, Central_Size);
      Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
      return Bytes;
   end Generated_Zip;

   function Generated_Zip_Local_Size_Mismatch return Zlib.Byte_Array is
      Bytes : Zlib.Byte_Array := Generated_Zip;
   begin
      Put32 (Bytes, 18, 4);
      return Bytes;
   end Generated_Zip_Local_Size_Mismatch;

   function Generated_Zip_Data_Descriptor return Zlib.Byte_Array is
      Name  : constant String := "a.txt";
      Plain : constant Zlib.Byte_Array := Payload_ABC;
      Payload : constant Zlib.Byte_Array := Plain;
      CRC : constant Natural := 16#3524_41C2#;
      Flags : constant Natural := 8;
      Method : constant Natural := 0;
      Local_Offset : constant Natural := 0;
      Descriptor_Offset : constant Natural := 30 + Name'Length + Payload'Length;
      Central_Offset : constant Natural := Descriptor_Offset + 16;
      Central_Size : constant Natural := 46 + Name'Length;
      EOCD_Offset : constant Natural := Central_Offset + Central_Size;
      Total : constant Natural := EOCD_Offset + 22;
      Bytes : Zlib.Byte_Array (1 .. Total) := [others => 0];
   begin
      Put32 (Bytes, Local_Offset, 16#0403_4B50#);
      Put16 (Bytes, Local_Offset + 6, Flags);
      Put16 (Bytes, Local_Offset + 8, Method);
      Put16 (Bytes, Local_Offset + 26, Name'Length);
      Put_Text (Bytes, Local_Offset + 30, Name);
      for Index in Payload'Range loop
         Bytes (Bytes'First + Local_Offset + 30 + Name'Length + Index - Payload'First) :=
           Payload (Index);
      end loop;

      Put32 (Bytes, Descriptor_Offset, 16#0807_4B50#);
      Put32 (Bytes, Descriptor_Offset + 4, CRC);
      Put32 (Bytes, Descriptor_Offset + 8, Payload'Length);
      Put32 (Bytes, Descriptor_Offset + 12, Plain'Length);

      Put32 (Bytes, Central_Offset, 16#0201_4B50#);
      Put16 (Bytes, Central_Offset + 8, Flags);
      Put16 (Bytes, Central_Offset + 10, Method);
      Put32 (Bytes, Central_Offset + 16, CRC);
      Put32 (Bytes, Central_Offset + 20, Payload'Length);
      Put32 (Bytes, Central_Offset + 24, Plain'Length);
      Put16 (Bytes, Central_Offset + 28, Name'Length);
      Put32 (Bytes, Central_Offset + 42, Local_Offset);
      Put_Text (Bytes, Central_Offset + 46, Name);

      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 1);
      Put16 (Bytes, EOCD_Offset + 10, 1);
      Put32 (Bytes, EOCD_Offset + 12, Central_Size);
      Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
      return Bytes;
   end Generated_Zip_Data_Descriptor;

   function Generated_Zip_ZIP64 return Zlib.Byte_Array is
      Name  : constant String := "a.txt";
      Plain : constant Zlib.Byte_Array := Payload_ABC;
      Payload : constant Zlib.Byte_Array := Plain;
      CRC : constant Natural := 16#3524_41C2#;
      Extra_Len : constant Natural := 20;
      Local_Offset : constant Natural := 0;
      Central_Offset : constant Natural := 30 + Name'Length + Extra_Len + Payload'Length;
      Central_Size : constant Natural := 46 + Name'Length + Extra_Len;
      EOCD_Offset : constant Natural := Central_Offset + Central_Size;
      Total : constant Natural := EOCD_Offset + 22;
      Bytes : Zlib.Byte_Array (1 .. Total) := [others => 0];
   begin
      Put32 (Bytes, Local_Offset, 16#0403_4B50#);
      Put32 (Bytes, Local_Offset + 14, CRC);
      Put32_U (Bytes, Local_Offset + 18, 16#FFFF_FFFF#);
      Put32_U (Bytes, Local_Offset + 22, 16#FFFF_FFFF#);
      Put16 (Bytes, Local_Offset + 26, Name'Length);
      Put16 (Bytes, Local_Offset + 28, Extra_Len);
      Put_Text (Bytes, Local_Offset + 30, Name);
      Put16 (Bytes, Local_Offset + 30 + Name'Length, 16#0001#);
      Put16 (Bytes, Local_Offset + 32 + Name'Length, 16);
      Put64_U (Bytes, Local_Offset + 34 + Name'Length, Interfaces.Unsigned_64 (Plain'Length));
      Put64_U (Bytes, Local_Offset + 42 + Name'Length, Interfaces.Unsigned_64 (Payload'Length));
      for Index in Payload'Range loop
         Bytes (Bytes'First + Local_Offset + 30 + Name'Length + Extra_Len + Index - Payload'First) :=
           Payload (Index);
      end loop;

      Put32 (Bytes, Central_Offset, 16#0201_4B50#);
      Put32 (Bytes, Central_Offset + 16, CRC);
      Put32_U (Bytes, Central_Offset + 20, 16#FFFF_FFFF#);
      Put32_U (Bytes, Central_Offset + 24, 16#FFFF_FFFF#);
      Put16 (Bytes, Central_Offset + 28, Name'Length);
      Put16 (Bytes, Central_Offset + 30, Extra_Len);
      Put32 (Bytes, Central_Offset + 42, Local_Offset);
      Put_Text (Bytes, Central_Offset + 46, Name);
      Put16 (Bytes, Central_Offset + 46 + Name'Length, 16#0001#);
      Put16 (Bytes, Central_Offset + 48 + Name'Length, 16);
      Put64_U (Bytes, Central_Offset + 50 + Name'Length, Interfaces.Unsigned_64 (Plain'Length));
      Put64_U (Bytes, Central_Offset + 58 + Name'Length, Interfaces.Unsigned_64 (Payload'Length));

      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 1);
      Put16 (Bytes, EOCD_Offset + 10, 1);
      Put32 (Bytes, EOCD_Offset + 12, Central_Size);
      Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
      return Bytes;
   end Generated_Zip_ZIP64;

   function Generated_Zip_ZIP64_Missing_Extra return Zlib.Byte_Array is
      Bytes : Zlib.Byte_Array := Generated_Zip;
      Central_Offset : constant Natural := 30 + 5 + 3;
   begin
      Put32_U (Bytes, Central_Offset + 20, 16#FFFF_FFFF#);
      Put32_U (Bytes, Central_Offset + 24, 16#FFFF_FFFF#);
      return Bytes;
   end Generated_Zip_ZIP64_Missing_Extra;

   function Generated_Zip_Central_CRC_Mismatch return Zlib.Byte_Array is
      Bytes : Zlib.Byte_Array := Generated_Zip;
      Central_Offset : constant Natural := 30 + 5 + 3;
   begin
      Put32 (Bytes, Central_Offset + 16, 0);
      return Bytes;
   end Generated_Zip_Central_CRC_Mismatch;

   function Generated_Zip_Unicode_Path
     (Bad_CRC     : Boolean := False;
      Bad_Version : Boolean := False)
      return Zlib.Byte_Array
   is
      Name  : constant String := "a.txt";
      Unicode_Name : constant String := "unicode.txt";
      Plain : constant Zlib.Byte_Array := Payload_ABC;
      Payload : constant Zlib.Byte_Array := Plain;
      CRC : constant Natural := 16#3524_41C2#;
      Extra_Len : constant Natural := 4 + 5 + Unicode_Name'Length;
      Local_Offset : constant Natural := 0;
      Central_Offset : constant Natural := 30 + Name'Length + Payload'Length;
      Central_Size : constant Natural := 46 + Name'Length + Extra_Len;
      EOCD_Offset : constant Natural := Central_Offset + Central_Size;
      Total : constant Natural := EOCD_Offset + 22;
      Bytes : Zlib.Byte_Array (1 .. Total) := [others => 0];
      Extra_Offset : constant Natural := Central_Offset + 46 + Name'Length;
   begin
      Put32 (Bytes, Local_Offset, 16#0403_4B50#);
      Put32 (Bytes, Local_Offset + 14, CRC);
      Put32 (Bytes, Local_Offset + 18, Payload'Length);
      Put32 (Bytes, Local_Offset + 22, Plain'Length);
      Put16 (Bytes, Local_Offset + 26, Name'Length);
      Put_Text (Bytes, Local_Offset + 30, Name);
      for Index in Payload'Range loop
         Bytes (Bytes'First + Local_Offset + 30 + Name'Length + Index - Payload'First) :=
           Payload (Index);
      end loop;

      Put32 (Bytes, Central_Offset, 16#0201_4B50#);
      Put32 (Bytes, Central_Offset + 16, CRC);
      Put32 (Bytes, Central_Offset + 20, Payload'Length);
      Put32 (Bytes, Central_Offset + 24, Plain'Length);
      Put16 (Bytes, Central_Offset + 28, Name'Length);
      Put16 (Bytes, Central_Offset + 30, Extra_Len);
      Put32 (Bytes, Central_Offset + 42, Local_Offset);
      Put_Text (Bytes, Central_Offset + 46, Name);
      Put16 (Bytes, Extra_Offset, 16#7075#);
      Put16 (Bytes, Extra_Offset + 2, 5 + Unicode_Name'Length);
      Bytes (Bytes'First + Extra_Offset + 4) :=
        (if Bad_Version then 2 else 1);
      Put32_U
        (Bytes,
         Extra_Offset + 5,
         (if Bad_CRC then 0 else CRC32_String (Name)));
      Put_Text (Bytes, Extra_Offset + 9, Unicode_Name);

      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 1);
      Put16 (Bytes, EOCD_Offset + 10, 1);
      Put32 (Bytes, EOCD_Offset + 12, Central_Size);
      Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
      return Bytes;
   end Generated_Zip_Unicode_Path;

   function Generated_Zip_ZIP64_Too_Large return Zlib.Byte_Array is
      Bytes : Zlib.Byte_Array := Generated_Zip_ZIP64;
      Name_Length : constant Natural := 5;
      Central_Offset : constant Natural := 30 + Name_Length + 20 + 3;
      Too_Large : constant Interfaces.Unsigned_64 :=
        Interfaces.Shift_Left (Interfaces.Unsigned_64 (1), 63);
   begin
      Put64_U (Bytes, 30 + Name_Length + 4, Too_Large);
      Put64_U (Bytes, Central_Offset + 46 + Name_Length + 4, Too_Large);
      return Bytes;
   end Generated_Zip_ZIP64_Too_Large;

   function Generated_Zip_Bad_Local_Signature return Zlib.Byte_Array is
      Bytes : Zlib.Byte_Array := Generated_Zip;
   begin
      Put32 (Bytes, 0, 16#0403_4B51#);
      return Bytes;
   end Generated_Zip_Bad_Local_Signature;

   function Generated_Fixture (Id : String) return Zlib.Byte_Array is
   begin
      if Id = "tar-basic" then
         return Generated_Tar;
      elsif Id = "tar-gzip-basic" then
         return Generated_Tar_Gzip;
      elsif Id = "tar-duplicate-path" then
         return Generated_Tar_Duplicate_Path;
      elsif Id = "zip-stored-basic" then
         return Generated_Zip;
      elsif Id = "zip-deflate-basic" then
         return Generated_Zip (Method => 8);
      elsif Id = "zip-data-descriptor" then
         return Generated_Zip_Data_Descriptor;
      elsif Id = "zip-zip64-basic" then
         return Generated_Zip_ZIP64;
      elsif Id = "zip-unicode-path" then
         return Generated_Zip_Unicode_Path;
      elsif Id = "gzip-basic" then
         return Generated_Gzip;
      elsif Id = "gzip-empty" then
         return Generated_Gzip_Empty;
      elsif Id = "zip-bad-crc" then
         return Generated_Zip (Bad_CRC => True);
      elsif Id = "zip-central-crc-mismatch" then
         return Generated_Zip_Central_CRC_Mismatch;
      elsif Id = "zip-unicode-path-bad-crc" then
         return Generated_Zip_Unicode_Path (Bad_CRC => True);
      elsif Id = "zip-unicode-path-bad-version" then
         return Generated_Zip_Unicode_Path (Bad_Version => True);
      elsif Id = "zip-unsupported-method" then
         return Generated_Zip (Method => 99);
      elsif Id = "zip-encrypted" then
         return Generated_Zip (Encrypted => True);
      elsif Id = "zip-zip64-missing-extra" then
         return Generated_Zip_ZIP64_Missing_Extra;
      elsif Id = "zip-zip64-too-large" then
         return Generated_Zip_ZIP64_Too_Large;
      elsif Id = "zip-local-size-mismatch" then
         return Generated_Zip_Local_Size_Mismatch;
      elsif Id = "zip-bad-local-signature" then
         return Generated_Zip_Bad_Local_Signature;
      elsif Id = "gzip-bad-header-crc" then
         return Generated_Gzip_Bad_Header_CRC;
      elsif Id = "gzip-bad-trailer" then
         return Generated_Gzip_Bad_Trailer;
      else
         Fail ("unknown generated fixture id: " & Id);
         return [];
      end if;
   end Generated_Fixture;

   function Truncated
     (Bytes        : Zlib.Byte_Array;
      Remove_Count : Natural)
      return Zlib.Byte_Array
   is
      New_Length : constant Natural :=
        (if Bytes'Length > Remove_Count then Bytes'Length - Remove_Count else 0);
      Result     : Zlib.Byte_Array (1 .. New_Length);
   begin
      for Index in Result'Range loop
         Result (Index) := Bytes (Bytes'First + Index - Result'First);
      end loop;
      return Result;
   end Truncated;

   function Archive_Input (Value : String) return Zlib.Byte_Array is
   begin
      if Value = "zip-truncated-central" then
         return Truncated (Generated_Zip, 12);
      elsif Value = "gzip-truncated" then
         return Truncated (Generated_Gzip, 3);
      elsif Value = "tar-truncated" then
         return Truncated (Generated_Tar, 1_400);
      elsif Value = "zip-central-crc-mismatch" then
         return Generated_Fixture ("zip-central-crc-mismatch");
      elsif Value = "zip-zip64-missing-extra" then
         return Generated_Fixture ("zip-zip64-missing-extra");
      elsif Value = "zip-unsupported-method" then
         return Generated_Fixture ("zip-unsupported-method");
      elsif Value = "zip-encrypted" then
         return Generated_Fixture ("zip-encrypted");
      elsif Value = "zip-local-size-mismatch" then
         return Generated_Fixture ("zip-local-size-mismatch");
      elsif Value = "zip-bad-local-signature" then
         return Generated_Fixture ("zip-bad-local-signature");
      elsif Value = "gzip-bad-header-crc" then
         return Generated_Fixture ("gzip-bad-header-crc");
      elsif Value = "gzip-bad-trailer" then
         return Generated_Fixture ("gzip-bad-trailer");
      else
         return Generated_Fixture (Value);
      end if;
   end Archive_Input;

   procedure Validate_Generated_Fixture
     (Id     : String;
      Format : String;
      Bytes  : Zlib.Byte_Array)
   is
      Source_Name : constant String :=
        (if Format = "tar" then "fixture.tar"
         elsif Format = "tar.gz" then "fixture.tar.gz"
         elsif Format = "zip" then "fixture.zip"
         elsif Format = "gzip" then "fixture.gz"
         else "fixture.bin");
      Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
        Open_Dispatch (Bytes, Source_Name);
   begin
      if Id = "zip-bad-crc" then
         if Opened.Status /= Archive.Archives.Errors.Ok then
            Fail ("generated bad-CRC ZIP should remain indexable");
         end if;
      elsif Opened.Status /= Archive.Archives.Errors.Ok then
         Fail ("generated fixture " & Id & " does not reopen through dispatch");
      elsif Archive.Archives.Index.Physical_Count (Opened.Index) = 0 then
         Fail ("generated fixture " & Id & " has no physical entries");
      end if;
   end Validate_Generated_Fixture;

   procedure Check_Fixture_Line (Line : String; Line_Number : Positive) is
      Id       : constant String := Field_Value (Line, "id");
      Path     : constant String := Field_Value (Line, "path");
      Format   : constant String := Field_Value (Line, "format");
      Purpose  : constant String := Field_Value (Line, "purpose");
      Size_Text : constant String := Field_Value (Line, "size");
      CRC_Text : constant String := Ada.Characters.Handling.To_Upper
        (Field_Value (Line, "crc32"));
      Generated : constant Boolean := Has_Prefix (Path, "generated:");
      Full     : constant String := Root & "/" & Path;
      Expected_Size : Natural;
   begin
      if Id = "" or else Path = "" or else Format = ""
        or else Purpose = "" or else Size_Text = "" or else CRC_Text = ""
      then
         Fail
           (Root & "/tests/fixtures/manifest.txt:"
            & Line_Number'Image & ": fixture entry has missing fields");
      end if;

      if not Generated and then not Has_Prefix (Path, "tests/fixtures/") then
         Fail
           (Root & "/tests/fixtures/manifest.txt:"
            & Line_Number'Image & ": fixture path must stay under tests/fixtures");
      end if;

      if not Generated and then not Ada.Directories.Exists (Full) then
         Fail (Full & ": listed fixture is missing");
      end if;

      Expected_Size := Natural'Value (Size_Text);
      if Generated then
         declare
            Bytes      : constant Zlib.Byte_Array := Generated_Fixture (Id);
            Actual_CRC : constant String := To_Hex8 (CRC32_Compute (Bytes));
         begin
            if Bytes'Length /= Expected_Size then
               Fail
                 (Full & ": fixture size mismatch, expected "
                  & Size_Text & " got" & Bytes'Length'Image);
            end if;

            if CRC_Text'Length /= 8 or else Actual_CRC /= CRC_Text then
               Fail
                 (Full & ": fixture CRC32 mismatch, expected "
                  & CRC_Text & " got " & Actual_CRC);
            end if;

            Validate_Generated_Fixture (Id, Format, Bytes);
         end;
      else
         declare
            Hashed     : constant File_CRC_Result := Compute_File_CRC32 (Full);
            Actual_CRC : constant String := To_Hex8 (Hashed.CRC);
         begin
            if Hashed.Bytes /= Expected_Size then
               Fail
                 (Full & ": fixture size mismatch, expected "
                  & Size_Text & " got" & Hashed.Bytes'Image);
            end if;

            if CRC_Text'Length /= 8 or else Actual_CRC /= CRC_Text then
               Fail
                 (Full & ": fixture CRC32 mismatch, expected "
                  & CRC_Text & " got " & Actual_CRC);
            end if;
         end;
      end if;
   exception
      when Constraint_Error =>
         Fail
           (Root & "/tests/fixtures/manifest.txt:"
            & Line_Number'Image & ": invalid numeric fixture field");
   end Check_Fixture_Line;

   procedure Check_Fixtures is
      Manifest : constant String := Root & "/tests/fixtures/manifest.txt";
      File     : Ada.Text_IO.File_Type;
      Buffer   : String (1 .. 1024);
      Last     : Natural;
      Line_No  : Natural := 0;
      Count    : Natural := 0;
      Has_Tar   : Boolean := False;
      Has_Settings_Current : Boolean := False;
      Has_Settings_Migration : Boolean := False;
      Has_Settings_Invalid : Boolean := False;
      Has_Tar_Gzip : Boolean := False;
      Has_Zip_Stored : Boolean := False;
      Has_Zip_Deflate : Boolean := False;
      Has_Zip_Descriptor : Boolean := False;
      Has_Zip64 : Boolean := False;
      Has_Gzip : Boolean := False;
      Has_Gzip_Empty : Boolean := False;
      Has_Tar_Duplicate : Boolean := False;
      Has_Zip_Bad_CRC : Boolean := False;
      Has_Zip_Unsupported : Boolean := False;
      Has_Zip_Encrypted : Boolean := False;
      Has_Gzip_Bad_Trailer : Boolean := False;
   begin
      if not Ada.Directories.Exists (Manifest) then
         Fail (Manifest & ": fixture manifest is missing");
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Manifest);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         Line_No := Line_No + 1;

         declare
            Line : constant String := Buffer (1 .. Last);
         begin
            if Last = 0 or else Line (Line'First) = '#' then
               null;
            elsif Has_Prefix (Line, "fixture ") then
               Check_Fixture_Line (Line, Positive (Line_No));
               declare
                  Id : constant String := Field_Value (Line, "id");
               begin
                  if Id = "tar-basic" then
                     Has_Tar := True;
                  elsif Id = "settings-current-valid" then
                     Has_Settings_Current := True;
                  elsif Id = "settings-schema0-migration" then
                     Has_Settings_Migration := True;
                  elsif Id = "settings-invalid-future-schema" then
                     Has_Settings_Invalid := True;
                  elsif Id = "tar-gzip-basic" then
                     Has_Tar_Gzip := True;
                  elsif Id = "tar-duplicate-path" then
                     Has_Tar_Duplicate := True;
                  elsif Id = "zip-stored-basic" then
                     Has_Zip_Stored := True;
                  elsif Id = "zip-deflate-basic" then
                     Has_Zip_Deflate := True;
                  elsif Id = "zip-data-descriptor" then
                     Has_Zip_Descriptor := True;
                  elsif Id = "zip-zip64-basic" then
                     Has_Zip64 := True;
                  elsif Id = "gzip-basic" then
                     Has_Gzip := True;
                  elsif Id = "gzip-empty" then
                     Has_Gzip_Empty := True;
                  elsif Id = "zip-bad-crc" then
                     Has_Zip_Bad_CRC := True;
                  elsif Id = "zip-unsupported-method" then
                     Has_Zip_Unsupported := True;
                  elsif Id = "zip-encrypted" then
                     Has_Zip_Encrypted := True;
                  elsif Id = "gzip-bad-trailer" then
                     Has_Gzip_Bad_Trailer := True;
                  end if;
               end;
               Count := Count + 1;
            else
               Fail (Manifest & ":" & Line_No'Image & ": unknown manifest record");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if Count = 0 then
         Fail (Manifest & ": fixture manifest contains no fixtures");
      elsif not Has_Settings_Current or else not Has_Settings_Migration
        or else not Has_Settings_Invalid
        or else not Has_Tar or else not Has_Tar_Gzip or else not Has_Zip_Stored
        or else not Has_Zip_Deflate or else not Has_Gzip
        or else not Has_Tar_Duplicate
        or else not Has_Zip_Descriptor or else not Has_Zip64
        or else not Has_Gzip_Empty
        or else not Has_Zip_Bad_CRC
        or else not Has_Zip_Unsupported or else not Has_Zip_Encrypted
        or else not Has_Gzip_Bad_Trailer
      then
         Fail (Manifest & ": fixture manifest is missing required archive matrix entries");
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Check_Fixtures;

   procedure Require_Manifest_Text
     (Relative_Path : String;
      Marker        : String)
   is
      Path    : constant String := Root & "/" & Relative_Path;
      Content : constant String := To_String (Read_Text_File (Path));
   begin
      if not Contains (Content, Marker) then
         Fail (Path & ": missing dependency/license marker: " & Marker);
      end if;
   end Require_Manifest_Text;

   procedure Check_Dependency_Licenses is
   begin
      Require_Manifest_Text ("alire.toml", "licenses = ""MIT OR Apache-2.0 WITH LLVM-exception""");
      Require_Manifest_Text ("tests/alire.toml", "licenses = ""MIT OR Apache-2.0 WITH LLVM-exception""");
      Require_Manifest_Text ("alire.toml", "guikit = ""*""");
      Require_Manifest_Text ("alire.toml", "i18n = ""*""");
      Require_Manifest_Text ("alire.toml", "messages = ""*""");
      Require_Manifest_Text ("alire.toml", "tarlib = ""*""");
      Require_Manifest_Text ("alire.toml", "zlib = ""*""");
      Require_Manifest_Text ("alire.toml", "cryptolib = ""*""");
      Require_Manifest_Text ("alire.toml", "hostkit = ""*""");
      Require_Manifest_Text ("alire.toml", "textrender = ""*""");
      Require_Manifest_Text ("tests/alire.toml", "archive = ""*""");
      Require_Manifest_Text ("tests/alire.toml", "messages = ""*""");
      Require_Manifest_Text ("tests/alire.toml", "project_tools = ""*""");
      Require_Manifest_Text ("tests/alire.toml", "tarlib = ""*""");
      Require_Manifest_Text ("tests/alire.toml", "aunit = ""^26.0.0""");
      Require_Manifest_Text ("tests/alire.toml", "project_tools = { path = ""../../project_tools"" }");
      Require_Manifest_Text ("docs/phase-0-dependency-audit.md", "`project_tools` exposes Ada process");
      Require_Manifest_Text ("docs/release-guide.md", "dependency/license checks are enforced by Ada tooling");
   end Check_Dependency_Licenses;

   function Decode_Token (Value : String) return String is
   begin
      if Value = "__empty__" then
         return "";
      else
         return Value;
      end if;
   end Decode_Token;

   function Parse_Safety (Value : String) return Archive.Archives.Entries.Path_Safety is
   begin
      if Value = "Safe_Path" then
         return Archive.Archives.Entries.Safe_Path;
      elsif Value = "Empty_Path" then
         return Archive.Archives.Entries.Empty_Path;
      elsif Value = "Absolute_Path" then
         return Archive.Archives.Entries.Absolute_Path;
      elsif Value = "Parent_Traversal" then
         return Archive.Archives.Entries.Parent_Traversal;
      elsif Value = "Windows_Drive_Path" then
         return Archive.Archives.Entries.Windows_Drive_Path;
      elsif Value = "Windows_UNC_Path" then
         return Archive.Archives.Entries.Windows_UNC_Path;
      elsif Value = "Alternate_Data_Stream" then
         return Archive.Archives.Entries.Alternate_Data_Stream;
      elsif Value = "Reserved_Name" then
         return Archive.Archives.Entries.Reserved_Name;
      elsif Value = "Invalid_Component" then
         return Archive.Archives.Entries.Invalid_Component;
      elsif Value = "Too_Long" then
         return Archive.Archives.Entries.Too_Long;
      elsif Value = "Unsafe_Encoding" then
         return Archive.Archives.Entries.Unsafe_Encoding;
      else
         Fail ("unknown corpus path-safety value: " & Value);
         return Archive.Archives.Entries.Unsafe_Encoding;
      end if;
   end Parse_Safety;

   function Parse_Decision (Value : String) return Archive.Extraction.Paths.Path_Decision is
   begin
      if Value = "Path_Accepted" then
         return Archive.Extraction.Paths.Path_Accepted;
      elsif Value = "Path_Blocked_Unsafe" then
         return Archive.Extraction.Paths.Path_Blocked_Unsafe;
      elsif Value = "Path_Blocked_Empty" then
         return Archive.Extraction.Paths.Path_Blocked_Empty;
      elsif Value = "Path_Blocked_Unsupported_Entry" then
         return Archive.Extraction.Paths.Path_Blocked_Unsupported_Entry;
      else
         Fail ("unknown corpus path-decision value: " & Value);
         return Archive.Extraction.Paths.Path_Blocked_Unsafe;
      end if;
   end Parse_Decision;

   function Parse_Platform (Value : String) return Archive.Extraction.Paths.Platform_Path_Model is
   begin
      if Value = "POSIX" then
         return Archive.Extraction.Paths.POSIX_Path_Model;
      elsif Value = "Windows" then
         return Archive.Extraction.Paths.Windows_Path_Model;
      elsif Value = "MacOS" then
         return Archive.Extraction.Paths.MacOS_Path_Model;
      else
         Fail ("unknown corpus platform value: " & Value);
         return Archive.Extraction.Paths.POSIX_Path_Model;
      end if;
   end Parse_Platform;

   function Parse_Format (Value : String) return Archive.Archives.Formats.Format_Id is
   begin
      if Value = "Unknown_Format" then
         return Archive.Archives.Formats.Unknown_Format;
      elsif Value = "Seven_Zip_Format" then
         return Archive.Archives.Formats.Seven_Zip_Format;
      elsif Value = "Rar_Format" then
         return Archive.Archives.Formats.Rar_Format;
      elsif Value = "Zip_Format" then
         return Archive.Archives.Formats.Zip_Format;
      elsif Value = "GZip_Format" then
         return Archive.Archives.Formats.GZip_Format;
      elsif Value = "Tar_Format" then
         return Archive.Archives.Formats.Tar_Format;
      elsif Value = "Cab_Format" then
         return Archive.Archives.Formats.Cab_Format;
      elsif Value = "Cpio_Format" then
         return Archive.Archives.Formats.Cpio_Format;
      elsif Value = "Iso_Format" then
         return Archive.Archives.Formats.Iso_Format;
      elsif Value = "Ar_Format" then
         return Archive.Archives.Formats.Ar_Format;
      elsif Value = "Split_Zip_Format" then
         return Archive.Archives.Formats.Split_Zip_Format;
      else
         Fail ("unknown corpus format value: " & Value);
         return Archive.Archives.Formats.Unknown_Format;
      end if;
   end Parse_Format;

   function Parse_Detection_Status
     (Value : String) return Archive.Archives.Formats.Detection_Status
   is
   begin
      if Value = "Detected" then
         return Archive.Archives.Formats.Detected;
      elsif Value = "Recognized_Unsupported" then
         return Archive.Archives.Formats.Recognized_Unsupported;
      elsif Value = "Invalid" then
         return Archive.Archives.Formats.Invalid;
      else
         Fail ("unknown corpus detection-status value: " & Value);
         return Archive.Archives.Formats.Invalid;
      end if;
   end Parse_Detection_Status;

   function Parse_Error_Code
     (Value : String) return Archive.Archives.Errors.Error_Code
   is
   begin
      if Value = "Ok" then
         return Archive.Archives.Errors.Ok;
      elsif Value = "Read_Failed" then
         return Archive.Archives.Errors.Read_Failed;
      elsif Value = "Write_Failed" then
         return Archive.Archives.Errors.Write_Failed;
      elsif Value = "Invalid_Format" then
         return Archive.Archives.Errors.Invalid_Format;
      elsif Value = "Unsupported_Format" then
         return Archive.Archives.Errors.Unsupported_Format;
      elsif Value = "Unsupported_Method" then
         return Archive.Archives.Errors.Unsupported_Method;
      elsif Value = "Zlib_Failed" then
         return Archive.Archives.Errors.Zlib_Failed;
      elsif Value = "Limit_Exceeded" then
         return Archive.Archives.Errors.Limit_Exceeded;
      elsif Value = "Cancelled" then
         return Archive.Archives.Errors.Cancelled;
      else
         Fail ("unknown corpus archive error value: " & Value);
         return Archive.Archives.Errors.Invalid_Format;
      end if;
   end Parse_Error_Code;

   function Format_Input (Value : String) return Zlib.Byte_Array is
   begin
      if Value = "7z-signature" then
         return [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#];
      elsif Value = "rar-signature" then
         return [16#52#, 16#61#, 16#72#, 16#21#, 16#1A#, 16#07#, 16#00#];
      elsif Value = "random-bytes" then
         return [16#6E#, 16#6F#, 16#74#, 16#61#, 16#72#, 16#63#];
      elsif Value = "cab-signature" then
         return [Character'Pos ('M'), Character'Pos ('S'), Character'Pos ('C'), Character'Pos ('F')];
      elsif Value = "cpio-newc-signature" then
         return
           [Character'Pos ('0'), Character'Pos ('7'), Character'Pos ('0'),
            Character'Pos ('7'), Character'Pos ('0'), Character'Pos ('1')];
      elsif Value = "ar-signature" then
         return
           [Character'Pos ('!'), Character'Pos ('<'), Character'Pos ('a'),
            Character'Pos ('r'), Character'Pos ('c'), Character'Pos ('h'),
            Character'Pos ('>'), 16#0A#];
      elsif Value = "split-zip-signature" then
         return [16#50#, 16#4B#, 16#07#, 16#08#];
      elsif Value = "iso-signature" then
         declare
            Result : Zlib.Byte_Array (1 .. 32_774) := [others => 0];
         begin
            Result (32_770) := Character'Pos ('C');
            Result (32_771) := Character'Pos ('D');
            Result (32_772) := Character'Pos ('0');
            Result (32_773) := Character'Pos ('0');
            Result (32_774) := Character'Pos ('1');
            return Result;
         end;
      else
         Fail ("unknown corpus format input: " & Value);
         return [];
      end if;
   end Format_Input;

   procedure Check_Path_Corpus_Case
     (Line : String; Line_Number : Positive; Id : String)
   is
      Input    : constant String := Decode_Token (Field_Value (Line, "input"));
      Expected : constant Archive.Archives.Entries.Path_Safety :=
        Parse_Safety (Field_Value (Line, "safety"));
      Expected_Decision : constant Archive.Extraction.Paths.Path_Decision :=
        Parse_Decision (Field_Value (Line, "decision"));
      Platform : constant Archive.Extraction.Paths.Platform_Path_Model :=
        Parse_Platform (Field_Value (Line, "platform"));
      Item     : Archive.Archives.Entries.Archive_Entry;
      Planned  : Archive.Extraction.Paths.Planned_Path;
   begin
      Item.Kind := Archive.Archives.Entries.Regular_File;
      Item.Original_Path := To_Unbounded_String (Input);
      Planned := Archive.Extraction.Paths.Plan_Relative_Path (Item, Platform);

      if Planned.Safety /= Expected then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " safety mismatch");
      elsif Planned.Decision /= Expected_Decision then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " extraction decision mismatch");
      end if;
   end Check_Path_Corpus_Case;

   procedure Check_Platform_Key_Corpus_Case
     (Line : String; Line_Number : Positive; Id : String)
   is
      Input    : constant String := Decode_Token (Field_Value (Line, "input"));
      Expected : constant String := Decode_Token (Field_Value (Line, "expected"));
      Platform : constant Archive.Extraction.Paths.Platform_Path_Model :=
        Parse_Platform (Field_Value (Line, "platform"));
      Item     : Archive.Archives.Entries.Archive_Entry;
      Planned  : Archive.Extraction.Paths.Planned_Path;
   begin
      Item.Kind := Archive.Archives.Entries.Regular_File;
      Item.Original_Path := To_Unbounded_String (Input);
      Planned := Archive.Extraction.Paths.Plan_Relative_Path (Item, Platform);

      if To_String (Planned.Relative_Key) /= Expected then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " platform key mismatch");
      end if;
   end Check_Platform_Key_Corpus_Case;

   procedure Check_Platform_Collision_Corpus_Case
     (Line : String; Line_Number : Positive; Id : String)
   is
      Left_Input  : constant String := Decode_Token (Field_Value (Line, "left"));
      Right_Input : constant String := Decode_Token (Field_Value (Line, "right"));
      Expected_Text : constant String := Field_Value (Line, "collision");
      Platform : constant Archive.Extraction.Paths.Platform_Path_Model :=
        Parse_Platform (Field_Value (Line, "platform"));
      Left_Item  : Archive.Archives.Entries.Archive_Entry;
      Right_Item : Archive.Archives.Entries.Archive_Entry;
      Left_Path  : Archive.Extraction.Paths.Planned_Path;
      Right_Path : Archive.Extraction.Paths.Planned_Path;
      Expected   : Boolean;
   begin
      if Expected_Text = "true" then
         Expected := True;
      elsif Expected_Text = "false" then
         Expected := False;
      else
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " has invalid collision expectation");
      end if;

      Left_Item.Kind := Archive.Archives.Entries.Regular_File;
      Left_Item.Original_Path := To_Unbounded_String (Left_Input);
      Right_Item.Kind := Archive.Archives.Entries.Regular_File;
      Right_Item.Original_Path := To_Unbounded_String (Right_Input);
      Left_Path := Archive.Extraction.Paths.Plan_Relative_Path (Left_Item, Platform);
      Right_Path := Archive.Extraction.Paths.Plan_Relative_Path (Right_Item, Platform);

      if (Left_Path.Decision = Archive.Extraction.Paths.Path_Accepted
          and then Right_Path.Decision = Archive.Extraction.Paths.Path_Accepted
          and then To_String (Left_Path.Relative_Key) =
                   To_String (Right_Path.Relative_Key)) /= Expected
      then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " platform collision mismatch");
      end if;
   end Check_Platform_Collision_Corpus_Case;

   procedure Check_Format_Corpus_Case
     (Line : String; Line_Number : Positive; Id : String)
   is
      Bytes : constant Zlib.Byte_Array := Format_Input (Field_Value (Line, "input"));
      Detection : constant Archive.Archives.Formats.Detection_Result :=
        Detect_Bytes (Bytes);
      Expected_Format : constant Archive.Archives.Formats.Format_Id :=
        Parse_Format (Field_Value (Line, "expected"));
      Expected_Status : constant Archive.Archives.Formats.Detection_Status :=
        Parse_Detection_Status (Field_Value (Line, "status"));
   begin
      if Detection.Format /= Expected_Format then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " format mismatch");
      elsif Detection.Status /= Expected_Status then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " detection status mismatch");
      end if;
   end Check_Format_Corpus_Case;

   procedure Check_Archive_Corpus_Case
     (Line : String; Line_Number : Positive; Id : String)
   is
      Bytes : constant Zlib.Byte_Array := Archive_Input (Field_Value (Line, "input"));
      Source : constant String := Field_Value (Line, "source");
      Expected_Status : constant Archive.Archives.Errors.Error_Code :=
        Parse_Error_Code (Field_Value (Line, "open"));
      Expected_Entries : constant Natural := Natural'Value (Field_Value (Line, "entries"));
      Expected_Payload : constant String := Field_Value (Line, "payload");
      Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
        Open_Dispatch (Bytes, Source);
      Payload_Path : constant String := Root & "/obj/check_all_payload_" & Id & ".bin";

      procedure Write_Corpus_Archive is
         File : Ada.Streams.Stream_IO.File_Type;
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
      begin
         Ada.Directories.Create_Path (Root & "/obj");
         for Index in Bytes'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
              Ada.Streams.Stream_Element (Bytes (Index));
         end loop;
         Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Payload_Path);
         Ada.Streams.Stream_IO.Write (File, Data);
         Ada.Streams.Stream_IO.Close (File);
      end Write_Corpus_Archive;

      function First_Regular_Entry
        return Archive.Archives.Entries.Archive_Entry
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Opened.Index) loop
            declare
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For
                   (Opened.Index, Archive.Types.Entry_Id (Raw_Id));
            begin
               if not Item.Synthetic
                 and then Item.Kind = Archive.Archives.Entries.Regular_File
               then
                  return Item;
               end if;
            end;
         end loop;

         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " has no regular payload entry");
         return Archive.Archives.Entries.Archive_Entry'(others => <>);
      end First_Regular_Entry;
   begin
      if Opened.Status /= Expected_Status then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " archive open status mismatch"
            & ", expected " & Archive.Archives.Errors.Error_Code'Image (Expected_Status)
            & " got " & Archive.Archives.Errors.Error_Code'Image (Opened.Status));
      elsif Archive.Archives.Index.Physical_Count (Opened.Index) /= Expected_Entries then
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " physical entry count mismatch");
      end if;

      if Expected_Payload /= "" then
         declare
            procedure Ignore
              (Chunk : Zlib.Byte_Array;
               Continue : in out Boolean)
            is
            begin
               pragma Unreferenced (Chunk);
               Continue := True;
            end Ignore;

            Expected : constant Archive.Archives.Errors.Error_Code :=
              Parse_Error_Code (Expected_Payload);
            Payload : Archive.Archives.Readers.Dispatch.Stream_Result;
         begin
            Write_Corpus_Archive;
            Payload :=
              Archive.Archives.Readers.Dispatch.Stream_Payload_File
                (Payload_Path, Source, First_Regular_Entry, Ignore'Access);
            if Payload.Status /= Expected then
               Fail
                 (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
                  & ": corpus " & Id & " payload status mismatch"
                  & ", expected " & Archive.Archives.Errors.Error_Code'Image (Expected)
                  & " got " & Archive.Archives.Errors.Error_Code'Image (Payload.Status));
            end if;
         end;
      end if;
   exception
      when Constraint_Error =>
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": corpus " & Id & " has invalid numeric archive fields");
   end Check_Archive_Corpus_Case;

   procedure Check_Corpus_Line (Line : String; Line_Number : Positive) is
      Id   : constant String := Field_Value (Line, "id");
      Kind : constant String := Field_Value (Line, "kind");
   begin
      if Id = "" or else Kind = "" then
         Fail
           (Root & "/tests/fixtures/corpus.txt:"
            & Line_Number'Image & ": corpus entry has missing fields");
      elsif Kind = "path" then
         Check_Path_Corpus_Case (Line, Line_Number, Id);
      elsif Kind = "platform-key" then
         Check_Platform_Key_Corpus_Case (Line, Line_Number, Id);
      elsif Kind = "platform-collision" then
         Check_Platform_Collision_Corpus_Case (Line, Line_Number, Id);
      elsif Kind = "format" then
         Check_Format_Corpus_Case (Line, Line_Number, Id);
      elsif Kind = "archive" then
         Check_Archive_Corpus_Case (Line, Line_Number, Id);
      else
         Fail
           (Root & "/tests/fixtures/corpus.txt:" & Line_Number'Image
            & ": unknown corpus kind " & Kind);
      end if;
   end Check_Corpus_Line;

   procedure Check_Corpus is
      Manifest : constant String := Root & "/tests/fixtures/corpus.txt";
      File     : Ada.Text_IO.File_Type;
      Buffer   : String (1 .. 1024);
      Last     : Natural;
      Line_No  : Natural := 0;
      Count    : Natural := 0;
      Has_Path_Attack : Boolean := False;
      Has_Unsupported_Format : Boolean := False;
      Has_Tar : Boolean := False;
      Has_Tar_Gzip : Boolean := False;
      Has_Zip_Stored : Boolean := False;
      Has_Zip_Deflate : Boolean := False;
      Has_Gzip : Boolean := False;
      Has_Malformed : Boolean := False;
      Has_Platform_Collision : Boolean := False;
      Has_Zip_Unicode : Boolean := False;
      Has_Zip64_Overflow : Boolean := False;
   begin
      if not Ada.Directories.Exists (Manifest) then
         Fail (Manifest & ": corpus manifest is missing");
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Manifest);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         Line_No := Line_No + 1;

         declare
            Line : constant String := Buffer (1 .. Last);
         begin
            if Last = 0 or else Line (Line'First) = '#' then
               null;
            elsif Has_Prefix (Line, "case ") then
               Check_Corpus_Line (Line, Positive (Line_No));
               declare
                  Id   : constant String := Field_Value (Line, "id");
                  Kind : constant String := Field_Value (Line, "kind");
               begin
                  if Kind = "path"
                    and then Field_Value (Line, "decision") = "Path_Blocked_Unsafe"
                  then
                     Has_Path_Attack := True;
                  elsif Kind = "format"
                    and then Field_Value (Line, "status") = "Recognized_Unsupported"
                  then
                     Has_Unsupported_Format := True;
                  elsif Kind = "platform-collision" then
                     Has_Platform_Collision := True;
                  elsif Id = "archive-tar-basic" then
                     Has_Tar := True;
                  elsif Id = "archive-tar-gzip-basic" then
                     Has_Tar_Gzip := True;
                  elsif Id = "archive-zip-stored-basic" then
                     Has_Zip_Stored := True;
                  elsif Id = "archive-zip-deflate-basic" then
                     Has_Zip_Deflate := True;
                  elsif Id = "archive-gzip-basic" then
                     Has_Gzip := True;
                  elsif Id = "archive-zip-unicode-path" then
                     Has_Zip_Unicode := True;
                  elsif Id = "archive-zip-zip64-too-large" then
                     Has_Zip64_Overflow := True;
                  elsif Id = "archive-zip-truncated-central"
                    or else Id = "archive-gzip-truncated"
                    or else Id = "archive-tar-truncated"
                    or else Id = "archive-zip-bad-crc"
                  then
                     Has_Malformed := True;
                  end if;
               end;
               Count := Count + 1;
            else
               Fail (Manifest & ":" & Line_No'Image & ": unknown corpus record");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if Count < 12 then
         Fail (Manifest & ": corpus manifest has too few cases");
      elsif not Has_Path_Attack or else not Has_Unsupported_Format
        or else not Has_Tar or else not Has_Tar_Gzip or else not Has_Zip_Stored
        or else not Has_Zip_Deflate or else not Has_Gzip or else not Has_Malformed
        or else not Has_Platform_Collision
        or else not Has_Zip_Unicode or else not Has_Zip64_Overflow
      then
         Fail (Manifest & ": corpus manifest is missing required format/security breadth");
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Check_Corpus;

   procedure Check_Persisted_Release_Report is
      Report_Path : constant String := Tests & "/obj/release-report.json";
      Report      : constant String := To_String (Read_Text_File (Report_Path));
   begin
      if Report'Length = 0 then
         Fail (Report_Path & ": persisted release report is missing or empty");
      elsif not Contains (Report, """package_input_count""") then
         Fail (Report_Path & ": release report is missing package input count");
      elsif not Contains (Report, """package_crc32_xor""") then
         Fail (Report_Path & ": release report is missing package checksum aggregate");
      elsif not Contains (Report, """mandatory_release_gates"":  20") then
         Fail (Report_Path & ": release report is missing mandatory gate count");
      elsif not Contains (Report, """enforced_release_gates"":  20") then
         Fail (Report_Path & ": release report is missing enforced gate count");
      elsif not Contains (Report, """release_gates""") then
         Fail (Report_Path & ": release report is missing gate matrix");
      elsif not Contains (Report, """malformed/security corpus""") then
         Fail (Report_Path & ": release report is missing corpus validation check");
      elsif not Contains (Report, """extraction security tests""") then
         Fail (Report_Path & ": release report is missing extraction security check");
      elsif not Contains (Report, """deterministic mutation tests""") then
         Fail (Report_Path & ": release report is missing deterministic mutation check");
      elsif not Contains (Report, """dependency/license manifests""") then
         Fail (Report_Path & ": release report is missing dependency/license check");
      elsif not Contains (Report, """id"": ""run_gnatprove""") then
         Fail (Report_Path & ": release report is missing GNATprove gate tracking");
      elsif not Contains (Report, """status"": ""enforced""") then
         Fail (Report_Path & ": release report is missing enforced gate status");
      elsif Contains (Report, """status"": ""tracked""") then
         Fail (Report_Path & ": release report still contains tracked gates");
      end if;
   end Check_Persisted_Release_Report;

begin
   if not Ada.Directories.Exists (Root & "/archive.gpr")
     or else not Ada.Directories.Exists (Tests & "/archive_tests.gpr")
   then
      Put_Line (Standard_Error, "check_all must be run from the archive root or tests directory");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Project_Tools.Processes.Require_Command
     ("alr", "alr is required for the archive check_all workflow");
   Project_Tools.Processes.Require_Command
     ("gnatprove", "gnatprove is required for the archive release workflow");

   Check_Architecture;
   Check_Catalogs;
   Check_Documentation;
   Check_Fixtures;
   Check_Corpus;
   Check_Dependency_Licenses;
   Run ("root build", Root, Alr, [1 => new String'("build")]);
   Run ("tests build", Tests, Alr, [1 => new String'("build")]);
   Run ("AUnit tests", Tests, "./bin/archive_tests", []);
   Run ("integration tests", Tests, "./bin/archive_tests", []);
   Run ("headless smoke", Root, "./bin/archive", [1 => new String'("--headless-smoke")]);
   Run ("headless gui", Root, "./bin/archive", [1 => new String'("--headless-gui")]);
   Run ("root release build", Root, Alr, [1 => new String'("build"), 2 => new String'("--release")]);
   Run ("tests release build", Tests, Alr, [1 => new String'("build"), 2 => new String'("--release")]);
   Run
     ("GNATprove",
      Root,
      Gnatprove,
      [1 => new String'("-P"),
       2 => new String'("tests/proof/archive_release_proof.gpr"),
       3 => new String'("-U"),
       4 => new String'("--level=0"),
       5 => new String'("--mode=check")]);
   Run ("packaged smoke test", Root, "./bin/archive", [1 => new String'("--headless-smoke")]);
   Run ("release report", Tests, "./bin/release_report", [1 => new String'("--check")]);
   Run
     ("persisted release report",
      Tests,
      "./bin/release_report",
      [1 => new String'("--write"), 2 => new String'("obj/release-report.json")]);
   Check_Persisted_Release_Report;
   Check_Release_Cleanliness;

   Put_Line ("archive check_all passed");
exception
   when Error : others =>
      Put_Line (Standard_Error, "archive check_all failed: " & Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Check_All;
