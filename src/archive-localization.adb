with Ada.Characters.Handling;
with Ada.Environment_Variables;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Archive.Localization is
   use Ada.Strings.Unbounded;

   function Lookup_In_File (Path : String; Key : String; Found : out Boolean) return String is
      File : Ada.Text_IO.File_Type;
   begin
      Found := False;
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
            Sep  : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
         begin
            if Sep > Line'First and then Line (Line'First .. Sep - 1) = Key then
               Ada.Text_IO.Close (File);
               Found := True;
               return Line (Sep + 1 .. Line'Last);
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return "";
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Found := False;
         return "";
   end Lookup_In_File;

   function Lookup_Catalog (Key : String; Found : out Boolean) return String is
      Value : Unbounded_String;
   begin
      Value := To_Unbounded_String (Lookup_In_File ("share/archive.catalog", Key, Found));
      if Found then
         return To_String (Value);
      end if;

      Value := To_Unbounded_String (Lookup_In_File ("../share/archive.catalog", Key, Found));
      if Found then
         return To_String (Value);
      end if;

      return "";
   end Lookup_Catalog;

   function Normalize_Locale (Value : String) return String is
      Raw    : constant String := Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both);
      Last   : Natural := Raw'Last;
      Result : Unbounded_String;
      Region : Boolean := False;
   begin
      if Raw'Length = 0 then
         return "en";
      end if;
      for Index in Raw'Range loop
         if Raw (Index) = '.' or else Raw (Index) = '@' then
            Last := Index - 1;
            exit;
         end if;
      end loop;
      if Last < Raw'First then
         return "en";
      end if;
      declare
         Base : constant String := Raw (Raw'First .. Last);
      begin
         if Base = "C" or else Base = "POSIX" then
            return "en";
         end if;
         for C of Base loop
            if C = '_' or else C = '-' then
               Append (Result, '-');
               Region := True;
            elsif Region then
               Append (Result, Ada.Characters.Handling.To_Upper (C));
            else
               Append (Result, Ada.Characters.Handling.To_Lower (C));
            end if;
         end loop;
      end;
      if Length (Result) = 0 then
         return "en";
      end if;
      return To_String (Result);
   end Normalize_Locale;

   function System_Locale return String is
   begin
      if Ada.Environment_Variables.Exists ("LC_ALL") then
         return Normalize_Locale (Ada.Environment_Variables.Value ("LC_ALL"));
      elsif Ada.Environment_Variables.Exists ("LC_MESSAGES") then
         return Normalize_Locale (Ada.Environment_Variables.Value ("LC_MESSAGES"));
      elsif Ada.Environment_Variables.Exists ("LANG") then
         return Normalize_Locale (Ada.Environment_Variables.Value ("LANG"));
      else
         return "en";
      end if;
   end System_Locale;

   function Text (Key : String; Locale : String := "") return String is
      pragma Unreferenced (Locale);
      Found : Boolean := False;
      Value : constant String := Lookup_Catalog (Key, Found);
   begin
      if Found then
         return Value;
      elsif Key = "application.title" then
         return "archive";
      elsif Key = "application.version" then
         return "archive 0.1.0-dev";
      elsif Key = "help.summary" then
         return "archive is a graphical archive manager.";
      elsif Key = "runtime.backend.headless" then
         return "headless guikit shell";
      elsif Key = "format.tar.name" then
         return "TAR";
      elsif Key = "format.tar.description" then
         return "POSIX tar archive handled through tarlib.";
      elsif Key = "format.tar.gz.name" then
         return "TAR gzip";
      elsif Key = "format.tar.gz.description" then
         return "gzip-compressed TAR archive handled through zlib and tarlib.";
      elsif Key = "format.zip.name" then
         return "ZIP";
      elsif Key = "format.zip.description" then
         return "ZIP archive with stored and DEFLATE entries.";
      elsif Key = "format.gzip.name" then
         return "gzip";
      elsif Key = "format.gzip.description" then
         return "Standalone gzip stream exposed as one logical file.";
      elsif Key = "format.7z.name" then
         return "7z";
      elsif Key = "format.7z.description" then
         return "7z archive; recognized but unsupported in this version.";
      elsif Key = "format.rar.name" then
         return "RAR";
      elsif Key = "format.rar.description" then
         return "RAR archive; recognized but unsupported in this version.";
      elsif Key = "format.xz.name" then
         return "XZ";
      elsif Key = "format.xz.description" then
         return "XZ stream; recognized but unsupported in this version.";
      elsif Key = "format.bzip2.name" then
         return "bzip2";
      elsif Key = "format.bzip2.description" then
         return "bzip2 stream; recognized but unsupported in this version.";
      elsif Key = "format.zstd.name" then
         return "Zstandard";
      elsif Key = "format.zstd.description" then
         return "Zstandard stream; recognized but unsupported in this version.";
      elsif Key = "format.cab.name" then
         return "CAB";
      elsif Key = "format.cab.description" then
         return "Microsoft Cabinet archive; recognized but unsupported in this version.";
      elsif Key = "format.cpio.name" then
         return "CPIO";
      elsif Key = "format.cpio.description" then
         return "CPIO archive; recognized but unsupported in this version.";
      elsif Key = "format.iso.name" then
         return "ISO";
      elsif Key = "format.iso.description" then
         return "ISO 9660 image; recognized but unsupported in this version.";
      elsif Key = "format.ar.name" then
         return "AR";
      elsif Key = "format.ar.description" then
         return "Unix ar archive; recognized but unsupported in this version.";
      elsif Key = "format.split_zip.name" then
         return "split ZIP";
      elsif Key = "format.split_zip.description" then
         return "Split or spanning ZIP archive; recognized but unsupported in this version.";
      elsif Key = "unavailable.encrypted" then
         return "Encrypted entries cannot be previewed or extracted in this version.";
      elsif Key = "unavailable.unsupported_method" then
         return "This entry uses an unsupported compression method.";
      elsif Key = "unavailable.unsafe_path" then
         return "This entry has an unsafe archive path.";
      elsif Key = "unavailable.unsupported_entry_kind" then
         return "This entry kind cannot be previewed or extracted in this version.";
      elsif Key = "column.name" then
         return "Name";
      elsif Key = "column.type" then
         return "Type";
      elsif Key = "column.uncompressed_size" then
         return "Uncompressed size";
      elsif Key = "column.compressed_size" then
         return "Compressed size";
      elsif Key = "column.compression_ratio" then
         return "Compression ratio";
      elsif Key = "column.modified_time" then
         return "Modified time";
      elsif Key = "column.compression_method" then
         return "Compression method";
      elsif Key = "column.archive_position" then
         return "Archive position";
      elsif Key = "column.original_path" then
         return "Original path";
      elsif Key = "column.owner" then
         return "Owner";
      elsif Key = "column.group" then
         return "Group";
      elsif Key = "column.permissions" then
         return "Permissions";
      elsif Key = "column.integrity" then
         return "Integrity";
      elsif Key = "column.path_safety" then
         return "Path safety";
      elsif Key = "column.link_target" then
         return "Link target";
      elsif Key = "command.unavailable.none" then
         return "This command is unavailable.";
      elsif Key = "command.unavailable.no_archive" then
         return "Open an archive before using this command.";
      elsif Key = "command.unavailable.no_selection" then
         return "Select an archive entry before using this command.";
      elsif Key = "command.unavailable.no_filter" then
         return "Enter a filter before using this command.";
      elsif Key = "command.unavailable.no_pending_changes" then
         return "Change the archive before saving it.";
      elsif Key = "command.unavailable.not_ready" then
         return "The current archive state cannot run this command.";
      elsif Key = "command.unavailable.read_only_archive" then
         return "This archive format does not support writing.";
      elsif Key = "command.archive.new.name" then
         return "New Archive";
      elsif Key = "command.archive.new.description" then
         return "Create a new archive through a validated write plan.";
      elsif Key = "command.archive.save.name" then
         return "Save Archive";
      elsif Key = "command.archive.save.description" then
         return "Publish pending archive changes safely.";
      elsif Key = "command.archive.save_as.name" then
         return "Save Archive As";
      elsif Key = "command.archive.save_as.description" then
         return "Publish the current archive to a new destination.";
      elsif Key = "command.archive.discard_changes.name" then
         return "Discard Changes";
      elsif Key = "command.archive.discard_changes.description" then
         return "Discard pending archive changes that have not been saved.";
      elsif Key = "command.archive.add_files.name" then
         return "Add Files";
      elsif Key = "command.archive.add_files.description" then
         return "Add files to the archive through a validated write plan.";
      elsif Key = "command.archive.add_directory.name" then
         return "Add Directory";
      elsif Key = "command.archive.add_directory.description" then
         return "Add a directory tree to the archive through a validated write plan.";
      elsif Key = "command.archive.replace_selected.name" then
         return "Replace Selected";
      elsif Key = "command.archive.replace_selected.description" then
         return "Replace the selected file through a validated archive rewrite plan.";
      elsif Key = "command.archive.remove_selected.name" then
         return "Remove Selected";
      elsif Key = "command.archive.remove_selected.description" then
         return "Remove selected entries through a validated archive rewrite plan.";
      elsif Key = "command.archive.rename_selected.name" then
         return "Rename Selected";
      elsif Key = "command.archive.rename_selected.description" then
         return "Rename the selected entry through a validated archive rewrite plan.";
      elsif Key = "ui.notification.open_complete" then
         return "Archive opened.";
      elsif Key = "ui.notification.open_failed" then
         return "Archive open failed.";
      elsif Key = "ui.notification.source_changed" then
         return "Archive source changed. Reload before reading entries.";
      elsif Key = "ui.notification.extract_complete" then
         return "Extraction completed.";
      elsif Key = "ui.notification.extract_failed" then
         return "Extraction failed.";
      elsif Key = "ui.notification.extract_failed_checksum" then
         return "Extraction failed because integrity verification failed.";
      elsif Key = "ui.notification.extract_failed_limit" then
         return "Extraction failed because an extraction limit was exceeded.";
      elsif Key = "ui.notification.extract_failed_containment" then
         return "Extraction failed because an output path was unsafe.";
      elsif Key = "ui.notification.extract_blocked" then
         return "Extraction blocked by the extraction plan.";
      elsif Key = "ui.notification.extract_cancelled" then
         return "Extraction cancelled.";
      elsif Key = "ui.preview.state.none" then
         return "No preview";
      elsif Key = "ui.preview.state.loading" then
         return "Loading preview";
      elsif Key = "ui.preview.state.ready" then
         return "Preview ready";
      elsif Key = "ui.preview.state.failed" then
         return "Preview failed";
      elsif Key = "ui.preview.truncated" then
         return "Truncated";
      elsif Key = "settings.title" then
         return "Settings";
      elsif Key = "settings.section.general" then
         return "General";
      elsif Key = "settings.section.layout" then
         return "Layout";
      elsif Key = "settings.view" then
         return "Default view";
      elsif Key = "settings.directories_first" then
         return "Directories first";
      elsif Key = "settings.preview_visible" then
         return "Show preview";
      elsif Key = "settings.preview_limit" then
         return "Preview byte limit";
      elsif Key = "settings.per_entry_extraction_limit" then
         return "Per-entry extraction limit";
      elsif Key = "settings.total_extraction_limit" then
         return "Total extraction limit";
      elsif Key = "settings.conflict_policy" then
         return "Extraction conflicts";
      elsif Key = "settings.conflict.ask" then
         return "Ask";
      elsif Key = "settings.conflict.skip" then
         return "Skip";
      elsif Key = "settings.conflict.overwrite" then
         return "Overwrite";
      elsif Key = "settings.conflict.rename" then
         return "Rename";
      elsif Key = "settings.link_policy" then
         return "Links";
      elsif Key = "settings.link.skip" then
         return "Skip links";
      elsif Key = "settings.link.safe_internal" then
         return "Safe internal links";
      elsif Key = "settings.show_unsafe_entries" then
         return "Show unsafe entries";
      elsif Key = "settings.toolbar_visible" then
         return "Show toolbar";
      elsif Key = "settings.status_bar_visible" then
         return "Show status bar";
      elsif Key = "settings.status.ready" then
         return "Settings ready";
      elsif Key = "entry.kind.file" then
         return "File";
      elsif Key = "entry.kind.directory" then
         return "Directory";
      elsif Key = "entry.kind.symlink" then
         return "Symbolic link";
      elsif Key = "entry.kind.hardlink" then
         return "Hard link";
      elsif Key = "entry.kind.character_device" then
         return "Character device";
      elsif Key = "entry.kind.block_device" then
         return "Block device";
      elsif Key = "entry.kind.fifo" then
         return "FIFO";
      elsif Key = "entry.kind.socket" then
         return "Socket";
      elsif Key = "entry.kind.metadata" then
         return "Metadata";
      elsif Key = "entry.kind.unknown" then
         return "Unknown";
      elsif Key = "menu.file" then
         return "File";
      elsif Key = "menu.edit" then
         return "Edit";
      elsif Key = "menu.view" then
         return "View";
      elsif Key = "menu.navigate" then
         return "Navigate";
      elsif Key = "menu.tools" then
         return "Tools";
      elsif Key = "menu.settings" then
         return "Settings";
      elsif Key = "menu.application" then
         return "Application";
      else
         return Key;
      end if;
   end Text;
end Archive.Localization;
