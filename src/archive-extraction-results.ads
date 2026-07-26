package Archive.Extraction.Results is
   type Extraction_Status is
     (Completed,
      Blocked_By_Plan,
      Cancelled,
      Failed_Checksum,
      Failed_Containment,
      Failed_Limit,
      Failed_Write,
      Failed_Publish);

   type File_Result is record
      Status : Extraction_Status := Completed;
   end record;

   type Plan_Execution_Status is
     (Execution_Completed,
      Execution_Partial,
      Execution_Blocked,
      Execution_Cancelled,
      Execution_Failed);

   type Plan_Result is record
      Status          : Plan_Execution_Status := Execution_Completed;
      Completed_Count : Natural := 0;
      Failed_Count    : Natural := 0;
      Blocked_Count   : Natural := 0;
      Last_Status     : Extraction_Status := Completed;
   end record;
end Archive.Extraction.Results;
