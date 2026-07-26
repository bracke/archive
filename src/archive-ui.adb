with Ada.Strings.Unbounded;

with Archive.Archives.Capabilities;
with Archive.Archives.Index;
with Archive.Localization;

package body Archive.UI is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Types.Entry_Id;
   use type Archive.Model.Dialog_Kind;
   use type Archive.Model.Focus_Region;
   use type Archive.Model.Notification_Severity;
   use type Archive.Model.Overlay_Kind;

   function Locale_Text (Config : Shell_Configuration; Key : String) return String is
   begin
      return Archive.Localization.Text (Key, To_String (Config.Locale));
   end Locale_Text;

   function Status_Key (State : Archive.Model.Lifecycle_State) return String is
   begin
      case State is
         when Archive.Model.Starting =>
            return "ui.status.starting";
         when Archive.Model.No_Archive =>
            return "ui.status.no_archive";
         when Archive.Model.Opening_Archive =>
            return "ui.status.opening";
         when Archive.Model.Archive_Ready =>
            return "ui.status.ready";
         when Archive.Model.Archive_Dirty =>
            return "ui.status.dirty";
         when Archive.Model.Saving_Archive =>
            return "ui.status.saving";
         when Archive.Model.Archive_Save_Failed =>
            return "ui.status.save_failed";
         when Archive.Model.Archive_Warnings =>
            return "ui.status.warnings";
         when Archive.Model.Archive_Failed =>
            return "ui.status.failed";
         when Archive.Model.Shutting_Down =>
            return "ui.status.shutting_down";
      end case;
   end Status_Key;

   function Build_Layout
     (Config          : Shell_Configuration;
      Preview_Visible : Boolean)
      return Shell_Layout
   is
      Toolbar_H    : constant Natural :=
        Guikit.Layout.Toolbar_Input_Height (Config.Line_Height)
        + 2 * Guikit.Layout.Bottom_Bar_Padding;
      Breadcrumb_H : constant Natural := Config.Line_Height + 8;
      Status_H     : constant Natural := Config.Line_Height + 8;
      Top_H        : constant Natural := Toolbar_H + Breadcrumb_H;
      Body_H       : constant Natural :=
        (if Config.Height > Top_H + Status_H then Config.Height - Top_H - Status_H else 0);
      Preview_W    : constant Natural :=
        (if Preview_Visible and then Config.Width >= 720 then Config.Width / 3 else 0);
      Content_W    : constant Natural :=
        (if Config.Width > Preview_W then Config.Width - Preview_W else 0);
   begin
      return
        (Toolbar      => Guikit.Layout.Calculate_Toolbar_Layout (Config.Width),
         Toolbar_H    => Toolbar_H,
         Breadcrumb_Y => Toolbar_H,
         Breadcrumb_H => Breadcrumb_H,
         Content_Y    => Top_H,
         Content_W    => Content_W,
         Content_H    => Body_H,
         Preview_X    => (if Preview_W = 0 then Config.Width else Config.Width - Preview_W),
         Preview_W    => Preview_W,
         Status_Y     => (if Config.Height > Status_H then Config.Height - Status_H else 0),
         Status_H     => Status_H);
   end Build_Layout;

   function View_Label_Key (Mode : Archive.Types.View_Mode) return String is
   begin
      case Mode is
         when Archive.Types.Grid_View =>
            return "ui.view.grid";
         when Archive.Types.Compact_View =>
            return "ui.view.compact";
         when Archive.Types.Details_View =>
            return "ui.view.details";
      end case;
   end View_Label_Key;

   function Build_Content_View
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration;
      Projection : Archive.View_Snapshots.Projection_Result)
      return Content_View_Snapshot
   is
      Mode     : constant Archive.Types.View_Mode := Archive.Model.View_Mode (Model);
      Settings : constant Archive.Settings.Settings_Model :=
        Archive.Model.Effective_Settings (Model);
      Layout   : constant Shell_Layout :=
        Build_Layout (Config, Archive.Model.Preview_Visible (Model));
      Row_H    : constant Positive :=
        (case Mode is
            when Archive.Types.Grid_View => 132,
            when Archive.Types.Compact_View => Config.Line_Height + 10,
            when Archive.Types.Details_View => Config.Line_Height + 8);
      Page_Rows : constant Positive := Positive'Max (1, Layout.Content_H / Row_H);
      Total    : constant Natural := Natural (Projection.Entries.Length);
      Last_Row : constant Natural := (if Total = 0 then 0 else Natural'Min (Total, Page_Rows));
   begin
      case Mode is
         when Archive.Types.Grid_View =>
            return
              (Mode             => Mode,
               Label            => To_Unbounded_String (Locale_Text (Config, View_Label_Key (Mode))),
               Accessible_Name  => To_Unbounded_String (Locale_Text (Config, "ui.accessible.grid")),
               Preferred_Cell_W => 160,
               Preferred_Row_H  => 132,
               Virtualized      => True,
               Keyboard_Navigation => True,
               Type_Ahead       => True,
               Selection_Model  => To_Unbounded_String ("entry-id"),
               Filter_Text      => To_Unbounded_String (Archive.Model.Filter_Text (Model)),
               Sort_Field       => Archive.Model.Sort_Field (Model),
               Sort_Direction   => Archive.Model.Sort_Direction (Model),
               Directories_First => Archive.Model.Directories_First (Model),
               Details_Columns   => Settings.Details_Columns,
               Visible_First_Row => (if Total = 0 then 0 else 1),
               Visible_Last_Row  => Last_Row,
               Total_Rows        => Total,
               Page_Row_Count    => Page_Rows);
         when Archive.Types.Compact_View =>
            return
              (Mode             => Mode,
               Label            => To_Unbounded_String (Locale_Text (Config, View_Label_Key (Mode))),
               Accessible_Name  => To_Unbounded_String (Locale_Text (Config, "ui.accessible.compact")),
               Preferred_Cell_W => 320,
               Preferred_Row_H  => Config.Line_Height + 10,
               Virtualized      => True,
               Keyboard_Navigation => True,
               Type_Ahead       => True,
               Selection_Model  => To_Unbounded_String ("entry-id"),
               Filter_Text      => To_Unbounded_String (Archive.Model.Filter_Text (Model)),
               Sort_Field       => Archive.Model.Sort_Field (Model),
               Sort_Direction   => Archive.Model.Sort_Direction (Model),
               Directories_First => Archive.Model.Directories_First (Model),
               Details_Columns   => Settings.Details_Columns,
               Visible_First_Row => (if Total = 0 then 0 else 1),
               Visible_Last_Row  => Last_Row,
               Total_Rows        => Total,
               Page_Row_Count    => Page_Rows);
         when Archive.Types.Details_View =>
            return
              (Mode             => Mode,
               Label            => To_Unbounded_String (Locale_Text (Config, View_Label_Key (Mode))),
               Accessible_Name  => To_Unbounded_String (Locale_Text (Config, "ui.accessible.details")),
               Preferred_Cell_W => 640,
               Preferred_Row_H  => Config.Line_Height + 8,
               Virtualized      => True,
               Keyboard_Navigation => True,
               Type_Ahead       => True,
               Selection_Model  => To_Unbounded_String ("entry-id"),
               Filter_Text      => To_Unbounded_String (Archive.Model.Filter_Text (Model)),
               Sort_Field       => Archive.Model.Sort_Field (Model),
               Sort_Direction   => Archive.Model.Sort_Direction (Model),
               Directories_First => Archive.Model.Directories_First (Model),
               Details_Columns   => Settings.Details_Columns,
               Visible_First_Row => (if Total = 0 then 0 else 1),
               Visible_Last_Row  => Last_Row,
               Total_Rows        => Total,
               Page_Row_Count    => Page_Rows);
      end case;
   end Build_Content_View;

   function Focus_Name_Key (Region : Archive.Model.Focus_Region) return String is
   begin
      case Region is
         when Archive.Model.Content_Focus =>
            return "ui.focus.content";
         when Archive.Model.Toolbar_Focus =>
            return "ui.focus.toolbar";
         when Archive.Model.Breadcrumb_Focus =>
            return "ui.focus.breadcrumb";
         when Archive.Model.Preview_Focus =>
            return "ui.focus.preview";
         when Archive.Model.Command_Palette_Focus =>
            return "ui.focus.command_palette";
         when Archive.Model.Settings_Focus =>
            return "ui.focus.settings";
      end case;
   end Focus_Name_Key;

   function Build_Focus
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Focus_Snapshot
   is
      Region : constant Archive.Model.Focus_Region := Archive.Model.Current_Focus (Model);
   begin
      return
        (Region          => Region,
         Accessible_Name => To_Unbounded_String (Locale_Text (Config, Focus_Name_Key (Region))),
         Restore_Region  => Archive.Model.Content_Focus);
   end Build_Focus;

   function Overlay_Name_Key (Overlay : Archive.Model.Overlay_Kind) return String is
   begin
      case Overlay is
         when Archive.Model.No_Overlay =>
            return "ui.overlay.none";
         when Archive.Model.Command_Palette_Overlay =>
            return "ui.overlay.command_palette";
         when Archive.Model.Settings_Overlay =>
            return "ui.overlay.settings";
      end case;
   end Overlay_Name_Key;

   function Build_Overlay
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Overlay_Snapshot
   is
      Overlay : constant Archive.Model.Overlay_Kind := Archive.Model.Active_Overlay (Model);
   begin
      return
        (Active          => Overlay,
         Visible         => Overlay /= Archive.Model.No_Overlay,
         Priority        => (if Overlay = Archive.Model.No_Overlay then 0 else 100),
         Accessible_Name => To_Unbounded_String (Locale_Text (Config, Overlay_Name_Key (Overlay))),
         Escape_Closes   => Overlay /= Archive.Model.No_Overlay);
   end Build_Overlay;

   function Dialog_Key (Dialog : Archive.Model.Dialog_Kind) return String is
   begin
      case Dialog is
         when Archive.Model.No_Dialog =>
            return "ui.dialog.none";
         when Archive.Model.Open_Archive_Dialog =>
            return "ui.dialog.open_archive";
         when Archive.Model.Add_Files_Dialog =>
            return "ui.dialog.add_files";
         when Archive.Model.Add_Directory_Dialog =>
            return "ui.dialog.add_directory";
         when Archive.Model.Replace_File_Dialog =>
            return "ui.dialog.replace_file";
         when Archive.Model.Rename_Entry_Dialog =>
            return "ui.dialog.rename_entry";
         when Archive.Model.Extract_Destination_Dialog =>
            return "ui.dialog.extract_destination";
         when Archive.Model.Save_As_Dialog =>
            return "ui.dialog.save_as";
         when Archive.Model.Write_Conflict_Dialog =>
            return "ui.dialog.write_conflicts";
         when Archive.Model.Confirm_Close_Dialog =>
            return "ui.dialog.confirm_close";
         when Archive.Model.Archive_Properties_Dialog =>
            return "ui.dialog.archive_properties";
         when Archive.Model.Entry_Properties_Dialog =>
            return "ui.dialog.entry_properties";
      end case;
   end Dialog_Key;

   function Build_Dialog
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Dialog_Snapshot
   is
      Dialog : constant Archive.Model.Dialog_Kind := Archive.Model.Active_Dialog (Model);
   begin
      return
        (Active          => Dialog,
         Visible         => Dialog /= Archive.Model.No_Dialog,
         Title           => To_Unbounded_String (Locale_Text (Config, Dialog_Key (Dialog))),
         Accessible_Name => To_Unbounded_String (Locale_Text (Config, Dialog_Key (Dialog))),
         Modal           => Dialog /= Archive.Model.No_Dialog);
   end Build_Dialog;

   function Build_Notification
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Notification_Snapshot
   is
      Severity : constant Archive.Model.Notification_Severity := Archive.Model.Notification (Model);
      Key      : constant String := Archive.Model.Notification_Key (Model);
   begin
      return
        (Severity => Severity,
         Visible  => Severity /= Archive.Model.No_Notification,
         Text     => To_Unbounded_String
           ((if Key = "" then "" else Locale_Text (Config, Key))));
   end Build_Notification;

   function Build_Status_Bar
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Status_Bar_Snapshot
   is
      State : constant Archive.Model.Lifecycle_State := Archive.Model.Lifecycle (Model);
   begin
      return
        (Text                => To_Unbounded_String (Locale_Text (Config, Status_Key (State))),
         Accessible_Name     => To_Unbounded_String
           (Locale_Text (Config, "ui.status_bar.accessible")),
         Lifecycle           => State,
         Selected_Count      => Archive.Model.Selected_Count (Model),
         Pending_Write_Count => Archive.Model.Pending_Write_Count (Model),
         Verification_Count  => Archive.Model.Verification_Entry_Count (Model),
         Has_Pending_Writes  => Archive.Model.Has_Pending_Writes (Model));
   end Build_Status_Bar;

   function Build_Breadcrumb
     (Model : Archive.Model.Application_Model)
      return Archive.View_Snapshots.Breadcrumbs.Breadcrumb_Snapshot
   is
   begin
      if Archive.Model.Has_Index (Model) then
         return Archive.View_Snapshots.Breadcrumbs.Build
           (Archive.Model.Published_Index (Model),
            Archive.Model.Current_Directory (Model));
      else
         return (Items => Archive.View_Snapshots.Breadcrumbs.Breadcrumb_Vectors.Empty_Vector,
                 Valid => False);
      end if;
   end Build_Breadcrumb;

   function Build_Content_Projection
     (Model : Archive.Model.Application_Model)
      return Archive.View_Snapshots.Projection_Result
   is
   begin
      if Archive.Model.Has_Index (Model) then
         return Archive.View_Snapshots.Project
           (Archive.Model.Published_Index (Model),
            (Parent            => Archive.Model.Current_Directory (Model),
             Filter_Text       => To_Unbounded_String (Archive.Model.Filter_Text (Model)),
             Field             => Archive.Model.Sort_Field (Model),
             Direction         => Archive.Model.Sort_Direction (Model),
             Directories_First => Archive.Model.Directories_First (Model),
             Limit             => 10_000));
      else
         return (Entries => Archive.Types.Entry_Id_Vectors.Empty_Vector,
                 Truncated => False);
      end if;
   end Build_Content_Projection;

   function Kind_Key (Kind : Archive.Archives.Entries.Entry_Kind) return String is
   begin
      case Kind is
         when Archive.Archives.Entries.Regular_File => return "entry.kind.file";
         when Archive.Archives.Entries.Directory => return "entry.kind.directory";
         when Archive.Archives.Entries.Symbolic_Link => return "entry.kind.symlink";
         when Archive.Archives.Entries.Hard_Link => return "entry.kind.hardlink";
         when Archive.Archives.Entries.Character_Device => return "entry.kind.character_device";
         when Archive.Archives.Entries.Block_Device => return "entry.kind.block_device";
         when Archive.Archives.Entries.FIFO => return "entry.kind.fifo";
         when Archive.Archives.Entries.Socket => return "entry.kind.socket";
         when Archive.Archives.Entries.Metadata_Record => return "entry.kind.metadata";
         when Archive.Archives.Entries.Unknown => return "entry.kind.unknown";
      end case;
   end Kind_Key;

   function Method_Text (Method : Archive.Archives.Entries.Compression_Method) return String is
   begin
      case Method is
         when Archive.Archives.Entries.No_Compression => return "store";
         when Archive.Archives.Entries.GZip_Deflate => return "gzip-deflate";
         when Archive.Archives.Entries.Zip_Stored => return "zip-store";
         when Archive.Archives.Entries.Zip_Deflate => return "zip-deflate";
         when Archive.Archives.Entries.BZip2_Compression => return "bzip2";
         when Archive.Archives.Entries.LZMA_Compression => return "lzma";
         when Archive.Archives.Entries.Zstd_Compression => return "zstandard";
         when Archive.Archives.Entries.PPMd_Compression => return "ppmd";
         when Archive.Archives.Entries.Unsupported_Compression => return "unsupported";
         when Archive.Archives.Entries.Unknown_Compression => return "unknown";
      end case;
   end Method_Text;

   function Size_Text (Size : Archive.Types.Optional_Size) return String is
   begin
      if Size.Present then
         return Archive.Types.Uncompressed_Size'Image (Size.Value);
      end if;
      return "";
   end Size_Text;

   function Row_Accessible_Description
     (Config : Shell_Configuration;
      Item   : Archive.Archives.Entries.Archive_Entry;
      Selected : Boolean)
      return String
   is
   begin
      return To_String (Item.Display_Name)
        & ", " & Locale_Text (Config, Kind_Key (Item.Kind))
        & (if Item.Uncompressed.Present then ", " & Size_Text (Item.Uncompressed) & " bytes" else "")
        & (if Selected then ", selected" else "");
   end Row_Accessible_Description;

   function Build_Content_Rows
     (Model      : Archive.Model.Application_Model;
      Config     : Shell_Configuration;
      Projection : Archive.View_Snapshots.Projection_Result)
      return Content_Row_Vectors.Vector
   is
      Result : Content_Row_Vectors.Vector;
   begin
      if not Archive.Model.Has_Index (Model) then
         return Result;
      end if;

      for Id of Projection.Entries loop
         if Archive.Archives.Index.Contains (Archive.Model.Published_Index (Model), Id) then
            declare
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Archive.Model.Published_Index (Model), Id);
               Caps : constant Archive.Archives.Capabilities.Entry_Capabilities :=
                 Archive.Archives.Capabilities.For_Entry (Item);
               Selected : constant Boolean := Archive.Model.Is_Selected (Model, Item.Id);
               Context_Count : constant Natural :=
                 (if Caps.Can_Preview then 1 else 0)
                 + (if Caps.Can_Extract then 1 else 0)
                 + (if Caps.Can_Verify then 1 else 0)
                 + (if Caps.Can_Rename then 1 else 0)
                 + (if Caps.Can_Remove then 1 else 0);
            begin
               Result.Append
                 (Content_Row_Snapshot'
                    (Entry_Id    => Item.Id,
                     Name        => Item.Display_Name,
                     Kind        => Item.Kind,
                     Kind_Text   => To_Unbounded_String (Locale_Text (Config, Kind_Key (Item.Kind))),
                     Size_Text   => To_Unbounded_String (Size_Text (Item.Uncompressed)),
                     Method_Text => To_Unbounded_String (Method_Text (Item.Method)),
                     Path_Text   => Item.Original_Path,
                     Selected    => Selected,
                     Focused     => Archive.Model.Focused_Entry (Model) = Item.Id,
                     Synthetic   => Item.Synthetic,
                     Accessible_Name => Item.Display_Name,
                     Accessible_Description => To_Unbounded_String
                       (Row_Accessible_Description (Config, Item, Selected)),
                     Primary_Action =>
                       (if Item.Kind = Archive.Archives.Entries.Directory
                        then Archive.Commands.Activate_Entry_Command
                        elsif Caps.Can_Preview
                        then Archive.Commands.Preview_Entry_Command
                        else Archive.Commands.No_Command),
                     Context_Command_Count => Context_Count));
            end;
         end if;
      end loop;
      return Result;
   end Build_Content_Rows;

   function Build_Command_Palette
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Archive.View_Snapshots.Command_Palette.Palette_Snapshot
   is
   begin
      return Archive.View_Snapshots.Command_Palette.Build
        (Model,
         (Locale      => Config.Locale,
          Filter_Text => To_Unbounded_String (Archive.Model.Command_Palette_Filter (Model)),
          Limit       => 200));
   end Build_Command_Palette;

   function Build_Archive_Properties
     (Model : Archive.Model.Application_Model)
      return Archive.View_Snapshots.Archive_Properties.Archive_Property_Snapshot
   is
   begin
      if Archive.Model.Has_Index (Model) then
         return Archive.View_Snapshots.Archive_Properties.Build
           (Archive.Model.Published_Format (Model),
            Archive.Model.Published_Index (Model));
      else
         return (others => <>);
      end if;
   end Build_Archive_Properties;

   function Build_Entry_Properties
     (Model : Archive.Model.Application_Model)
      return Archive.View_Snapshots.Entry_Properties.Entry_Property_Snapshot
   is
      Id : constant Archive.Types.Entry_Id := Archive.Model.Focused_Entry (Model);
   begin
      if Archive.Model.Has_Index (Model)
        and then Archive.Archives.Index.Contains (Archive.Model.Published_Index (Model), Id)
      then
         return Archive.View_Snapshots.Entry_Properties.Build
           (Archive.Archives.Index.Entry_For (Archive.Model.Published_Index (Model), Id));
      else
         return (others => <>);
      end if;
   end Build_Entry_Properties;

   function Build_Selection
     (Model : Archive.Model.Application_Model)
      return Selection_Snapshot
   is
   begin
      return
        (Items  => Archive.Model.Selected_Items (Model),
         Count  => Archive.Model.Selected_Count (Model),
         Anchor => Archive.Model.Selection_Anchor (Model));
   end Build_Selection;

   function Build_Preview_Panel
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Preview_Panel_Snapshot
   is
      Phase : constant Archive.Model.Preview_State := Archive.Model.Preview_Phase (Model);
      Result : constant Archive.Preview.Preview_Result := Archive.Model.Current_Preview (Model);

      function Preview_State_Key return String is
      begin
         case Phase is
            when Archive.Model.No_Preview => return "ui.preview.state.none";
            when Archive.Model.Preview_Loading => return "ui.preview.state.loading";
            when Archive.Model.Preview_Ready => return "ui.preview.state.ready";
            when Archive.Model.Preview_Failed => return "ui.preview.state.failed";
         end case;
      end Preview_State_Key;
   begin
      return
        (Visible         => Archive.Model.Preview_Visible (Model),
         Phase           => Phase,
         Entry_Id        => Archive.Model.Preview_Entry (Model),
         Generation      => Archive.Model.Current_Preview_Generation (Model),
         Result          => Result,
         Accessible_Name => To_Unbounded_String
           (Locale_Text (Config, "ui.preview.accessible")),
         State_Text      => To_Unbounded_String
           (Locale_Text (Config, Preview_State_Key)),
         Bytes_Text      => To_Unbounded_String
           (Natural'Image (Result.Bytes_Used)),
         Truncated_Text  => To_Unbounded_String
           ((if Result.Truncated then Locale_Text (Config, "ui.preview.truncated") else "")));
   end Build_Preview_Panel;

   function Build_Navigation
     (Model : Archive.Model.Application_Model)
      return Navigation_Snapshot
   is
      Directory : constant Archive.Types.Entry_Id := Archive.Model.Current_Directory (Model);
      Can_Parent : Boolean := False;
   begin
      if Archive.Model.Has_Index (Model)
        and then Archive.Archives.Index.Contains (Archive.Model.Published_Index (Model), Directory)
      then
         Can_Parent :=
           Archive.Archives.Index.Entry_For
             (Archive.Model.Published_Index (Model), Directory).Parent /= Archive.Types.No_Entry;
      end if;

      return
        (Current_Directory => Directory,
         Focused_Entry     => Archive.Model.Focused_Entry (Model),
         Can_Back          => Archive.Model.Can_Navigate_Back (Model),
         Can_Forward       => Archive.Model.Can_Navigate_Forward (Model),
         Can_Parent        => Can_Parent);
   end Build_Navigation;

   function Build_Copy
     (Model : Archive.Model.Application_Model)
      return Copy_Snapshot
   is
   begin
      return
        (Kind => Archive.Model.Last_Copy_Kind (Model),
         Text => To_Unbounded_String (Archive.Model.Last_Copy_Text (Model)));
   end Build_Copy;

   function Build_Settings
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Settings_Snapshot
   is
      Effective : constant Archive.Settings.Settings_Model :=
        Archive.Model.Effective_Settings (Model);
   begin
      return
        (Effective           => Effective,
         Recent_Archives     => Archive.Model.Recent_Archives (Model),
         Recent_Count        => Natural (Archive.Model.Recent_Archives (Model).Length),
         Title               => To_Unbounded_String (Locale_Text (Config, "settings.title")),
         General_Section_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.section.general")),
         Layout_Section_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.section.layout")),
         View_Label          => To_Unbounded_String (Locale_Text (Config, "settings.view")),
         Grid_Label          => To_Unbounded_String (Locale_Text (Config, "ui.view.grid")),
         Compact_Label       => To_Unbounded_String (Locale_Text (Config, "ui.view.compact")),
         Details_Label       => To_Unbounded_String (Locale_Text (Config, "ui.view.details")),
         Directories_First_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.directories_first")),
         Preview_Visible_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.preview_visible")),
         Preview_Limit_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.preview_limit")),
         Per_Entry_Extraction_Limit_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.per_entry_extraction_limit")),
         Total_Extraction_Limit_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.total_extraction_limit")),
         Conflict_Policy_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.conflict_policy")),
         Write_Conflict_Policy_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.write_conflict_policy")),
         Conflict_Ask_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.conflict.ask")),
         Conflict_Skip_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.conflict.skip")),
         Conflict_Overwrite_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.conflict.overwrite")),
         Conflict_Rename_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.conflict.rename")),
         Link_Policy_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.link_policy")),
         Link_Skip_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.link.skip")),
         Link_Safe_Internal_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.link.safe_internal")),
         Show_Unsafe_Entries_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.show_unsafe_entries")),
         Startup_Reopen_Recent_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.startup_reopen_recent")),
         Toolbar_Visible_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.toolbar_visible")),
         Status_Bar_Visible_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.status_bar_visible")),
         Window_Maximized_Label => To_Unbounded_String
           (Locale_Text (Config, "settings.window_maximized")),
         Status_Text         => To_Unbounded_String (Locale_Text (Config, "settings.status.ready")),
         Default_View        => Effective.Default_View,
         Directories_First   => Effective.Directories_First,
         Preview_Visible     => Effective.Preview_Visible,
         Preview_Byte_Limit  => Effective.Preview_Byte_Limit,
         Per_Entry_Extraction_Limit => Effective.Per_Entry_Extraction_Limit,
         Total_Extraction_Limit => Effective.Total_Extraction_Limit,
         Conflict_Policy     => Effective.Conflict_Policy,
         Write_Conflict_Policy => Effective.Write_Conflict_Policy,
         Link_Policy         => Effective.Link_Policy,
         Show_Unsafe_Entries => Effective.Show_Unsafe_Entries,
         Startup_Reopen_Recent => Effective.Startup_Reopen_Recent,
         Toolbar_Visible     => Effective.Toolbar_Visible,
         Status_Bar_Visible  => Effective.Status_Bar_Visible,
         Window_Maximized    => Effective.Window_Maximized);
   end Build_Settings;

   function Build_Verification
     (Model : Archive.Model.Application_Model)
      return Verification_Snapshot
   is
   begin
      return
        (Session_Generation   => Archive.Model.Session_Generation (Model),
         Operation_Generation => Archive.Model.Current_Verification_Generation (Model),
         Phase                => Archive.Model.Verification_Phase (Model),
         Entry_Count          => Archive.Model.Verification_Entry_Count (Model));
   end Build_Verification;

   function Build_Extraction
     (Model : Archive.Model.Application_Model)
      return Extraction_Snapshot
   is
      Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
        Archive.Model.Current_Extraction_Plan (Model);
   begin
      return
        (Phase           => Archive.Model.Extraction_Phase (Model),
         Plan_Status     => Plan.Status,
         Session         => Plan.Session,
         Entry_Count     => Natural (Plan.Entries.Length),
         Requested_Count => Plan.Requested_Count,
         Blocked_Count   => Plan.Blocked_Count,
         Conflict_Count  => Plan.Conflict_Count,
         Last_Plan_Status => Archive.Model.Last_Extraction_Plan_Status (Model),
         Last_Status      => Archive.Model.Last_Extraction_Status (Model),
         Completed_Count  => Archive.Model.Last_Extraction_Completed_Count (Model),
         Failed_Count     => Archive.Model.Last_Extraction_Failed_Count (Model),
         Last_Blocked_Count => Archive.Model.Last_Extraction_Blocked_Count (Model));
   end Build_Extraction;

   function Build_Write
     (Model : Archive.Model.Application_Model)
      return Write_Snapshot
   is
      Plan : constant Archive.Writes.Plans.Write_Plan :=
        Archive.Model.Current_Write_Plan (Model);
   begin
      return
        (Plan_Status     => Plan.Status,
         Session         => Plan.Session,
         Operation       => Archive.Model.Current_Write_Generation (Model),
         Change_Count    => Natural (Plan.Changes.Length),
         Requested_Count => Plan.Requested_Count,
         Blocked_Count   => Plan.Blocked_Count,
         Conflict_Count  => Plan.Conflict_Count,
         Duplicate_Target_Count => Plan.Duplicate_Target_Count,
         File_Directory_Conflict_Count => Plan.File_Directory_Conflict_Count,
         Auto_Resolved_Count => Plan.Auto_Resolved_Count,
         Has_Pending     => Archive.Model.Has_Pending_Writes (Model),
         Saveable        => Archive.Model.Has_Saveable_Write_Plan (Model),
         Last_Status     => Archive.Model.Last_Write_Status (Model));
   end Build_Write;

   function Build_Source
     (Model : Archive.Model.Application_Model)
      return Source_Snapshot
   is
      Fingerprint : constant Archive.Source_Monitoring.Source_Fingerprint :=
        Archive.Model.Source_Fingerprint (Model);
   begin
      return
        (Path        => To_Unbounded_String (Archive.Model.Source_Path (Model)),
         Fingerprint => Fingerprint,
         Status      => Fingerprint.Status,
         Change      => Archive.Model.Last_Source_Change (Model));
   end Build_Source;

   function Build_Lifecycle_Request
     (Model : Archive.Model.Application_Model)
      return Lifecycle_Snapshot
   is
   begin
      return (Request => Archive.Model.Last_Lifecycle_Request (Model));
   end Build_Lifecycle_Request;

   function Build_Shell
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Shell_Snapshot
   is
      State : constant Archive.Model.Lifecycle_State := Archive.Model.Lifecycle (Model);
      Projection : constant Archive.View_Snapshots.Projection_Result := Build_Content_Projection (Model);
   begin
      return
        (Title                 => To_Unbounded_String (Locale_Text (Config, "application.title")),
         Status_Text           => To_Unbounded_String (Locale_Text (Config, Status_Key (State))),
         Content_Label         => To_Unbounded_String (Locale_Text (Config, "ui.region.content")),
         Breadcrumb_Label      => To_Unbounded_String (Locale_Text (Config, "ui.region.breadcrumb")),
         Preview_Label         => To_Unbounded_String (Locale_Text (Config, "ui.region.preview")),
         Command_Palette_Label => To_Unbounded_String (Locale_Text (Config, "ui.region.command_palette")),
         Menus                 => Archive.View_Snapshots.Command_Surfaces.Build_Menus
           (Model, Config.Locale),
         Toolbar               => Archive.View_Snapshots.Command_Surfaces.Build_Toolbar
           (Model, Config.Locale),
         Breadcrumb            => Build_Breadcrumb (Model),
         Content_Projection    => Projection,
         Content_Rows          => Build_Content_Rows (Model, Config, Projection),
         Command_Palette       => Build_Command_Palette (Model, Config),
         Archive_Properties    => Build_Archive_Properties (Model),
         Entry_Properties      => Build_Entry_Properties (Model),
         Selection             => Build_Selection (Model),
         Preview_Panel         => Build_Preview_Panel (Model, Config),
         Navigation            => Build_Navigation (Model),
         Copy_Result           => Build_Copy (Model),
         Settings              => Build_Settings (Model, Config),
         Verification          => Build_Verification (Model),
         Extraction            => Build_Extraction (Model),
         Write                 => Build_Write (Model),
         Source                => Build_Source (Model),
         Lifecycle_Request     => Build_Lifecycle_Request (Model),
         Layout                => Build_Layout (Config, Archive.Model.Preview_Visible (Model)),
         Content_View          => Build_Content_View (Model, Config, Projection),
         Focus                 => Build_Focus (Model, Config),
         Overlay               => Build_Overlay (Model, Config),
         Dialog                => Build_Dialog (Model, Config),
         Notification          => Build_Notification (Model, Config),
         Status_Bar            => Build_Status_Bar (Model, Config),
         Lifecycle             => State,
         View_Mode             => Archive.Model.View_Mode (Model),
         Preview_Visible       => Archive.Model.Preview_Visible (Model),
         Focus_Command_Id      => To_Unbounded_String
           (Archive.Commands.Identifier (Archive.Commands.Open_Archive_Command)));
   end Build_Shell;

   function View_Mode_Name (Mode : Archive.Types.View_Mode) return String is
   begin
      case Mode is
         when Archive.Types.Grid_View =>
            return "grid";
         when Archive.Types.Compact_View =>
            return "compact";
         when Archive.Types.Details_View =>
            return "details";
      end case;
   end View_Mode_Name;

   function Dispatch_Command
     (Model   : in out Archive.Model.Application_Model;
      Command : Archive.Commands.Command_Id;
      Source  : Dispatch_Source)
      return Dispatch_Result
   is
      pragma Unreferenced (Source);
   begin
      if Command not in Archive.Commands.Registered_Command_Id then
         return (Matched => False, Accepted => False, Command => Command);
      end if;

      Archive.Commands.Execute (Command, Model);
      return
        (Matched  => True,
         Accepted => Archive.Model.Last_Command_Accepted (Model),
         Command  => Command);
   end Dispatch_Command;

   function Dispatch_Shortcut
     (Model     : in out Archive.Model.Application_Model;
      Key       : Guikit.Input.Key_Code;
      Modifiers : Guikit.Input.Modifier_Set)
      return Dispatch_Result
   is
      use type Guikit.Input.Key_Code;
      use type Guikit.Input.Modifier_Set;

      function Next_Focus
        (Current         : Archive.Model.Focus_Region;
         Preview_Visible : Boolean;
         Backward        : Boolean)
         return Archive.Model.Focus_Region
      is
      begin
         if Backward then
            case Current is
               when Archive.Model.Content_Focus =>
                  return (if Preview_Visible then Archive.Model.Preview_Focus else Archive.Model.Breadcrumb_Focus);
               when Archive.Model.Toolbar_Focus =>
                  return Archive.Model.Content_Focus;
               when Archive.Model.Breadcrumb_Focus =>
                  return Archive.Model.Toolbar_Focus;
               when Archive.Model.Preview_Focus =>
                  return Archive.Model.Breadcrumb_Focus;
               when Archive.Model.Command_Palette_Focus | Archive.Model.Settings_Focus =>
                  return Archive.Model.Content_Focus;
            end case;
         else
            case Current is
               when Archive.Model.Content_Focus =>
                  return Archive.Model.Toolbar_Focus;
               when Archive.Model.Toolbar_Focus =>
                  return Archive.Model.Breadcrumb_Focus;
               when Archive.Model.Breadcrumb_Focus =>
                  return (if Preview_Visible then Archive.Model.Preview_Focus else Archive.Model.Content_Focus);
               when Archive.Model.Preview_Focus =>
                  return Archive.Model.Content_Focus;
               when Archive.Model.Command_Palette_Focus | Archive.Model.Settings_Focus =>
                  return Archive.Model.Content_Focus;
            end case;
         end if;
      end Next_Focus;

      function Is_Content_Navigation_Key (Candidate : Guikit.Input.Key_Code) return Boolean is
      begin
         case Candidate is
            when Guikit.Input.Key_Left
               | Guikit.Input.Key_Right
               | Guikit.Input.Key_Up
               | Guikit.Input.Key_Down
               | Guikit.Input.Key_Home
               | Guikit.Input.Key_End
               | Guikit.Input.Key_Page_Up
               | Guikit.Input.Key_Page_Down
               | Guikit.Input.Key_Return
               | Guikit.Input.Key_Space =>
               return True;
            when others =>
               return False;
         end case;
      end Is_Content_Navigation_Key;

      function Projection_For_Content return Archive.View_Snapshots.Projection_Result is
      begin
         return Build_Content_Projection (Model);
      end Projection_For_Content;

      function Position_Of
        (Projection : Archive.View_Snapshots.Projection_Result;
         Id         : Archive.Types.Entry_Id)
         return Natural
      is
         Pos : Natural := 0;
      begin
         if Projection.Entries.Is_Empty then
            return 0;
         end if;
         for Index in Projection.Entries.First_Index .. Projection.Entries.Last_Index loop
            Pos := Pos + 1;
            if Projection.Entries.Element (Index) = Id then
               return Pos;
            end if;
         end loop;
         return 0;
      end Position_Of;

      procedure Focus_Row
        (Projection : Archive.View_Snapshots.Projection_Result;
         Position   : Natural;
         Select_Row : Boolean := False)
      is
         Id : Archive.Types.Entry_Id;
      begin
         if Position = 0 or else Position > Natural (Projection.Entries.Length) then
            return;
         end if;
         Id := Projection.Entries.Element (Positive (Position));
         if Select_Row then
            Archive.Model.Select_Only (Model, Id);
         else
            Archive.Model.Set_Focused_Entry (Model, Id);
         end if;
      end Focus_Row;

      procedure Move_Content_Focus
        (Projection : Archive.View_Snapshots.Projection_Result;
         Offset     : Integer;
         Page       : Boolean := False)
      is
         Count : constant Natural := Natural (Projection.Entries.Length);
         Current : Natural := Position_Of (Projection, Archive.Model.Focused_Entry (Model));
         Step : constant Natural := (if Page then 10 else 1);
         Target : Integer;
      begin
         if Count = 0 then
            return;
         elsif Current = 0 then
            Current := 1;
         end if;

         Target := Integer (Current) + Offset * Integer (Step);
         if Target < 1 then
            Target := 1;
         elsif Target > Integer (Count) then
            Target := Integer (Count);
         end if;
         Focus_Row (Projection, Natural (Target));
      end Move_Content_Focus;
   begin
      if Key = Guikit.Input.Key_Escape
        and then Archive.Model.Active_Dialog (Model) /= Archive.Model.No_Dialog
      then
         Archive.Model.Close_Dialog (Model);
         return (Matched => True, Accepted => True, Command => Archive.Commands.No_Command);
      elsif Key = Guikit.Input.Key_Escape
        and then Archive.Model.Active_Overlay (Model) /= Archive.Model.No_Overlay
      then
         Archive.Model.Close_Overlay (Model);
         return (Matched => True, Accepted => True, Command => Archive.Commands.No_Command);
      elsif Archive.Model.Active_Dialog (Model) /= Archive.Model.No_Dialog
        or else Archive.Model.Active_Overlay (Model) /= Archive.Model.No_Overlay
      then
         return (Matched => False, Accepted => False, Command => Archive.Commands.No_Command);
      elsif Key = Guikit.Input.Key_Tab then
         Archive.Model.Set_Focus
           (Model,
            Next_Focus
              (Archive.Model.Current_Focus (Model),
               Archive.Model.Preview_Visible (Model),
               Modifiers (Guikit.Input.Shift_Key)));
         return (Matched => True, Accepted => True, Command => Archive.Commands.No_Command);
      elsif Archive.Model.Current_Focus (Model) = Archive.Model.Content_Focus
        and then Is_Content_Navigation_Key (Key)
      then
         declare
            Projection : constant Archive.View_Snapshots.Projection_Result :=
              Projection_For_Content;
         begin
            case Key is
               when Guikit.Input.Key_Up | Guikit.Input.Key_Left =>
                  Move_Content_Focus (Projection, -1);
               when Guikit.Input.Key_Down | Guikit.Input.Key_Right =>
                  Move_Content_Focus (Projection, 1);
               when Guikit.Input.Key_Home =>
                  Focus_Row (Projection, 1);
               when Guikit.Input.Key_End =>
                  Focus_Row (Projection, Natural (Projection.Entries.Length));
               when Guikit.Input.Key_Page_Up =>
                  Move_Content_Focus (Projection, -1, Page => True);
               when Guikit.Input.Key_Page_Down =>
                  Move_Content_Focus (Projection, 1, Page => True);
               when Guikit.Input.Key_Space =>
                  declare
                     Pos : constant Natural :=
                       Position_Of (Projection, Archive.Model.Focused_Entry (Model));
                  begin
                     Focus_Row (Projection, Pos, Select_Row => True);
                  end;
               when Guikit.Input.Key_Return =>
                  Archive.Model.Activate_Focused_Entry (Model);
               when others =>
                  null;
            end case;
         end;
         return (Matched => True, Accepted => True, Command => Archive.Commands.No_Command);
      end if;

      for Id in Archive.Commands.Registered_Command_Id loop
         declare
            Shortcut : constant Archive.Commands.Shortcut := Archive.Commands.Shortcut_For (Id);
         begin
            if Shortcut.Present
              and then Shortcut.Key = Key
              and then Shortcut.Modifiers = Modifiers
            then
               return Dispatch_Command (Model, Id, Shortcut_Source);
            end if;
         end;
      end loop;

      return (Matched => False, Accepted => False, Command => Archive.Commands.No_Command);
   end Dispatch_Shortcut;

   function Desktop_Report
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return String
   is
      Shell : constant Shell_Snapshot := Build_Shell (Model, Config);
   begin
      return "archive desktop shell: title="
        & To_String (Shell.Title)
        & " menus=" & Natural'Image (Natural (Shell.Menus.Sections.Length))
        & " toolbar=" & Natural'Image (Natural (Shell.Toolbar.Commands.Length))
        & " view=" & View_Mode_Name (Shell.View_Mode)
        & " preview=" & Boolean'Image (Shell.Preview_Visible)
        & " recent=" & Natural'Image (Shell.Settings.Recent_Count)
        & " status=" & To_String (Shell.Status_Text);
   end Desktop_Report;
end Archive.UI;
