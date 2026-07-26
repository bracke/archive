with Archive.Tasking.Services;
with Archive.Types;

package Archive.Archives.Opening.Tasks is
   protected type Result_Box is
      procedure Store
        (Operation : Archive.Types.Generation_Id;
         Result    : Archive.Archives.Opening.Prepared_Open_Result);
      entry Wait
        (Operation : out Archive.Types.Generation_Id;
         Result    : out Archive.Archives.Opening.Prepared_Open_Result);
      procedure Take
        (Operation : out Archive.Types.Generation_Id;
         Result    : out Archive.Archives.Opening.Prepared_Open_Result;
         Found     : out Boolean);
      function Available return Boolean;
   private
      Has_Result       : Boolean := False;
      Stored_Operation : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Stored_Result    : Archive.Archives.Opening.Prepared_Open_Result;
   end Result_Box;

   type Event_Bridge_Access is access all Archive.Tasking.Services.Event_Bridge;
   type Result_Box_Access is access all Result_Box;

   task type Open_Worker is
      entry Start
        (Path           : String;
         Session        : Archive.Types.Generation_Id;
         Operation      : Archive.Types.Generation_Id;
         Max_Bytes      : Positive;
         Check_Identity : Boolean;
         Bridge         : Event_Bridge_Access;
         Results        : Result_Box_Access);
   end Open_Worker;
end Archive.Archives.Opening.Tasks;
