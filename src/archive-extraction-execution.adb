with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

with Archive.Archives.Entries;
with Archive.Extraction.Paths;
with Archive.Temporary_Resources;
with Archive.Verification.CRC32;

package body Archive.Extraction.Execution is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Kind;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Extraction.Plans.Plan_Status;
   use type Archive.Extraction.Results.Extraction_Status;
   use type Archive.Resource_Limits.Limit_Value;
   use type Archive.Types.CRC32_Value;
   use type Archive.Extraction.Paths.Path_Decision;

   function Parent_Directory (Path : String) return String is
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '/' then
            if Index = Path'First then
               return "/";
            end if;
            return Path (Path'First .. Index - 1);
         end if;
      end loop;
      return ".";
   end Parent_Directory;

   function Publish_Directory
     (Destination_Root : String;
      Plan             : Archive.Extraction.Plans.Plan_Entry)
      return Archive.Extraction.Results.File_Result
   is
      Relative : constant String := To_String (Plan.Path.Relative_Key);
      Root     : constant String :=
        (if Destination_Root'Length > 1 and then Destination_Root (Destination_Root'Last) = '/'
         then Destination_Root (Destination_Root'First .. Destination_Root'Last - 1)
         else Destination_Root);
      Target   : constant String := Root & "/" & Relative;
   begin
      if Plan.Path.Decision /= Archive.Extraction.Paths.Path_Accepted or else Plan.Conflict then
         return (Status => Archive.Extraction.Results.Blocked_By_Plan);
      elsif Plan.Kind /= Archive.Archives.Entries.Directory then
         return (Status => Archive.Extraction.Results.Blocked_By_Plan);
      elsif not Archive.Temporary_Resources.Under_Root (Root, Target) then
         return (Status => Archive.Extraction.Results.Failed_Containment);
      elsif Ada.Directories.Exists (Target)
        and then Ada.Directories.Kind (Target) /= Ada.Directories.Directory
      then
         return (Status => Archive.Extraction.Results.Blocked_By_Plan);
      end if;

      Ada.Directories.Create_Path (Target);
      return (Status => Archive.Extraction.Results.Completed);
   exception
      when others =>
         return (Status => Archive.Extraction.Results.Failed_Write);
   end Publish_Directory;

   function Publish_File_Stream
     (Destination_Root : String;
      Plan             : Archive.Extraction.Plans.Plan_Entry;
      Provider         : not null Stream_Payload_Provider;
      Bytes_Written    : out Archive.Resource_Limits.Limit_Value;
      Overwrite        : Boolean := False;
      Fault            : Publish_Fault_Point := No_Publish_Fault;
      Max_Output_Bytes : Archive.Resource_Limits.Limit_Value :=
        Archive.Resource_Limits.Default_Configured
          (Archive.Resource_Limits.Per_Entry_Extraction_Output))
      return Archive.Extraction.Results.File_Result
   is
      Relative : constant String := To_String (Plan.Path.Relative_Key);
      Root     : constant String :=
        (if Destination_Root'Length > 1 and then Destination_Root (Destination_Root'Last) = '/'
         then Destination_Root (Destination_Root'First .. Destination_Root'Last - 1)
         else Destination_Root);
      Target   : constant String := Root & "/" & Relative;
      Temp     : constant String :=
        Archive.Temporary_Resources.Fresh_Sibling_Path (Root, Target, "tmp");
      File     : Ada.Streams.Stream_IO.File_Type;
      Written  : Archive.Resource_Limits.Limit_Value := 0;
      CRC      : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
      Consumer_Status : Archive.Extraction.Results.Extraction_Status :=
        Archive.Extraction.Results.Completed;

      procedure Consume
        (Bytes : Zlib.Byte_Array;
         Continue : in out Boolean)
      is
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
      begin
         if Consumer_Status /= Archive.Extraction.Results.Completed then
            Continue := False;
            return;
         elsif Written > Max_Output_Bytes
           or else Archive.Resource_Limits.Limit_Value (Bytes'Length) > Max_Output_Bytes - Written
         then
            Consumer_Status := Archive.Extraction.Results.Failed_Limit;
            Continue := False;
            return;
         end if;

         for Index in Bytes'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
              Ada.Streams.Stream_Element (Bytes (Index));
         end loop;

         Archive.Verification.CRC32.Update (CRC, Bytes);
         Ada.Streams.Stream_IO.Write (File, Data);
         Written := Written + Archive.Resource_Limits.Limit_Value (Bytes'Length);
      exception
         when others =>
            Consumer_Status := Archive.Extraction.Results.Failed_Write;
         Continue := False;
      end Consume;
   begin
      Bytes_Written := 0;
      if Plan.Path.Decision /= Archive.Extraction.Paths.Path_Accepted or else Plan.Conflict then
         return (Status => Archive.Extraction.Results.Blocked_By_Plan);
      elsif Plan.Kind /= Archive.Archives.Entries.Regular_File then
         return (Status => Archive.Extraction.Results.Blocked_By_Plan);
      elsif not Archive.Temporary_Resources.Under_Root (Root, Target) then
         return (Status => Archive.Extraction.Results.Failed_Containment);
      elsif Temp = "" then
         return (Status => Archive.Extraction.Results.Failed_Publish);
      elsif Ada.Directories.Exists (Target) and then not Overwrite then
         return (Status => Archive.Extraction.Results.Blocked_By_Plan);
      end if;

      Ada.Directories.Create_Path (Parent_Directory (Target));
      if Fault = Fault_Before_Write then
         return (Status => Archive.Extraction.Results.Failed_Write);
      elsif Fault = Fault_Target_Replaced then
         return (Status => Archive.Extraction.Results.Failed_Containment);
      end if;

      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Temp);
      declare
         Streamed : constant Stream_Payload_Result :=
           Provider.all (Plan.Source, Consume'Unrestricted_Access);
      begin
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Bytes_Written := Written;

         if Consumer_Status /= Archive.Extraction.Results.Completed then
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
            return (Status => Consumer_Status);
         elsif Streamed.Status /= Archive.Extraction.Results.Completed then
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
            return (Status => Streamed.Status);
         elsif Written /= Streamed.Bytes_Written then
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
            return (Status => Archive.Extraction.Results.Failed_Write);
         elsif Plan.Expected_CRC32.Present
           and then Archive.Verification.CRC32.Final (CRC) /= Plan.Expected_CRC32.Value
         then
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
            return (Status => Archive.Extraction.Results.Failed_Checksum);
         elsif Fault = Fault_After_Write or else Fault = Fault_After_Close then
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
            return (Status => Archive.Extraction.Results.Failed_Write);
         end if;
      end;

      if not Archive.Temporary_Resources.Under_Root (Root, Target) then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Extraction.Results.Failed_Containment);
      elsif Fault = Fault_Before_Rename then
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         return (Status => Archive.Extraction.Results.Failed_Publish);
      end if;

      if Ada.Directories.Exists (Target) then
         declare
            Backup : constant String :=
              Archive.Temporary_Resources.Fresh_Sibling_Path (Root, Target, "old");
         begin
            if Backup = "" then
               if Ada.Directories.Exists (Temp) then
                  Ada.Directories.Delete_File (Temp);
               end if;
               return (Status => Archive.Extraction.Results.Failed_Publish);
            end if;

            if Ada.Directories.Exists (Backup) then
               Ada.Directories.Delete_File (Backup);
            end if;
            Ada.Directories.Rename (Target, Backup);
            begin
               Ada.Directories.Rename (Temp, Target);
               Ada.Directories.Delete_File (Backup);
            exception
               when others =>
                  if Ada.Directories.Exists (Target) then
                     Ada.Directories.Delete_File (Target);
                  end if;
                  if Ada.Directories.Exists (Backup) then
                     Ada.Directories.Rename (Backup, Target);
                  end if;
                  raise;
            end;
         end;
      else
         Ada.Directories.Rename (Temp, Target);
      end if;

      return (Status => Archive.Extraction.Results.Completed);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         if Ada.Directories.Exists (Temp) then
            begin
               Ada.Directories.Delete_File (Temp);
            exception
               when others =>
                  null;
            end;
         end if;
         return (Status => Archive.Extraction.Results.Failed_Write);
   end Publish_File_Stream;

   function Execute_Plan_Streaming
     (Destination_Root : String;
      Plan             : Archive.Extraction.Plans.Extraction_Plan;
      Provider         : Stream_Payload_Provider;
      Cancelled        : Cancellation_Check := null;
      Overwrite        : Boolean := False;
      Per_Entry_Limit  : Archive.Resource_Limits.Limit_Value :=
        Archive.Resource_Limits.Default_Configured
          (Archive.Resource_Limits.Per_Entry_Extraction_Output);
      Total_Limit      : Archive.Resource_Limits.Limit_Value :=
        Archive.Resource_Limits.Default_Configured
          (Archive.Resource_Limits.Total_Extraction_Output))
      return Archive.Extraction.Results.Plan_Result
   is
      Result : Archive.Extraction.Results.Plan_Result;
      Total_Output : Archive.Resource_Limits.Limit_Value := 0;

      procedure Note (Item : Archive.Extraction.Results.File_Result) is
      begin
         Result.Last_Status := Item.Status;
         if Item.Status = Archive.Extraction.Results.Completed then
            Result.Completed_Count := Result.Completed_Count + 1;
         elsif Item.Status = Archive.Extraction.Results.Cancelled then
            null;
         elsif Item.Status = Archive.Extraction.Results.Blocked_By_Plan then
            Result.Blocked_Count := Result.Blocked_Count + 1;
         else
            Result.Failed_Count := Result.Failed_Count + 1;
         end if;
      end Note;
   begin
      if Plan.Status /= Archive.Extraction.Plans.Plan_Ready then
         return
           (Status          => Archive.Extraction.Results.Execution_Blocked,
            Completed_Count => 0,
            Failed_Count    => 0,
            Blocked_Count   => Natural (Plan.Entries.Length),
            Last_Status     => Archive.Extraction.Results.Blocked_By_Plan);
      end if;

      for Item of Plan.Entries loop
         declare
            Published : Archive.Extraction.Results.File_Result;
            Remaining_Total : Archive.Resource_Limits.Limit_Value := 0;
            Entry_Output : Archive.Resource_Limits.Limit_Value := 0;
         begin
            if Cancelled /= null and then Cancelled.all then
               Result.Last_Status := Archive.Extraction.Results.Cancelled;
               Result.Status :=
                 (if Result.Completed_Count > 0
                  then Archive.Extraction.Results.Execution_Partial
                  else Archive.Extraction.Results.Execution_Cancelled);
               return Result;
            end if;

            if Item.Kind = Archive.Archives.Entries.Directory then
               Published := Publish_Directory (Destination_Root, Item);
            elsif Item.Kind = Archive.Archives.Entries.Regular_File then
               if Provider = null then
                  Published := (Status => Archive.Extraction.Results.Failed_Write);
               elsif Total_Output >= Total_Limit then
                  Published := (Status => Archive.Extraction.Results.Failed_Limit);
               else
                  Remaining_Total := Total_Limit - Total_Output;
                  Published :=
                    Publish_File_Stream
                      (Destination_Root, Item, Provider, Entry_Output,
                       Overwrite => Overwrite,
                       Fault => No_Publish_Fault,
                       Max_Output_Bytes =>
                         Archive.Resource_Limits.Limit_Value'Min
                           (Per_Entry_Limit, Remaining_Total));
                  if Published.Status = Archive.Extraction.Results.Completed then
                     Total_Output := Total_Output + Entry_Output;
                  end if;
               end if;
            else
               Published := (Status => Archive.Extraction.Results.Blocked_By_Plan);
            end if;

            Note (Published);

            if Cancelled /= null and then Cancelled.all then
               Result.Last_Status := Archive.Extraction.Results.Cancelled;
               Result.Status :=
                 (if Result.Completed_Count > 0
                  then Archive.Extraction.Results.Execution_Partial
                  else Archive.Extraction.Results.Execution_Cancelled);
               return Result;
            end if;

            exit when Published.Status /= Archive.Extraction.Results.Completed;
         end;
      end loop;

      if Result.Failed_Count > 0 or else Result.Blocked_Count > 0 then
         if Result.Completed_Count > 0 then
            Result.Status := Archive.Extraction.Results.Execution_Partial;
         elsif Result.Blocked_Count > 0 then
            Result.Status := Archive.Extraction.Results.Execution_Blocked;
         else
            Result.Status := Archive.Extraction.Results.Execution_Failed;
         end if;
      else
         Result.Status := Archive.Extraction.Results.Execution_Completed;
         Result.Last_Status := Archive.Extraction.Results.Completed;
      end if;

      return Result;
   exception
      when others =>
         return
           (Status          =>
              (if Result.Completed_Count > 0
               then Archive.Extraction.Results.Execution_Partial
               else Archive.Extraction.Results.Execution_Failed),
            Completed_Count => Result.Completed_Count,
            Failed_Count    => Result.Failed_Count + 1,
            Blocked_Count   => Result.Blocked_Count,
            Last_Status     => Archive.Extraction.Results.Failed_Write);
   end Execute_Plan_Streaming;
end Archive.Extraction.Execution;
