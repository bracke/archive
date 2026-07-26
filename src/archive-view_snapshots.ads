with Archive.Archives.Index;
with Archive.Types;

package Archive.View_Snapshots is
   type Sort_Field is
     (Sort_By_Name,
      Sort_By_Kind,
      Sort_By_Uncompressed_Size,
      Sort_By_Compressed_Size,
      Sort_By_Archive_Order);

   type Sort_Direction is (Ascending, Descending);

   type Projection_Request is record
      Parent            : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Filter_Text       : Archive.Types.UString;
      Field             : Sort_Field := Sort_By_Name;
      Direction         : Sort_Direction := Ascending;
      Directories_First : Boolean := True;
      Limit             : Natural := 10_000;
   end record;

   type Projection_Result is record
      Entries   : Archive.Types.Entry_Id_Vectors.Vector;
      Truncated : Boolean := False;
   end record;

   function Project
     (Index   : Archive.Archives.Index.Archive_Index;
      Request : Projection_Request)
      return Projection_Result;
end Archive.View_Snapshots;
