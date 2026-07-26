with Ada.Strings.Unbounded;

with Guikit.Vulkan;

package Archive.Application.Windows is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   Desktop_Error : exception;

   type Desktop_Capabilities is record
      Display_Available       : Boolean := False;
      Vulkan_Available        : Boolean := False;
      Headless_Rendering      : Boolean := True;
      Live_Window_Smoke_Ready : Boolean := False;
      Event_Loop_Model        : Boolean := True;
      Resize_Runtime_Model    : Boolean := True;
      Vulkan_Presentation     : Boolean := True;
   end record;

   type Live_Smoke_Plan is record
      Can_Run          : Boolean := False;
      Needs_Display    : Boolean := True;
      Needs_Vulkan     : Boolean := True;
      Width            : Natural := 1024;
      Height           : Natural := 768;
      Frame_Count      : Positive := 1;
      Input_Poll_Count : Positive := 1;
      Resize_Width     : Natural := 800;
      Resize_Height    : Natural := 600;
      Reason_Key       : UString;
   end record;

   type Live_Smoke_Result is record
      Attempted        : Boolean := False;
      Window_Created   : Boolean := False;
      Frame_Rendered   : Boolean := False;
      Frames_Attempted : Natural := 0;
      Frames_Presented : Natural := 0;
      Input_Polled     : Boolean := False;
      Resize_Applied   : Boolean := False;
      Runtime_Validated : Boolean := False;
      Closed_Cleanly   : Boolean := False;
      Skipped_By_Plan  : Boolean := True;
      Last_Status      : Guikit.Vulkan.Vulkan_Status :=
        Guikit.Vulkan.Vulkan_Not_Initialized;
      Error_Key        : UString;
   end record;

   function Live_Display_Available return Boolean;
   function Vulkan_Runtime_Available return Boolean;
   function Runtime_Capabilities return Desktop_Capabilities;
   function Default_Live_Smoke_Plan return Live_Smoke_Plan;
   function Live_Smoke (Plan : Live_Smoke_Plan := Default_Live_Smoke_Plan) return Live_Smoke_Result;
   function Live_Smoke_Report return String;

   procedure Run (Initial_Path : String := "");
end Archive.Application.Windows;
