with Guikit.Input;

with Archive.Commands;
with Archive.Extraction.Service;
with Archive.GUI_Frame;
with Archive.Model;
with Archive.Operations.Opening;
with Archive.UI;
with Archive.Types;
with Archive.Writes.Dispatch;
with Archive.Writes.Service;

package Archive.GUI_Runtime is
   type Runtime_State is private;

   type Validation_Result is record
      Ready : Boolean := False;
      Reason_Key : Archive.Types.UString;
   end record;

   procedure Initialize
     (Runtime : out Runtime_State;
      Locale  : String := "en";
      Width   : Natural := 1280;
      Height  : Natural := 800);

   function Snapshot (Runtime : Runtime_State) return Archive.UI.Shell_Snapshot;
   function Render_Frame (Runtime : Runtime_State) return Archive.GUI_Frame.Frame;
   function Model (Runtime : Runtime_State) return Archive.Model.Application_Model;
   procedure Start_Open_Archive
     (Runtime : in out Runtime_State;
      Path    : String);
   function Drain_Operations
     (Runtime : in out Runtime_State)
      return Archive.Operations.Opening.Drain_Result;
   function Open_Operation_Status
     (Runtime : Runtime_State)
      return Archive.Operations.Opening.Operation_Status;
   function Validate (Runtime : Runtime_State) return Validation_Result;

   procedure Resize
     (Runtime : in out Runtime_State;
      Width   : Natural;
      Height  : Natural);

   function Dispatch_Command
     (Runtime : in out Runtime_State;
      Command : Archive.Commands.Command_Id;
      Source  : Archive.UI.Dispatch_Source)
      return Archive.UI.Dispatch_Result;

   function Dispatch_Shortcut
     (Runtime   : in out Runtime_State;
      Key       : Guikit.Input.Key_Code;
      Modifiers : Guikit.Input.Modifier_Set)
      return Archive.UI.Dispatch_Result;

   function Execute_Palette_Command
     (Runtime    : in out Runtime_State;
      Identifier : String)
      return Archive.UI.Dispatch_Result;

   procedure Complete_Open_Dialog
     (Runtime : in out Runtime_State;
      Path    : String);

   procedure Complete_Add_File_Dialog
     (Runtime     : in out Runtime_State;
      Host_Source : String;
      Target_Path : String);

   procedure Complete_Add_Directory_Dialog
     (Runtime     : in out Runtime_State;
      Host_Source : String;
      Target_Path : String);

   procedure Complete_Replace_File_Dialog
     (Runtime     : in out Runtime_State;
      Host_Source : String);

   procedure Complete_Rename_Dialog
     (Runtime          : in out Runtime_State;
      Replacement_Path : String);

   function Complete_Save_As_Dialog
     (Runtime     : in out Runtime_State;
      Destination : String;
      Method      : Archive.Writes.Dispatch.Zip_Method :=
        Archive.Writes.Dispatch.Zip_Deflate_Method;
      Overwrite   : Boolean := False)
      return Archive.Writes.Service.Save_Result;

   function Complete_Extraction_Dialog
     (Runtime          : in out Runtime_State;
      Destination_Root : String;
      Overwrite        : Boolean := False;
      Check_Identity   : Boolean := True)
      return Archive.Extraction.Service.Extract_Result;

   procedure Request_Close (Runtime : in out Runtime_State);
   function Runtime_Report (Runtime : Runtime_State) return String;

private
   type Open_Coordinator_Access is access Archive.Operations.Opening.Coordinator;

   type Runtime_State is record
      App_Model : Archive.Model.Application_Model;
      Config    : Archive.UI.Shell_Configuration;
      Open_Coord : Open_Coordinator_Access;
      Started   : Boolean := False;
   end record;
end Archive.GUI_Runtime;
