pragma SPARK_Mode (On);

package Archive_Release_Proof is
   subtype Bounded_Count is Natural range 0 .. 1_000_000;
   subtype Safe_Index is Positive range 1 .. 1_000_000;

   function Checked_Sum
     (Left  : Bounded_Count;
      Right : Bounded_Count)
      return Bounded_Count
   with
     Pre  => Left <= Bounded_Count'Last - Right,
     Post => Checked_Sum'Result = Left + Right;

   function Accepted_Extraction
     (Path_Accepted : Boolean;
      Has_Conflict  : Boolean;
      Under_Root     : Boolean;
      Verified       : Boolean)
      return Boolean
   with
     Post =>
       Accepted_Extraction'Result =
         (Path_Accepted and then not Has_Conflict and then Under_Root and then Verified);

   function Stable_Entry_Position
     (Archive_Ordinal : Safe_Index;
      Synthetic_Count : Bounded_Count)
      return Safe_Index
   with
     Pre  => Synthetic_Count < Bounded_Count (Safe_Index'Last)
             and then Archive_Ordinal
               <= Safe_Index'Last - Safe_Index (Synthetic_Count),
     Post => Stable_Entry_Position'Result >= Archive_Ordinal;

   function Publish_Output_Allowed
     (Path_Accepted      : Boolean;
      Under_Root         : Boolean;
      Checksum_Verified  : Boolean;
      Temporary_Closed   : Boolean;
      Cancellation_Point : Boolean)
      return Boolean
   with
     Post =>
       Publish_Output_Allowed'Result =
         (Path_Accepted and then Under_Root and then Checksum_Verified
          and then Temporary_Closed and then not Cancellation_Point);

   function Queue_Count_After_Coalesce
     (Current_Count : Bounded_Count;
      Capacity      : Bounded_Count;
      Has_Terminal  : Boolean;
      Is_Progress   : Boolean)
      return Bounded_Count
   with
     Pre  => Current_Count <= Capacity,
     Post =>
       Queue_Count_After_Coalesce'Result <= Capacity
       and then
       (if Is_Progress and then not Has_Terminal
        then Queue_Count_After_Coalesce'Result = Current_Count);
end Archive_Release_Proof;
