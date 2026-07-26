package body Archive.Tasking.Services is
   use type Archive.Tasking.Events.Event_Decision;
   use type Archive.Tasking.Events.Event_Kind;
   use type Archive.Tasking.Queues.Enqueue_Result;

   function Current_Operation_For
     (Item  : Archive.Tasking.Events.Event;
      State : Bridge_State)
      return Archive.Types.Generation_Id
   is
   begin
      case Item.Kind is
         when Archive.Tasking.Events.Open_Completed =>
            return State.Current_Open;
         when Archive.Tasking.Events.Preview_Completed =>
            return State.Current_Preview;
         when Archive.Tasking.Events.Verification_Completed =>
            return State.Current_Verification;
         when Archive.Tasking.Events.Extraction_Progress
            | Archive.Tasking.Events.Extraction_Completed =>
            return State.Current_Extraction;
         when Archive.Tasking.Events.Save_Completed =>
            return State.Current_Save;
         when Archive.Tasking.Events.Source_Changed =>
            return State.Current_Source_Watch;
         when Archive.Tasking.Events.Shutdown =>
            return Archive.Types.No_Generation;
      end case;
   end Current_Operation_For;

   function Is_Progress (Item : Archive.Tasking.Events.Event) return Boolean is
   begin
      return Item.Kind = Archive.Tasking.Events.Extraction_Progress;
   end Is_Progress;

   function Owner_For (Item : Archive.Tasking.Events.Event) return Operation_Owner is
   begin
      case Item.Kind is
         when Archive.Tasking.Events.Open_Completed =>
            return Open_Owner;
         when Archive.Tasking.Events.Preview_Completed =>
            return Preview_Owner;
         when Archive.Tasking.Events.Verification_Completed =>
            return Verification_Owner;
         when Archive.Tasking.Events.Extraction_Progress
            | Archive.Tasking.Events.Extraction_Completed =>
            return Extraction_Owner;
         when Archive.Tasking.Events.Save_Completed =>
            return Save_Owner;
         when Archive.Tasking.Events.Source_Changed =>
            return Source_Watch_Owner;
         when Archive.Tasking.Events.Shutdown =>
            return Shutdown_Owner;
      end case;
   end Owner_For;

   protected body Event_Bridge is
      procedure Configure (State : Bridge_State) is
      begin
         Event_Bridge.State := State;
      end Configure;

      procedure Publish
        (Item   : Archive.Tasking.Events.Event;
         Result : out Publish_Result)
      is
         Decision : constant Archive.Tasking.Events.Event_Decision :=
           Archive.Tasking.Events.Classify
             (Item,
              Current_Session   => State.Current_Session,
              Current_Operation => Current_Operation_For (Item, State));
         Enqueued_Result : Archive.Tasking.Queues.Enqueue_Result;
      begin
         Result := (others => <>);

         if State.Shutting_Down and then Item.Kind /= Archive.Tasking.Events.Shutdown then
            Rejected_Stale := Rejected_Stale + 1;
            Last_Rejected := Owner_For (Item);
            Result.Stale := True;
            return;
         elsif Decision = Archive.Tasking.Events.Reject_Stale_Event then
            Rejected_Stale := Rejected_Stale + 1;
            Last_Rejected := Owner_For (Item);
            Result.Stale := True;
            return;
         end if;

         if Is_Progress (Item) then
            Result.Coalesced := Has_Latest_Progress;
            Latest_Progress := Item;
            Has_Latest_Progress := True;
            Accepted := Accepted + 1;
            Last_Accepted := Owner_For (Item);
            Result.Accepted := True;
         else
            Queue.Enqueue (Item, Enqueued_Result);
            if Enqueued_Result = Archive.Tasking.Queues.Enqueued then
               Accepted := Accepted + 1;
               Last_Accepted := Owner_For (Item);
               Result.Accepted := True;
            else
               Rejected_Full := Rejected_Full + 1;
               Last_Rejected := Owner_For (Item);
               Result.Queue_Full := True;
               return;
            end if;
         end if;

         if not Wakeup then
            Wakeup := True;
            Result.Wakeup_Requested := True;
         end if;
      end Publish;

      procedure Dequeue
        (Item  : out Archive.Tasking.Events.Event;
         Found : out Boolean)
      is
      begin
         Queue.Dequeue (Item, Found);
      end Dequeue;

      procedure Take_Latest_Progress
        (Item  : out Archive.Tasking.Events.Event;
         Found : out Boolean)
      is
      begin
         if Has_Latest_Progress then
            Item := Latest_Progress;
            Has_Latest_Progress := False;
            Found := True;
         else
            Item := (others => <>);
            Found := False;
         end if;
      end Take_Latest_Progress;

      procedure Acknowledge_Wakeup is
      begin
         Wakeup := False;
      end Acknowledge_Wakeup;

      procedure Begin_Shutdown is
         Result : Publish_Result;
      begin
         State.Shutting_Down := True;
         Publish
           ((Kind                 => Archive.Tasking.Events.Shutdown,
             Session_Generation   => Archive.Types.No_Generation,
             Operation_Generation => Archive.Types.No_Generation,
             Progress_Numerator   => 0,
             Progress_Denominator => 0),
            Result);
      end Begin_Shutdown;

      function Wakeup_Pending return Boolean is
      begin
         return Wakeup;
      end Wakeup_Pending;

      function Queue_Count return Natural is
      begin
         return Queue.Count;
      end Queue_Count;

      function Accepted_Count return Natural is
      begin
         return Accepted;
      end Accepted_Count;

      function Rejected_Stale_Count return Natural is
      begin
         return Rejected_Stale;
      end Rejected_Stale_Count;

      function Rejected_Full_Count return Natural is
      begin
         return Rejected_Full;
      end Rejected_Full_Count;

      function Snapshot return Supervision_Snapshot is
      begin
         return
           (State                 => State,
            Last_Accepted_Owner   => Last_Accepted,
            Last_Rejected_Owner   => Last_Rejected,
            Latest_Progress_Ready => Has_Latest_Progress,
            Queue                 => Queue.Snapshot,
            Wakeup_Pending        => Wakeup,
            Accepted_Count        => Accepted,
            Rejected_Stale_Count  => Rejected_Stale,
            Rejected_Full_Count   => Rejected_Full);
      end Snapshot;
   end Event_Bridge;
end Archive.Tasking.Services;
