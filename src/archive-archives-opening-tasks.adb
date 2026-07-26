with Ada.Strings.Unbounded;

with Archive.Tasking.Events;

package body Archive.Archives.Opening.Tasks is
   use Ada.Strings.Unbounded;

   protected body Result_Box is
      procedure Store
        (Operation : Archive.Types.Generation_Id;
         Result    : Archive.Archives.Opening.Prepared_Open_Result)
      is
      begin
         Stored_Operation := Operation;
         Stored_Result := Result;
         Has_Result := True;
      end Store;

      entry Wait
        (Operation : out Archive.Types.Generation_Id;
         Result    : out Archive.Archives.Opening.Prepared_Open_Result)
        when Has_Result
      is
      begin
         Operation := Stored_Operation;
         Result := Stored_Result;
         Has_Result := False;
      end Wait;

      procedure Take
        (Operation : out Archive.Types.Generation_Id;
         Result    : out Archive.Archives.Opening.Prepared_Open_Result;
         Found     : out Boolean)
      is
      begin
         if Has_Result then
            Operation := Stored_Operation;
            Result := Stored_Result;
            Has_Result := False;
            Found := True;
         else
            Operation := Archive.Types.No_Generation;
            Result := (others => <>);
            Found := False;
         end if;
      end Take;

      function Available return Boolean is
      begin
         return Has_Result;
      end Available;
   end Result_Box;

   task body Open_Worker is
      Request_Path    : Unbounded_String;
      Request_Session : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Request_Open    : Archive.Types.Generation_Id := Archive.Types.No_Generation;
      Request_Limit   : Positive := Archive.Archives.Opening.Default_Max_Open_Bytes;
      Check_Source    : Boolean := True;
      Target_Bridge   : Event_Bridge_Access;
      Target_Results  : Result_Box_Access;
   begin
      accept Start
        (Path           : String;
         Session        : Archive.Types.Generation_Id;
         Operation      : Archive.Types.Generation_Id;
         Max_Bytes      : Positive;
         Check_Identity : Boolean;
         Bridge         : Event_Bridge_Access;
         Results        : Result_Box_Access)
      do
         Request_Path := To_Unbounded_String (Path);
         Request_Session := Session;
         Request_Open := Operation;
         Request_Limit := Max_Bytes;
         Check_Source := Check_Identity;
         Target_Bridge := Bridge;
         Target_Results := Results;
      end Start;

      declare
         Prepared : constant Archive.Archives.Opening.Prepared_Open_Result :=
           Archive.Archives.Opening.Prepare_Path
             (To_String (Request_Path), Request_Limit, Check_Source);
         Published : Archive.Tasking.Services.Publish_Result;
      begin
         Target_Results.Store (Request_Open, Prepared);
         Target_Bridge.Publish
           ((Kind                 => Archive.Tasking.Events.Open_Completed,
             Session_Generation   => Request_Session,
             Operation_Generation => Request_Open,
             Progress_Numerator   => 0,
             Progress_Denominator => 0),
            Published);
      end;
   end Open_Worker;
end Archive.Archives.Opening.Tasks;
