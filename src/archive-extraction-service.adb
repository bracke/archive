with Archive.Archives.Entries;
with Archive.Archives.Index;
with Archive.Archives.Readers.Dispatch;
with Archive.Extraction.Plans;
with Archive.Extraction.Paths;
with Archive.Resource_Limits;
with Archive.Settings;
with Archive.Source_Monitoring;
with Archive.Types;
with Zlib;

package body Archive.Extraction.Service is
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Extraction.Execution.Cancellation_Check;
   use type Archive.Extraction.Plans.Plan_Status;
   use type Archive.Extraction.Paths.Destination_Decision;
   use type Archive.Extraction.Results.Extraction_Status;
   use type Archive.Extraction.Results.Plan_Execution_Status;
   use type Archive.Model.Extraction_State;
   use type Archive.Source_Monitoring.Source_Status;

   function Extract_Planned
     (Model            : in out Archive.Model.Application_Model;
      Destination_Root : String;
      Overwrite        : Boolean := False;
      Check_Identity   : Boolean := True;
      Cancelled        : Archive.Extraction.Execution.Cancellation_Check := null)
      return Extract_Result
   is
      Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
        Archive.Model.Current_Extraction_Plan (Model);
      Path : constant String := Archive.Model.Source_Path (Model);
      Before : constant Archive.Source_Monitoring.Source_Fingerprint :=
        Archive.Model.Source_Fingerprint (Model);
      Settings : constant Archive.Settings.Settings_Model :=
        Archive.Model.Effective_Settings (Model);
      Payload_Error : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
   begin
      if Cancelled /= null and then Cancelled.all then
         Archive.Model.Publish_Extraction_Result
           (Model,
            Success        => False,
            Cancelled      => True,
            Plan_Status    => Archive.Extraction.Results.Execution_Cancelled,
            Publish_Status => Archive.Extraction.Results.Cancelled);
         return
           (Status          => Extract_Cancelled,
            Payload_Status  => Archive.Archives.Errors.Ok,
            Plan_Status     => Archive.Extraction.Results.Execution_Cancelled,
            Publish_Status  => Archive.Extraction.Results.Cancelled,
            Completed_Count => 0,
            Failed_Count    => 0,
            Blocked_Count   => 0);
      end if;

      if Archive.Model.Extraction_Phase (Model) /= Archive.Model.Extraction_Planned
        or else Plan.Status /= Archive.Extraction.Plans.Plan_Ready
      then
         Archive.Model.Publish_Extraction_Result
           (Model,
            Success        => False,
            Plan_Status    => Archive.Extraction.Results.Execution_Blocked,
            Publish_Status => Archive.Extraction.Results.Blocked_By_Plan,
            Blocked_Count  => Natural (Plan.Entries.Length));
         return
           (Status          => Extract_Not_Ready,
            Payload_Status  => Archive.Archives.Errors.Invalid_Format,
            Plan_Status     => Archive.Extraction.Results.Execution_Blocked,
            Publish_Status  => Archive.Extraction.Results.Blocked_By_Plan,
            Completed_Count => 0,
            Failed_Count    => 0,
            Blocked_Count   => Natural (Plan.Entries.Length));
      end if;

      if Archive.Extraction.Paths.Validate_Destination_Root (Destination_Root) /=
        Archive.Extraction.Paths.Destination_Accepted
      then
         Archive.Model.Publish_Extraction_Result
           (Model,
            Success        => False,
            Plan_Status    => Archive.Extraction.Results.Execution_Blocked,
            Publish_Status => Archive.Extraction.Results.Blocked_By_Plan,
            Blocked_Count  => Natural (Plan.Entries.Length));
         return
           (Status          => Extract_Destination_Failed,
            Payload_Status  => Archive.Archives.Errors.Invalid_Format,
            Plan_Status     => Archive.Extraction.Results.Execution_Blocked,
            Publish_Status  => Archive.Extraction.Results.Blocked_By_Plan,
            Completed_Count => 0,
            Failed_Count    => 0,
            Blocked_Count   => Natural (Plan.Entries.Length));
      end if;

      if Check_Identity
        and then not Archive.Source_Monitoring.Same_Source
          (Before, Archive.Source_Monitoring.Fingerprint (Path))
      then
         Archive.Model.Publish_Extraction_Result
           (Model,
            Success        => False,
            Plan_Status    => Archive.Extraction.Results.Execution_Failed,
            Publish_Status => Archive.Extraction.Results.Failed_Write,
            Failed_Count   => 1);
         return
           (Status          => Extract_Source_Changed,
            Payload_Status  => Archive.Archives.Errors.Read_Failed,
            Plan_Status     => Archive.Extraction.Results.Execution_Failed,
            Publish_Status  => Archive.Extraction.Results.Failed_Write,
            Completed_Count => 0,
            Failed_Count    => 1,
            Blocked_Count   => 0);
      end if;

      declare
         Payload_Path : constant String := Archive.Model.Payload_Source_Path (Model);
      begin
         if Cancelled /= null and then Cancelled.all then
            Archive.Model.Publish_Extraction_Result
              (Model,
               Success        => False,
               Cancelled      => True,
               Plan_Status    => Archive.Extraction.Results.Execution_Cancelled,
               Publish_Status => Archive.Extraction.Results.Cancelled);
            return
              (Status          => Extract_Cancelled,
               Payload_Status  => Archive.Archives.Errors.Ok,
               Plan_Status     => Archive.Extraction.Results.Execution_Cancelled,
               Publish_Status  => Archive.Extraction.Results.Cancelled,
               Completed_Count => 0,
               Failed_Count    => 0,
               Blocked_Count   => 0);
         end if;

         if Check_Identity
           and then not Archive.Source_Monitoring.Same_Source
             (Before, Archive.Source_Monitoring.Fingerprint (Path))
         then
            Archive.Model.Publish_Extraction_Result
              (Model,
               Success        => False,
               Plan_Status    => Archive.Extraction.Results.Execution_Failed,
               Publish_Status => Archive.Extraction.Results.Failed_Write,
               Failed_Count   => 1);
            return
              (Status          => Extract_Source_Changed,
               Payload_Status  => Archive.Archives.Errors.Read_Failed,
               Plan_Status     => Archive.Extraction.Results.Execution_Failed,
               Publish_Status  => Archive.Extraction.Results.Failed_Write,
               Completed_Count => 0,
               Failed_Count    => 1,
               Blocked_Count   => 0);
         end if;

         declare
            function Payload_For
              (Source   : Archive.Types.Entry_Id;
               Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
               return Archive.Extraction.Execution.Stream_Payload_Result
            is
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For
                   (Archive.Model.Published_Index (Model), Source);
               procedure Forward
                 (Bytes : Zlib.Byte_Array;
                  Continue : in out Boolean) is
               begin
                  Consumer.all (Bytes, Continue);
               end Forward;

               Payload : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
                 Archive.Archives.Readers.Dispatch.Stream_Payload_File
                   (Payload_Path, Path, Item, Forward'Access);
            begin
               if Payload.Status /= Archive.Archives.Errors.Ok
                 and then Payload.Status /= Archive.Archives.Errors.Cancelled
               then
                  Payload_Error := Payload.Status;
                  return
                    (Status => Archive.Extraction.Results.Failed_Write,
                     Bytes_Written => Archive.Resource_Limits.Limit_Value (Payload.Bytes_Written));
               end if;
               return
                 (Status => Archive.Extraction.Results.Completed,
                  Bytes_Written => Archive.Resource_Limits.Limit_Value (Payload.Bytes_Written));
            end Payload_For;

            Executed : constant Archive.Extraction.Results.Plan_Result :=
              Archive.Extraction.Execution.Execute_Plan_Streaming
                (Destination_Root, Plan, Payload_For'Unrestricted_Access,
                 Cancelled => Cancelled,
                 Overwrite => Overwrite,
                 Per_Entry_Limit => Settings.Per_Entry_Extraction_Limit,
                 Total_Limit     => Settings.Total_Extraction_Limit);
         begin
            if Payload_Error /= Archive.Archives.Errors.Ok then
               Archive.Model.Publish_Extraction_Result
                 (Model,
                  Success         => False,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
               return
                 (Status          => Extract_Payload_Failed,
                  Payload_Status  => Payload_Error,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
            elsif Executed.Status = Archive.Extraction.Results.Execution_Completed then
               Archive.Model.Publish_Extraction_Result
                 (Model,
                  Success         => True,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
               return
                 (Status          => Extract_Completed,
                  Payload_Status  => Archive.Archives.Errors.Ok,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
            elsif Executed.Status = Archive.Extraction.Results.Execution_Cancelled
              or else Executed.Last_Status = Archive.Extraction.Results.Cancelled
            then
               Archive.Model.Publish_Extraction_Result
                 (Model,
                  Success         => False,
                  Cancelled       => True,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
               return
                 (Status          => Extract_Cancelled,
                  Payload_Status  => Archive.Archives.Errors.Ok,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
            else
               Archive.Model.Publish_Extraction_Result
                 (Model,
                  Success         => False,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
               return
                 (Status          => Extract_Publish_Failed,
                  Payload_Status  => Archive.Archives.Errors.Ok,
                  Plan_Status     => Executed.Status,
                  Publish_Status  => Executed.Last_Status,
                  Completed_Count => Executed.Completed_Count,
                  Failed_Count    => Executed.Failed_Count,
                  Blocked_Count   => Executed.Blocked_Count);
            end if;
         end;
      end;
   exception
      when Constraint_Error =>
         Archive.Model.Publish_Extraction_Result
           (Model,
            Success        => False,
            Plan_Status    => Archive.Extraction.Results.Execution_Failed,
            Publish_Status => Archive.Extraction.Results.Failed_Limit,
            Failed_Count   => 1);
         return
           (Status          => Extract_Read_Failed,
            Payload_Status  => Archive.Archives.Errors.Limit_Exceeded,
            Plan_Status     => Archive.Extraction.Results.Execution_Failed,
            Publish_Status  => Archive.Extraction.Results.Failed_Write,
            Completed_Count => 0,
            Failed_Count    => 1,
            Blocked_Count   => 0);
      when others =>
         Archive.Model.Publish_Extraction_Result
           (Model,
            Success        => False,
            Plan_Status    => Archive.Extraction.Results.Execution_Failed,
            Publish_Status => Archive.Extraction.Results.Failed_Write,
            Failed_Count   => 1);
         return
           (Status          => Extract_Read_Failed,
            Payload_Status  => Archive.Archives.Errors.Read_Failed,
            Plan_Status     => Archive.Extraction.Results.Execution_Failed,
            Publish_Status  => Archive.Extraction.Results.Failed_Write,
            Completed_Count => 0,
            Failed_Count    => 1,
            Blocked_Count   => 0);
   end Extract_Planned;
end Archive.Extraction.Service;
