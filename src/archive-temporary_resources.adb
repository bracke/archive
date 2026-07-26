with Ada.Strings.Unbounded;

package body Archive.Temporary_Resources is
   use Ada.Strings.Unbounded;
   use type Archive.Types.Generation_Id;

   function Trim_Trailing_Separator (Value : String) return String is
   begin
      if Value'Length > 1 and then Value (Value'Last) = '/' then
         return Value (Value'First .. Value'Last - 1);
      end if;
      return Value;
   end Trim_Trailing_Separator;

   function Under_Root (Root : String; Path : String) return Boolean is
      R : constant String := Trim_Trailing_Separator (Root);
   begin
      if R = "" or else Path'Length <= R'Length then
         return False;
      end if;

      return Path (Path'First .. Path'First + R'Length - 1) = R
        and then Path (Path'First + R'Length) = '/';
   end Under_Root;

   protected body Registry is
      procedure Register
        (Kind   : Resource_Kind;
         Owner  : Archive.Types.Generation_Id;
         Path   : String;
         Id     : out Resource_Id;
         Stored : out Boolean)
      is
      begin
         if Used = Capacity then
            Id := No_Resource;
            Stored := False;
            return;
         end if;

         Used := Used + 1;
         Id := Next_Id;
         Items (Used) :=
           (Id => Id,
            Kind => Kind,
            Owner => Owner,
            Path => To_Unbounded_String (Path),
            State => Registered);
         Next_Id := Next_Id + 1;
         Stored := True;
      end Register;

      procedure Request_Cleanup
        (Id       : Resource_Id;
         Temp_Root : String;
         Decision : out Cleanup_Decision)
      is
      begin
         for Index in 1 .. Used loop
            if Items (Index).Id = Id then
               if Items (Index).State in Cleaned | Cleanup_Failed then
                  Decision := Cleanup_Rejected_Already_Final;
               elsif not Under_Root (Temp_Root, To_String (Items (Index).Path)) then
                  Decision := Cleanup_Rejected_Outside_Root;
               else
                  Items (Index).State := Cleanup_Requested;
                  Decision := Cleanup_Allowed;
               end if;
               return;
            end if;
         end loop;
         Decision := Cleanup_Rejected_Already_Final;
      end Request_Cleanup;

      procedure Mark_Cleaned (Id : Resource_Id) is
      begin
         for Index in 1 .. Used loop
            if Items (Index).Id = Id then
               Items (Index).State := Cleaned;
               return;
            end if;
         end loop;
      end Mark_Cleaned;

      procedure Mark_Failed (Id : Resource_Id) is
      begin
         for Index in 1 .. Used loop
            if Items (Index).Id = Id then
               Items (Index).State := Cleanup_Failed;
               return;
            end if;
         end loop;
      end Mark_Failed;

      function Count return Natural is
      begin
         return Used;
      end Count;

      function Active_Count return Natural is
         Result : Natural := 0;
      begin
         for Index in 1 .. Used loop
            if Items (Index).State not in Cleaned | Cleanup_Failed then
               Result := Result + 1;
            end if;
         end loop;
         return Result;
      end Active_Count;

      function Contains (Id : Resource_Id) return Boolean is
      begin
         for Index in 1 .. Used loop
            if Items (Index).Id = Id then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      function Resource (Id : Resource_Id) return Resource_Record is
      begin
         for Index in 1 .. Used loop
            if Items (Index).Id = Id then
               return Items (Index);
            end if;
         end loop;
         return (others => <>);
      end Resource;
   end Registry;
end Archive.Temporary_Resources;
