pragma SPARK_Mode (On);

package body Archive_Release_Proof is
   function Checked_Sum
     (Left  : Bounded_Count;
      Right : Bounded_Count)
      return Bounded_Count
   is
   begin
      return Left + Right;
   end Checked_Sum;

   function Accepted_Extraction
     (Path_Accepted : Boolean;
      Has_Conflict  : Boolean;
      Under_Root     : Boolean;
      Verified       : Boolean)
      return Boolean
   is
   begin
      return Path_Accepted and then not Has_Conflict and then Under_Root and then Verified;
   end Accepted_Extraction;

   function Stable_Entry_Position
     (Archive_Ordinal : Safe_Index;
      Synthetic_Count : Bounded_Count)
      return Safe_Index
   is
   begin
      return Archive_Ordinal + Safe_Index (Synthetic_Count);
   end Stable_Entry_Position;

   function Publish_Output_Allowed
     (Path_Accepted      : Boolean;
      Under_Root         : Boolean;
      Checksum_Verified  : Boolean;
      Temporary_Closed   : Boolean;
      Cancellation_Point : Boolean)
      return Boolean
   is
   begin
      return Path_Accepted
        and then Under_Root
        and then Checksum_Verified
        and then Temporary_Closed
        and then not Cancellation_Point;
   end Publish_Output_Allowed;

   function Save_As_Publication_Allowed
     (Plan_Ready       : Boolean;
      Staging_Complete : Boolean;
      Reopened_Cleanly : Boolean;
      Source_Current   : Boolean;
      Dirty_Cleared    : Boolean)
      return Boolean
   is
   begin
      return Plan_Ready
        and then Staging_Complete
        and then Reopened_Cleanly
        and then Source_Current
        and then Dirty_Cleared;
   end Save_As_Publication_Allowed;

   function Queue_Count_After_Coalesce
     (Current_Count : Bounded_Count;
      Capacity      : Bounded_Count;
      Has_Terminal  : Boolean;
      Is_Progress   : Boolean)
      return Bounded_Count
   is
   begin
      if Is_Progress and then not Has_Terminal then
         return Current_Count;
      elsif Current_Count < Capacity then
         return Current_Count + 1;
      else
         return Capacity;
      end if;
   end Queue_Count_After_Coalesce;
end Archive_Release_Proof;
