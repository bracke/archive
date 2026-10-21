with Ada.Directories;
with Ada.Strings.Unbounded;

with Guikit.Command_Palette;
with Guikit.Draw;

with Archive.Localization;

package body Archive.GUI_Runtime is
   use Ada.Strings.Unbounded;
   use type Archive.Commands.Command_Id;
   use type Archive.Model.Dialog_Kind;
   use type Archive.Model.Overlay_Kind;
   use type Archive.Extraction.Service.Extract_Status;
   use type Archive.Writes.Service.Save_Status;

   function Failure (Key : String) return Validation_Result is
   begin
      return (Ready => False, Reason_Key => To_Unbounded_String (Key));
   end Failure;

   procedure Initialize
     (Runtime : out Runtime_State;
      Locale  : String := "en";
      Width   : Natural := 1280;
      Height  : Natural := 800)
   is
   begin
      Runtime := (others => <>);
      Archive.Model.Initialize (Runtime.App_Model);
      Runtime.Config :=
        (Width       => Width,
         Height      => Height,
         Locale      => To_Unbounded_String (Locale),
         Line_Height => Archive.UI.Default_Line_Height);
      Runtime.Open_Coord := new Archive.Operations.Opening.Coordinator;
      Runtime.Started := True;
   end Initialize;

   function Snapshot (Runtime : Runtime_State) return Archive.UI.Shell_Snapshot is
   begin
      return Archive.UI.Build_Shell (Runtime.App_Model, Runtime.Config);
   end Snapshot;

   function Render_Frame (Runtime : Runtime_State) return Archive.GUI_Frame.Frame is
   begin
      return Archive.GUI_Frame.Build (Snapshot (Runtime));
   end Render_Frame;

   function Model (Runtime : Runtime_State) return Archive.Model.Application_Model is
   begin
      return Runtime.App_Model;
   end Model;

   function Revision (Runtime : Runtime_State) return Archive.Types.Generation_Id is
   begin
      return Archive.Model.Revision (Runtime.App_Model);
   end Revision;

   procedure Start_Open_Archive
     (Runtime : in out Runtime_State;
      Path    : String)
   is
   begin
      if Runtime.Open_Coord = null then
         Runtime.Open_Coord := new Archive.Operations.Opening.Coordinator;
      end if;
      Archive.Operations.Opening.Start_Open (Runtime.Open_Coord.all, Runtime.App_Model, Path);
   end Start_Open_Archive;

   function Drain_Operations
     (Runtime : in out Runtime_State)
      return Archive.Operations.Opening.Drain_Result
   is
      Result : Archive.Operations.Opening.Drain_Result;
   begin
      if Runtime.Open_Coord = null then
         return Result;
      end if;
      Archive.Operations.Opening.Drain_Events (Runtime.Open_Coord.all, Runtime.App_Model, Result);
      return Result;
   end Drain_Operations;

   function Open_Operation_Status
     (Runtime : Runtime_State)
      return Archive.Operations.Opening.Operation_Status
   is
   begin
      if Runtime.Open_Coord = null then
         return Archive.Operations.Opening.Operation_Idle;
      else
         return Archive.Operations.Opening.Last_Status (Runtime.Open_Coord.all);
      end if;
   end Open_Operation_Status;

   function Validate (Runtime : Runtime_State) return Validation_Result is
      Shell : constant Archive.UI.Shell_Snapshot := Snapshot (Runtime);
      Frame_Check : constant Archive.GUI_Frame.Frame_Validation :=
        Archive.GUI_Frame.Validate (Archive.GUI_Frame.Build (Shell));
   begin
      if not Runtime.Started then
         return Failure ("runtime.not_started");
      elsif Length (Shell.Title) = 0 then
         return Failure ("runtime.missing_title");
      elsif Shell.Layout.Content_W = 0 or else Shell.Layout.Content_H = 0 then
         return Failure ("runtime.invalid_content_layout");
      elsif Natural (Shell.Menus.Sections.Length) = 0 then
         return Failure ("runtime.missing_menus");
      elsif Natural (Shell.Toolbar.Commands.Length) = 0 then
         return Failure ("runtime.missing_toolbar");
      elsif not Shell.Content_View.Virtualized then
         return Failure ("runtime.content_not_virtualized");
      elsif Length (Shell.Status_Bar.Accessible_Name) = 0 then
         return Failure ("runtime.missing_status_accessibility");
      elsif not Frame_Check.Valid then
         return Failure ("runtime.invalid_frame");
      else
         return (Ready => True, Reason_Key => To_Unbounded_String ("runtime.ready"));
      end if;
   end Validate;

   procedure Resize
     (Runtime : in out Runtime_State;
      Width   : Natural;
      Height  : Natural)
   is
   begin
      Runtime.Config.Width := Width;
      Runtime.Config.Height := Height;
   end Resize;

   function Dispatch_Command
     (Runtime : in out Runtime_State;
      Command : Archive.Commands.Command_Id;
      Source  : Archive.UI.Dispatch_Source)
      return Archive.UI.Dispatch_Result
   is
   begin
      return Archive.UI.Dispatch_Command (Runtime.App_Model, Command, Source);
   end Dispatch_Command;

   function Dispatch_Shortcut
     (Runtime   : in out Runtime_State;
      Key       : Guikit.Input.Key_Code;
      Modifiers : Guikit.Input.Modifier_Set)
      return Archive.UI.Dispatch_Result
   is
   begin
      return Archive.UI.Dispatch_Shortcut (Runtime.App_Model, Key, Modifiers);
   end Dispatch_Shortcut;

   function Execute_Palette_Command
     (Runtime    : in out Runtime_State;
      Identifier : String)
      return Archive.UI.Dispatch_Result
   is
      Id : constant Archive.Commands.Command_Id :=
        Archive.Commands.Id_For_Identifier (Identifier);
      Result : Archive.UI.Dispatch_Result;
   begin
      if Id = Archive.Commands.No_Command then
         Archive.Model.Publish_Notification
           (Runtime.App_Model,
            Archive.Model.Warning_Notification,
            "ui.notification.command_unavailable");
         return
           (Matched  => False,
            Accepted => False,
            Command  => Archive.Commands.No_Command);
      end if;

      Result := Archive.UI.Dispatch_Command
        (Runtime.App_Model, Id, Archive.UI.Command_Palette_Source);
      if Result.Accepted then
         Archive.Model.Close_Overlay (Runtime.App_Model);
      end if;
      return Result;
   end Execute_Palette_Command;

   procedure Complete_Open_Dialog
     (Runtime : in out Runtime_State;
      Path    : String)
   is
   begin
      Archive.Model.Close_Dialog (Runtime.App_Model);
      Start_Open_Archive (Runtime, Path);
   end Complete_Open_Dialog;

   procedure Complete_Add_File_Dialog
     (Runtime     : in out Runtime_State;
      Host_Source : String;
      Target_Path : String)
   is
   begin
      Archive.Model.Plan_Add_File (Runtime.App_Model, Host_Source, Target_Path);
      Archive.Model.Close_Dialog (Runtime.App_Model);
   end Complete_Add_File_Dialog;

   procedure Complete_Add_Directory_Dialog
     (Runtime     : in out Runtime_State;
      Host_Source : String;
      Target_Path : String)
   is
   begin
      Archive.Model.Plan_Add_Directory (Runtime.App_Model, Host_Source, Target_Path);
      Archive.Model.Close_Dialog (Runtime.App_Model);
   end Complete_Add_Directory_Dialog;

   procedure Complete_Replace_File_Dialog
     (Runtime     : in out Runtime_State;
      Host_Source : String)
   is
   begin
      Archive.Model.Plan_Selected_Replacement (Runtime.App_Model, Host_Source);
      Archive.Model.Close_Dialog (Runtime.App_Model);
   end Complete_Replace_File_Dialog;

   procedure Complete_Rename_Dialog
     (Runtime          : in out Runtime_State;
      Replacement_Path : String)
   is
   begin
      Archive.Model.Plan_Selected_Rename (Runtime.App_Model, Replacement_Path);
      Archive.Model.Close_Dialog (Runtime.App_Model);
   end Complete_Rename_Dialog;

   function Complete_Save_As_Dialog
     (Runtime     : in out Runtime_State;
      Destination : String;
      Method      : Archive.Writes.Dispatch.Zip_Method :=
        Archive.Writes.Dispatch.Zip_Deflate_Method;
      Overwrite   : Boolean := False)
      return Archive.Writes.Service.Save_Result
   is
      Result : constant Archive.Writes.Service.Save_Result :=
        Archive.Writes.Service.Save_As
          (Runtime.App_Model, Destination, Method, Overwrite);
   begin
      if Result.Status = Archive.Writes.Service.Save_Completed then
         Archive.Model.Close_Dialog (Runtime.App_Model);
      end if;
      return Result;
   end Complete_Save_As_Dialog;

   function Complete_Extraction_Dialog
     (Runtime          : in out Runtime_State;
      Destination_Root : String;
      Overwrite        : Boolean := False;
      Check_Identity   : Boolean := True)
      return Archive.Extraction.Service.Extract_Result
   is
      Result : constant Archive.Extraction.Service.Extract_Result :=
        Archive.Extraction.Service.Extract_Planned
          (Runtime.App_Model, Destination_Root, Overwrite, Check_Identity);
   begin
      if Result.Status = Archive.Extraction.Service.Extract_Completed then
         Archive.Model.Close_Dialog (Runtime.App_Model);
      end if;
      return Result;
   end Complete_Extraction_Dialog;

   --  Text without its last UTF-8 character.
   function Without_Last (Text : String) return String is
      Last : Natural := Text'Last;
   begin
      if Text'Length = 0 then
         return Text;
      end if;
      while Last > Text'First
        and then Character'Pos (Text (Last)) in 16#80# .. 16#BF#
      loop
         Last := Last - 1;
      end loop;
      return Text (Text'First .. Last - 1);
   end Without_Last;

   --  Answer the open path dialog with the typed path.
   procedure Commit_Dialog (Runtime : in out Runtime_State) is
      Path : constant String := Archive.Model.Dialog_Text (Runtime.App_Model);

      function Leaf return String is
        (if Ada.Directories.Simple_Name (Path) = "" then Path else Ada.Directories.Simple_Name (Path));
   begin
      if Path = "" then
         return;
      end if;
      case Archive.Model.Active_Dialog (Runtime.App_Model) is
         when Archive.Model.Open_Archive_Dialog =>
            Complete_Open_Dialog (Runtime, Path);
         when Archive.Model.Add_Files_Dialog =>
            Complete_Add_File_Dialog (Runtime, Path, Leaf);
         when Archive.Model.Add_Directory_Dialog =>
            Complete_Add_Directory_Dialog (Runtime, Path, Leaf);
         when Archive.Model.Replace_File_Dialog =>
            Complete_Replace_File_Dialog (Runtime, Path);
         when Archive.Model.Rename_Entry_Dialog =>
            Complete_Rename_Dialog (Runtime, Path);
         when Archive.Model.Extract_Destination_Dialog =>
            declare
               Ignored : constant Archive.Extraction.Service.Extract_Result :=
                 Complete_Extraction_Dialog (Runtime, Path);
            begin
               null;  --  the model reports how it went
            end;
         when Archive.Model.Save_As_Dialog =>
            declare
               Ignored : constant Archive.Writes.Service.Save_Result :=
                 Complete_Save_As_Dialog (Runtime, Path);
            begin
               null;  --  the model reports how it went
            end;
         when others =>
            null;
      end case;
   exception
      when Ada.Directories.Name_Error =>
         null;  --  not a path at all; the dialog stays open to be corrected
   end Commit_Dialog;

   --  Run the palette's highlighted command, as the frame shows it.
   procedure Run_Palette_Selection (Runtime : in out Runtime_State) is
      Palette : constant Guikit.Command_Palette.Palette :=
        Archive.GUI_Frame.Command_Palette_For (Snapshot (Runtime));
      Results : constant Guikit.Command_Palette.Command_Vectors.Vector :=
        Guikit.Command_Palette.Results (Palette);
      Index   : constant Natural := Guikit.Command_Palette.Selected_Index (Palette);
   begin
      if Index in 1 .. Natural (Results.Length) then
         declare
            Ignored : constant Archive.UI.Dispatch_Result :=
              Execute_Palette_Command (Runtime, To_String (Results.Element (Index).Identifier));
         begin
            null;
         end;
      end if;
   end Run_Palette_Selection;

   procedure Key_Pressed
     (Runtime   : in out Runtime_State;
      Key       : Guikit.Input.Key_Code;
      Modifiers : Guikit.Input.Modifier_Set)
   is
      use type Guikit.Input.Key_Code;
      use type Guikit.Input.Modifier_Set;
      Plain   : constant Boolean := Modifiers = Guikit.Input.No_Modifiers;
      Ignored : Archive.UI.Dispatch_Result;
   begin
      if Archive.UI.Dialog_Takes_Path (Archive.Model.Active_Dialog (Runtime.App_Model)) and then Plain then
         if Key = Guikit.Input.Key_Backspace then
            Archive.Model.Set_Dialog_Text
              (Runtime.App_Model, Without_Last (Archive.Model.Dialog_Text (Runtime.App_Model)));
            return;
         elsif Key = Guikit.Input.Key_Return then
            Commit_Dialog (Runtime);
            return;
         end if;
      elsif Archive.Model.Active_Overlay (Runtime.App_Model) = Archive.Model.Command_Palette_Overlay
        and then Plain
      then
         case Key is
            when Guikit.Input.Key_Backspace =>
               Archive.Model.Set_Command_Palette_Filter
                 (Runtime.App_Model, Without_Last (Archive.Model.Command_Palette_Filter (Runtime.App_Model)));
               return;
            when Guikit.Input.Key_Up =>
               Archive.Model.Move_Command_Palette_Selection (Runtime.App_Model, -1);
               return;
            when Guikit.Input.Key_Down =>
               Archive.Model.Move_Command_Palette_Selection (Runtime.App_Model, 1);
               return;
            when Guikit.Input.Key_Return =>
               Run_Palette_Selection (Runtime);
               return;
            when others =>
               null;
         end case;
      end if;
      Ignored := Dispatch_Shortcut (Runtime, Key, Modifiers);
   end Key_Pressed;

   procedure Text_Typed
     (Runtime : in out Runtime_State;
      Text    : String) is
   begin
      if Archive.UI.Dialog_Takes_Path (Archive.Model.Active_Dialog (Runtime.App_Model)) then
         Archive.Model.Set_Dialog_Text (Runtime.App_Model, Archive.Model.Dialog_Text (Runtime.App_Model) & Text);
      elsif Archive.Model.Active_Overlay (Runtime.App_Model) = Archive.Model.Command_Palette_Overlay then
         Archive.Model.Set_Command_Palette_Filter
           (Runtime.App_Model, Archive.Model.Command_Palette_Filter (Runtime.App_Model) & Text);
      end if;
   end Text_Typed;

   procedure Clicked
     (Runtime : in out Runtime_State;
      X, Y    : Integer)
   is
      Shell : constant Archive.UI.Shell_Snapshot := Snapshot (Runtime);
   begin
      if Archive.Model.Active_Dialog (Runtime.App_Model) /= Archive.Model.No_Dialog then
         return;  --  a modal dialog answers to the keyboard
      elsif Archive.Model.Active_Overlay (Runtime.App_Model) = Archive.Model.Command_Palette_Overlay then
         declare
            Palette : Guikit.Command_Palette.Palette := Archive.GUI_Frame.Command_Palette_For (Shell);
            Rects   : Guikit.Draw.Rectangle_Command_Vectors.Vector;
            Text    : Guikit.Draw.Text_Command_Vectors.Vector;
            Icons   : Guikit.Draw.Icon_Command_Vectors.Vector;
            Nodes   : Guikit.Draw.Accessibility_Node_Vectors.Vector;
            Box_X, Box_Y, Box_W, Box_H : Natural;
         begin
            --  Lay the palette out as drawn, then let it hit-test the click.
            Archive.GUI_Frame.Command_Palette_Box
              (Runtime.Config.Width, Runtime.Config.Height, Box_X, Box_Y, Box_W, Box_H);
            Guikit.Command_Palette.Build_Frame
              (Palette, Box_X, Box_Y, Box_W, Box_H, Runtime.Config.Width, Runtime.Config.Height,
               True, -1, -1, Rects, Text, Icons, Nodes);
            if Guikit.Command_Palette.Click (Palette, X, Y) then
               declare
                  Results : constant Guikit.Command_Palette.Command_Vectors.Vector :=
                    Guikit.Command_Palette.Results (Palette);
                  Index   : constant Natural := Guikit.Command_Palette.Selected_Index (Palette);
               begin
                  if Index in 1 .. Natural (Results.Length) then
                     declare
                        Ignored : constant Archive.UI.Dispatch_Result :=
                          Execute_Palette_Command (Runtime, To_String (Results.Element (Index).Identifier));
                     begin
                        null;
                     end;
                  end if;
               end;
            end if;
         end;
         return;
      end if;

      for Button of Archive.GUI_Frame.Toolbar_Buttons (Shell, Runtime.Config.Width) loop
         if X >= Button.X and then X < Button.X + Button.Width
           and then Y >= Button.Y and then Y < Button.Y + Button.Height
         then
            if Button.Enabled then
               declare
                  Ignored : constant Archive.UI.Dispatch_Result :=
                    Dispatch_Command (Runtime, Button.Command, Archive.UI.Toolbar_Source);
               begin
                  null;
               end;
            end if;
            return;
         end if;
      end loop;
   end Clicked;

   procedure Request_Close (Runtime : in out Runtime_State) is
   begin
      Archive.Model.Request_Quit (Runtime.App_Model);
   end Request_Close;

   function Runtime_Report (Runtime : Runtime_State) return String is
      Shell      : constant Archive.UI.Shell_Snapshot := Snapshot (Runtime);
      Validation : constant Validation_Result := Validate (Runtime);
      Frame      : constant Archive.GUI_Frame.Frame := Render_Frame (Runtime);
      Frame_Check : constant Archive.GUI_Frame.Frame_Validation := Archive.GUI_Frame.Validate (Frame);
   begin
      return "archive gui runtime: ready=" & Boolean'Image (Validation.Ready)
        & " reason=" & To_String (Validation.Reason_Key)
        & " title=" & To_String (Shell.Title)
        & " open_status=" & Archive.Operations.Opening.Operation_Status'Image
          (Open_Operation_Status (Runtime))
        & " source=" & To_String (Shell.Source.Path)
        & " recent=" & Natural'Image (Shell.Settings.Recent_Count)
        & " menus=" & Natural'Image (Natural (Shell.Menus.Sections.Length))
        & " toolbar=" & Natural'Image (Natural (Shell.Toolbar.Commands.Length))
        & " status=" & To_String (Shell.Status_Text)
        & " backend=" & Archive.Localization.Text ("runtime.backend.headless", To_String (Runtime.Config.Locale))
        & " rectangles=" & Natural'Image (Frame_Check.Rectangle_Count)
        & " text=" & Natural'Image (Frame_Check.Text_Count)
        & " accessibility=" & Natural'Image (Frame_Check.Accessibility_Count)
        & " vertices=" & Natural'Image (Frame_Check.Vertex_Count);
   end Runtime_Report;
end Archive.GUI_Runtime;
