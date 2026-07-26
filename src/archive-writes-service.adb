with Ada.Directories;
with Ada.Strings.Unbounded;

with Archive.Archives.Readers.Dispatch;
with Archive.Archives.Formats;
with Archive.Writes.Plans;
with Archive.Source_Monitoring;

package body Archive.Writes.Service is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Formats.Format_Id;
   use type Archive.Writes.Dispatch.Zip_Method;
   use type Archive.Writes.Plans.Write_Action;
   use type Archive.Writes.Results.Write_Status;
   use type Archive.Source_Monitoring.Source_Status;

   function Needs_Source_Bytes (Plan : Archive.Writes.Plans.Write_Plan) return Boolean is
   begin
      for Change of Plan.Changes loop
         if Change.Request.Action = Archive.Writes.Plans.Replace_File
           or else Change.Request.Action = Archive.Writes.Plans.Remove_Entry
           or else Change.Request.Action = Archive.Writes.Plans.Rename_Entry
         then
            return True;
         end if;
      end loop;
      return False;
   end Needs_Source_Bytes;

   function Save_As
     (Model       : in out Archive.Model.Application_Model;
      Destination : String;
      Method      : Archive.Writes.Dispatch.Zip_Method := Archive.Writes.Dispatch.Zip_Deflate_Method;
      Overwrite   : Boolean := False)
      return Save_Result
   is
      Plan : constant Archive.Writes.Plans.Write_Plan := Archive.Model.Current_Write_Plan (Model);
      Source_Path : constant String := Archive.Model.Source_Path (Model);
      Source_FP   : constant Archive.Source_Monitoring.Source_Fingerprint :=
        Archive.Model.Source_Fingerprint (Model);
   begin
      if not Archive.Model.Has_Saveable_Write_Plan (Model) then
         Archive.Model.Publish_Write_Result
           (Model,
            Success => False,
            Status  => Archive.Writes.Results.Write_Blocked_By_Plan);
         return
           (Status         => Save_Not_Ready,
            Payload_Status => Archive.Archives.Errors.Invalid_Format,
            Publish_Status => Archive.Writes.Results.Write_Blocked_By_Plan,
            Operation      => Archive.Model.Current_Write_Generation (Model));
      end if;

      Archive.Model.Begin_Save (Model);
      declare
         Operation : constant Archive.Types.Generation_Id :=
           Archive.Model.Current_Save_Generation (Model);
      begin
         if Overwrite
           and then Source_Path = Destination
           and then Source_FP.Status = Archive.Source_Monitoring.Source_Ready
           and then not Archive.Source_Monitoring.Same_Source
             (Source_FP, Archive.Source_Monitoring.Fingerprint (Destination))
         then
            declare
               Accepted : constant Boolean :=
                 Archive.Model.Publish_Write_Result
                   (Model, Operation,
                    Success => False,
                    Status  => Archive.Writes.Results.Write_Failed_Source_Changed);
            begin
               pragma Unreferenced (Accepted);
            end;
            return
              (Status         => Save_Publish_Failed,
               Payload_Status => Archive.Archives.Errors.Ok,
               Publish_Status => Archive.Writes.Results.Write_Failed_Source_Changed,
               Operation      => Operation);
         end if;

         declare
            Source_Required : constant Boolean := Needs_Source_Bytes (Plan);
            Source_Available : constant Boolean :=
              Source_Path /= "" and then Ada.Directories.Exists (Source_Path);
         begin
            if Source_Required and then not Source_Available then
               declare
                  Accepted : constant Boolean :=
                    Archive.Model.Publish_Write_Result
                      (Model, Operation,
                       Success => False,
                       Status  => Archive.Writes.Results.Write_Blocked_By_Plan);
               begin
                  pragma Unreferenced (Accepted);
               end;
               return
                 (Status         => Save_Payload_Failed,
                  Payload_Status => Archive.Archives.Errors.Read_Failed,
                  Publish_Status => Archive.Writes.Results.Write_Blocked_By_Plan,
                  Operation      => Operation);
            end if;

            declare
               Published : constant Archive.Writes.Results.Publish_Result :=
                 Archive.Writes.Dispatch.Publish
                   (Archive.Model.Published_Format (Model),
                    Destination,
                    Plan,
                    Method,
                    Source_Path => (if Source_Required then Source_Path else ""),
                    Source_Name => Source_Path,
                    Overwrite   => Overwrite);
            begin
               if Published.Status = Archive.Writes.Results.Write_Completed then
                  declare
                     Reopened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
                       Archive.Archives.Readers.Dispatch.Open_File
                         (Destination,
                          Source_Name => Destination,
                          Retain_Backing =>
                            Archive.Model.Published_Format (Model) =
                            Archive.Archives.Formats.Tar_GZip_Format);
                     Accepted : Boolean := False;
                  begin
                     if Reopened.Status = Archive.Archives.Errors.Ok then
                        Accepted :=
                          Archive.Model.Publish_Saved_Archive_Index
                            (Model, Operation, Destination, Reopened.Index, Reopened.Format,
                             Archive.Writes.Results.Write_Completed,
                             Backing_Path => To_String (Reopened.Backing_Path));
                     end if;

                     if not Accepted then
                        Accepted :=
                          Archive.Model.Publish_Write_Result
                            (Model, Operation,
                             Success => True,
                             Status  => Archive.Writes.Results.Write_Completed);
                     end if;
                  end;
               else
                  declare
                     Accepted : constant Boolean :=
                       Archive.Model.Publish_Write_Result
                         (Model, Operation,
                          Success => False,
                          Status  => Published.Status);
                  begin
                     pragma Unreferenced (Accepted);
                  end;
               end if;
               return
                 (Status         =>
                    (if Published.Status = Archive.Writes.Results.Write_Completed
                     then Save_Completed
                     else Save_Publish_Failed),
                  Payload_Status => Archive.Archives.Errors.Ok,
                  Publish_Status => Published.Status,
                  Operation      => Operation);
            end;
         end;
      end;
   end Save_As;
end Archive.Writes.Service;
