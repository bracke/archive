with Archive.Types;
with Archive.Archives.Capabilities;
with Archive.Archives.Formats;
with Archive.Archives.Index;
with Archive.Archives.Entries;
with Archive.Extraction.Plans;
with Archive.Extraction.Results;
with Archive.Navigation;
with Archive.Preview;
with Archive.Selection;
with Archive.Settings;
with Archive.Source_Monitoring;
with Archive.View_Snapshots;
with Archive.Verification.Overlays;
with Archive.Writes.Plans;
with Archive.Writes.Results;

package Archive.Model is
   subtype UString is Archive.Types.UString;

   type Lifecycle_State is
     (Starting,
      No_Archive,
      Opening_Archive,
      Archive_Ready,
      Archive_Dirty,
      Saving_Archive,
      Archive_Save_Failed,
      Archive_Warnings,
      Archive_Failed,
      Shutting_Down);

   type Overlay_Kind is
     (No_Overlay,
      Command_Palette_Overlay,
      Settings_Overlay);

   type Focus_Region is
     (Content_Focus,
      Toolbar_Focus,
      Breadcrumb_Focus,
      Preview_Focus,
      Command_Palette_Focus,
      Settings_Focus);

   type Dialog_Kind is
     (No_Dialog,
      Open_Archive_Dialog,
      Add_Files_Dialog,
      Add_Directory_Dialog,
      Replace_File_Dialog,
      Rename_Entry_Dialog,
      Extract_Destination_Dialog,
      Save_As_Dialog,
      Write_Conflict_Dialog,
      Confirm_Close_Dialog,
      Archive_Properties_Dialog,
      Entry_Properties_Dialog);

   type Notification_Severity is
     (No_Notification,
      Info_Notification,
      Warning_Notification,
      Error_Notification);

   type Preview_State is
     (No_Preview,
      Preview_Loading,
      Preview_Ready,
      Preview_Failed);

   type Copy_Result_Kind is
     (No_Copy_Result,
      Entry_Path_Copy,
      Entry_Information_Copy);

   type Extraction_State is
     (No_Extraction,
      Extraction_Planned);

   type Lifecycle_Request is
     (No_Lifecycle_Request,
      Open_Recent_Request,
      Quit_Request);

   type Source_Change_State is
     (No_Source_Change,
      Source_Unchanged,
      Source_Modified,
      Source_Unavailable);

   type Application_Model is private;

   procedure Initialize (Model : out Application_Model);
   function Lifecycle (Model : Application_Model) return Lifecycle_State;
   function Has_Open_Archive (Model : Application_Model) return Boolean;
   --  The model's monotonic change revision, bumped by every mutator via Touch.
   --  The render layer compares it against the revision it last built a frame at
   --  to decide whether the cached frame is still current.
   function Revision (Model : Application_Model) return Archive.Types.Generation_Id;
   procedure Publish_Archive (Model : in out Application_Model; Source_Path : String);
   procedure Create_New_Archive (Model : in out Application_Model);
   function Begin_Open (Model : in out Application_Model) return Archive.Types.Generation_Id;
   function Current_Open_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id;
   function Publish_Open_Result
      (Model       : in out Application_Model;
      Operation   : Archive.Types.Generation_Id;
      Source_Path : String;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id;
      Success     : Boolean;
      Backing_Path : String := "")
      return Boolean;
   procedure Reload_Archive (Model : in out Application_Model);
   procedure Request_Close_Archive (Model : in out Application_Model);
   procedure Request_Open_Recent (Model : in out Application_Model);
   procedure Request_Quit (Model : in out Application_Model);
   function Last_Lifecycle_Request (Model : Application_Model) return Lifecycle_Request;
   procedure Publish_Archive_Index
     (Model       : in out Application_Model;
      Source_Path : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format);
   procedure Publish_Archive_Index
     (Model       : in out Application_Model;
      Source_Path : String;
      Backing_Path : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format);
   procedure Close_Archive (Model : in out Application_Model);
   function Source_Path (Model : Application_Model) return String;
   function Backing_Path (Model : Application_Model) return String;
   function Payload_Source_Path (Model : Application_Model) return String;
   function Source_Fingerprint
     (Model : Application_Model)
      return Archive.Source_Monitoring.Source_Fingerprint;
   procedure Set_Source_Fingerprint
     (Model       : in out Application_Model;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint);
   function Source_Changed
     (Model       : Application_Model;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint)
      return Boolean;
   function Observe_Source_Fingerprint
     (Model       : in out Application_Model;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint)
      return Source_Change_State;
   function Last_Source_Change (Model : Application_Model) return Source_Change_State;

   function Has_Index (Model : Application_Model) return Boolean;
   function Published_Format
     (Model : Application_Model)
      return Archive.Archives.Formats.Format_Id;
   function Published_Index
     (Model : Application_Model)
      return Archive.Archives.Index.Archive_Index;
   function Current_Directory (Model : Application_Model) return Archive.Types.Entry_Id;
   function Can_Navigate_Back (Model : Application_Model) return Boolean;
   function Can_Navigate_Forward (Model : Application_Model) return Boolean;
   procedure Set_Current_Directory
     (Model     : in out Application_Model;
      Directory : Archive.Types.Entry_Id);
   procedure Navigate_Back (Model : in out Application_Model);
   procedure Navigate_Forward (Model : in out Application_Model);
   procedure Navigate_Root (Model : in out Application_Model);
   procedure Navigate_Parent (Model : in out Application_Model);
   function Focused_Entry (Model : Application_Model) return Archive.Types.Entry_Id;
   procedure Set_Focused_Entry
     (Model    : in out Application_Model;
      Entry_Id : Archive.Types.Entry_Id);

   function Current_Verification_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id;
   procedure Start_Verification (Model : in out Application_Model);
   function Publish_Verification
     (Model     : in out Application_Model;
      Overlay   : Archive.Verification.Overlays.Verification_Overlay;
      Cancelled : Boolean := False)
      return Archive.Verification.Overlays.Overlay_Acceptance;
   function Verification_Entry_Count (Model : Application_Model) return Natural;
   function Verification_Phase
     (Model : Application_Model)
      return Archive.Verification.Overlays.Verification_Phase;
   function Verification_Integrity
     (Model : Application_Model;
      Entry_Id : Archive.Types.Entry_Id)
      return Archive.Archives.Entries.Integrity_State;

   function View_Mode (Model : Application_Model) return Archive.Types.View_Mode;
   procedure Set_View_Mode (Model : in out Application_Model; Mode : Archive.Types.View_Mode);
   function Effective_Settings (Model : Application_Model) return Archive.Settings.Settings_Model;
   function Has_Recent_Archives (Model : Application_Model) return Boolean;
   function Recent_Archives
     (Model : Application_Model)
      return Archive.Types.String_Vectors.Vector;
   procedure Apply_Settings
     (Model    : in out Application_Model;
      Settings : Archive.Settings.Settings_Model);

   function Filter_Text (Model : Application_Model) return String;
   procedure Set_Filter (Model : in out Application_Model; Text : String);
   function Sort_Field (Model : Application_Model) return Archive.View_Snapshots.Sort_Field;
   function Sort_Direction (Model : Application_Model) return Archive.View_Snapshots.Sort_Direction;
   function Directories_First (Model : Application_Model) return Boolean;
   procedure Set_Sorting
     (Model             : in out Application_Model;
      Field             : Archive.View_Snapshots.Sort_Field;
      Direction         : Archive.View_Snapshots.Sort_Direction;
      Directories_First : Boolean);
   procedure Toggle_Sort_Direction (Model : in out Application_Model);

   function Preview_Visible (Model : Application_Model) return Boolean;
   procedure Set_Preview_Visible (Model : in out Application_Model; Visible : Boolean);
   function Current_Preview_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id;
   function Preview_Phase (Model : Application_Model) return Preview_State;
   function Preview_Entry (Model : Application_Model) return Archive.Types.Entry_Id;
   function Current_Preview
     (Model : Application_Model)
      return Archive.Preview.Preview_Result;
   procedure Start_Preview
     (Model    : in out Application_Model;
      Entry_Id : Archive.Types.Entry_Id);
   function Publish_Preview
     (Model      : in out Application_Model;
      Generation : Archive.Types.Generation_Id;
      Result     : Archive.Preview.Preview_Result;
      Failed     : Boolean := False)
      return Boolean;

   function Active_Overlay (Model : Application_Model) return Overlay_Kind;
   function Current_Focus (Model : Application_Model) return Focus_Region;
   function Command_Palette_Filter (Model : Application_Model) return String;
   procedure Open_Command_Palette (Model : in out Application_Model);
   procedure Open_Settings (Model : in out Application_Model);
   procedure Close_Overlay (Model : in out Application_Model);
   procedure Set_Focus (Model : in out Application_Model; Region : Focus_Region);
   procedure Set_Command_Palette_Filter
     (Model : in out Application_Model;
      Text  : String);

   function Active_Dialog (Model : Application_Model) return Dialog_Kind;
   function Notification (Model : Application_Model) return Notification_Severity;
   function Notification_Key (Model : Application_Model) return String;
   procedure Open_Dialog (Model : in out Application_Model; Dialog : Dialog_Kind);
   procedure Close_Dialog (Model : in out Application_Model);
   procedure Publish_Notification
     (Model    : in out Application_Model;
      Severity : Notification_Severity;
      Key      : String);
   procedure Clear_Notification (Model : in out Application_Model);

   function Selected_Count (Model : Application_Model) return Natural;
   procedure Set_Selected_Count (Model : in out Application_Model; Count : Natural);
   function Selected_Items
     (Model : Application_Model)
      return Archive.Types.Entry_Id_Vectors.Vector;
   function Selection_Anchor (Model : Application_Model) return Archive.Types.Entry_Id;
   function Is_Selected
     (Model : Application_Model;
      Id    : Archive.Types.Entry_Id)
      return Boolean;
   function Has_Actionable_Focused_Entry (Model : Application_Model) return Boolean;
   function Focused_Entry_Capabilities
     (Model            : Application_Model;
      Archive_Writable : Boolean := True)
      return Archive.Archives.Capabilities.Entry_Capabilities;
   procedure Clear_Selection (Model : in out Application_Model);
   procedure Select_Only
     (Model : in out Application_Model;
      Id    : Archive.Types.Entry_Id);
   procedure Toggle_Selection
     (Model : in out Application_Model;
      Id    : Archive.Types.Entry_Id);
   procedure Activate_Focused_Entry (Model : in out Application_Model);
   function Last_Copy_Kind (Model : Application_Model) return Copy_Result_Kind;
   function Last_Copy_Text (Model : Application_Model) return String;
   procedure Copy_Focused_Entry_Path (Model : in out Application_Model);
   procedure Copy_Focused_Entry_Information (Model : in out Application_Model);

   function Extraction_Phase (Model : Application_Model) return Extraction_State;
   function Current_Extraction_Plan
     (Model : Application_Model)
      return Archive.Extraction.Plans.Extraction_Plan;
   procedure Plan_Selected_Extraction (Model : in out Application_Model);
   procedure Plan_All_Extraction (Model : in out Application_Model);
   procedure Cancel_Extraction (Model : in out Application_Model);
   procedure Publish_Extraction_Result
     (Model           : in out Application_Model;
      Success         : Boolean;
      Cancelled       : Boolean := False;
      Plan_Status     : Archive.Extraction.Results.Plan_Execution_Status :=
        Archive.Extraction.Results.Execution_Completed;
      Publish_Status  : Archive.Extraction.Results.Extraction_Status :=
        Archive.Extraction.Results.Completed;
      Completed_Count : Natural := 0;
      Failed_Count    : Natural := 0;
      Blocked_Count   : Natural := 0);
   function Last_Extraction_Plan_Status
     (Model : Application_Model)
      return Archive.Extraction.Results.Plan_Execution_Status;
   function Last_Extraction_Status
     (Model : Application_Model)
      return Archive.Extraction.Results.Extraction_Status;
   function Last_Extraction_Completed_Count (Model : Application_Model) return Natural;
   function Last_Extraction_Failed_Count (Model : Application_Model) return Natural;
   function Last_Extraction_Blocked_Count (Model : Application_Model) return Natural;

   function Pending_Write_Count (Model : Application_Model) return Natural;
   function Has_Pending_Writes (Model : Application_Model) return Boolean;
   function Has_Saveable_Write_Plan (Model : Application_Model) return Boolean;
   function Current_Write_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id;
   function Current_Save_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id;
   function Current_Write_Plan
     (Model : Application_Model)
      return Archive.Writes.Plans.Write_Plan;
   procedure Mark_Pending_Write (Model : in out Application_Model);
   procedure Plan_Add_File
     (Model       : in out Application_Model;
      Host_Source : String;
      Target_Path : String);
   procedure Plan_Add_Directory
     (Model       : in out Application_Model;
      Host_Source : String;
      Target_Path : String);
   procedure Plan_Selected_Replacement
     (Model       : in out Application_Model;
      Host_Source : String);
   procedure Plan_Selected_Removal (Model : in out Application_Model);
   procedure Plan_Selected_Rename
     (Model            : in out Application_Model;
      Replacement_Path : String);
   procedure Clear_Pending_Writes (Model : in out Application_Model);
   procedure Skip_Write_Conflicts (Model : in out Application_Model);
   procedure Begin_Save (Model : in out Application_Model);
   function Publish_Write_Result
     (Model     : in out Application_Model;
      Operation : Archive.Types.Generation_Id;
      Success   : Boolean;
      Status    : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed)
      return Boolean;
   function Publish_Saved_Archive_Index
     (Model       : in out Application_Model;
      Operation   : Archive.Types.Generation_Id;
      Source_Path : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id;
      Status      : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed;
      Backing_Path : String := "")
      return Boolean;
   procedure Publish_Write_Result
     (Model  : in out Application_Model;
      Success : Boolean;
      Status  : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed);
   function Last_Write_Status
     (Model : Application_Model)
      return Archive.Writes.Results.Write_Status;

   function Session_Generation (Model : Application_Model) return Archive.Types.Generation_Id;
   function Last_Command (Model : Application_Model) return String;
   function Last_Command_Accepted (Model : Application_Model) return Boolean;
   procedure Set_Last_Command
     (Model       : in out Application_Model;
      Id_Executed : String;
      Accepted    : Boolean);

private
   type Application_Model is record
      State          : Lifecycle_State := No_Archive;
      Source_Path    : UString;
      Backing_Path   : UString;
      Source_FP      : Archive.Source_Monitoring.Source_Fingerprint;
      Source_Change  : Source_Change_State := No_Source_Change;
      Index          : Archive.Archives.Index.Archive_Index;
      Format         : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format;
      Index_Present  : Boolean := False;
      Directory      : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Focused        : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Navigation     : Archive.Navigation.Navigation_Model;
      Generation     : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Open_Id        : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Verification    : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Verify_Overlay  : Archive.Verification.Overlays.Verification_Overlay :=
        Archive.Verification.Overlays.Empty
          (Archive.Types.No_Generation, Archive.Types.No_Generation,
           Archive.Verification.Overlays.Verification_Not_Run);
      Active_View    : Archive.Types.View_Mode := Archive.Types.Grid_View;
      Settings       : Archive.Settings.Settings_Model := Archive.Settings.Default_Settings;
      Filter         : UString;
      Sort_Field     : Archive.View_Snapshots.Sort_Field := Archive.View_Snapshots.Sort_By_Name;
      Sort_Direction : Archive.View_Snapshots.Sort_Direction := Archive.View_Snapshots.Ascending;
      Dirs_First     : Boolean := True;
      Preview        : Boolean := True;
      Preview_Id     : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Preview_Status : Preview_State := No_Preview;
      Preview_Target : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Preview_Result : Archive.Preview.Preview_Result;
      Overlay        : Overlay_Kind := No_Overlay;
      Focus          : Focus_Region := Content_Focus;
      Palette_Filter : UString;
      Dialog         : Dialog_Kind := No_Dialog;
      Notice         : Notification_Severity := No_Notification;
      Notice_Key     : UString;
      Selection      : Archive.Selection.Selection_Model;
      Copy_Kind      : Copy_Result_Kind := No_Copy_Result;
      Copy_Text      : UString;
      Extract_State  : Extraction_State := No_Extraction;
      Extract_Plan   : Archive.Extraction.Plans.Extraction_Plan;
      Last_Extract_Plan_Status : Archive.Extraction.Results.Plan_Execution_Status :=
        Archive.Extraction.Results.Execution_Completed;
      Last_Extract_Status : Archive.Extraction.Results.Extraction_Status :=
        Archive.Extraction.Results.Completed;
      Last_Extract_Completed : Natural := 0;
      Last_Extract_Failed    : Natural := 0;
      Last_Extract_Blocked   : Natural := 0;
      Life_Request   : Lifecycle_Request := No_Lifecycle_Request;
      Pending_Writes : Natural := 0;
      Write_Id       : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Save_Id        : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Save_Active    : Boolean := False;
      Write_Plan     : Archive.Writes.Plans.Write_Plan;
      Last_Write      : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed;
      Last_Id        : UString;
      Last_Accepted  : Boolean := False;
      Revision       : Archive.Types.Generation_Id := 0;
   end record;
end Archive.Model;
