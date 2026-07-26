package Archive.Writes.Results is
   type Write_Status is
     (Write_Completed,
      Write_Blocked_By_Plan,
      Write_Failed_Containment,
      Write_Failed_Staging,
      Write_Failed_Verification,
      Write_Failed_Source_Changed,
      Write_Cancelled,
      Write_Failed_Publish);

   type Publish_Result is record
      Status : Write_Status := Write_Completed;
   end record;
end Archive.Writes.Results;
