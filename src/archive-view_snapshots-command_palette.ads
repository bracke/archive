with Ada.Containers.Vectors;
with Archive.Commands;
with Archive.Model;
with Archive.Types;

package Archive.View_Snapshots.Command_Palette is
   type Command_Row is record
      Id               : Archive.Commands.Command_Id := Archive.Commands.No_Command;
      Identifier       : Archive.Types.UString;
      Name             : Archive.Types.UString;
      Description      : Archive.Types.UString;
      Unavailable_Text : Archive.Types.UString;
      Icon_Name        : Archive.Types.UString;
      Category         : Archive.Commands.Command_Category :=
        Archive.Commands.Application_Category;
      Enabled          : Boolean := False;
      Shortcut_Present : Boolean := False;
   end record;

   package Command_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Command_Row);

   type Palette_Request is record
      Locale      : Archive.Types.UString;
      Filter_Text : Archive.Types.UString;
      Limit       : Natural := 200;
   end record;

   type Palette_Snapshot is record
      Rows      : Command_Row_Vectors.Vector;
      Truncated : Boolean := False;
   end record;

   function Build
     (Model   : Archive.Model.Application_Model;
      Request : Palette_Request)
      return Palette_Snapshot;
end Archive.View_Snapshots.Command_Palette;
