with Ada.Containers;

package body Archive.Tasking.Queues is
   use type Ada.Containers.Count_Type;
   use type Archive.Tasking.Events.Event_Kind;

   function Is_Progress (Item : Archive.Tasking.Events.Event) return Boolean is
   begin
      return Item.Kind = Archive.Tasking.Events.Extraction_Progress;
   end Is_Progress;

   function Is_Terminal (Item : Archive.Tasking.Events.Event) return Boolean is
   begin
      return Item.Kind in Archive.Tasking.Events.Open_Completed
      | Archive.Tasking.Events.Preview_Completed
      | Archive.Tasking.Events.Verification_Completed
      | Archive.Tasking.Events.Extraction_Completed
      | Archive.Tasking.Events.Save_Completed
      | Archive.Tasking.Events.Source_Changed
      | Archive.Tasking.Events.Shutdown;
   end Is_Terminal;

   function Is_Ordinary (Item : Archive.Tasking.Events.Event) return Boolean is
   begin
      return not Is_Progress (Item) and then not Is_Terminal (Item);
   end Is_Ordinary;

   protected body Event_Queue is
      procedure Enqueue
        (Item   : Archive.Tasking.Events.Event;
         Result : out Enqueue_Result)
      is
      begin
         if Items.Length < Ada.Containers.Count_Type (Capacity) then
            Items.Append (Item);
            Result := Enqueued;
         elsif Is_Progress (Item) then
            Rejected_Progress_Count := Rejected_Progress_Count + 1;
            Result := Rejected_Full;
         elsif Is_Terminal (Item) then
            for Index in Items.First_Index .. Items.Last_Index loop
               if Is_Progress (Items.Element (Index)) then
                  Items.Delete (Index);
                  Items.Append (Item);
                  Displaced_Progress_Count := Displaced_Progress_Count + 1;
                  Result := Enqueued;
                  return;
               end if;
            end loop;
            for Index in Items.First_Index .. Items.Last_Index loop
               if Is_Ordinary (Items.Element (Index)) then
                  Items.Delete (Index);
                  Items.Append (Item);
                  Displaced_Ordinary_Count := Displaced_Ordinary_Count + 1;
                  Result := Enqueued;
                  return;
               end if;
            end loop;
            Rejected_Terminal_Count := Rejected_Terminal_Count + 1;
            Result := Rejected_Full;
         else
            Rejected_Ordinary_Count := Rejected_Ordinary_Count + 1;
            Result := Rejected_Full;
         end if;
      end Enqueue;

      procedure Dequeue
        (Item  : out Archive.Tasking.Events.Event;
         Found : out Boolean)
      is
      begin
         if Items.Is_Empty then
            Item := (others => <>);
            Found := False;
         else
            Item := Items.First_Element;
            Items.Delete_First;
            Found := True;
         end if;
      end Dequeue;

      function Count return Natural is
      begin
         return Natural (Items.Length);
      end Count;

      function Is_Full return Boolean is
      begin
         return Items.Length >= Ada.Containers.Count_Type (Capacity);
      end Is_Full;

      function Snapshot return Queue_Policy_Snapshot is
         Result : Queue_Policy_Snapshot :=
           (Count                => Natural (Items.Length),
            Terminal_Count       => 0,
            Progress_Count       => 0,
            Ordinary_Count       => 0,
            Displaced_Progress   => Displaced_Progress_Count,
            Displaced_Ordinary   => Displaced_Ordinary_Count,
            Rejected_Progress    => Rejected_Progress_Count,
            Rejected_Ordinary    => Rejected_Ordinary_Count,
            Rejected_Terminal    => Rejected_Terminal_Count);
      begin
         if not Items.Is_Empty then
            for Index in Items.First_Index .. Items.Last_Index loop
               if Is_Progress (Items.Element (Index)) then
                  Result.Progress_Count := Result.Progress_Count + 1;
               elsif Is_Terminal (Items.Element (Index)) then
                  Result.Terminal_Count := Result.Terminal_Count + 1;
               else
                  Result.Ordinary_Count := Result.Ordinary_Count + 1;
               end if;
            end loop;
         end if;
         return Result;
      end Snapshot;
   end Event_Queue;
end Archive.Tasking.Queues;
