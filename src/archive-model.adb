with Ada.Directories;
with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Archive.Model is
   use Ada.Strings.Unbounded;
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Generation_Id;
   use type Archive.Extraction.Results.Extraction_Status;
   use type Archive.View_Snapshots.Sort_Direction;
   use type Archive.Verification.Overlays.Overlay_Acceptance;
   use type Archive.Writes.Plans.Entry_Decision;
   use type Archive.Writes.Plans.Plan_Status;

   procedure Touch (Model : in out Application_Model) is
   begin
      Model.Revision := Model.Revision + 1;
   end Touch;

   function Has_Suffix (Value : String; Suffix : String) return Boolean is
      Lower_Value  : constant String := Ada.Characters.Handling.To_Lower (Value);
      Lower_Suffix : constant String := Ada.Characters.Handling.To_Lower (Suffix);
   begin
      return Lower_Value'Length >= Lower_Suffix'Length
        and then Lower_Value
          (Lower_Value'Last - Lower_Suffix'Length + 1 .. Lower_Value'Last) = Lower_Suffix;
   end Has_Suffix;

   function Format_Hint_From_Path (Path : String) return Archive.Archives.Formats.Format_Id is
   begin
      if Has_Suffix (Path, ".tar.gz") or else Has_Suffix (Path, ".tgz") then
         return Archive.Archives.Formats.Tar_GZip_Format;
      elsif Has_Suffix (Path, ".tar") then
         return Archive.Archives.Formats.Tar_Format;
      elsif Has_Suffix (Path, ".zip") then
         return Archive.Archives.Formats.Zip_Format;
      elsif Has_Suffix (Path, ".gz") then
         return Archive.Archives.Formats.GZip_Format;
      elsif Has_Suffix (Path, ".7z") or else Has_Suffix (Path, ".7z.001") then
         return Archive.Archives.Formats.Seven_Zip_Format;
      elsif Has_Suffix (Path, ".rar") then
         return Archive.Archives.Formats.Rar_Format;
      elsif Has_Suffix (Path, ".xz") then
         return Archive.Archives.Formats.Xz_Format;
      elsif Has_Suffix (Path, ".bz2") or else Has_Suffix (Path, ".bzip2") then
         return Archive.Archives.Formats.BZip2_Format;
      elsif Has_Suffix (Path, ".zst") or else Has_Suffix (Path, ".zstd") then
         return Archive.Archives.Formats.Zstd_Format;
      else
         return Archive.Archives.Formats.Unknown_Format;
      end if;
   end Format_Hint_From_Path;

   procedure Initialize (Model : out Application_Model) is
   begin
      Model := (others => <>);
      Model.State := No_Archive;
   end Initialize;

   function Lifecycle (Model : Application_Model) return Lifecycle_State is (Model.State);

   function Has_Open_Archive (Model : Application_Model) return Boolean is
   begin
      return Model.State in Archive_Ready | Archive_Dirty | Saving_Archive | Archive_Save_Failed | Archive_Warnings;
   end Has_Open_Archive;

   procedure Reset_Operation_State (Model : in out Application_Model) is
   begin
      Model.Preview_Id := Model.Preview_Id + 1;
      Model.Preview_Status := No_Preview;
      Model.Preview_Target := Archive.Types.No_Entry;
      Model.Preview_Result := (others => <>);
      Model.Extract_State := No_Extraction;
      Model.Extract_Plan := (others => <>);
      Model.Write_Plan := (others => <>);
      Model.Save_Active := False;
      Model.Copy_Kind := No_Copy_Result;
      Model.Copy_Text := Null_Unbounded_String;
      Model.Verification := Archive.Types.No_Generation;
      Model.Verify_Overlay :=
        Archive.Verification.Overlays.Empty
          (Model.Generation, Model.Verification,
           Archive.Verification.Overlays.Verification_Not_Run);
   end Reset_Operation_State;

   procedure Cleanup_Backing (Model : in out Application_Model) is
      Path : constant String := To_String (Model.Backing_Path);
   begin
      if Path /= "" and then Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Model.Backing_Path := Null_Unbounded_String;
   exception
      when others =>
         Model.Backing_Path := Null_Unbounded_String;
   end Cleanup_Backing;

   procedure Publish_Archive (Model : in out Application_Model; Source_Path : String) is
   begin
      Model.State := Archive_Ready;
      Model.Source_Path := To_Unbounded_String (Source_Path);
      Model.Backing_Path := Null_Unbounded_String;
      Model.Source_Change := No_Source_Change;
      Archive.Settings.Remember_Recent_Archive (Model.Settings, Source_Path);
      Model.Format := Format_Hint_From_Path (Source_Path);
      Model.Index_Present := False;
      Model.Directory := Archive.Types.No_Entry;
      Model.Focused := Archive.Types.No_Entry;
      Model.Generation := Model.Generation + 1;
      Reset_Operation_State (Model);
      Archive.Selection.Clear (Model.Selection);
      Model.Pending_Writes := 0;
      Model.Save_Active := False;
      Model.Overlay := No_Overlay;
      Model.Focus := Content_Focus;
      Model.Dialog := No_Dialog;
      Touch (Model);
   end Publish_Archive;

   procedure Create_New_Archive (Model : in out Application_Model) is
      Empty_Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Build          : constant Archive.Archives.Index.Build_Result :=
        Archive.Archives.Index.Build (Empty_Physical);
   begin
      Publish_Archive_Index
        (Model, "", Build.Index, Archive.Archives.Formats.Zip_Format);
      Model.State := Archive_Dirty;
      Model.Pending_Writes := 1;
      Model.Write_Id := Model.Write_Id + 1;
      Model.Save_Active := False;
      Touch (Model);
   end Create_New_Archive;

   function Begin_Open (Model : in out Application_Model) return Archive.Types.Generation_Id is
   begin
      Model.Open_Id := Model.Open_Id + 1;
      if not Has_Open_Archive (Model) then
         Model.State := Opening_Archive;
      end if;
      Model.Dialog := No_Dialog;
      Model.Overlay := No_Overlay;
      Touch (Model);
      return Model.Open_Id;
   end Begin_Open;

   function Current_Open_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id
   is (Model.Open_Id);

   function Publish_Open_Result
     (Model       : in out Application_Model;
      Operation   : Archive.Types.Generation_Id;
      Source_Path : String;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id;
      Success     : Boolean;
      Backing_Path : String := "")
      return Boolean
   is
   begin
      if Operation /= Model.Open_Id then
         return False;
      end if;

      if Success then
         Publish_Archive_Index (Model, Source_Path, Backing_Path, Index, Format);
         Model.Source_FP := Fingerprint;
         Publish_Notification (Model, Info_Notification, "ui.notification.open_complete");
      else
         if not Has_Open_Archive (Model) then
            Model.State := Archive_Failed;
         end if;
         Publish_Notification (Model, Error_Notification, "ui.notification.open_failed");
      end if;
      Touch (Model);
      return True;
   end Publish_Open_Result;

   procedure Reload_Archive (Model : in out Application_Model) is
      Existing_Index  : constant Archive.Archives.Index.Archive_Index := Model.Index;
      Existing_Format : constant Archive.Archives.Formats.Format_Id := Model.Format;
      Existing_Source : constant String := To_String (Model.Source_Path);
      Existing_Backing : constant String := To_String (Model.Backing_Path);
      Existing_FP     : constant Archive.Source_Monitoring.Source_Fingerprint := Model.Source_FP;
   begin
      if Model.Index_Present then
         Publish_Archive_Index
           (Model, Existing_Source, Existing_Backing, Existing_Index, Existing_Format);
         Model.Source_FP := Existing_FP;
      end if;
      Touch (Model);
   end Reload_Archive;

   procedure Request_Close_Archive (Model : in out Application_Model) is
   begin
      if Has_Pending_Writes (Model) then
         Open_Dialog (Model, Confirm_Close_Dialog);
      else
         Close_Archive (Model);
      end if;
      Touch (Model);
   end Request_Close_Archive;

   procedure Request_Open_Recent (Model : in out Application_Model) is
   begin
      Model.Life_Request := Open_Recent_Request;
      Open_Dialog (Model, Open_Archive_Dialog);
      Touch (Model);
   end Request_Open_Recent;

   procedure Request_Quit (Model : in out Application_Model) is
   begin
      Model.Life_Request := Quit_Request;
      Model.State := Shutting_Down;
      Model.Overlay := No_Overlay;
      Model.Dialog := No_Dialog;
      Touch (Model);
   end Request_Quit;

   function Last_Lifecycle_Request (Model : Application_Model) return Lifecycle_Request is
     (Model.Life_Request);

   procedure Publish_Archive_Index
     (Model       : in out Application_Model;
      Source_Path : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format)
   is
   begin
      Publish_Archive_Index (Model, Source_Path, "", Index, Format);
   end Publish_Archive_Index;

   procedure Publish_Archive_Index
     (Model       : in out Application_Model;
      Source_Path : String;
      Backing_Path : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format)
   is
      Root : constant Archive.Types.Entry_Id := Archive.Archives.Index.Root_Id (Index);
      Old_Backing : constant String := To_String (Model.Backing_Path);
   begin
      if Old_Backing /= "" and then Old_Backing /= Backing_Path then
         Cleanup_Backing (Model);
      end if;
      Publish_Archive (Model, Source_Path);
      Model.Backing_Path := To_Unbounded_String (Backing_Path);
      if Root /= Archive.Types.No_Entry and then Archive.Archives.Index.Contains (Index, Root) then
         Model.Index := Index;
         Model.Format := Format;
         Model.Index_Present := True;
         Model.Directory := Root;
         Model.Focused := Root;
         Archive.Navigation.Reset (Model.Navigation, Model.Generation, Root);
      end if;
      Touch (Model);
   end Publish_Archive_Index;

   procedure Close_Archive (Model : in out Application_Model) is
   begin
      Cleanup_Backing (Model);
      Model.State := No_Archive;
      Model.Source_Path := Null_Unbounded_String;
      Model.Backing_Path := Null_Unbounded_String;
      Model.Source_FP := (others => <>);
      Model.Source_Change := No_Source_Change;
      Model.Format := Archive.Archives.Formats.Unknown_Format;
      Model.Index_Present := False;
      Model.Directory := Archive.Types.No_Entry;
      Model.Focused := Archive.Types.No_Entry;
      Model.Generation := Model.Generation + 1;
      Reset_Operation_State (Model);
      Archive.Selection.Clear (Model.Selection);
      Model.Pending_Writes := 0;
      Model.Save_Active := False;
      Model.Overlay := No_Overlay;
      Model.Focus := Content_Focus;
      Model.Dialog := No_Dialog;
      Touch (Model);
   end Close_Archive;

   function Source_Path (Model : Application_Model) return String is
     (To_String (Model.Source_Path));

   function Backing_Path (Model : Application_Model) return String is
     (To_String (Model.Backing_Path));

   function Payload_Source_Path (Model : Application_Model) return String is
   begin
      if To_String (Model.Backing_Path) /= "" then
         return To_String (Model.Backing_Path);
      end if;
      return To_String (Model.Source_Path);
   end Payload_Source_Path;

   function Source_Fingerprint
     (Model : Application_Model)
      return Archive.Source_Monitoring.Source_Fingerprint
   is (Model.Source_FP);

   procedure Set_Source_Fingerprint
     (Model       : in out Application_Model;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint)
   is
   begin
      Model.Source_FP := Fingerprint;
      Touch (Model);
   end Set_Source_Fingerprint;

   function Source_Changed
     (Model       : Application_Model;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint)
      return Boolean
   is
   begin
      return not Archive.Source_Monitoring.Same_Source (Model.Source_FP, Fingerprint);
   end Source_Changed;

   function Observe_Source_Fingerprint
     (Model       : in out Application_Model;
      Fingerprint : Archive.Source_Monitoring.Source_Fingerprint)
      return Source_Change_State
   is
      use type Archive.Source_Monitoring.Source_Status;
      Changed : constant Boolean := Source_Changed (Model, Fingerprint);
   begin
      if not Has_Open_Archive (Model) then
         Model.Source_Change := No_Source_Change;
         return Model.Source_Change;
      elsif not Changed then
         Model.Source_Change := Source_Unchanged;
         Touch (Model);
         return Model.Source_Change;
      end if;

      Model.Source_FP := Fingerprint;
      Model.Source_Change :=
        (if Fingerprint.Status = Archive.Source_Monitoring.Source_Ready
         then Source_Modified
         else Source_Unavailable);
      Model.State := Archive_Warnings;
      Model.Preview_Id := Model.Preview_Id + 1;
      Model.Preview_Status := Preview_Failed;
      Model.Preview_Target := Archive.Types.No_Entry;
      Model.Preview_Result := (others => <>);
      Model.Extract_State := No_Extraction;
      Model.Extract_Plan := (others => <>);
      Model.Verification := Model.Verification + 1;
      Model.Verify_Overlay :=
        Archive.Verification.Overlays.Empty
          (Model.Generation, Model.Verification,
           Archive.Verification.Overlays.Verification_Not_Run);
      Publish_Notification (Model, Warning_Notification, "ui.notification.source_changed");
      Touch (Model);
      return Model.Source_Change;
   end Observe_Source_Fingerprint;

   function Last_Source_Change (Model : Application_Model) return Source_Change_State is
     (Model.Source_Change);

   function Has_Index (Model : Application_Model) return Boolean is (Model.Index_Present);

   function Published_Format
     (Model : Application_Model)
      return Archive.Archives.Formats.Format_Id
   is (Model.Format);

   function Published_Index
     (Model : Application_Model)
      return Archive.Archives.Index.Archive_Index
   is (Model.Index);

   function Current_Directory (Model : Application_Model) return Archive.Types.Entry_Id is
     (Model.Directory);

   function Can_Navigate_Back (Model : Application_Model) return Boolean is
     (Archive.Navigation.Can_Back (Model.Navigation));

   function Can_Navigate_Forward (Model : Application_Model) return Boolean is
     (Archive.Navigation.Can_Forward (Model.Navigation));

   procedure Set_Current_Directory
     (Model     : in out Application_Model;
      Directory : Archive.Types.Entry_Id)
   is
   begin
      if Model.Index_Present
        and then Archive.Archives.Index.Contains (Model.Index, Directory)
      then
         Model.Directory := Directory;
         Model.Focused := Directory;
         Archive.Navigation.Navigate_To (Model.Navigation, Directory => Directory, Focused => Directory);
         Touch (Model);
      end if;
   end Set_Current_Directory;

   procedure Apply_History (Model : in out Application_Model; Item : Archive.Navigation.History_Entry) is
   begin
      if Model.Index_Present
        and then Item.Session = Model.Generation
        and then Archive.Archives.Index.Contains (Model.Index, Item.Directory)
      then
         Model.Directory := Item.Directory;
         Model.Focused := Item.Focused;
         Touch (Model);
      end if;
   end Apply_History;

   procedure Navigate_Back (Model : in out Application_Model) is
   begin
      Apply_History (Model, Archive.Navigation.Back (Model.Navigation));
   end Navigate_Back;

   procedure Navigate_Forward (Model : in out Application_Model) is
   begin
      Apply_History (Model, Archive.Navigation.Forward (Model.Navigation));
   end Navigate_Forward;

   procedure Navigate_Root (Model : in out Application_Model) is
   begin
      if Model.Index_Present then
         Set_Current_Directory (Model, Archive.Archives.Index.Root_Id (Model.Index));
      end if;
   end Navigate_Root;

   procedure Navigate_Parent (Model : in out Application_Model) is
   begin
      if Model.Index_Present and then Archive.Archives.Index.Contains (Model.Index, Model.Directory) then
         declare
            Current : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Model.Index, Model.Directory);
         begin
            if Current.Parent /= Archive.Types.No_Entry then
               Set_Current_Directory (Model, Current.Parent);
            end if;
         end;
      end if;
   end Navigate_Parent;

   function Focused_Entry (Model : Application_Model) return Archive.Types.Entry_Id is
     (Model.Focused);

   procedure Set_Focused_Entry
     (Model    : in out Application_Model;
      Entry_Id : Archive.Types.Entry_Id)
   is
   begin
      if Model.Index_Present
        and then Archive.Archives.Index.Contains (Model.Index, Entry_Id)
      then
         Model.Focused := Entry_Id;
         Touch (Model);
      end if;
   end Set_Focused_Entry;

   function Current_Verification_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id
   is (Model.Verification);

   procedure Start_Verification (Model : in out Application_Model) is
   begin
      Model.Verification := Model.Verification + 1;
      Model.Verify_Overlay :=
        Archive.Verification.Overlays.Empty
          (Model.Generation, Model.Verification,
           Archive.Verification.Overlays.Verification_Running);
      Touch (Model);
   end Start_Verification;

   function Publish_Verification
     (Model     : in out Application_Model;
      Overlay   : Archive.Verification.Overlays.Verification_Overlay;
      Cancelled : Boolean := False)
      return Archive.Verification.Overlays.Overlay_Acceptance
   is
      Decision : constant Archive.Verification.Overlays.Overlay_Acceptance :=
        Archive.Verification.Overlays.Accept_Result
          (Overlay,
           Current_Session      => Model.Generation,
           Current_Verification => Model.Verification,
           Cancelled            => Cancelled);
   begin
      if Decision = Archive.Verification.Overlays.Overlay_Accepted then
         Model.Verify_Overlay := Overlay;
         Touch (Model);
      end if;
      return Decision;
   end Publish_Verification;

   function Verification_Entry_Count (Model : Application_Model) return Natural is
     (Archive.Verification.Overlays.Entry_Count (Model.Verify_Overlay));

   function Verification_Phase
     (Model : Application_Model)
      return Archive.Verification.Overlays.Verification_Phase
   is (Archive.Verification.Overlays.Phase (Model.Verify_Overlay));

   function Verification_Integrity
     (Model : Application_Model;
      Entry_Id : Archive.Types.Entry_Id)
      return Archive.Archives.Entries.Integrity_State
   is (Archive.Verification.Overlays.Integrity_For (Model.Verify_Overlay, Entry_Id));

   function View_Mode (Model : Application_Model) return Archive.Types.View_Mode is (Model.Active_View);

   procedure Set_View_Mode (Model : in out Application_Model; Mode : Archive.Types.View_Mode) is
   begin
      Model.Active_View := Mode;
      Touch (Model);
   end Set_View_Mode;

   function Effective_Settings (Model : Application_Model) return Archive.Settings.Settings_Model is
     (Model.Settings);

   function Has_Recent_Archives (Model : Application_Model) return Boolean is
     (not Model.Settings.Recent_Archives.Is_Empty);

   function Recent_Archives
     (Model : Application_Model)
      return Archive.Types.String_Vectors.Vector
   is (Model.Settings.Recent_Archives);

   procedure Apply_Settings
     (Model    : in out Application_Model;
      Settings : Archive.Settings.Settings_Model)
   is
   begin
      Model.Settings := Settings;
      Model.Active_View := Settings.Default_View;
      Model.Dirs_First := Settings.Directories_First;
      Model.Preview := Settings.Preview_Visible;
      Touch (Model);
   end Apply_Settings;

   function Filter_Text (Model : Application_Model) return String is (To_String (Model.Filter));

   procedure Set_Filter (Model : in out Application_Model; Text : String) is
   begin
      Model.Filter := To_Unbounded_String (Text);
      Touch (Model);
   end Set_Filter;

   function Sort_Field (Model : Application_Model) return Archive.View_Snapshots.Sort_Field is
     (Model.Sort_Field);

   function Sort_Direction (Model : Application_Model) return Archive.View_Snapshots.Sort_Direction is
     (Model.Sort_Direction);

   function Directories_First (Model : Application_Model) return Boolean is (Model.Dirs_First);

   procedure Set_Sorting
     (Model             : in out Application_Model;
      Field             : Archive.View_Snapshots.Sort_Field;
      Direction         : Archive.View_Snapshots.Sort_Direction;
      Directories_First : Boolean)
   is
   begin
      Model.Sort_Field := Field;
      Model.Sort_Direction := Direction;
      Model.Dirs_First := Directories_First;
      Touch (Model);
   end Set_Sorting;

   procedure Toggle_Sort_Direction (Model : in out Application_Model) is
   begin
      if Model.Sort_Direction = Archive.View_Snapshots.Ascending then
         Model.Sort_Direction := Archive.View_Snapshots.Descending;
      else
         Model.Sort_Direction := Archive.View_Snapshots.Ascending;
      end if;
      Touch (Model);
   end Toggle_Sort_Direction;

   function Preview_Visible (Model : Application_Model) return Boolean is (Model.Preview);

   procedure Set_Preview_Visible (Model : in out Application_Model; Visible : Boolean) is
   begin
      Model.Preview := Visible;
      Touch (Model);
   end Set_Preview_Visible;

   function Current_Preview_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id
   is (Model.Preview_Id);

   function Preview_Phase (Model : Application_Model) return Preview_State is
     (Model.Preview_Status);

   function Preview_Entry (Model : Application_Model) return Archive.Types.Entry_Id is
     (Model.Preview_Target);

   function Current_Preview
     (Model : Application_Model)
      return Archive.Preview.Preview_Result
   is (Model.Preview_Result);

   procedure Start_Preview
     (Model    : in out Application_Model;
      Entry_Id : Archive.Types.Entry_Id)
   is
   begin
      Model.Preview_Id := Model.Preview_Id + 1;
      Model.Preview_Status := Preview_Loading;
      Model.Preview_Target := Entry_Id;
      Model.Preview_Result := (others => <>);
      Touch (Model);
   end Start_Preview;

   function Publish_Preview
     (Model      : in out Application_Model;
      Generation : Archive.Types.Generation_Id;
      Result     : Archive.Preview.Preview_Result;
      Failed     : Boolean := False)
      return Boolean
   is
   begin
      if Generation /= Model.Preview_Id then
         return False;
      end if;

      Model.Preview_Result := Result;
      Model.Preview_Status := (if Failed then Preview_Failed else Preview_Ready);
      Touch (Model);
      return True;
   end Publish_Preview;

   function Active_Overlay (Model : Application_Model) return Overlay_Kind is (Model.Overlay);

   function Current_Focus (Model : Application_Model) return Focus_Region is (Model.Focus);

   function Command_Palette_Filter (Model : Application_Model) return String is
     (To_String (Model.Palette_Filter));

   procedure Open_Command_Palette (Model : in out Application_Model) is
   begin
      Model.Overlay := Command_Palette_Overlay;
      Model.Focus := Command_Palette_Focus;
      Touch (Model);
   end Open_Command_Palette;

   procedure Open_Settings (Model : in out Application_Model) is
   begin
      Model.Overlay := Settings_Overlay;
      Model.Focus := Settings_Focus;
      Touch (Model);
   end Open_Settings;

   procedure Close_Overlay (Model : in out Application_Model) is
   begin
      Model.Overlay := No_Overlay;
      Model.Focus := Content_Focus;
      Touch (Model);
   end Close_Overlay;

   procedure Set_Focus (Model : in out Application_Model; Region : Focus_Region) is
   begin
      Model.Focus := Region;
      Touch (Model);
   end Set_Focus;

   procedure Set_Command_Palette_Filter
     (Model : in out Application_Model;
      Text  : String)
   is
   begin
      Model.Palette_Filter := To_Unbounded_String (Text);
      Touch (Model);
   end Set_Command_Palette_Filter;

   function Active_Dialog (Model : Application_Model) return Dialog_Kind is (Model.Dialog);

   function Notification (Model : Application_Model) return Notification_Severity is (Model.Notice);

   function Notification_Key (Model : Application_Model) return String is (To_String (Model.Notice_Key));

   procedure Open_Dialog (Model : in out Application_Model; Dialog : Dialog_Kind) is
   begin
      Model.Dialog := Dialog;
      Model.Overlay := No_Overlay;
      Model.Focus := Content_Focus;
      Touch (Model);
   end Open_Dialog;

   procedure Close_Dialog (Model : in out Application_Model) is
   begin
      Model.Dialog := No_Dialog;
      Touch (Model);
   end Close_Dialog;

   procedure Publish_Notification
     (Model    : in out Application_Model;
      Severity : Notification_Severity;
      Key      : String)
   is
   begin
      Model.Notice := Severity;
      Model.Notice_Key := To_Unbounded_String (Key);
      Touch (Model);
   end Publish_Notification;

   procedure Clear_Notification (Model : in out Application_Model) is
   begin
      Model.Notice := No_Notification;
      Model.Notice_Key := Null_Unbounded_String;
      Touch (Model);
   end Clear_Notification;

   function Selected_Count (Model : Application_Model) return Natural is
     (Archive.Selection.Count (Model.Selection));

   procedure Set_Selected_Count (Model : in out Application_Model; Count : Natural) is
   begin
      Archive.Selection.Clear (Model.Selection);
      for Id in 1 .. Count loop
         Archive.Selection.Add (Model.Selection, Archive.Types.Entry_Id (Id));
      end loop;
      Model.Focused := (if Count = 0 then Archive.Types.No_Entry else 1);
      Touch (Model);
   end Set_Selected_Count;

   function Selected_Items
     (Model : Application_Model)
      return Archive.Types.Entry_Id_Vectors.Vector
   is (Archive.Selection.Items (Model.Selection));

   function Selection_Anchor (Model : Application_Model) return Archive.Types.Entry_Id is
     (Archive.Selection.Anchor (Model.Selection));

   function Is_Selected
     (Model : Application_Model;
      Id    : Archive.Types.Entry_Id)
      return Boolean
   is (Archive.Selection.Contains (Model.Selection, Id));

   function Has_Actionable_Focused_Entry (Model : Application_Model) return Boolean is
   begin
      if Archive.Selection.Count (Model.Selection) = 0
        or else Model.Focused = Archive.Types.No_Entry
        or else not Archive.Selection.Contains (Model.Selection, Model.Focused)
      then
         return False;
      elsif Model.Index_Present then
         return Archive.Archives.Index.Contains (Model.Index, Model.Focused);
      else
         return True;
      end if;
   end Has_Actionable_Focused_Entry;

   function Focused_Entry_Capabilities
     (Model            : Application_Model;
      Archive_Writable : Boolean := True)
      return Archive.Archives.Capabilities.Entry_Capabilities
   is
   begin
      if not Has_Actionable_Focused_Entry (Model) then
         return (others => <>);
      end if;

      return Archive.Archives.Capabilities.For_Entry
        (Archive.Archives.Index.Entry_For (Model.Index, Model.Focused),
         Archive_Writable);
   end Focused_Entry_Capabilities;

   procedure Clear_Selection (Model : in out Application_Model) is
   begin
      Archive.Selection.Clear (Model.Selection);
      Touch (Model);
   end Clear_Selection;

   procedure Select_Only
     (Model : in out Application_Model;
      Id    : Archive.Types.Entry_Id)
   is
   begin
      Archive.Selection.Select_Only (Model.Selection, Id);
      Model.Focused := Id;
      Touch (Model);
   end Select_Only;

   procedure Toggle_Selection
     (Model : in out Application_Model;
      Id    : Archive.Types.Entry_Id)
   is
   begin
      Archive.Selection.Toggle (Model.Selection, Id);
      Model.Focused := Id;
      Touch (Model);
   end Toggle_Selection;

   procedure Activate_Focused_Entry (Model : in out Application_Model) is
   begin
      if Model.Index_Present
        and then Archive.Archives.Index.Contains (Model.Index, Model.Focused)
      then
         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Model.Index, Model.Focused);
         begin
            case Item.Kind is
               when Archive.Archives.Entries.Directory =>
                  Set_Current_Directory (Model, Item.Id);
               when Archive.Archives.Entries.Regular_File =>
                  Start_Preview (Model, Item.Id);
               when others =>
                  null;
            end case;
         end;
      end if;
   end Activate_Focused_Entry;

   function Last_Copy_Kind (Model : Application_Model) return Copy_Result_Kind is (Model.Copy_Kind);

   function Last_Copy_Text (Model : Application_Model) return String is (To_String (Model.Copy_Text));

   function Focused_Item (Model : Application_Model) return Archive.Archives.Entries.Archive_Entry is
   begin
      if Model.Index_Present
        and then Archive.Archives.Index.Contains (Model.Index, Model.Focused)
      then
         return Archive.Archives.Index.Entry_For (Model.Index, Model.Focused);
      end if;
      return (others => <>);
   end Focused_Item;

   procedure Copy_Focused_Entry_Path (Model : in out Application_Model) is
      Item : constant Archive.Archives.Entries.Archive_Entry := Focused_Item (Model);
   begin
      if Item.Id /= Archive.Types.No_Entry then
         Model.Copy_Kind := Entry_Path_Copy;
         Model.Copy_Text := Item.Original_Path;
         Publish_Notification (Model, Info_Notification, "ui.notification.copy_complete");
      end if;
      Touch (Model);
   end Copy_Focused_Entry_Path;

   procedure Copy_Focused_Entry_Information (Model : in out Application_Model) is
      Item : constant Archive.Archives.Entries.Archive_Entry := Focused_Item (Model);
   begin
      if Item.Id /= Archive.Types.No_Entry then
         Model.Copy_Kind := Entry_Information_Copy;
         Model.Copy_Text :=
           To_Unbounded_String
             ("id=" & Archive.Types.Entry_Id'Image (Item.Id)
              & ASCII.LF & "name=" & To_String (Item.Display_Name)
              & ASCII.LF & "path=" & To_String (Item.Original_Path));
         Publish_Notification (Model, Info_Notification, "ui.notification.copy_complete");
      end if;
      Touch (Model);
   end Copy_Focused_Entry_Information;

   function Extraction_Phase (Model : Application_Model) return Extraction_State is
     (Model.Extract_State);

   function Current_Extraction_Plan
     (Model : Application_Model)
      return Archive.Extraction.Plans.Extraction_Plan
   is (Model.Extract_Plan);

   procedure Publish_Extraction_Plan
     (Model     : in out Application_Model;
      Selection : Archive.Types.Entry_Id_Vectors.Vector)
   is
   begin
      if Model.Index_Present then
         Model.Extract_Plan :=
           Archive.Extraction.Plans.Build
             (Model.Index, Selection, Session => Model.Generation);
         Model.Extract_State := Extraction_Planned;
      else
         Model.Extract_Plan := (others => <>);
         Model.Extract_State := No_Extraction;
      end if;
      Touch (Model);
   end Publish_Extraction_Plan;

   procedure Plan_Selected_Extraction (Model : in out Application_Model) is
   begin
      Publish_Extraction_Plan (Model, Archive.Selection.Items (Model.Selection));
   end Plan_Selected_Extraction;

   procedure Plan_All_Extraction (Model : in out Application_Model) is
      All_Entries : Archive.Types.Entry_Id_Vectors.Vector;
   begin
      if Model.Index_Present then
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Model.Index) loop
            declare
               Id : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
            begin
               if Archive.Archives.Index.Contains (Model.Index, Id) then
                  declare
                     Item : constant Archive.Archives.Entries.Archive_Entry :=
                       Archive.Archives.Index.Entry_For (Model.Index, Id);
                  begin
                     if not Item.Synthetic then
                        All_Entries.Append (Id);
                     end if;
                  end;
               end if;
            end;
         end loop;
      end if;
      Publish_Extraction_Plan (Model, All_Entries);
   end Plan_All_Extraction;

   procedure Cancel_Extraction (Model : in out Application_Model) is
   begin
      Model.Extract_State := No_Extraction;
      Model.Extract_Plan := (others => <>);
      Touch (Model);
   end Cancel_Extraction;

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
      Blocked_Count   : Natural := 0)
   is
   begin
      Model.Last_Extract_Plan_Status := Plan_Status;
      Model.Last_Extract_Status := Publish_Status;
      Model.Last_Extract_Completed := Completed_Count;
      Model.Last_Extract_Failed := Failed_Count;
      Model.Last_Extract_Blocked := Blocked_Count;

      if Success then
         Model.Extract_State := No_Extraction;
         Model.Extract_Plan := (others => <>);
         Publish_Notification
           (Model, Info_Notification, "ui.notification.extract_complete");
      elsif Cancelled then
         Model.Extract_State := No_Extraction;
         Model.Extract_Plan := (others => <>);
         Publish_Notification
           (Model, Warning_Notification, "ui.notification.extract_cancelled");
      else
         Publish_Notification
           (Model, Error_Notification,
            (if Publish_Status = Archive.Extraction.Results.Failed_Checksum then
                "ui.notification.extract_failed_checksum"
             elsif Publish_Status = Archive.Extraction.Results.Failed_Limit then
                "ui.notification.extract_failed_limit"
             elsif Publish_Status = Archive.Extraction.Results.Failed_Containment then
                "ui.notification.extract_failed_containment"
             elsif Publish_Status = Archive.Extraction.Results.Blocked_By_Plan then
                "ui.notification.extract_blocked"
             else
                "ui.notification.extract_failed"));
      end if;
      Touch (Model);
   end Publish_Extraction_Result;

   function Last_Extraction_Plan_Status
     (Model : Application_Model)
      return Archive.Extraction.Results.Plan_Execution_Status
   is (Model.Last_Extract_Plan_Status);

   function Last_Extraction_Status
     (Model : Application_Model)
      return Archive.Extraction.Results.Extraction_Status
   is (Model.Last_Extract_Status);

   function Last_Extraction_Completed_Count (Model : Application_Model) return Natural is
     (Model.Last_Extract_Completed);

   function Last_Extraction_Failed_Count (Model : Application_Model) return Natural is
     (Model.Last_Extract_Failed);

   function Last_Extraction_Blocked_Count (Model : Application_Model) return Natural is
     (Model.Last_Extract_Blocked);

   function Pending_Write_Count (Model : Application_Model) return Natural is (Model.Pending_Writes);

   function Has_Pending_Writes (Model : Application_Model) return Boolean is (Model.Pending_Writes > 0);

   function Has_Saveable_Write_Plan (Model : Application_Model) return Boolean is
   begin
      return Model.Pending_Writes > 0
        and then Model.Write_Plan.Status = Archive.Writes.Plans.Write_Plan_Ready;
   end Has_Saveable_Write_Plan;

   function Current_Write_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id
   is (Model.Write_Id);

   function Current_Save_Generation
     (Model : Application_Model)
      return Archive.Types.Generation_Id
   is (Model.Save_Id);

   function Current_Write_Plan
     (Model : Application_Model)
      return Archive.Writes.Plans.Write_Plan
   is (Model.Write_Plan);

   procedure Mark_Pending_Write (Model : in out Application_Model) is
   begin
      Model.Pending_Writes := Model.Pending_Writes + 1;
      if Has_Open_Archive (Model) then
         Model.State := Archive_Dirty;
      end if;
      Touch (Model);
   end Mark_Pending_Write;

   procedure Publish_Write_Plan
     (Model    : in out Application_Model;
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector)
   is
   begin
      Model.Write_Id := Model.Write_Id + 1;
      Model.Save_Active := False;
      if Model.Index_Present then
         Model.Write_Plan := Archive.Writes.Plans.Build (Model.Index, Requests, Model.Generation);
      else
         Model.Write_Plan :=
           Archive.Writes.Plans.Build (Model.Index, Requests, Archive.Types.No_Generation);
      end if;
      Model.Pending_Writes := Natural (Model.Write_Plan.Changes.Length);
      if Model.Pending_Writes > 0 and then Has_Open_Archive (Model) then
         Model.State := Archive_Dirty;
      elsif Model.Pending_Writes = 0 and then Has_Open_Archive (Model) then
         Model.State := Archive_Ready;
      end if;
      if Model.Write_Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts then
         Open_Dialog (Model, Write_Conflict_Dialog);
      end if;
      Touch (Model);
   end Publish_Write_Plan;

   procedure Plan_Add_File
     (Model       : in out Application_Model;
      Host_Source : String;
      Target_Path : String)
   is
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
   begin
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_Source),
            Target_Path      => To_Unbounded_String (Target_Path),
            Replacement_Path => To_Unbounded_String ("")));
      Publish_Write_Plan (Model, Requests);
   end Plan_Add_File;

   procedure Plan_Add_Directory
     (Model       : in out Application_Model;
      Host_Source : String;
      Target_Path : String)
   is
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
   begin
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_Directory,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_Source),
            Target_Path      => To_Unbounded_String (Target_Path),
            Replacement_Path => To_Unbounded_String ("")));
      Publish_Write_Plan (Model, Requests);
   end Plan_Add_Directory;

   procedure Plan_Selected_Replacement
     (Model       : in out Application_Model;
      Host_Source : String)
   is
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
      Selected : constant Archive.Types.Entry_Id_Vectors.Vector := Selected_Items (Model);
   begin
      if not Selected.Is_Empty and then Model.Index_Present then
         declare
            Id   : constant Archive.Types.Entry_Id := Selected.Element (Selected.First_Index);
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Model.Index, Id);
         begin
            Requests.Append
              (Archive.Writes.Plans.Write_Request'
                 (Action           => Archive.Writes.Plans.Replace_File,
                  Source_Entry     => Id,
                  Host_Source      => To_Unbounded_String (Host_Source),
                  Target_Path      => Item.Original_Path,
                  Replacement_Path => To_Unbounded_String ("")));
         end;
      end if;
      Publish_Write_Plan (Model, Requests);
   end Plan_Selected_Replacement;

   procedure Plan_Selected_Removal (Model : in out Application_Model) is
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
      Selected : constant Archive.Types.Entry_Id_Vectors.Vector := Selected_Items (Model);
   begin
      if not Selected.Is_Empty then
         for Position in Selected.First_Index .. Selected.Last_Index loop
            Requests.Append
              (Archive.Writes.Plans.Write_Request'
                 (Action           => Archive.Writes.Plans.Remove_Entry,
                  Source_Entry     => Selected.Element (Position),
                  Host_Source      => To_Unbounded_String (""),
                  Target_Path      => To_Unbounded_String (""),
                  Replacement_Path => To_Unbounded_String ("")));
         end loop;
      end if;
      Publish_Write_Plan (Model, Requests);
   end Plan_Selected_Removal;

   procedure Plan_Selected_Rename
     (Model            : in out Application_Model;
      Replacement_Path : String)
   is
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
      Selected : constant Archive.Types.Entry_Id_Vectors.Vector := Selected_Items (Model);
   begin
      if not Selected.Is_Empty then
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Rename_Entry,
               Source_Entry     => Selected.Element (Selected.First_Index),
               Host_Source      => To_Unbounded_String (""),
               Target_Path      => To_Unbounded_String (""),
               Replacement_Path => To_Unbounded_String (Replacement_Path)));
      end if;
      Publish_Write_Plan (Model, Requests);
   end Plan_Selected_Rename;

   procedure Clear_Pending_Writes (Model : in out Application_Model) is
   begin
      Model.Pending_Writes := 0;
      Model.Write_Plan := (others => <>);
      Model.Write_Id := Model.Write_Id + 1;
      Model.Save_Active := False;
      if Has_Open_Archive (Model) then
         Model.State := Archive_Ready;
      end if;
      Touch (Model);
   end Clear_Pending_Writes;

   procedure Skip_Write_Conflicts (Model : in out Application_Model) is
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
   begin
      for Change of Model.Write_Plan.Changes loop
         if Change.Decision = Archive.Writes.Plans.Entry_Ready then
            Requests.Append (Change.Request);
         end if;
      end loop;

      Publish_Write_Plan (Model, Requests);
      if Model.Write_Plan.Status /= Archive.Writes.Plans.Write_Plan_Has_Conflicts then
         Close_Dialog (Model);
      end if;
   end Skip_Write_Conflicts;

   procedure Begin_Save (Model : in out Application_Model) is
   begin
      if Has_Saveable_Write_Plan (Model) then
         Model.Save_Id := Model.Save_Id + 1;
         Model.Save_Active := True;
         Model.State := Saving_Archive;
         Touch (Model);
      end if;
   end Begin_Save;

   function Publish_Write_Result
     (Model     : in out Application_Model;
      Operation : Archive.Types.Generation_Id;
      Success   : Boolean;
      Status    : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed)
      return Boolean
   is
   begin
      if not Model.Save_Active
        or else Operation = Archive.Types.No_Generation
        or else Operation /= Model.Save_Id
      then
         return False;
      end if;

      Model.Last_Write := Status;
      Model.Save_Active := False;
      if Success then
         Model.Pending_Writes := 0;
         Model.Generation := Model.Generation + 1;
         Reset_Operation_State (Model);
         if Model.Index_Present
           and then Model.Directory /= Archive.Types.No_Entry
           and then Archive.Archives.Index.Contains (Model.Index, Model.Directory)
         then
            Archive.Navigation.Reset (Model.Navigation, Model.Generation, Model.Directory);
         end if;
         if Has_Open_Archive (Model) then
            Model.State := Archive_Ready;
         end if;
         Publish_Notification (Model, Info_Notification, "ui.notification.save_complete");
      else
         if Has_Open_Archive (Model) then
            Model.State := Archive_Save_Failed;
         end if;
         Publish_Notification (Model, Error_Notification, "ui.notification.save_failed");
      end if;
      Touch (Model);
      return True;
   end Publish_Write_Result;

   function Publish_Saved_Archive_Index
     (Model       : in out Application_Model;
      Operation   : Archive.Types.Generation_Id;
      Source_Path : String;
      Index       : Archive.Archives.Index.Archive_Index;
      Format      : Archive.Archives.Formats.Format_Id;
      Status      : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed;
      Backing_Path : String := "")
      return Boolean
   is
      Root : constant Archive.Types.Entry_Id := Archive.Archives.Index.Root_Id (Index);
      Old_Backing : constant String := To_String (Model.Backing_Path);
   begin
      if not Model.Save_Active
        or else Operation = Archive.Types.No_Generation
        or else Operation /= Model.Save_Id
        or else Root = Archive.Types.No_Entry
        or else not Archive.Archives.Index.Contains (Index, Root)
      then
         return False;
      end if;

      Model.Last_Write := Status;
      if Old_Backing /= "" and then Old_Backing /= Backing_Path then
         Cleanup_Backing (Model);
      end if;
      Model.Save_Active := False;
      Model.Pending_Writes := 0;
      Model.Generation := Model.Generation + 1;
      Reset_Operation_State (Model);
      Model.Source_Path := To_Unbounded_String (Source_Path);
      Model.Backing_Path := To_Unbounded_String (Backing_Path);
      Model.Source_FP := Archive.Source_Monitoring.Fingerprint (Source_Path);
      Model.Source_Change := No_Source_Change;
      Model.Format := Format;
      Model.Index := Index;
      Model.Index_Present := True;
      Model.Directory := Root;
      Model.Focused := Root;
      Archive.Selection.Clear (Model.Selection);
      Archive.Navigation.Reset (Model.Navigation, Model.Generation, Root);
      Model.State := Archive_Ready;
      Publish_Notification (Model, Info_Notification, "ui.notification.save_complete");
      Touch (Model);
      return True;
   end Publish_Saved_Archive_Index;

   procedure Publish_Write_Result
     (Model  : in out Application_Model;
      Success : Boolean;
      Status  : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed)
   is
      Accepted : constant Boolean :=
        Publish_Write_Result (Model, Model.Save_Id, Success, Status);
   begin
      pragma Unreferenced (Accepted);
      null;
   end Publish_Write_Result;

   function Last_Write_Status
     (Model : Application_Model)
      return Archive.Writes.Results.Write_Status
   is (Model.Last_Write);

   function Session_Generation (Model : Application_Model) return Archive.Types.Generation_Id is
     (Model.Generation);

   function Last_Command (Model : Application_Model) return String is (To_String (Model.Last_Id));
   function Last_Command_Accepted (Model : Application_Model) return Boolean is (Model.Last_Accepted);

   procedure Set_Last_Command
     (Model       : in out Application_Model;
      Id_Executed : String;
      Accepted    : Boolean)
   is
   begin
      Model.Last_Id := To_Unbounded_String (Id_Executed);
      Model.Last_Accepted := Accepted;
      Touch (Model);
   end Set_Last_Command;
end Archive.Model;
