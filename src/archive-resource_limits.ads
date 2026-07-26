with Interfaces;

package Archive.Resource_Limits is
   type Limit_Id is
     (Physical_Entry_Count,
      Synthetic_Directory_Count,
      Path_Length,
      Path_Component_Count,
      Path_Depth,
      Metadata_Bytes_Per_Entry,
      Retained_Warnings,
      Preview_Input_Bytes,
      Preview_Output_Bytes,
      Image_Pixels,
      Per_Entry_Extraction_Output,
      Total_Extraction_Output,
      Compression_Ratio,
      Zlib_Input_Chunk_Bytes,
      Zlib_Output_Chunk_Bytes,
      Event_Queue_Capacity,
      Temporary_Backing_Bytes);

   type Limit_Value is new Interfaces.Unsigned_64;

   type Validation_Status is
     (Accepted,
      Clamped_To_Hard_Ceiling,
      Rejected_Zero,
      Rejected_Above_Hard_Ceiling);

   type Validation_Result is record
      Status    : Validation_Status := Accepted;
      Effective : Limit_Value := 0;
      Ceiling   : Limit_Value := 0;
   end record;

   function Hard_Ceiling (Id : Limit_Id) return Limit_Value;
   function Default_Configured (Id : Limit_Id) return Limit_Value;

   function Validate
     (Id              : Limit_Id;
      Configured      : Limit_Value;
      Clamp_To_Hard   : Boolean := True;
      Zero_Is_Allowed : Boolean := False)
      return Validation_Result;
end Archive.Resource_Limits;
