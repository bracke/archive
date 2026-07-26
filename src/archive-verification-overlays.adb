with Ada.Strings.Unbounded;

package body Archive.Verification.Overlays is
   use Ada.Strings.Unbounded;
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Generation_Id;

   function Empty
     (Session   : Archive.Types.Generation_Id;
      Operation : Archive.Types.Generation_Id;
      Phase     : Verification_Phase := Verification_Running)
      return Verification_Overlay
   is
   begin
      return
        (Session   => Session,
         Operation => Operation,
         State     => Phase,
         Results   => Entry_Result_Vectors.Empty_Vector);
   end Empty;

   procedure Set_Result
     (Overlay    : in out Verification_Overlay;
      Entry_Id   : Archive.Types.Entry_Id;
      Integrity  : Archive.Archives.Entries.Integrity_State;
      Message_Key : String := "")
   is
   begin
      for Index in Overlay.Results.First_Index .. Overlay.Results.Last_Index loop
         if Overlay.Results.Element (Index).Entry_Id = Entry_Id then
            Overlay.Results.Replace_Element
              (Index,
               (Entry_Id    => Entry_Id,
                Integrity   => Integrity,
                Message_Key => To_Unbounded_String (Message_Key)));
            return;
         end if;
      end loop;

      Overlay.Results.Append
        (Entry_Result'
           (Entry_Id    => Entry_Id,
            Integrity   => Integrity,
            Message_Key => To_Unbounded_String (Message_Key)));
   end Set_Result;

   function Contains
     (Overlay : Verification_Overlay;
      Entry_Id : Archive.Types.Entry_Id)
      return Boolean
   is
   begin
      for Item of Overlay.Results loop
         if Item.Entry_Id = Entry_Id then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Integrity_For
     (Overlay : Verification_Overlay;
      Entry_Id : Archive.Types.Entry_Id)
      return Archive.Archives.Entries.Integrity_State
   is
   begin
      for Item of Overlay.Results loop
         if Item.Entry_Id = Entry_Id then
            return Item.Integrity;
         end if;
      end loop;
      return Archive.Archives.Entries.Not_Checked;
   end Integrity_For;

   function Entry_Count (Overlay : Verification_Overlay) return Natural is
   begin
      return Natural (Overlay.Results.Length);
   end Entry_Count;

   function Session_Generation (Overlay : Verification_Overlay) return Archive.Types.Generation_Id is
   begin
      return Overlay.Session;
   end Session_Generation;

   function Operation_Generation (Overlay : Verification_Overlay) return Archive.Types.Generation_Id is
   begin
      return Overlay.Operation;
   end Operation_Generation;

   function Phase (Overlay : Verification_Overlay) return Verification_Phase is
   begin
      return Overlay.State;
   end Phase;

   function Accept_Result
     (Candidate            : Verification_Overlay;
      Current_Session      : Archive.Types.Generation_Id;
      Current_Verification : Archive.Types.Generation_Id;
      Cancelled            : Boolean := False)
      return Overlay_Acceptance
   is
   begin
      if Cancelled or else Candidate.State = Verification_Cancelled then
         return Overlay_Rejected_Cancelled;
      elsif Candidate.Session /= Current_Session
        or else Candidate.Operation /= Current_Verification
      then
         return Overlay_Rejected_Stale;
      else
         return Overlay_Accepted;
      end if;
   end Accept_Result;
end Archive.Verification.Overlays;
