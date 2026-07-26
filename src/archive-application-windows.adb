with Ada.Environment_Variables;
with Ada.Unchecked_Deallocation;

with Glfw;
with Glfw.Windows;
with Glfw.Windows.Vulkan;

with Archive.GUI_Frame;
with Archive.GUI_Runtime;
with Archive.Localization;
with Archive.Operations.Opening;

package body Archive.Application.Windows is
   use Ada.Strings.Unbounded;
   use type Glfw.Size;
   use type Guikit.Vulkan.Vulkan_Status;

   Event_Wait_Timeout : constant Duration := 0.016;

   type Desktop_Window is new Glfw.Windows.Window with null record;
   type Window_Access is access all Desktop_Window;

   procedure Free_Window is new Ada.Unchecked_Deallocation
     (Object => Desktop_Window,
      Name   => Window_Access);

   function As_Window (Handle : Window_Access) return Glfw.Windows.Window_Reference is
   begin
      return Glfw.Windows.Window_Reference (Handle);
   end As_Window;

   function Safe_Environment_Value (Name : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name) then
         return Ada.Environment_Variables.Value (Name);
      end if;
      return "";
   exception
      when others =>
         return "";
   end Safe_Environment_Value;

   function Live_Display_Available return Boolean is
      Display         : constant String := Safe_Environment_Value ("DISPLAY");
      Wayland_Display : constant String := Safe_Environment_Value ("WAYLAND_DISPLAY");
      Comspec         : constant String := Safe_Environment_Value ("COMSPEC");
   begin
      return Display /= "" or else Wayland_Display /= "" or else Comspec /= "";
   end Live_Display_Available;

   function Vulkan_Runtime_Available return Boolean is
      Initialized : Boolean := False;
   begin
      Glfw.Init;
      Initialized := True;
      declare
         Supported : constant Boolean := Glfw.Windows.Vulkan.Supported;
      begin
         Glfw.Shutdown;
         return Supported;
      end;
   exception
      when others =>
         if Initialized then
            Glfw.Shutdown;
         end if;
         return False;
   end Vulkan_Runtime_Available;

   function Runtime_Capabilities return Desktop_Capabilities is
      Display : constant Boolean := Live_Display_Available;
      Vulkan  : constant Boolean := Vulkan_Runtime_Available;
   begin
      return
        (Display_Available       => Display,
         Vulkan_Available        => Vulkan,
         Headless_Rendering      => True,
         Live_Window_Smoke_Ready => Display and then Vulkan,
         Event_Loop_Model        => True,
         Resize_Runtime_Model    => True,
         Vulkan_Presentation     => True);
   end Runtime_Capabilities;

   function Default_Live_Smoke_Plan return Live_Smoke_Plan is
      Caps : constant Desktop_Capabilities := Runtime_Capabilities;
   begin
      return
        (Can_Run          => Caps.Live_Window_Smoke_Ready,
         Needs_Display    => True,
         Needs_Vulkan     => True,
         Width            => 1024,
         Height           => 768,
         Frame_Count      => 1,
         Input_Poll_Count => 1,
         Reason_Key       => To_Unbounded_String
           ((if Caps.Live_Window_Smoke_Ready then "runtime.live.ready"
             elsif not Caps.Display_Available then "runtime.live.no_display"
             elsif not Caps.Vulkan_Available then "runtime.live.no_vulkan"
             else "runtime.live.unavailable")));
   end Default_Live_Smoke_Plan;

   procedure Render_Once
     (Runtime : in out Archive.GUI_Runtime.Runtime_State;
      Window  : not null access Glfw.Windows.Window;
      Vulkan  : in out Guikit.Vulkan.Vulkan_Renderer;
      Status  : out Guikit.Vulkan.Vulkan_Status)
   is
      Width  : Glfw.Size := 0;
      Height : Glfw.Size := 0;
   begin
      Glfw.Windows.Get_Framebuffer_Size (Window, Width, Height);
      if Width = 0 or else Height = 0 then
         Status := Guikit.Vulkan.Vulkan_Present_Skipped;
         return;
      end if;

      declare
         Drain : constant Archive.Operations.Opening.Drain_Result :=
           Archive.GUI_Runtime.Drain_Operations (Runtime);
      begin
         pragma Unreferenced (Drain);
      end;

      Archive.GUI_Runtime.Resize (Runtime, Natural (Width), Natural (Height));
      Glfw.Windows.Set_Title
        (Window, To_String (Archive.GUI_Runtime.Snapshot (Runtime).Title));
      Guikit.Vulkan.Ensure_Ready
        (Renderer => Vulkan,
         Window   => Window,
         Width    => Natural (Width),
         Height   => Natural (Height));

      declare
         Frame : constant Archive.GUI_Frame.Frame := Archive.GUI_Runtime.Render_Frame (Runtime);
         Batch : constant Guikit.Vulkan.Submission_Batch := Archive.GUI_Frame.To_Submission (Frame);
      begin
         Status := Guikit.Vulkan.Present_Frame
           (Renderer => Vulkan,
            Batch    => Batch,
            Width    => Natural (Width),
            Height   => Natural (Height));
      end;
   end Render_Once;

   function Live_Smoke (Plan : Live_Smoke_Plan := Default_Live_Smoke_Plan) return Live_Smoke_Result is
      Result      : Live_Smoke_Result;
      Initialized : Boolean := False;
      Handle      : Window_Access := null;
      Runtime     : Archive.GUI_Runtime.Runtime_State;
      Vulkan      : Guikit.Vulkan.Vulkan_Renderer;
   begin
      Result.Skipped_By_Plan := not Plan.Can_Run;
      if not Plan.Can_Run then
         Result.Error_Key := Plan.Reason_Key;
         return Result;
      end if;

      Result.Attempted := True;
      Glfw.Init;
      Initialized := True;
      Guikit.Vulkan.Configure_Window_Hints (Resizable => True, Visible => False);
      Handle := new Desktop_Window;
      Glfw.Windows.Init
        (Object => As_Window (Handle),
         Width  => Glfw.Size (Plan.Width),
         Height => Glfw.Size (Plan.Height),
         Title  => Archive.Localization.Text ("application.title"));
      Result.Window_Created := True;
      Archive.GUI_Runtime.Initialize (Runtime, Width => Plan.Width, Height => Plan.Height);

      for Poll_Index in 1 .. Plan.Input_Poll_Count loop
         Guikit.Vulkan.Poll_Events;
         Result.Input_Polled := True;
      end loop;

      for Frame_Index in 1 .. Plan.Frame_Count loop
         Render_Once (Runtime, As_Window (Handle), Vulkan, Result.Last_Status);
         Result.Frames_Attempted := Result.Frames_Attempted + 1;
         if Result.Last_Status = Guikit.Vulkan.Vulkan_Presented then
            Result.Frames_Presented := Result.Frames_Presented + 1;
         end if;
      end loop;

      Result.Frame_Rendered := Result.Frames_Attempted > 0;
      Guikit.Vulkan.Shutdown (Vulkan);
      Glfw.Windows.Destroy (As_Window (Handle));
      Free_Window (Handle);
      Glfw.Shutdown;
      Result.Closed_Cleanly := True;
      Result.Skipped_By_Plan := False;
      return Result;
   exception
      when others =>
         Result.Error_Key := To_Unbounded_String ("runtime.live.failed");
         if Handle /= null then
            if Glfw.Windows.Initialized (As_Window (Handle)) then
               Glfw.Windows.Destroy (As_Window (Handle));
            end if;
            Free_Window (Handle);
         end if;
         Guikit.Vulkan.Shutdown (Vulkan);
         if Initialized then
            Glfw.Shutdown;
         end if;
         return Result;
   end Live_Smoke;

   function Live_Smoke_Report return String is
      Caps   : constant Desktop_Capabilities := Runtime_Capabilities;
      Plan   : constant Live_Smoke_Plan := Default_Live_Smoke_Plan;
      Result : constant Live_Smoke_Result := Live_Smoke (Plan);
   begin
      return "archive live runtime: display=" & Boolean'Image (Caps.Display_Available)
        & " vulkan=" & Boolean'Image (Caps.Vulkan_Available)
        & " smoke_ready=" & Boolean'Image (Caps.Live_Window_Smoke_Ready)
        & " attempted=" & Boolean'Image (Result.Attempted)
        & " window=" & Boolean'Image (Result.Window_Created)
        & " frames=" & Natural'Image (Result.Frames_Attempted)
        & " presented=" & Natural'Image (Result.Frames_Presented)
        & " input_polled=" & Boolean'Image (Result.Input_Polled)
        & " closed=" & Boolean'Image (Result.Closed_Cleanly)
        & " status=" & Guikit.Vulkan.Vulkan_Status'Image (Result.Last_Status)
        & " reason=" & To_String (Result.Error_Key);
   end Live_Smoke_Report;

   procedure Run (Initial_Path : String := "") is
      Handle      : Window_Access := null;
      Runtime     : Archive.GUI_Runtime.Runtime_State;
      Vulkan      : Guikit.Vulkan.Vulkan_Renderer;
      Status      : Guikit.Vulkan.Vulkan_Status := Guikit.Vulkan.Vulkan_Not_Initialized;
      Initialized : Boolean := False;
   begin
      Glfw.Init;
      Initialized := True;
      Guikit.Vulkan.Configure_Window_Hints (Resizable => True, Visible => True);
      Handle := new Desktop_Window;
      Glfw.Windows.Init
        (Object => As_Window (Handle),
         Width  => 1024,
         Height => 768,
         Title  => Archive.Localization.Text ("application.title"));
      Glfw.Windows.Show (As_Window (Handle));
      Archive.GUI_Runtime.Initialize (Runtime, Width => 1024, Height => 768);
      if Initial_Path /= "" then
         Archive.GUI_Runtime.Start_Open_Archive (Runtime, Initial_Path);
      end if;

      while not Glfw.Windows.Should_Close (As_Window (Handle)) loop
         Render_Once (Runtime, As_Window (Handle), Vulkan, Status);
         Guikit.Vulkan.Wait_For_Events (Event_Wait_Timeout);
      end loop;

      Guikit.Vulkan.Shutdown (Vulkan);
      Glfw.Windows.Destroy (As_Window (Handle));
      Free_Window (Handle);
      Glfw.Shutdown;
   exception
      when others =>
         if Handle /= null then
            if Glfw.Windows.Initialized (As_Window (Handle)) then
               Glfw.Windows.Destroy (As_Window (Handle));
            end if;
            Free_Window (Handle);
         end if;
         Guikit.Vulkan.Shutdown (Vulkan);
         if Initialized then
            Glfw.Shutdown;
         end if;
         raise Desktop_Error with "runtime.live.failed";
   end Run;
end Archive.Application.Windows;
