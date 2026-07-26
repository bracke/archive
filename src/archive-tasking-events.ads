with Ada.Containers.Vectors;
with Archive.Types;

package Archive.Tasking.Events is
   type Event_Kind is
     (Open_Completed,
      Preview_Completed,
      Verification_Completed,
      Extraction_Progress,
      Extraction_Completed,
      Save_Completed,
      Source_Changed,
      Shutdown);

   type Event is record
      Kind                  : Event_Kind := Open_Completed;
      Session_Generation    : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Operation_Generation  : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Progress_Numerator    : Natural := 0;
      Progress_Denominator  : Natural := 0;
   end record;

   package Event_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Event);

   type Event_Decision is (Accept_Event, Reject_Stale_Event);

   function Classify
     (Incoming          : Event;
      Current_Session   : Archive.Types.Generation_Id;
      Current_Operation : Archive.Types.Generation_Id)
      return Event_Decision;
end Archive.Tasking.Events;
