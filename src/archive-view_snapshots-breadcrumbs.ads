with Ada.Containers.Vectors;
with Archive.Archives.Index;
with Archive.Types;

package Archive.View_Snapshots.Breadcrumbs is
   type Breadcrumb_Item is record
      Entry_Id : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Name     : Archive.Types.UString;
   end record;

   package Breadcrumb_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Breadcrumb_Item);

   type Breadcrumb_Snapshot is record
      Items : Breadcrumb_Vectors.Vector;
      Valid : Boolean := False;
   end record;

   function Build
     (Index     : Archive.Archives.Index.Archive_Index;
      Directory : Archive.Types.Entry_Id)
      return Breadcrumb_Snapshot;
end Archive.View_Snapshots.Breadcrumbs;
