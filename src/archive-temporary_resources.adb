with Ada.Directories;
with Ada.Numerics.Discrete_Random;
with Ada.Strings.Unbounded;

package body Archive.Temporary_Resources is
   use Ada.Strings.Unbounded;
   use type Archive.Types.Generation_Id;

   subtype Temp_Nonce is Natural range 0 .. 16#7FFF_FFFF#;
   package Temp_Nonce_Random is new Ada.Numerics.Discrete_Random (Temp_Nonce);
   Temp_Generator : Temp_Nonce_Random.Generator;

   function Hex_Digit (Value : Natural) return Character is
      Hex_Chars : constant String := "0123456789abcdef";
   begin
      return Hex_Chars (Hex_Chars'First + Value);
   end Hex_Digit;

   function Hex_Image (Value : Temp_Nonce) return String is
      Result : String (1 .. 8);
      Work   : Natural := Natural (Value);
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Hex_Digit (Work mod 16);
         Work := Work / 16;
      end loop;
      return Result;
   end Hex_Image;

   function Candidate_Sibling
     (Target : String;
      Role   : String;
      Nonce  : Temp_Nonce)
      return String
   is
   begin
      return Target & ".archive-" & Role & "-" & Hex_Image (Nonce);
   end Candidate_Sibling;

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

   function Fresh_Sibling_Path
     (Root   : String;
      Target : String;
      Role   : String)
      return String
   is
      Candidate : String :=
        Candidate_Sibling (Target, Role, Temp_Nonce_Random.Random (Temp_Generator));
   begin
      for Attempt in 1 .. 64 loop
         Candidate :=
           Candidate_Sibling (Target, Role, Temp_Nonce_Random.Random (Temp_Generator));
         if Under_Root (Root, Candidate)
           and then not Ada.Directories.Exists (Candidate)
         then
            return Candidate;
         end if;
      end loop;

      return "";
   end Fresh_Sibling_Path;

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
begin
   Temp_Nonce_Random.Reset (Temp_Generator);
end Archive.Temporary_Resources;
