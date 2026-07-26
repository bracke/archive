with Archive.Tasking.Events;
with Archive.Tasking.Queues;
with Archive.Types;

package Archive.Tasking.Services is
   type Publish_Result is record
      Accepted         : Boolean := False;
      Stale            : Boolean := False;
      Queue_Full       : Boolean := False;
      Wakeup_Requested : Boolean := False;
      Coalesced        : Boolean := False;
   end record;

   type Bridge_State is record
      Current_Session      : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Current_Open         : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Current_Preview      : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Current_Verification : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Current_Extraction   : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Current_Save         : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Current_Source_Watch : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Shutting_Down        : Boolean := False;
   end record;

   type Operation_Owner is
     (No_Operation_Owner,
      Open_Owner,
      Preview_Owner,
      Verification_Owner,
      Extraction_Owner,
      Save_Owner,
      Source_Watch_Owner,
      Shutdown_Owner);

   type Supervision_Snapshot is record
      State                 : Bridge_State;
      Last_Accepted_Owner   : Operation_Owner := No_Operation_Owner;
      Last_Rejected_Owner   : Operation_Owner := No_Operation_Owner;
      Latest_Progress_Ready : Boolean := False;
      Queue                 : Archive.Tasking.Queues.Queue_Policy_Snapshot;
      Wakeup_Pending        : Boolean := False;
      Accepted_Count        : Natural := 0;
      Rejected_Stale_Count  : Natural := 0;
      Rejected_Full_Count   : Natural := 0;
   end record;

   protected type Event_Bridge (Capacity : Positive) is
      procedure Configure (State : Bridge_State);
      procedure Publish
        (Item   : Archive.Tasking.Events.Event;
         Result : out Publish_Result);
      procedure Dequeue
        (Item  : out Archive.Tasking.Events.Event;
         Found : out Boolean);
      procedure Take_Latest_Progress
        (Item  : out Archive.Tasking.Events.Event;
         Found : out Boolean);
      procedure Acknowledge_Wakeup;
      procedure Begin_Shutdown;
      function Wakeup_Pending return Boolean;
      function Queue_Count return Natural;
      function Accepted_Count return Natural;
      function Rejected_Stale_Count return Natural;
      function Rejected_Full_Count return Natural;
      function Snapshot return Supervision_Snapshot;
   private
      Queue               : Archive.Tasking.Queues.Event_Queue (Capacity);
      State               : Bridge_State;
      Wakeup              : Boolean := False;
      Latest_Progress     : Archive.Tasking.Events.Event;
      Has_Latest_Progress : Boolean := False;
      Accepted            : Natural := 0;
      Rejected_Stale      : Natural := 0;
      Rejected_Full       : Natural := 0;
      Last_Accepted       : Operation_Owner := No_Operation_Owner;
      Last_Rejected       : Operation_Owner := No_Operation_Owner;
   end Event_Bridge;
end Archive.Tasking.Services;
