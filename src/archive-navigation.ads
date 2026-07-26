with Ada.Containers.Vectors;
with Archive.Types;

package Archive.Navigation is
   type History_Entry is record
      Session        : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Directory      : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Focused        : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Selection_Anchor : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Viewport_First : Natural := 0;
   end record;

   type Navigation_Model is private;

   procedure Reset
     (Model   : in out Navigation_Model;
      Session : Archive.Types.Generation_Id;
      Root    : Archive.Types.Entry_Id);

   procedure Navigate_To
     (Model     : in out Navigation_Model;
      Directory : Archive.Types.Entry_Id;
      Focused   : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Viewport  : Natural := 0);

   function Can_Back (Model : Navigation_Model) return Boolean;
   function Can_Forward (Model : Navigation_Model) return Boolean;
   function Back (Model : in out Navigation_Model) return History_Entry;
   function Forward (Model : in out Navigation_Model) return History_Entry;
   function Current (Model : Navigation_Model) return History_Entry;

private
   package History_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => History_Entry);

   type Navigation_Model is record
      Entries : History_Vectors.Vector;
      Cursor  : Natural := 0;
   end record;
end Archive.Navigation;
