with Archive.Tasking.Events;

package body Archive.Operations.Opening is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Opening.Open_Status;
   use type Archive.Tasking.Events.Event_Kind;
   use type Archive.Types.Generation_Id;

   procedure Start_Open
     (Self      : in out Coordinator;
      Model     : in out Archive.Model.Application_Model;
      Path      : String;
      Max_Bytes : Positive := Archive.Archives.Opening.Default_Max_Open_Bytes)
   is
      Session : constant Archive.Types.Generation_Id := Archive.Model.Session_Generation (Model);
   begin
      Self.Operation := Archive.Model.Begin_Open (Model);
      Self.Path := To_Unbounded_String (Path);
      Self.Status := Operation_Running;
      Self.Bridge.Configure
        ((Current_Session      => Session,
          Current_Open         => Self.Operation,
          Current_Preview      => Archive.Types.No_Generation,
          Current_Verification => Archive.Types.No_Generation,
          Current_Extraction   => Archive.Types.No_Generation,
          Current_Save         => Archive.Types.No_Generation,
          Current_Source_Watch => Archive.Types.No_Generation,
          Shutting_Down        => False));
      Self.Worker := new Archive.Archives.Opening.Tasks.Open_Worker;
      Self.Worker.Start
        (Path           => Path,
         Session        => Session,
         Operation      => Self.Operation,
         Max_Bytes      => Max_Bytes,
         Check_Identity => True,
         Bridge         => Self.Bridge'Unchecked_Access,
         Results        => Self.Results'Unchecked_Access);
   end Start_Open;

   procedure Drain_Events
     (Self   : in out Coordinator;
      Model  : in out Archive.Model.Application_Model;
      Result : out Drain_Result)
   is
      Event              : Archive.Tasking.Events.Event;
      Found              : Boolean := False;
      Prepared_Operation : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Prepared           : Archive.Archives.Opening.Prepared_Open_Result;
      Have_Prepared      : Boolean := False;
   begin
      Result := (others => <>);
      Self.Bridge.Dequeue (Event, Found);
      if not Found then
         Result.Status := Self.Status;
         return;
      end if;

      Result.Event_Seen := True;
      if Event.Kind = Archive.Tasking.Events.Open_Completed then
         Self.Results.Take (Prepared_Operation, Prepared, Have_Prepared);
         if Have_Prepared then
            declare
               Applied : constant Archive.Archives.Opening.Open_Attempt_Result :=
                 Archive.Archives.Opening.Publish_Prepared
                   (Model, Prepared_Operation, To_String (Self.Path), Prepared);
            begin
               Result.Applied := Applied.Published;
               Result.Open_Status := Applied.Status;
               Result.Operation := Applied.Operation;
               if Applied.Status = Archive.Archives.Opening.Open_Rejected_Stale then
                  Self.Status := Operation_Rejected_Stale;
               elsif Applied.Published then
                  Self.Status := Operation_Completed;
               else
                  Self.Status := Operation_Failed;
               end if;
            end;
         else
            Self.Status := Operation_Failed;
         end if;
      end if;

      Self.Bridge.Acknowledge_Wakeup;
      Result.Wakeup_Acknowledged := True;
      Result.Status := Self.Status;
   end Drain_Events;

   function Active (Self : Coordinator) return Boolean is
   begin
      return Self.Status = Operation_Running;
   end Active;

   function Last_Status (Self : Coordinator) return Operation_Status is
   begin
      return Self.Status;
   end Last_Status;

   function Current_Operation (Self : Coordinator) return Archive.Types.Generation_Id is
   begin
      return Self.Operation;
   end Current_Operation;
end Archive.Operations.Opening;
