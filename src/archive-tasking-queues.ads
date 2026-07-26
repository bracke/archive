with Archive.Tasking.Events;

package Archive.Tasking.Queues is
   type Enqueue_Result is
     (Enqueued,
      Rejected_Full,
      Rejected_Progress_Displaced);

   type Queue_Policy_Snapshot is record
      Count                : Natural := 0;
      Terminal_Count       : Natural := 0;
      Progress_Count       : Natural := 0;
      Ordinary_Count       : Natural := 0;
      Displaced_Progress   : Natural := 0;
      Displaced_Ordinary   : Natural := 0;
      Rejected_Progress    : Natural := 0;
      Rejected_Ordinary    : Natural := 0;
      Rejected_Terminal    : Natural := 0;
   end record;

   protected type Event_Queue (Capacity : Positive) is
      procedure Enqueue
        (Item   : Archive.Tasking.Events.Event;
         Result : out Enqueue_Result);
      procedure Dequeue
        (Item  : out Archive.Tasking.Events.Event;
         Found : out Boolean);
      function Count return Natural;
      function Is_Full return Boolean;
      function Snapshot return Queue_Policy_Snapshot;
   private
      Items : Archive.Tasking.Events.Event_Vectors.Vector;
      Displaced_Progress_Count : Natural := 0;
      Displaced_Ordinary_Count : Natural := 0;
      Rejected_Progress_Count  : Natural := 0;
      Rejected_Ordinary_Count  : Natural := 0;
      Rejected_Terminal_Count  : Natural := 0;
   end Event_Queue;
end Archive.Tasking.Queues;
