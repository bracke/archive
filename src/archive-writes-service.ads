with Archive.Archives.Errors;
with Archive.Model;
with Archive.Types;
with Archive.Writes.Dispatch;
with Archive.Writes.Results;

package Archive.Writes.Service is
   type Save_Status is
     (Save_Completed,
      Save_Not_Ready,
      Save_Payload_Failed,
      Save_Publish_Failed);

   type Save_Result is record
      Status         : Save_Status := Save_Not_Ready;
      Payload_Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Publish_Status : Archive.Writes.Results.Write_Status :=
        Archive.Writes.Results.Write_Completed;
      Operation      : Archive.Types.Generation_Id := Archive.Types.No_Generation;
   end record;

   function Save_As
     (Model       : in out Archive.Model.Application_Model;
      Destination : String;
      Method      : Archive.Writes.Dispatch.Zip_Method := Archive.Writes.Dispatch.Zip_Deflate_Method;
      Overwrite   : Boolean := False)
      return Save_Result;
end Archive.Writes.Service;
