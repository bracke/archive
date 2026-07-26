with Archive.Archives.Capabilities;
with Archive.Archives.Formats;
with Archive.Types;
with Archive.Writes.Service;

package body Archive.Commands is
   function Current_Format_Capabilities
     (Model : Archive.Model.Application_Model)
      return Archive.Archives.Formats.Format_Capabilities
   is
   begin
      return Archive.Archives.Formats.Capabilities (Archive.Model.Published_Format (Model));
   end Current_Format_Capabilities;

   function Focused_Capabilities
     (Model : Archive.Model.Application_Model)
      return Archive.Archives.Capabilities.Entry_Capabilities
   is
   begin
      return Archive.Model.Focused_Entry_Capabilities
        (Model, Archive_Writable => Current_Format_Capabilities (Model).Can_Add_Entries);
   end Focused_Capabilities;

   function Bounded (Value : String) return Bounded_Text_64 is
      Result : Bounded_Text_64;
      Count  : constant Natural := Natural'Min (Value'Length, Result.Text'Length);
   begin
      if Count > 0 then
         Result.Text (1 .. Count) := Value (Value'First .. Value'First + Count - 1);
      end if;
      Result.Length := Count;
      return Result;
   end Bounded;

   function To_String (Value : Bounded_Text_64) return String is
   begin
      if Value.Length = 0 then
         return "";
      end if;
      return Value.Text (1 .. Value.Length);
   end To_String;

   function Ctrl (Key : Guikit.Input.Key_Code) return Shortcut is
      Mods : Guikit.Input.Modifier_Set := Guikit.Input.No_Modifiers;
   begin
      Mods (Guikit.Input.Control_Key) := True;
      return (True, Key, Mods);
   end Ctrl;

   function Identifier (Id : Command_Id) return String is
   begin
      case Id is
         when No_Command => return "archive.noop";
         when Open_Archive_Command => return "archive.open";
         when New_Archive_Command => return "archive.new";
         when Close_Archive_Command => return "archive.close";
         when Reload_Archive_Command => return "archive.reload";
         when Open_Recent_Archive_Command => return "archive.open_recent";
         when Save_Archive_Command => return "archive.save";
         when Save_Archive_As_Command => return "archive.save_as";
         when Discard_Changes_Command => return "archive.discard_changes";
         when Add_Files_Command => return "archive.add_files";
         when Add_Directory_Command => return "archive.add_directory";
         when Replace_Selected_Command => return "archive.replace_selected";
         when Remove_Selected_Command => return "archive.remove_selected";
         when Rename_Selected_Command => return "archive.rename_selected";
         when Navigate_Back_Command => return "navigate.back";
         when Navigate_Forward_Command => return "navigate.forward";
         when Navigate_Parent_Command => return "navigate.parent";
         when Navigate_Root_Command => return "navigate.root";
         when Activate_Entry_Command => return "entry.activate";
         when Preview_Entry_Command => return "entry.preview";
         when Extract_Selected_Command => return "extract.selected";
         when Extract_All_Command => return "extract.all";
         when Cancel_Extraction_Command => return "extract.cancel";
         when Verify_Archive_Command => return "archive.verify";
         when Copy_Entry_Path_Command => return "entry.copy_path";
         when Copy_Entry_Information_Command => return "entry.copy_information";
         when Show_Archive_Properties_Command => return "archive.properties";
         when Show_Entry_Properties_Command => return "entry.properties";
         when Select_Grid_View_Command => return "view.grid";
         when Select_Compact_View_Command => return "view.compact";
         when Select_Details_View_Command => return "view.details";
         when Change_Sorting_Command => return "view.sort";
         when Clear_Filter_Command => return "filter.clear";
         when Toggle_Preview_Command => return "preview.toggle";
         when Open_Settings_Command => return "settings.open";
         when Open_Command_Palette_Command => return "palette.open";
         when Quit_Command => return "application.quit";
      end case;
   end Identifier;

   function Name_Key (Id : Command_Id) return String is
   begin
      return "command." & Identifier (Id) & ".name";
   end Name_Key;

   function Description_Key (Id : Command_Id) return String is
   begin
      return "command." & Identifier (Id) & ".description";
   end Description_Key;

   function Unavailable_Key (Id : Command_Id; Model : Archive.Model.Application_Model) return String is
      use type Archive.Model.Lifecycle_State;
      use type Archive.Archives.Capabilities.Entry_Unavailable_Reason;
   begin
      if Is_Enabled (Id, Model) then
         return "";
      end if;

      case Id is
         when No_Command =>
            return "command.unavailable.none";
         when Open_Recent_Archive_Command =>
            return "command.unavailable.no_recent_archives";
         when Close_Archive_Command | Reload_Archive_Command | Save_Archive_As_Command
            | Add_Files_Command | Add_Directory_Command | Extract_All_Command
            | Verify_Archive_Command | Show_Archive_Properties_Command =>
            if not Archive.Model.Has_Open_Archive (Model) then
               return "command.unavailable.no_archive";
            elsif Id in Save_Archive_As_Command | Add_Files_Command | Add_Directory_Command
              and then not Current_Format_Capabilities (Model).Can_Add_Entries
            then
               return "command.unavailable.read_only_archive";
            else
               return "command.unavailable.not_ready";
            end if;
         when Cancel_Extraction_Command =>
            return "command.unavailable.not_ready";
         when Save_Archive_Command =>
            if not Archive.Model.Has_Open_Archive (Model) then
               return "command.unavailable.no_archive";
            else
               return "command.unavailable.no_pending_changes";
            end if;
         when Discard_Changes_Command =>
            if not Archive.Model.Has_Open_Archive (Model) then
               return "command.unavailable.no_archive";
            else
               return "command.unavailable.no_pending_changes";
            end if;
         when Extract_Selected_Command | Replace_Selected_Command | Remove_Selected_Command | Rename_Selected_Command
            | Preview_Entry_Command | Activate_Entry_Command | Copy_Entry_Path_Command
            | Copy_Entry_Information_Command | Show_Entry_Properties_Command =>
            if not Archive.Model.Has_Open_Archive (Model) then
               return "command.unavailable.no_archive";
            elsif not Archive.Model.Has_Actionable_Focused_Entry (Model) then
               return "command.unavailable.no_selection";
            else
               declare
                  Caps : constant Archive.Archives.Capabilities.Entry_Capabilities :=
                    Focused_Capabilities (Model);
               begin
                  case Id is
                     when Extract_Selected_Command =>
                        return Archive.Archives.Capabilities.Unavailable_Key (Caps.Extract_Reason);
                     when Preview_Entry_Command | Activate_Entry_Command =>
                        return Archive.Archives.Capabilities.Unavailable_Key (Caps.Preview_Reason);
                     when Replace_Selected_Command =>
                        if not Current_Format_Capabilities (Model).Can_Replace_Entries then
                           return "command.unavailable.read_only_archive";
                        end if;
                        return Archive.Archives.Capabilities.Unavailable_Key
                          (Archive.Model.Focused_Entry_Capabilities
                             (Model, Archive_Writable => True).Replace_Reason);
                     when Remove_Selected_Command =>
                        if not Current_Format_Capabilities (Model).Can_Remove_Entries then
                           return "command.unavailable.read_only_archive";
                        end if;
                        return Archive.Archives.Capabilities.Unavailable_Key
                          (Archive.Model.Focused_Entry_Capabilities
                             (Model, Archive_Writable => True).Remove_Reason);
                     when Rename_Selected_Command =>
                        if not Current_Format_Capabilities (Model).Can_Rename_Entries then
                           return "command.unavailable.read_only_archive";
                        end if;
                        return Archive.Archives.Capabilities.Unavailable_Key
                          (Archive.Model.Focused_Entry_Capabilities
                             (Model, Archive_Writable => True).Rename_Reason);
                     when others =>
                        return "command.unavailable.no_selection";
                  end case;
               end;
            end if;
         when Clear_Filter_Command =>
            return "command.unavailable.no_filter";
         when others =>
            return "command.unavailable.not_ready";
      end case;
   end Unavailable_Key;

   function Icon_Name (Id : Command_Id) return String is
   begin
      case Id is
         when No_Command => return "circle";
         when Open_Archive_Command => return "folder-open";
         when New_Archive_Command => return "file-plus";
         when Close_Archive_Command => return "x";
         when Reload_Archive_Command => return "refresh-cw";
         when Open_Recent_Archive_Command => return "history";
         when Save_Archive_Command => return "save";
         when Save_Archive_As_Command => return "save-all";
         when Discard_Changes_Command => return "rotate-ccw";
         when Add_Files_Command => return "file-plus-2";
         when Add_Directory_Command => return "folder-plus";
         when Replace_Selected_Command => return "replace";
         when Remove_Selected_Command => return "trash-2";
         when Rename_Selected_Command => return "pencil";
         when Navigate_Back_Command => return "arrow-left";
         when Navigate_Forward_Command => return "arrow-right";
         when Navigate_Parent_Command => return "arrow-up";
         when Navigate_Root_Command => return "home";
         when Activate_Entry_Command => return "corner-down-right";
         when Preview_Entry_Command => return "eye";
         when Extract_Selected_Command => return "archive-restore";
         when Extract_All_Command => return "archive-restore";
         when Cancel_Extraction_Command => return "ban";
         when Verify_Archive_Command => return "shield-check";
         when Copy_Entry_Path_Command => return "copy";
         when Copy_Entry_Information_Command => return "clipboard-list";
         when Show_Archive_Properties_Command => return "info";
         when Show_Entry_Properties_Command => return "info";
         when Select_Grid_View_Command => return "grid-2x2";
         when Select_Compact_View_Command => return "list";
         when Select_Details_View_Command => return "table";
         when Change_Sorting_Command => return "arrow-up-down";
         when Clear_Filter_Command => return "filter-x";
         when Toggle_Preview_Command => return "panel-right";
         when Open_Settings_Command => return "settings";
         when Open_Command_Palette_Command => return "command";
         when Quit_Command => return "log-out";
      end case;
   end Icon_Name;

   function Category_For (Id : Command_Id) return Command_Category is
   begin
      case Id is
         when Open_Archive_Command | New_Archive_Command | Close_Archive_Command
            | Reload_Archive_Command | Open_Recent_Archive_Command | Save_Archive_Command
            | Save_Archive_As_Command | Discard_Changes_Command | Add_Files_Command
            | Add_Directory_Command
            | Extract_Selected_Command | Extract_All_Command | Show_Archive_Properties_Command =>
            return File_Category;
         when Activate_Entry_Command | Preview_Entry_Command | Copy_Entry_Path_Command
            | Copy_Entry_Information_Command | Replace_Selected_Command | Remove_Selected_Command
            | Rename_Selected_Command
            | Show_Entry_Properties_Command =>
            return Edit_Category;
         when Select_Grid_View_Command | Select_Compact_View_Command | Select_Details_View_Command
            | Change_Sorting_Command | Clear_Filter_Command | Toggle_Preview_Command =>
            return View_Category;
         when Navigate_Back_Command | Navigate_Forward_Command | Navigate_Parent_Command
            | Navigate_Root_Command =>
            return Navigate_Category;
         when Cancel_Extraction_Command | Verify_Archive_Command =>
            return Tools_Category;
         when Open_Settings_Command =>
            return Settings_Category;
         when No_Command | Open_Command_Palette_Command | Quit_Command =>
            return Application_Category;
      end case;
   end Category_For;

   function Shortcut_For (Id : Command_Id) return Shortcut is
   begin
      case Id is
         when Open_Archive_Command => return Ctrl (Guikit.Input.Key_O);
         when New_Archive_Command => return Ctrl (Guikit.Input.Key_N);
         when Close_Archive_Command => return Ctrl (Guikit.Input.Key_W);
         when Save_Archive_Command => return Ctrl (Guikit.Input.Key_S);
         when Discard_Changes_Command => return Ctrl (Guikit.Input.Key_D);
         when Reload_Archive_Command => return (True, Guikit.Input.Key_F5, Guikit.Input.No_Modifiers);
         when Extract_Selected_Command => return Ctrl (Guikit.Input.Key_E);
         when Verify_Archive_Command => return Ctrl (Guikit.Input.Key_R);
         when Open_Command_Palette_Command => return Ctrl (Guikit.Input.Key_P);
         when Quit_Command => return Ctrl (Guikit.Input.Key_Q);
         when others => return (Present => False, Key => Guikit.Input.Key_Unknown,
                                Modifiers => Guikit.Input.No_Modifiers);
      end case;
   end Shortcut_For;

   function Descriptor
     (Id    : Command_Id;
      Model : Archive.Model.Application_Model)
      return Command_Descriptor
   is
   begin
      return
        (Id              => Id,
         Identifier      => Bounded (Identifier (Id)),
         Name_Key        => Bounded (Name_Key (Id)),
         Description_Key => Bounded (Description_Key (Id)),
         Unavailable_Key => Bounded (Unavailable_Key (Id, Model)),
         Icon_Name       => Bounded (Icon_Name (Id)),
         Category        => Category_For (Id),
         Default_Shortcut => Shortcut_For (Id),
         Enabled         => Is_Enabled (Id, Model));
   end Descriptor;

   function Command_Count return Natural is
   begin
      return Registered_Command_Id'Pos (Registered_Command_Id'Last)
        - Registered_Command_Id'Pos (Registered_Command_Id'First) + 1;
   end Command_Count;

   function Contains (Identifier_Text : String) return Boolean is
   begin
      return Id_For_Identifier (Identifier_Text) /= No_Command;
   end Contains;

   function Id_For_Identifier (Identifier_Text : String) return Command_Id is
   begin
      for Id in Registered_Command_Id loop
         if Identifier (Id) = Identifier_Text then
            return Id;
         end if;
      end loop;
      return No_Command;
   end Id_For_Identifier;

   function Is_Enabled (Id : Command_Id; Model : Archive.Model.Application_Model) return Boolean is
      use type Archive.Model.Lifecycle_State;
      use type Archive.Model.Extraction_State;
      Caps : constant Archive.Archives.Formats.Format_Capabilities := Current_Format_Capabilities (Model);
      Entry_Caps : constant Archive.Archives.Capabilities.Entry_Capabilities :=
        Focused_Capabilities (Model);
   begin
      case Id is
         when No_Command => return False;
         when Open_Archive_Command | New_Archive_Command | Open_Settings_Command
            | Open_Command_Palette_Command | Quit_Command =>
            return True;
         when Open_Recent_Archive_Command =>
            return Archive.Model.Has_Recent_Archives (Model);
         when Close_Archive_Command | Reload_Archive_Command | Extract_All_Command
            | Verify_Archive_Command | Show_Archive_Properties_Command =>
            return Archive.Model.Has_Open_Archive (Model);
         when Save_Archive_As_Command | Add_Files_Command | Add_Directory_Command =>
            return Archive.Model.Has_Open_Archive (Model) and then Caps.Can_Add_Entries;
         when Cancel_Extraction_Command =>
            return Archive.Model.Extraction_Phase (Model) = Archive.Model.Extraction_Planned;
         when Save_Archive_Command =>
            return Archive.Model.Has_Open_Archive (Model)
              and then Archive.Model.Has_Saveable_Write_Plan (Model);
         when Discard_Changes_Command =>
            return Archive.Model.Has_Open_Archive (Model)
              and then Archive.Model.Has_Pending_Writes (Model);
         when Navigate_Back_Command =>
            return Archive.Model.Can_Navigate_Back (Model);
         when Navigate_Forward_Command =>
            return Archive.Model.Can_Navigate_Forward (Model);
         when Navigate_Parent_Command | Navigate_Root_Command =>
            return Archive.Model.Has_Open_Archive (Model);
         when Extract_Selected_Command =>
            return Archive.Model.Has_Actionable_Focused_Entry (Model)
              and then Entry_Caps.Can_Extract;
         when Preview_Entry_Command | Activate_Entry_Command =>
            return Archive.Model.Has_Actionable_Focused_Entry (Model)
              and then Entry_Caps.Can_Preview;
         when Copy_Entry_Path_Command | Copy_Entry_Information_Command | Show_Entry_Properties_Command =>
            return Archive.Model.Has_Actionable_Focused_Entry (Model);
         when Remove_Selected_Command =>
            return Archive.Model.Has_Actionable_Focused_Entry (Model)
              and then Caps.Can_Remove_Entries
              and then Archive.Model.Focused_Entry_Capabilities
                (Model, Archive_Writable => True).Can_Remove;
         when Replace_Selected_Command =>
            return Archive.Model.Has_Actionable_Focused_Entry (Model)
              and then Caps.Can_Replace_Entries
              and then Archive.Model.Focused_Entry_Capabilities
                (Model, Archive_Writable => True).Can_Replace;
         when Rename_Selected_Command =>
            return Archive.Model.Has_Actionable_Focused_Entry (Model)
              and then Caps.Can_Rename_Entries
              and then Archive.Model.Focused_Entry_Capabilities
                (Model, Archive_Writable => True).Can_Rename;
         when Clear_Filter_Command =>
            return Archive.Model.Filter_Text (Model) /= "";
         when others =>
            return Archive.Model.Has_Open_Archive (Model);
      end case;
   end Is_Enabled;

   procedure Execute (Id : Command_Id; Model : in out Archive.Model.Application_Model) is
   begin
      if not Is_Enabled (Id, Model) then
         Archive.Model.Publish_Notification
           (Model, Archive.Model.Warning_Notification, "ui.notification.command_unavailable");
         Archive.Model.Set_Last_Command (Model, Id_Executed => Identifier (Id), Accepted => False);
         return;
      end if;

      case Id is
         when Open_Archive_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Open_Archive_Dialog);
         when New_Archive_Command =>
            Archive.Model.Create_New_Archive (Model);
         when Reload_Archive_Command =>
            Archive.Model.Reload_Archive (Model);
         when Open_Recent_Archive_Command =>
            Archive.Model.Request_Open_Recent (Model);
         when Select_Grid_View_Command =>
            Archive.Model.Set_View_Mode (Model, Archive.Types.Grid_View);
         when Select_Compact_View_Command =>
            Archive.Model.Set_View_Mode (Model, Archive.Types.Compact_View);
         when Select_Details_View_Command =>
            Archive.Model.Set_View_Mode (Model, Archive.Types.Details_View);
         when Clear_Filter_Command =>
            Archive.Model.Set_Filter (Model, "");
         when Change_Sorting_Command =>
            Archive.Model.Toggle_Sort_Direction (Model);
         when Toggle_Preview_Command =>
            Archive.Model.Set_Preview_Visible (Model, not Archive.Model.Preview_Visible (Model));
         when Open_Command_Palette_Command =>
            Archive.Model.Open_Command_Palette (Model);
         when Open_Settings_Command =>
            Archive.Model.Open_Settings (Model);
         when Close_Archive_Command =>
            Archive.Model.Request_Close_Archive (Model);
         when Navigate_Back_Command =>
            Archive.Model.Navigate_Back (Model);
         when Navigate_Forward_Command =>
            Archive.Model.Navigate_Forward (Model);
         when Navigate_Parent_Command =>
            Archive.Model.Navigate_Parent (Model);
         when Navigate_Root_Command =>
            Archive.Model.Navigate_Root (Model);
         when Verify_Archive_Command =>
            Archive.Model.Start_Verification (Model);
         when Show_Archive_Properties_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Archive_Properties_Dialog);
         when Show_Entry_Properties_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Entry_Properties_Dialog);
         when Cancel_Extraction_Command =>
            Archive.Model.Cancel_Extraction (Model);
         when Activate_Entry_Command =>
            Archive.Model.Activate_Focused_Entry (Model);
         when Preview_Entry_Command =>
            Archive.Model.Start_Preview (Model, Archive.Model.Focused_Entry (Model));
         when Copy_Entry_Path_Command =>
            Archive.Model.Copy_Focused_Entry_Path (Model);
         when Copy_Entry_Information_Command =>
            Archive.Model.Copy_Focused_Entry_Information (Model);
         when Add_Files_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Add_Files_Dialog);
         when Add_Directory_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Add_Directory_Dialog);
         when Replace_Selected_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Replace_File_Dialog);
         when Rename_Selected_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Rename_Entry_Dialog);
         when Remove_Selected_Command =>
            Archive.Model.Plan_Selected_Removal (Model);
         when Save_Archive_Command =>
            if Archive.Model.Source_Path (Model) = "" then
               Archive.Model.Open_Dialog (Model, Archive.Model.Save_As_Dialog);
            else
               declare
                  Result : constant Archive.Writes.Service.Save_Result :=
                    Archive.Writes.Service.Save (Model);
               begin
                  pragma Unreferenced (Result);
                  null;
               end;
            end if;
         when Save_Archive_As_Command =>
            Archive.Model.Open_Dialog (Model, Archive.Model.Save_As_Dialog);
         when Discard_Changes_Command =>
            Archive.Model.Clear_Pending_Writes (Model);
         when Extract_Selected_Command =>
            Archive.Model.Plan_Selected_Extraction (Model);
            Archive.Model.Open_Dialog (Model, Archive.Model.Extract_Destination_Dialog);
         when Extract_All_Command =>
            Archive.Model.Plan_All_Extraction (Model);
            Archive.Model.Open_Dialog (Model, Archive.Model.Extract_Destination_Dialog);
         when Quit_Command =>
            Archive.Model.Request_Quit (Model);
         when others =>
            null;
      end case;
      Archive.Model.Set_Last_Command (Model, Id_Executed => Identifier (Id), Accepted => True);
   end Execute;
end Archive.Commands;
