with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Unchecked_Deallocation;

with Guikit.Draw;
with Guikit.Input;
with Guikit.Layout;
with Guikit.Text;
with Guikit.Utf8;

with Archive.Commands;
with Archive.Fonts;

with Glfw;
with Glfw.Input.Keys;
with Glfw.Input.Mouse;
with Glfw.Windows;
with Glfw.Windows.Vulkan;

with Archive.GUI_Frame;
with Archive.GUI_Runtime;
with Archive.Localization;
with Archive.Operations.Opening;
with Archive.UI;

package body Archive.Application.Windows is
   use Ada.Strings.Unbounded;
   use type Glfw.Size;
   use type Guikit.Vulkan.Vulkan_Status;
   use type Archive.Operations.Opening.Operation_Status;
   use type Archive.Commands.Command_Id;
   use type Archive.Types.Generation_Id;

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
   --  Present-grace window: after any change, keep presenting every frame for a
   --  short spell rather than stopping the instant the frame is unchanged.
   --  Presenting keeps us on the compositor's frame clock (which paces input at
   --  the display rate); once we stop, the first interaction after an idle gap
   --  stalls. ~24 frames is ~0.4s at 60fps, then a truly idle window stops.
   Present_Grace_Frames : constant := 24;

   type Render_Cache is record
      Presented_Once : Boolean := False;
      Frame_Valid    : Boolean := False;
      Last_Width     : Natural := 0;
      Last_Height    : Natural := 0;
      Present_Grace  : Natural := 0;
      Cached_Frame   : Archive.GUI_Frame.Frame;
      --  Model revision Cached_Frame was built at. Any model mutation bumps the
      --  revision (via Touch), so comparing it makes frame invalidation automatic
      --  rather than relying on every mutation site to signal a change.
      Cached_Revision : Archive.Types.Generation_Id := 0;
   end record;

   --  One text renderer for the process, brought up the first time a frame is
   --  drawn. It holds the font, its fallbacks and the glyph atlas, all of which
   --  outlive any single frame, and Guikit.Text.Renderer is limited, so it
   --  cannot live in the per-window cache record that gets copied about.
   --  What a frame carries when there is no font: the same thing the structural
   --  checks use, so the window falls back to exactly its old behaviour.
   function Unrendered_Text return Guikit.Draw.Text_Render_Result is
      Result : Guikit.Draw.Text_Render_Result;
   begin
      Result.Status := Guikit.Draw.Text_Render_Font_Not_Loaded;
      return Result;
   end Unrendered_Text;

   Text_Renderer : Guikit.Text.Renderer;
   Text_Ready    : Boolean := False;
   Text_Tried    : Boolean := False;

   --  Load the font once. A machine with no font it can read is not an error
   --  worth refusing to start over: the window still draws, without text, which
   --  is what it did before there was a renderer at all.
   procedure Ensure_Text_Ready;

   procedure Ensure_Text_Ready is
      use type Guikit.Draw.Text_Render_Status;
   begin
      if Text_Tried then
         return;
      end if;

      Text_Tried := True;

      if Archive.Fonts.Primary = "" then
         return;
      end if;

      Text_Ready :=
        Guikit.Text.Initialize
          (R              => Text_Renderer,
           Font_Path      => Archive.Fonts.Primary,
           Fallback_Paths => Archive.Fonts.Fallbacks,
           --  Sized from the layouts' line height, as files does: the font at
           --  four fifths of it, the cell at the advance layouts measure with.
           Pixel_Size     => Archive.UI.Default_Line_Height * 4 / 5,
           Cell_Width     => Guikit.Layout.Caret_Advance_Width (Archive.UI.Default_Line_Height),
           Cell_Height    => Archive.UI.Default_Line_Height,
           Atlas_Width    => 1024,
           Atlas_Height   => 1024) = Guikit.Draw.Text_Render_Success;
   end Ensure_Text_Ready;

   --  Window input in arrival order: the callbacks only queue it, and the
   --  render loop hands each event to the runtime between frames.
   type Input_Kind is (Key_Input, Text_Input, Click_Input);

   type Input_Event is record
      Kind      : Input_Kind := Text_Input;
      Key       : Guikit.Input.Key_Code := Guikit.Input.Key_Unknown;
      Modifiers : Guikit.Input.Modifier_Set := Guikit.Input.No_Modifiers;
      Text      : Unbounded_String;
      X, Y      : Integer := 0;
   end record;

   package Input_Event_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Input_Event);

   --  A mouse whose switch bounces reports a second press microseconds after
   --  the real one; presses closer together than this are one click.
   Click_Bounce : constant Glfw.Seconds := 0.04;

   type Desktop_Window is new Glfw.Windows.Window with record
      Pending     : Input_Event_Vectors.Vector;
      Mouse_X     : Integer := 0;
      Mouse_Y     : Integer := 0;
      Have_Press  : Boolean := False;
      Last_Press  : Glfw.Seconds := 0.0;
   end record;
   type Window_Access is access all Desktop_Window;

   overriding procedure Character_Entered
     (Object : not null access Desktop_Window;
      Char   : Wide_Wide_Character);
   overriding procedure Key_Changed
     (Object   : not null access Desktop_Window;
      Key      : Glfw.Input.Keys.Key;
      Scancode : Glfw.Input.Keys.Scancode;
      Action   : Glfw.Input.Keys.Action;
      Mods     : Glfw.Input.Keys.Modifiers);
   overriding procedure Mouse_Button_Changed
     (Object : not null access Desktop_Window;
      Button : Glfw.Input.Mouse.Button;
      State  : Glfw.Input.Button_State;
      Mods   : Glfw.Input.Keys.Modifiers);
   overriding procedure Mouse_Position_Changed
     (Object : not null access Desktop_Window;
      X      : Glfw.Input.Mouse.Coordinate;
      Y      : Glfw.Input.Mouse.Coordinate);

   --  The guikit key for a GLFW key. The two enumerations name the keys alike
   --  ("A" / "Key_A", "Key_End" / "Key_End"); Enter is guikit's Return.
   function To_Key_Code (Key : Glfw.Input.Keys.Key) return Guikit.Input.Key_Code is
      use type Glfw.Input.Keys.Key;
      Name : constant String := Glfw.Input.Keys.Key'Image (Key);
   begin
      if Key = Glfw.Input.Keys.Enter or else Key = Glfw.Input.Keys.Numpad_Enter then
         return Guikit.Input.Key_Return;
      end if;
      begin
         return Guikit.Input.Key_Code'Value (Name);
      exception
         when Constraint_Error =>
            return Guikit.Input.Key_Code'Value ("KEY_" & Name);
      end;
   exception
      when Constraint_Error =>
         return Guikit.Input.Key_Unknown;
   end To_Key_Code;

   overriding procedure Character_Entered
     (Object : not null access Desktop_Window;
      Char   : Wide_Wide_Character)
   is
      Code : constant Natural := Wide_Wide_Character'Pos (Char);
   begin
      if Code >= Character'Pos (' ') then
         Object.Pending.Append
           (Input_Event'(Kind => Text_Input, Text => To_Unbounded_String (Guikit.Utf8.Encode (Code)), others => <>));
      end if;
   end Character_Entered;

   overriding procedure Key_Changed
     (Object   : not null access Desktop_Window;
      Key      : Glfw.Input.Keys.Key;
      Scancode : Glfw.Input.Keys.Scancode;
      Action   : Glfw.Input.Keys.Action;
      Mods     : Glfw.Input.Keys.Modifiers)
   is
      use type Glfw.Input.Keys.Action;
      use type Guikit.Input.Key_Code;
      pragma Unreferenced (Scancode);
      Code : constant Guikit.Input.Key_Code := To_Key_Code (Key);
   begin
      if Action = Glfw.Input.Keys.Release or else Code = Guikit.Input.Key_Unknown then
         return;
      end if;
      Object.Pending.Append
        (Input_Event'
           (Kind      => Key_Input,
            Key       => Code,
            Modifiers =>
              [Guikit.Input.Shift_Key   => Mods.Shift,
               Guikit.Input.Control_Key => Mods.Control,
               Guikit.Input.Alt_Key     => Mods.Alt,
               Guikit.Input.Meta_Key    => Mods.Super],
            others    => <>));
   end Key_Changed;

   overriding procedure Mouse_Button_Changed
     (Object : not null access Desktop_Window;
      Button : Glfw.Input.Mouse.Button;
      State  : Glfw.Input.Button_State;
      Mods   : Glfw.Input.Keys.Modifiers)
   is
      use type Glfw.Input.Mouse.Button;
      use type Glfw.Input.Button_State;
      use type Glfw.Seconds;
      pragma Unreferenced (Mods);
      Now : constant Glfw.Seconds := Glfw.Time;
   begin
      if Button = Glfw.Input.Mouse.Left_Button and then State = Glfw.Input.Pressed then
         if Object.Have_Press and then Now - Object.Last_Press < Click_Bounce then
            return;
         end if;
         Object.Have_Press := True;
         Object.Last_Press := Now;
         Object.Pending.Append
           (Input_Event'(Kind => Click_Input, X => Object.Mouse_X, Y => Object.Mouse_Y, others => <>));
      end if;
   end Mouse_Button_Changed;

   overriding procedure Mouse_Position_Changed
     (Object : not null access Desktop_Window;
      X      : Glfw.Input.Mouse.Coordinate;
      Y      : Glfw.Input.Mouse.Coordinate) is
   begin
      Object.Mouse_X := Integer (X);
      Object.Mouse_Y := Integer (Y);
   end Mouse_Position_Changed;

   --  Hand the window's queued input to the runtime, in arrival order.
   procedure Drain_Input
     (Handle  : not null access Desktop_Window;
      Runtime : in out Archive.GUI_Runtime.Runtime_State)
   is
      Events : constant Input_Event_Vectors.Vector := Handle.Pending;
   begin
      Handle.Pending.Clear;
      for Event of Events loop
         case Event.Kind is
            when Key_Input =>
               Archive.GUI_Runtime.Key_Pressed (Runtime, Event.Key, Event.Modifiers);
            when Text_Input =>
               Archive.GUI_Runtime.Text_Typed (Runtime, To_String (Event.Text));
            when Click_Input =>
               Archive.GUI_Runtime.Clicked (Runtime, Event.X, Event.Y);
         end case;
      end loop;
   end Drain_Input;

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

      --  Pump the async open worker every frame. A dequeued event with no model
      --  change (Event_Seen without Applied) still needs a rebuild, so signal it
      --  explicitly; an applied change is also caught by the revision check below.
      declare
         Drain : constant Archive.Operations.Opening.Drain_Result :=
           Archive.GUI_Runtime.Drain_Operations (Runtime);
      begin
         if Drain.Applied or else Drain.Event_Seen then
            Cache.Frame_Valid := False;
         end if;
      end;

      --  Any model mutation -- the async worker above, or (once wired) keyboard
      --  and mouse input -- bumps the model revision via Touch, so a changed
      --  revision invalidates the cached frame automatically, with no per-site
      --  signalling to remember.
      if Archive.GUI_Runtime.Revision (Runtime) /= Cache.Cached_Revision then
         Cache.Frame_Valid := False;
      end if;

      if not Cache.Frame_Valid
        or else Cache.Last_Width /= Natural (Width)
        or else Cache.Last_Height /= Natural (Height)
      then
         Rebuilt := True;
      end if;

      --  A change opens the grace window; we keep presenting through it so input
      --  stays paced to the compositor's frame clock.
      if Rebuilt then
         Cache.Present_Grace := Present_Grace_Frames;
      end if;

      --  Present gate: an unchanged, out-of-grace frame is already on screen, so
      --  skip the whole resize/build/submit/present path. Force keeps the smoke
      --  presenting every frame so its present counts are unchanged.
      if Cache.Presented_Once
        and then not Rebuilt
        and then Cache.Present_Grace = 0
        and then not Force
      then
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
      Cache.Cached_Revision := Archive.GUI_Runtime.Revision (Runtime);
      Cache.Frame_Valid := True;

      Ensure_Text_Ready;

      declare
         Glyphs : constant Guikit.Draw.Text_Render_Result :=
           (if Text_Ready
            then Guikit.Text.Build_Glyphs
                   (Text_Renderer,
                    Cache.Cached_Frame.Text,
                    Cache.Cached_Frame.Overlay_Text)
            else Unrendered_Text);
         Batch : constant Guikit.Vulkan.Submission_Batch :=
           Archive.GUI_Frame.To_Submission (Cache.Cached_Frame, Glyphs);
      begin
         Status := Guikit.Vulkan.Present_Frame
           (Renderer => Vulkan,
            Batch    => Batch,
            Width    => Natural (Width),
            Height   => Natural (Height));
      end;
      Cache.Presented_Once := True;

      --  Burn down one frame of the grace window; it is refilled above on any
      --  change, so it only reaches zero after a genuine idle gap.
      if Cache.Present_Grace > 0 then
         Cache.Present_Grace := Cache.Present_Grace - 1;
      end if;
   end Render_Once;

   --  ARCHIVE_LIVE_SMOKE_HOLD=<seconds> keeps the smoke's last frame on screen
   --  that long, so a person or a screenshot tool can look at it.
   procedure Hold_For_Inspection is
      Value   : constant String := Safe_Environment_Value ("ARCHIVE_LIVE_SMOKE_HOLD");
      Seconds : Natural := 0;
   begin
      begin
         Seconds := (if Value = "" then 0 else Natural'Min (Natural'Value (Value), 600));
      exception
         when Constraint_Error =>
            Seconds := 0;
      end;
      for Tick in 1 .. Seconds * 10 loop
         Guikit.Vulkan.Poll_Events;
         delay 0.1;
      end loop;
   end Hold_For_Inspection;

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
      --  Hidden, unless someone asked to look at it.
      Guikit.Vulkan.Configure_Window_Hints
        (Resizable => True, Visible => Safe_Environment_Value ("ARCHIVE_LIVE_SMOKE_HOLD") /= "");
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

      --  Drive the window's own input queue: click Open archive, type a path,
      --  and render the dialog that should now hold it.
      declare
         Typed : constant String := "/tmp/example.zip";
         Shell : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         for Button of Archive.GUI_Frame.Toolbar_Buttons (Shell, Shell.Layout.Content_W + Shell.Layout.Preview_W) loop
            if Button.Command = Archive.Commands.Open_Archive_Command then
               Handle.Pending.Append
                 (Input_Event'
                    (Kind => Click_Input, X => Button.X + Button.Width / 2, Y => Button.Y + Button.Height / 2,
                     others => <>));
            end if;
         end loop;
         Handle.Pending.Append
           (Input_Event'(Kind => Text_Input, Text => To_Unbounded_String (Typed), others => <>));
         Drain_Input (Handle, Runtime);
         Render_Once (Runtime, As_Window (Handle), Vulkan, Smoke_Cache, Force => True, Status => Result.Last_Status);
         Result.Frames_Attempted := Result.Frames_Attempted + 1;
         if Result.Last_Status = Guikit.Vulkan.Vulkan_Presented then
            Result.Frames_Presented := Result.Frames_Presented + 1;
         end if;
         declare
            After : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
         begin
            Result.Input_Driven := After.Dialog.Takes_Path and then To_String (After.Dialog.Text) = Typed;
         end;
         Hold_For_Inspection;
      end;

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
        & " input=" & Boolean'Image (Result.Input_Driven)
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
      Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Char);
      Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Key);
      Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Mouse_Button);
      Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Mouse_Position);
      Archive.GUI_Runtime.Initialize (Runtime, Width => 1024, Height => 768);
      if Initial_Path /= "" then
         Archive.GUI_Runtime.Start_Open_Archive (Runtime, Initial_Path);
      end if;

      while not Glfw.Windows.Should_Close (As_Window (Handle)) loop
         Drain_Input (Handle, Runtime);
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
