--  The parser machine at a background, scenario, outline or Examples
--  header that has no step or row yet: which lines end its
--  description, and what each one opens or refuses.
with AUnit.Test_Cases;

package Fabula_Stepless_Tests is

   type Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   procedure Register_Tests (T : in out Test);

   overriding
   function Name (T : Test) return AUnit.Message_String;

end Fabula_Stepless_Tests;
