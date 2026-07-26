package body Archive.Preview.Service is
   use type Archive.Tasking.Events.Event_Decision;

   function Complete_Streamed_Entry
     (Item              : Archive.Archives.Entries.Archive_Entry;
      Producer          : not null Preview_Stream_Producer;
      Limits            : Archive.Preview.Preview_Limits;
      Cancelled         : Boolean;
      Event             : Archive.Tasking.Events.Event;
      Current_Session   : Archive.Types.Generation_Id;
      Current_Preview   : Archive.Types.Generation_Id)
      return Preview_Service_Result
   is
      Accumulator : Archive.Preview.Preview_Accumulator (Limits.Max_Input_Bytes);

      procedure Consume
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean)
      is
      begin
         Archive.Preview.Append (Accumulator, Bytes, Continue);
      end Consume;
   begin
      if Cancelled then
         return
           (Accepted       => False,
            Preview        => (others => <>),
            Bytes_Received => 0,
            Limit_Reached  => False);
      end if;

      if Archive.Tasking.Events.Classify
        (Event, Current_Session, Current_Preview)
        = Archive.Tasking.Events.Reject_Stale_Event
      then
         return
           (Accepted       => False,
            Preview        => (others => <>),
            Bytes_Received => 0,
            Limit_Reached  => False);
      end if;

      Archive.Preview.Initialize (Accumulator, Limits);
      declare
         Streamed : constant Preview_Stream_Status :=
           Producer.all (Consume'Unrestricted_Access);
      begin
         return
           (Accepted => True,
            Preview  =>
              Archive.Preview.Generate_Entry_From_Accumulator
                (Item, Accumulator, Streamed.Status, Streamed.Integrity),
            Bytes_Received => Archive.Preview.Bytes_Received (Accumulator),
            Limit_Reached  => Archive.Preview.Limit_Reached (Accumulator));
      end;
   end Complete_Streamed_Entry;
end Archive.Preview.Service;
