with Archive.Archives.Errors;
with Archive.Archives.Formats;
with Archive.Archives.Index;
with Archive.Model;
with Archive.Resource_Limits;
with Archive.Source_Monitoring;
with Archive.Types;
with Zlib;

package Archive.Archives.Opening is
   function Default_Max_Open_Bytes return Positive is
     (Positive
        (Archive.Resource_Limits.Default_Configured
           (Archive.Resource_Limits.Preview_Input_Bytes)));

   type Open_Status is
     (Open_Completed,
      Open_Source_Failed,
      Open_Source_Changed,
      Open_Read_Failed,
      Open_Limit_Exceeded,
      Open_Unsupported_Format,
      Open_Invalid_Format,
      Open_Reader_Failed,
      Open_Rejected_Stale);

   type Open_Attempt_Result is record
      Status        : Open_Status := Open_Read_Failed;
      Error         : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Read_Failed;
      Format        : Archive.Archives.Formats.Format_Id := Archive.Archives.Formats.Unknown_Format;
      Operation     : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Source_Status : Archive.Source_Monitoring.Source_Status := Archive.Source_Monitoring.Source_Missing;
      Published     : Boolean := False;
   end record;

   type Prepared_Open_Result is record
      Status        : Open_Status := Open_Read_Failed;
      Error         : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Read_Failed;
      Format        : Archive.Archives.Formats.Format_Id := Archive.Archives.Formats.Unknown_Format;
      Source_Status : Archive.Source_Monitoring.Source_Status := Archive.Source_Monitoring.Source_Missing;
      Fingerprint   : Archive.Source_Monitoring.Source_Fingerprint;
      Index         : Archive.Archives.Index.Archive_Index;
      Backing_Path  : Archive.Types.UString;
   end record;

   function Prepare_Path
     (Path           : String;
      Max_Bytes      : Positive := Default_Max_Open_Bytes;
      Check_Identity : Boolean := True)
      return Prepared_Open_Result;

   function Publish_Prepared
     (Model     : in out Archive.Model.Application_Model;
      Operation : Archive.Types.Generation_Id;
      Path      : String;
      Prepared  : Prepared_Open_Result)
      return Open_Attempt_Result;

   function Open_Path
     (Model          : in out Archive.Model.Application_Model;
      Path           : String;
      Max_Bytes      : Positive := Default_Max_Open_Bytes;
      Check_Identity : Boolean := True)
      return Open_Attempt_Result;
end Archive.Archives.Opening;
