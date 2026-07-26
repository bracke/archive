with AUnit.Test_Cases;

with Archive_Suite.Core;

package body Archive_Suite is
   type Root_Test_Case is new AUnit.Test_Cases.Test_Case with null record;
   overriding function Name (T : Root_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Root_Test_Case);

   overriding function Name (T : Root_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("archive root");
   end Name;

   overriding procedure Register_Tests (T : in out Root_Test_Case) is
   begin
      null;
   end Register_Tests;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (new Root_Test_Case);
      Result.Add_Test (Archive_Suite.Core.Suite);
      return Result;
   end Suite;
end Archive_Suite;
