with Archive.Extraction.Plans;
with Archive.Extraction.Results;
with Archive.Resource_Limits;
with Archive.Types;
with Zlib;

package Archive.Extraction.Execution is
   type Payload_Chunk_Consumer is access procedure
     (Bytes : Zlib.Byte_Array;
      Continue : in out Boolean);
   type Stream_Payload_Result is record
      Status : Archive.Extraction.Results.Extraction_Status :=
        Archive.Extraction.Results.Completed;
      Bytes_Written : Archive.Resource_Limits.Limit_Value := 0;
   end record;
   type Stream_Payload_Provider is access function
     (Source   : Archive.Types.Entry_Id;
      Consumer : not null Payload_Chunk_Consumer)
      return Stream_Payload_Result;
   type Cancellation_Check is access function return Boolean;
   type Publish_Fault_Point is
     (No_Publish_Fault,
      Fault_Before_Write,
      Fault_After_Write,
      Fault_After_Close,
      Fault_Before_Rename,
      Fault_Target_Replaced);

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
      return Archive.Extraction.Results.File_Result;

   function Publish_Directory
     (Destination_Root : String;
      Plan             : Archive.Extraction.Plans.Plan_Entry)
      return Archive.Extraction.Results.File_Result;

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
      return Archive.Extraction.Results.Plan_Result;
end Archive.Extraction.Execution;
