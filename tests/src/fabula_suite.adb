with AUnit.Test_Cases;

with Fabula_Limits_Tests;

package body Fabula_Suite is

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;

      --  Add_Test's second parameter is an anonymous access type, so each
      --  test case is allocated into a named Test_Case_Access constant
      --  first: allocating directly into an anonymous-access actual
      --  parameter is a distinct GNAT warning under -gnatwa.
      Limits_Test : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Limits_Tests.Test;
   begin
      AUnit.Test_Suites.Add_Test (Result, Limits_Test);
      return Result;
   end Suite;

end Fabula_Suite;
