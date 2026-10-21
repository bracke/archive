with Ada.Containers.Vectors;

with Guikit.Command_Palette;
with Guikit.Item_Grid;
with Guikit.Settings_Panel;
with Guikit.Draw;
with Guikit.Vulkan;

with Archive.Commands;
with Archive.Types;
with Archive.UI;

package Archive.GUI_Frame is
   type Frame is record
      Layout             : Guikit.Draw.Layout_Metrics;
      Rectangles         : Guikit.Draw.Rectangle_Command_Vectors.Vector;
      Triangles          : Guikit.Draw.Triangle_Command_Vectors.Vector;
      Text               : Guikit.Draw.Text_Command_Vectors.Vector;
      Icons              : Guikit.Draw.Icon_Command_Vectors.Vector;
      Overlay_Rectangles : Guikit.Draw.Rectangle_Command_Vectors.Vector;
      Overlay_Text       : Guikit.Draw.Text_Command_Vectors.Vector;
      Accessibility      : Guikit.Draw.Accessibility_Node_Vectors.Vector;
   end record;

   type Frame_Validation is record
      Valid               : Boolean := False;
      Rectangle_Count     : Natural := 0;
      Text_Count          : Natural := 0;
      Accessibility_Count : Natural := 0;
      Vertex_Count        : Natural := 0;
   end record;

   function Build (Shell : Archive.UI.Shell_Snapshot) return Frame;

   --  One toolbar button where the frame draws it. Drawing and click
   --  hit-testing both come from Toolbar_Buttons, so they cannot disagree.
   type Toolbar_Button is record
      X, Y, Width, Height : Natural := 0;
      Command : Archive.Commands.Command_Id := Archive.Commands.No_Command;
      Enabled : Boolean := False;
      Label   : Archive.Types.UString;
      More    : Boolean := False;
      --  The button that opens the overflow menu, not a command.
   end record;

   package Toolbar_Button_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Toolbar_Button);

   --  The toolbar's buttons, each as wide as its label, left to right. When
   --  they do not all fit a window Width wide, the last place holds a More
   --  button that opens the rest.
   function Toolbar_Buttons
     (Shell : Archive.UI.Shell_Snapshot;
      Width : Natural)
      return Toolbar_Button_Vectors.Vector;

   --  The commands that did not fit, as rows of the overflow menu under the
   --  More button (empty when everything fits).
   function Toolbar_Overflow_Rows
     (Shell : Archive.UI.Shell_Snapshot;
      Width : Natural)
      return Toolbar_Button_Vectors.Vector;

   --  The command palette as the frame draws it -- its rows, typed query and
   --  highlighted row -- so input reads the same result the user sees.
   function Command_Palette_For (Shell : Archive.UI.Shell_Snapshot) return Guikit.Command_Palette.Palette;

   --  The content area's item cells, as drawn and as clicks hit-test them.
   function Content_Cells (Shell : Archive.UI.Shell_Snapshot) return Guikit.Item_Grid.Item_Layout_Vectors.Vector;

   --  The settings panel as drawn (fields and values), and where it is drawn.
   function Settings_Panel_For (Shell : Archive.UI.Shell_Snapshot) return Guikit.Settings_Panel.Panel;
   procedure Settings_Panel_Box
     (Width, Height : Natural;
      X, Y, W, H    : out Natural);

   --  Where the palette is drawn in a Width x Height window.
   procedure Command_Palette_Box
     (Width, Height : Natural;
      X, Y, W, H    : out Natural);
   function To_Submission (Rendered : Frame) return Guikit.Vulkan.Submission_Batch;

   --  The same, with the frame's text rasterized.
   --
   --  The version above draws no text: it exists for the structural checks,
   --  which run with no font loaded and only look at geometry. A window has a
   --  renderer and passes the glyphs it built here.
   --
   --  @param Rendered The frame to submit.
   --  @param Text Glyphs built from the frame's text commands.
   --  @return Submission batch including the text.
   function To_Submission
     (Rendered : Frame;
      Text     : Guikit.Draw.Text_Render_Result) return Guikit.Vulkan.Submission_Batch;
   function Validate (Rendered : Frame) return Frame_Validation;
end Archive.GUI_Frame;
