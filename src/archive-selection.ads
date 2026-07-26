with Archive.Types;

package Archive.Selection is
   type Selection_Model is private;

   procedure Clear (Model : in out Selection_Model);
   procedure Select_Only (Model : in out Selection_Model; Id : Archive.Types.Entry_Id);
   procedure Add (Model : in out Selection_Model; Id : Archive.Types.Entry_Id);
   procedure Remove (Model : in out Selection_Model; Id : Archive.Types.Entry_Id);
   procedure Toggle (Model : in out Selection_Model; Id : Archive.Types.Entry_Id);

   procedure Select_Range
     (Model      : in out Selection_Model;
      Projection : Archive.Types.Entry_Id_Vectors.Vector;
      Anchor     : Archive.Types.Entry_Id;
      Target     : Archive.Types.Entry_Id);

   function Contains (Model : Selection_Model; Id : Archive.Types.Entry_Id) return Boolean;
   function Count (Model : Selection_Model) return Natural;
   function Items (Model : Selection_Model) return Archive.Types.Entry_Id_Vectors.Vector;
   function Anchor (Model : Selection_Model) return Archive.Types.Entry_Id;

private
   type Selection_Model is record
      Values       : Archive.Types.Entry_Id_Vectors.Vector;
      Anchor_Value : Archive.Types.Entry_Id := Archive.Types.No_Entry;
   end record;
end Archive.Selection;
