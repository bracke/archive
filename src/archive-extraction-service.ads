with Archive.Archives.Errors;
with Archive.Extraction.Execution;
with Archive.Extraction.Results;
with Archive.Model;

package Archive.Extraction.Service is
   type Extract_Status is
     (Extract_Completed,
      Extract_Not_Ready,
      Extract_Source_Changed,
      Extract_Read_Failed,
      Extract_Payload_Failed,
      Extract_Publish_Failed,
      Extract_Destination_Failed,
      Extract_Cancelled);

   type Extract_Result is record
      Status         : Extract_Status := Extract_Not_Ready;
      Payload_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Plan_Status    : Archive.Extraction.Results.Plan_Execution_Status :=
        Archive.Extraction.Results.Execution_Completed;
      Publish_Status : Archive.Extraction.Results.Extraction_Status :=
        Archive.Extraction.Results.Completed;
      Completed_Count : Natural := 0;
      Failed_Count    : Natural := 0;
      Blocked_Count   : Natural := 0;
   end record;

   function Extract_Planned
     (Model            : in out Archive.Model.Application_Model;
      Destination_Root : String;
      Overwrite        : Boolean := False;
      Check_Identity   : Boolean := True;
      Cancelled        : Archive.Extraction.Execution.Cancellation_Check := null)
      return Extract_Result;
end Archive.Extraction.Service;
