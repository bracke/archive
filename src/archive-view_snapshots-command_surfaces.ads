with Ada.Containers.Vectors;
with Archive.Commands;
with Archive.Model;
with Archive.Types;

package Archive.View_Snapshots.Command_Surfaces is
   type Surface_Command is record
      Id               : Archive.Commands.Command_Id := Archive.Commands.No_Command;
      Name             : Archive.Types.UString;
      Description      : Archive.Types.UString;
      Unavailable_Text : Archive.Types.UString;
      Icon_Name        : Archive.Types.UString;
      Enabled          : Boolean := False;
   end record;

   package Surface_Command_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Surface_Command);

   type Menu_Section is record
      Category : Archive.Commands.Command_Category := Archive.Commands.Application_Category;
      Name     : Archive.Types.UString;
      Commands : Surface_Command_Vectors.Vector;
   end record;

   package Menu_Section_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Menu_Section);

   type Menu_Snapshot is record
      Sections : Menu_Section_Vectors.Vector;
   end record;

   type Toolbar_Snapshot is record
      Commands : Surface_Command_Vectors.Vector;
   end record;

   function Build_Menus
     (Model  : Archive.Model.Application_Model;
      Locale : Archive.Types.UString)
      return Menu_Snapshot;

   function Build_Toolbar
     (Model  : Archive.Model.Application_Model;
      Locale : Archive.Types.UString)
      return Toolbar_Snapshot;
end Archive.View_Snapshots.Command_Surfaces;
