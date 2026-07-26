package body Archive.Resource_Limits is
   function Hard_Ceiling (Id : Limit_Id) return Limit_Value is
   begin
      case Id is
         when Physical_Entry_Count =>
            return 1_000_000;
         when Synthetic_Directory_Count =>
            return 250_000;
         when Path_Length =>
            return 32_768;
         when Path_Component_Count | Path_Depth =>
            return 512;
         when Metadata_Bytes_Per_Entry =>
            return 64 * 1024;
         when Retained_Warnings =>
            return 10_000;
         when Preview_Input_Bytes =>
            return 16 * 1024 * 1024;
         when Preview_Output_Bytes =>
            return 4 * 1024 * 1024;
         when Image_Pixels =>
            return 64_000_000;
         when Per_Entry_Extraction_Output =>
            return 4 * 1024 * 1024 * 1024;
         when Total_Extraction_Output =>
            return 64 * 1024 * 1024 * 1024;
         when Compression_Ratio =>
            return 10_000;
         when Zlib_Input_Chunk_Bytes | Zlib_Output_Chunk_Bytes =>
            return 1 * 1024 * 1024;
         when Event_Queue_Capacity =>
            return 65_536;
         when Temporary_Backing_Bytes =>
            return 16 * 1024 * 1024 * 1024;
      end case;
   end Hard_Ceiling;

   function Default_Configured (Id : Limit_Id) return Limit_Value is
   begin
      case Id is
         when Physical_Entry_Count =>
            return 100_000;
         when Synthetic_Directory_Count =>
            return 25_000;
         when Path_Length =>
            return 4096;
         when Path_Component_Count | Path_Depth =>
            return 128;
         when Metadata_Bytes_Per_Entry =>
            return 16 * 1024;
         when Retained_Warnings =>
            return 1000;
         when Preview_Input_Bytes =>
            return 1 * 1024 * 1024;
         when Preview_Output_Bytes =>
            return 512 * 1024;
         when Image_Pixels =>
            return 16_000_000;
         when Per_Entry_Extraction_Output =>
            return 1 * 1024 * 1024 * 1024;
         when Total_Extraction_Output =>
            return 8 * 1024 * 1024 * 1024;
         when Compression_Ratio =>
            return 1000;
         when Zlib_Input_Chunk_Bytes | Zlib_Output_Chunk_Bytes =>
            return 16 * 1024;
         when Event_Queue_Capacity =>
            return 1024;
         when Temporary_Backing_Bytes =>
            return 2 * 1024 * 1024 * 1024;
      end case;
   end Default_Configured;

   function Validate
     (Id              : Limit_Id;
      Configured      : Limit_Value;
      Clamp_To_Hard   : Boolean := True;
      Zero_Is_Allowed : Boolean := False)
      return Validation_Result
   is
      Ceiling : constant Limit_Value := Hard_Ceiling (Id);
   begin
      if Configured = 0 and then not Zero_Is_Allowed then
         return
           (Status    => Rejected_Zero,
            Effective => Default_Configured (Id),
            Ceiling   => Ceiling);
      elsif Configured > Ceiling then
         if Clamp_To_Hard then
            return
              (Status    => Clamped_To_Hard_Ceiling,
               Effective => Ceiling,
               Ceiling   => Ceiling);
         else
            return
              (Status    => Rejected_Above_Hard_Ceiling,
               Effective => Default_Configured (Id),
               Ceiling   => Ceiling);
         end if;
      else
         return
           (Status    => Accepted,
            Effective => Configured,
            Ceiling   => Ceiling);
      end if;
   end Validate;
end Archive.Resource_Limits;
