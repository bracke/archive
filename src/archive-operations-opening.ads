with Ada.Strings.Unbounded;

with Archive.Archives.Opening;
with Archive.Archives.Opening.Tasks;
with Archive.Model;
with Archive.Tasking.Services;
with Archive.Types;

package Archive.Operations.Opening is
   type Coordinator is limited private;

   type Operation_Status is
     (Operation_Idle,
      Operation_Running,
      Operation_Completed,
      Operation_Failed,
      Operation_Rejected_Stale);

   type Drain_Result is record
      Applied          : Boolean := False;
      Event_Seen       : Boolean := False;
      Status           : Operation_Status := Operation_Idle;
      Open_Status      : Archive.Archives.Opening.Open_Status :=
        Archive.Archives.Opening.Open_Read_Failed;
      Operation        : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Wakeup_Acknowledged : Boolean := False;
   end record;

   procedure Start_Open
     (Self      : in out Coordinator;
      Model     : in out Archive.Model.Application_Model;
      Path      : String;
      Max_Bytes : Positive := Archive.Archives.Opening.Default_Max_Open_Bytes);

   procedure Drain_Events
     (Self   : in out Coordinator;
      Model  : in out Archive.Model.Application_Model;
      Result : out Drain_Result);

   function Active (Self : Coordinator) return Boolean;
   function Last_Status (Self : Coordinator) return Operation_Status;
   function Current_Operation (Self : Coordinator) return Archive.Types.Generation_Id;

private
   type Open_Worker_Access is access Archive.Archives.Opening.Tasks.Open_Worker;

   type Coordinator is limited record
      Bridge    : aliased Archive.Tasking.Services.Event_Bridge (Capacity => 16);
      Results   : aliased Archive.Archives.Opening.Tasks.Result_Box;
      Worker    : Open_Worker_Access;
      Path      : Ada.Strings.Unbounded.Unbounded_String;
      Operation : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Status    : Operation_Status := Operation_Idle;
   end record;
end Archive.Operations.Opening;
