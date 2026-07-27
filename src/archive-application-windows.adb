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
   use type Archive.Operations.Opening.Operation_Status;

   Event_Wait_Timeout : constant Duration := 0.016;
   --  The loop always waits just a frame's worth: the Render_Cache below already
   --  skips the build/submit/present path for unchanged frames, so idle CPU stays
   --  near zero regardless. A short wait keeps input prompt (once we stop
   --  presenting the compositor stops waking us, so a long block genuinely delays
   --  keystrokes) and also lets the async open worker -- which signals internally,
   --  not through a window event -- be polled while it runs.

   --  Lets Render_Once leave an unchanged frame on screen instead of rebuilding
   --  and re-presenting it every wake. The frame is a pure function of the model,
   --  so it is invalidated only when the async open worker publishes a change or
   --  the window is resized.
   type Render_Cache is record
      Presented_Once : Boolean := False;
      Frame_Valid    : Boolean := False;
      Last_Width     : Natural := 0;
      Last_Height    : Natural := 0;
      Cached_Frame   : Archive.GUI_Frame.Frame;
   end record;

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
         Frame_Count      => 2,
         Input_Poll_Count => 2,
         Resize_Width     => 800,
         Resize_Height    => 600,
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
      Cache   : in out Render_Cache;
      Force   : Boolean;
      Status  : out Guikit.Vulkan.Vulkan_Status)
   is
      Width   : Glfw.Size := 0;
      Height  : Glfw.Size := 0;
      Rebuilt : Boolean := False;
   begin
      Glfw.Windows.Get_Framebuffer_Size (Window, Width, Height);
      if Width = 0 or else Height = 0 then
         Status := Guikit.Vulkan.Vulkan_Present_Skipped;
         return;
      end if;

      --  Pump the async open worker every frame; a published change or any
      --  dequeued event invalidates the cached frame. This is the sole per-loop
      --  model-mutation point, so it is the only place that needs to invalidate.
      declare
         Drain : constant Archive.Operations.Opening.Drain_Result :=
           Archive.GUI_Runtime.Drain_Operations (Runtime);
      begin
         if Drain.Applied or else Drain.Event_Seen then
            Cache.Frame_Valid := False;
         end if;
      end;

      if not Cache.Frame_Valid
        or else Cache.Last_Width /= Natural (Width)
        or else Cache.Last_Height /= Natural (Height)
      then
         Rebuilt := True;
      end if;

      --  Present gate: an unchanged frame is already on screen, so skip the whole
      --  resize/build/submit/present path. Force keeps the smoke presenting every
      --  frame so its present counts are unchanged.
      if Cache.Presented_Once and then not Rebuilt and then not Force then
         Status := Guikit.Vulkan.Vulkan_Present_Skipped;
         return;
      end if;

      Archive.GUI_Runtime.Resize (Runtime, Natural (Width), Natural (Height));
      Glfw.Windows.Set_Title
        (Window, To_String (Archive.GUI_Runtime.Snapshot (Runtime).Title));
      Guikit.Vulkan.Ensure_Ready
        (Renderer => Vulkan,
         Window   => Window,
         Width    => Natural (Width),
         Height   => Natural (Height));

      Cache.Cached_Frame := Archive.GUI_Runtime.Render_Frame (Runtime);
      Cache.Last_Width := Natural (Width);
      Cache.Last_Height := Natural (Height);
      Cache.Frame_Valid := True;

      declare
         Batch : constant Guikit.Vulkan.Submission_Batch :=
           Archive.GUI_Frame.To_Submission (Cache.Cached_Frame);
      begin
         Status := Guikit.Vulkan.Present_Frame
           (Renderer => Vulkan,
            Batch    => Batch,
            Width    => Natural (Width),
            Height   => Natural (Height));
      end;
      Cache.Presented_Once := True;
   end Render_Once;

   function Live_Smoke (Plan : Live_Smoke_Plan := Default_Live_Smoke_Plan) return Live_Smoke_Result is
      Result      : Live_Smoke_Result;
      Initialized : Boolean := False;
      Handle      : Window_Access := null;
      Runtime     : Archive.GUI_Runtime.Runtime_State;
      Vulkan      : Guikit.Vulkan.Vulkan_Renderer;
      Smoke_Cache : Render_Cache;
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
      Result.Runtime_Validated := Archive.GUI_Runtime.Validate (Runtime).Ready;

      for Poll_Index in 1 .. Plan.Input_Poll_Count loop
         Guikit.Vulkan.Poll_Events;
         Result.Input_Polled := True;
      end loop;

      for Frame_Index in 1 .. Plan.Frame_Count loop
         if Frame_Index = 2 and then Plan.Resize_Width > 0 and then Plan.Resize_Height > 0 then
            Glfw.Windows.Set_Size
              (As_Window (Handle),
               Glfw.Size (Plan.Resize_Width),
               Glfw.Size (Plan.Resize_Height));
            Archive.GUI_Runtime.Resize (Runtime, Plan.Resize_Width, Plan.Resize_Height);
            Result.Resize_Applied := True;
         end if;
         Render_Once (Runtime, As_Window (Handle), Vulkan, Smoke_Cache,
                      Force => True, Status => Result.Last_Status);
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
        & " resized=" & Boolean'Image (Result.Resize_Applied)
        & " runtime_validated=" & Boolean'Image (Result.Runtime_Validated)
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
      Cache       : Render_Cache;
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
         Render_Once (Runtime, As_Window (Handle), Vulkan, Cache,
                      Force => False, Status => Status);
         --  Wait a frame's worth so input stays prompt and a running archive-open
         --  (which signals internally, not through a window event) keeps ticking.
         --  The Render_Cache skips presenting unchanged frames, so this does not
         --  cost idle CPU.
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
