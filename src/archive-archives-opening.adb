with Archive.Archives.Readers.Dispatch;
with Ada.Strings.Unbounded;

package body Archive.Archives.Opening is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Source_Monitoring.Source_Status;
   use type Archive.Types.Uncompressed_Size;

   function Status_For_Error (Error : Archive.Archives.Errors.Error_Code) return Open_Status is
   begin
      case Error is
         when Archive.Archives.Errors.Ok =>
            return Open_Completed;
         when Archive.Archives.Errors.Unsupported_Format | Archive.Archives.Errors.Unsupported_Method =>
            return Open_Unsupported_Format;
         when Archive.Archives.Errors.Invalid_Format =>
            return Open_Invalid_Format;
         when Archive.Archives.Errors.Limit_Exceeded =>
            return Open_Limit_Exceeded;
         when Archive.Archives.Errors.Read_Failed =>
            return Open_Read_Failed;
         when others =>
            return Open_Reader_Failed;
      end case;
   end Status_For_Error;

   function Prepare_Path
     (Path           : String;
      Max_Bytes      : Positive := Default_Max_Open_Bytes;
      Check_Identity : Boolean := True)
      return Prepared_Open_Result
   is
      Before    : constant Archive.Source_Monitoring.Source_Fingerprint :=
        Archive.Source_Monitoring.Fingerprint (Path);
      Empty_Index : Archive.Archives.Index.Archive_Index;
   begin
      if Before.Status /= Archive.Source_Monitoring.Source_Ready then
         return
           (Status        => Open_Source_Failed,
            Error         => Archive.Archives.Errors.Read_Failed,
            Format        => Archive.Archives.Formats.Unknown_Format,
            Source_Status => Before.Status,
            Fingerprint   => Before,
            Index         => Empty_Index,
            Backing_Path  => Null_Unbounded_String);
      end if;

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File
             (Path, Max_Bytes, Retain_Backing => True);
      begin
         if Check_Identity
           and then not Archive.Source_Monitoring.Same_Source
             (Before, Archive.Source_Monitoring.Fingerprint (Path))
         then
            return
              (Status        => Open_Source_Changed,
               Error         => Archive.Archives.Errors.Read_Failed,
               Format        => Archive.Archives.Formats.Unknown_Format,
               Source_Status => Before.Status,
               Fingerprint   => Before,
               Index         => Empty_Index,
               Backing_Path  => Null_Unbounded_String);
         end if;

         return
           (Status        => Status_For_Error (Opened.Status),
            Error         => Opened.Status,
            Format        => Opened.Format,
            Source_Status => Before.Status,
            Fingerprint   => Before,
            Index         => Opened.Index,
            Backing_Path  => Opened.Backing_Path);
      end;
   end Prepare_Path;

   function Publish_Prepared
     (Model     : in out Archive.Model.Application_Model;
      Operation : Archive.Types.Generation_Id;
      Path      : String;
      Prepared  : Prepared_Open_Result)
      return Open_Attempt_Result
   is
      Success  : constant Boolean := Prepared.Status = Open_Completed;
      Accepted : constant Boolean :=
        Archive.Model.Publish_Open_Result
          (Model, Operation, Path, Prepared.Fingerprint, Prepared.Index,
           Prepared.Format, Success => Success,
           Backing_Path => To_String (Prepared.Backing_Path));
   begin
      return
        (Status        => (if Accepted then Prepared.Status else Open_Rejected_Stale),
         Error         => Prepared.Error,
         Format        => Prepared.Format,
         Operation     => Operation,
         Source_Status => Prepared.Source_Status,
         Published     => Accepted and then Success);
   end Publish_Prepared;

   function Open_Path
     (Model          : in out Archive.Model.Application_Model;
      Path           : String;
      Max_Bytes      : Positive := Default_Max_Open_Bytes;
      Check_Identity : Boolean := True)
      return Open_Attempt_Result
   is
      Operation : constant Archive.Types.Generation_Id := Archive.Model.Begin_Open (Model);
      Prepared  : constant Prepared_Open_Result :=
        Prepare_Path (Path, Max_Bytes, Check_Identity);
   begin
      return Publish_Prepared (Model, Operation, Path, Prepared);
   end Open_Path;
end Archive.Archives.Opening;
