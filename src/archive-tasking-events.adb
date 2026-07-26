package body Archive.Tasking.Events is
   use type Archive.Types.Generation_Id;

   function Classify
     (Incoming          : Event;
      Current_Session   : Archive.Types.Generation_Id;
      Current_Operation : Archive.Types.Generation_Id)
      return Event_Decision
   is
   begin
      if Incoming.Kind = Shutdown then
         return Accept_Event;
      elsif Incoming.Session_Generation /= Current_Session then
         return Reject_Stale_Event;
      elsif Incoming.Kind in Open_Completed | Preview_Completed | Verification_Completed
        | Extraction_Progress | Extraction_Completed | Save_Completed | Source_Changed
        and then Incoming.Operation_Generation /= Current_Operation
      then
         return Reject_Stale_Event;
      else
         return Accept_Event;
      end if;
   end Classify;
end Archive.Tasking.Events;
