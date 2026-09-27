with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Searches; use Fabula.Searches;

package body Fabula_Searches_Tests is

   use AUnit.Test_Cases.Registration;

   Marks : constant array (1 .. 6) of Boolean :=
     [False, True, False, True, False, False];

   function Marked (I : Positive) return Boolean
   is (I in Marks'Range and then Marks (I));

   function First_Marked is new Find_First (Marked);

   procedure Test_Find_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (First_Marked (1, 6) = 2, "the first marked position wins");
      Assert (First_Marked (3, 6) = 4, "the search starts at First");
      Assert (First_Marked (4, 4) = 4, "a match at Last is found");
      Assert (First_Marked (5, 6) = Not_Found, "no match is Not_Found");
      Assert (First_Marked (1, 1) = Not_Found, "a one-position miss");
      Assert (First_Marked (5, 4) = Not_Found, "an empty run finds nothing");
      Assert (First_Marked (1, 0) = Not_Found, "Last below 1 is empty too");
      Assert (First_Marked (1, 9) = 2, "positions past the data do not hold");
   end Test_Find_First;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T,
         Test_Find_First'Access,
         "Find_First: the first position that holds");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Searches (Find_First)"));

end Fabula_Searches_Tests;
