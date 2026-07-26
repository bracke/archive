with Ada.Containers.Vectors;

with Guikit.Layout;
with Guikit.Input;

with Archive.Archives.Entries;
with Archive.Commands;
with Archive.Model;
with Archive.Extraction.Plans;
with Archive.Extraction.Results;
with Archive.Preview;
with Archive.Resource_Limits;
with Archive.Settings;
with Archive.Source_Monitoring;
with Archive.Types;
with Archive.View_Snapshots;
with Archive.View_Snapshots.Archive_Properties;
with Archive.View_Snapshots.Breadcrumbs;
with Archive.View_Snapshots.Columns;
with Archive.View_Snapshots.Command_Palette;
with Archive.View_Snapshots.Command_Surfaces;
with Archive.View_Snapshots.Entry_Properties;
with Archive.Verification.Overlays;
with Archive.Writes.Plans;
with Archive.Writes.Results;

package Archive.UI is
   type Shell_Configuration is record
      Width       : Natural := 1280;
      Height      : Natural := 800;
      Locale      : Archive.Types.UString;
      Line_Height : Positive := 20;
   end record;

   type Shell_Layout is record
      Toolbar      : Guikit.Layout.Toolbar_Layout;
      Toolbar_H    : Natural := 0;
      Breadcrumb_Y : Natural := 0;
      Breadcrumb_H : Natural := 0;
      Content_Y    : Natural := 0;
      Content_W    : Natural := 0;
      Content_H    : Natural := 0;
      Preview_X    : Natural := 0;
      Preview_W    : Natural := 0;
      Status_Y     : Natural := 0;
      Status_H     : Natural := 0;
   end record;

   type Content_View_Snapshot is record
      Mode              : Archive.Types.View_Mode := Archive.Types.Grid_View;
      Label             : Archive.Types.UString;
      Accessible_Name   : Archive.Types.UString;
      Preferred_Cell_W  : Natural := 0;
      Preferred_Row_H   : Natural := 0;
      Virtualized       : Boolean := True;
      Keyboard_Navigation : Boolean := True;
      Type_Ahead          : Boolean := True;
      Selection_Model   : Archive.Types.UString;
      Filter_Text       : Archive.Types.UString;
      Sort_Field        : Archive.View_Snapshots.Sort_Field := Archive.View_Snapshots.Sort_By_Name;
      Sort_Direction    : Archive.View_Snapshots.Sort_Direction := Archive.View_Snapshots.Ascending;
      Directories_First : Boolean := True;
      Details_Columns   : Archive.View_Snapshots.Columns.Column_Vectors.Vector;
      Visible_First_Row : Natural := 0;
      Visible_Last_Row  : Natural := 0;
      Total_Rows        : Natural := 0;
      Page_Row_Count    : Positive := 1;
   end record;

   type Content_Row_Snapshot is record
      Entry_Id       : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Name           : Archive.Types.UString;
      Kind           : Archive.Archives.Entries.Entry_Kind := Archive.Archives.Entries.Unknown;
      Kind_Text      : Archive.Types.UString;
      Size_Text      : Archive.Types.UString;
      Method_Text    : Archive.Types.UString;
      Path_Text      : Archive.Types.UString;
      Selected       : Boolean := False;
      Focused        : Boolean := False;
      Synthetic      : Boolean := False;
      Accessible_Name : Archive.Types.UString;
      Accessible_Description : Archive.Types.UString;
      Primary_Action : Archive.Commands.Command_Id := Archive.Commands.No_Command;
      Context_Command_Count : Natural := 0;
   end record;

   package Content_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Content_Row_Snapshot);

   type Focus_Snapshot is record
      Region          : Archive.Model.Focus_Region := Archive.Model.Content_Focus;
      Accessible_Name : Archive.Types.UString;
      Restore_Region  : Archive.Model.Focus_Region := Archive.Model.Content_Focus;
   end record;

   type Overlay_Snapshot is record
      Active          : Archive.Model.Overlay_Kind := Archive.Model.No_Overlay;
      Visible         : Boolean := False;
      Priority        : Natural := 0;
      Accessible_Name : Archive.Types.UString;
      Escape_Closes   : Boolean := False;
   end record;

   type Dialog_Snapshot is record
      Active          : Archive.Model.Dialog_Kind := Archive.Model.No_Dialog;
      Visible         : Boolean := False;
      Title           : Archive.Types.UString;
      Accessible_Name : Archive.Types.UString;
      Modal           : Boolean := False;
   end record;

   type Notification_Snapshot is record
      Severity : Archive.Model.Notification_Severity := Archive.Model.No_Notification;
      Visible  : Boolean := False;
      Text     : Archive.Types.UString;
   end record;

   type Status_Bar_Snapshot is record
      Text                 : Archive.Types.UString;
      Accessible_Name      : Archive.Types.UString;
      Lifecycle            : Archive.Model.Lifecycle_State := Archive.Model.No_Archive;
      Selected_Count       : Natural := 0;
      Pending_Write_Count  : Natural := 0;
      Verification_Count   : Natural := 0;
      Has_Pending_Writes   : Boolean := False;
   end record;

   type Selection_Snapshot is record
      Items  : Archive.Types.Entry_Id_Vectors.Vector;
      Count  : Natural := 0;
      Anchor : Archive.Types.Entry_Id := Archive.Types.No_Entry;
   end record;

   type Preview_Panel_Snapshot is record
      Visible          : Boolean := True;
      Phase            : Archive.Model.Preview_State := Archive.Model.No_Preview;
      Entry_Id         : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Generation       : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Result           : Archive.Preview.Preview_Result;
      Accessible_Name  : Archive.Types.UString;
      State_Text       : Archive.Types.UString;
      Bytes_Text       : Archive.Types.UString;
      Truncated_Text   : Archive.Types.UString;
   end record;

   type Navigation_Snapshot is record
      Current_Directory : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Focused_Entry     : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Can_Back          : Boolean := False;
      Can_Forward       : Boolean := False;
      Can_Parent        : Boolean := False;
   end record;

   type Copy_Snapshot is record
      Kind : Archive.Model.Copy_Result_Kind := Archive.Model.No_Copy_Result;
      Text : Archive.Types.UString;
   end record;

   type Settings_Snapshot is record
      Effective              : Archive.Settings.Settings_Model;
      Recent_Archives        : Archive.Types.String_Vectors.Vector;
      Recent_Count           : Natural := 0;
      Title                  : Archive.Types.UString;
      General_Section_Label  : Archive.Types.UString;
      Layout_Section_Label   : Archive.Types.UString;
      View_Label             : Archive.Types.UString;
      Grid_Label             : Archive.Types.UString;
      Compact_Label          : Archive.Types.UString;
      Details_Label          : Archive.Types.UString;
      Directories_First_Label : Archive.Types.UString;
      Preview_Visible_Label  : Archive.Types.UString;
      Preview_Limit_Label    : Archive.Types.UString;
      Per_Entry_Extraction_Limit_Label : Archive.Types.UString;
      Total_Extraction_Limit_Label : Archive.Types.UString;
      Conflict_Policy_Label  : Archive.Types.UString;
      Write_Conflict_Policy_Label : Archive.Types.UString;
      Conflict_Ask_Label     : Archive.Types.UString;
      Conflict_Skip_Label    : Archive.Types.UString;
      Conflict_Overwrite_Label : Archive.Types.UString;
      Conflict_Rename_Label  : Archive.Types.UString;
      Link_Policy_Label      : Archive.Types.UString;
      Link_Skip_Label        : Archive.Types.UString;
      Link_Safe_Internal_Label : Archive.Types.UString;
      Show_Unsafe_Entries_Label : Archive.Types.UString;
      Startup_Reopen_Recent_Label : Archive.Types.UString;
      Toolbar_Visible_Label  : Archive.Types.UString;
      Status_Bar_Visible_Label : Archive.Types.UString;
      Window_Maximized_Label  : Archive.Types.UString;
      Status_Text            : Archive.Types.UString;
      Default_View           : Archive.Types.View_Mode := Archive.Types.Grid_View;
      Directories_First      : Boolean := True;
      Preview_Visible        : Boolean := True;
      Preview_Byte_Limit     : Natural := 0;
      Per_Entry_Extraction_Limit : Archive.Resource_Limits.Limit_Value := 0;
      Total_Extraction_Limit : Archive.Resource_Limits.Limit_Value := 0;
      Conflict_Policy        : Archive.Settings.Extraction_Conflict_Policy := Archive.Settings.Ask;
      Write_Conflict_Policy  : Archive.Settings.Extraction_Conflict_Policy := Archive.Settings.Ask;
      Link_Policy            : Archive.Settings.Link_Extraction_Policy := Archive.Settings.Skip_Links;
      Show_Unsafe_Entries    : Boolean := True;
      Startup_Reopen_Recent  : Boolean := False;
      Toolbar_Visible        : Boolean := True;
      Status_Bar_Visible     : Boolean := True;
      Window_Maximized       : Boolean := False;
   end record;

   type Verification_Snapshot is record
      Session_Generation      : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Operation_Generation    : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Phase                   : Archive.Verification.Overlays.Verification_Phase :=
        Archive.Verification.Overlays.Verification_Not_Run;
      Entry_Count             : Natural := 0;
   end record;

   type Extraction_Snapshot is record
      Phase           : Archive.Model.Extraction_State := Archive.Model.No_Extraction;
      Plan_Status     : Archive.Extraction.Plans.Plan_Status :=
        Archive.Extraction.Plans.Plan_Ready;
      Session         : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Entry_Count     : Natural := 0;
      Requested_Count : Natural := 0;
      Blocked_Count   : Natural := 0;
      Conflict_Count  : Natural := 0;
      Last_Plan_Status : Archive.Extraction.Results.Plan_Execution_Status :=
        Archive.Extraction.Results.Execution_Completed;
      Last_Status      : Archive.Extraction.Results.Extraction_Status :=
        Archive.Extraction.Results.Completed;
      Completed_Count  : Natural := 0;
      Failed_Count     : Natural := 0;
      Last_Blocked_Count : Natural := 0;
   end record;

   type Write_Snapshot is record
      Plan_Status     : Archive.Writes.Plans.Plan_Status :=
        Archive.Writes.Plans.Write_Plan_Ready;
      Session         : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Operation       : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Change_Count    : Natural := 0;
      Requested_Count : Natural := 0;
      Blocked_Count   : Natural := 0;
      Conflict_Count  : Natural := 0;
      Duplicate_Target_Count : Natural := 0;
      File_Directory_Conflict_Count : Natural := 0;
      Auto_Resolved_Count : Natural := 0;
      Has_Pending     : Boolean := False;
      Saveable        : Boolean := False;
      Last_Status     : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed;
   end record;

   type Source_Snapshot is record
      Path        : Archive.Types.UString;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint;
      Status      : Archive.Source_Monitoring.Source_Status :=
        Archive.Source_Monitoring.Source_Missing;
      Change      : Archive.Model.Source_Change_State :=
        Archive.Model.No_Source_Change;
   end record;

   type Lifecycle_Snapshot is record
      Request : Archive.Model.Lifecycle_Request := Archive.Model.No_Lifecycle_Request;
   end record;

   type Shell_Snapshot is record
      Title                : Archive.Types.UString;
      Status_Text          : Archive.Types.UString;
      Content_Label        : Archive.Types.UString;
      Breadcrumb_Label     : Archive.Types.UString;
      Preview_Label        : Archive.Types.UString;
      Command_Palette_Label : Archive.Types.UString;
      Menus                : Archive.View_Snapshots.Command_Surfaces.Menu_Snapshot;
      Toolbar              : Archive.View_Snapshots.Command_Surfaces.Toolbar_Snapshot;
      Breadcrumb           : Archive.View_Snapshots.Breadcrumbs.Breadcrumb_Snapshot;
      Content_Projection   : Archive.View_Snapshots.Projection_Result;
      Content_Rows         : Content_Row_Vectors.Vector;
      Command_Palette      : Archive.View_Snapshots.Command_Palette.Palette_Snapshot;
      Archive_Properties   : Archive.View_Snapshots.Archive_Properties.Archive_Property_Snapshot;
      Entry_Properties     : Archive.View_Snapshots.Entry_Properties.Entry_Property_Snapshot;
      Selection            : Selection_Snapshot;
      Preview_Panel        : Preview_Panel_Snapshot;
      Navigation           : Navigation_Snapshot;
      Copy_Result          : Copy_Snapshot;
      Settings             : Settings_Snapshot;
      Verification         : Verification_Snapshot;
      Extraction           : Extraction_Snapshot;
      Write                : Write_Snapshot;
      Source               : Source_Snapshot;
      Lifecycle_Request    : Lifecycle_Snapshot;
      Layout               : Shell_Layout;
      Content_View         : Content_View_Snapshot;
      Focus                : Focus_Snapshot;
      Overlay              : Overlay_Snapshot;
      Dialog               : Dialog_Snapshot;
      Notification         : Notification_Snapshot;
      Status_Bar           : Status_Bar_Snapshot;
      Lifecycle            : Archive.Model.Lifecycle_State := Archive.Model.No_Archive;
      View_Mode            : Archive.Types.View_Mode := Archive.Types.Grid_View;
      Preview_Visible      : Boolean := True;
      Focus_Command_Id     : Archive.Types.UString;
   end record;

   type Dispatch_Source is
     (Menu_Source,
      Toolbar_Source,
      Shortcut_Source,
      Command_Palette_Source,
      Context_Menu_Source,
      Accessibility_Source);

   type Dispatch_Result is record
      Matched  : Boolean := False;
      Accepted : Boolean := False;
      Command  : Archive.Commands.Command_Id := Archive.Commands.No_Command;
   end record;

   function Build_Shell
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return Shell_Snapshot;

   function Dispatch_Command
     (Model   : in out Archive.Model.Application_Model;
      Command : Archive.Commands.Command_Id;
      Source  : Dispatch_Source)
      return Dispatch_Result;

   function Dispatch_Shortcut
     (Model     : in out Archive.Model.Application_Model;
      Key       : Guikit.Input.Key_Code;
      Modifiers : Guikit.Input.Modifier_Set)
      return Dispatch_Result;

   function Desktop_Report
     (Model  : Archive.Model.Application_Model;
      Config : Shell_Configuration)
      return String;
end Archive.UI;
