with Ada.Containers.Vectors;
with Archive.Archives.Entries;
with Archive.Types;

package Archive.Verification.Overlays is
   type Verification_Phase is
     (Verification_Not_Run,
      Verification_Running,
      Verification_Completed,
      Verification_Cancelled,
      Verification_Failed);

   type Overlay_Acceptance is
     (Overlay_Accepted,
      Overlay_Rejected_Stale,
      Overlay_Rejected_Cancelled);

   type Entry_Result is record
      Entry_Id    : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      Integrity   : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
      Message_Key : Archive.Types.UString;
   end record;

   package Entry_Result_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Entry_Result);

   type Verification_Overlay is private;

   function Empty
     (Session   : Archive.Types.Generation_Id;
      Operation : Archive.Types.Generation_Id;
      Phase     : Verification_Phase := Verification_Running)
      return Verification_Overlay;

   procedure Set_Result
     (Overlay    : in out Verification_Overlay;
      Entry_Id   : Archive.Types.Entry_Id;
      Integrity  : Archive.Archives.Entries.Integrity_State;
      Message_Key : String := "");

   function Contains
     (Overlay : Verification_Overlay;
      Entry_Id : Archive.Types.Entry_Id)
      return Boolean;

   function Integrity_For
     (Overlay : Verification_Overlay;
      Entry_Id : Archive.Types.Entry_Id)
      return Archive.Archives.Entries.Integrity_State;

   function Entry_Count (Overlay : Verification_Overlay) return Natural;
   function Session_Generation (Overlay : Verification_Overlay) return Archive.Types.Generation_Id;
   function Operation_Generation (Overlay : Verification_Overlay) return Archive.Types.Generation_Id;
   function Phase (Overlay : Verification_Overlay) return Verification_Phase;

   function Accept_Result
     (Candidate            : Verification_Overlay;
      Current_Session      : Archive.Types.Generation_Id;
      Current_Verification : Archive.Types.Generation_Id;
      Cancelled            : Boolean := False)
      return Overlay_Acceptance;

private
   type Verification_Overlay is record
      Session   : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Operation : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      State     : Verification_Phase := Verification_Not_Run;
      Results   : Entry_Result_Vectors.Vector;
   end record;
end Archive.Verification.Overlays;
