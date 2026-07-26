with Guikit.Draw;
with Guikit.Vulkan;

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
   function To_Submission (Rendered : Frame) return Guikit.Vulkan.Submission_Batch;
   function Validate (Rendered : Frame) return Frame_Validation;
end Archive.GUI_Frame;
