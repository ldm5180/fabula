with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Names; use Fabula.Names;

package body Fabula_Names_Tests is

   use AUnit.Test_Cases.Registration;

   procedure Assert_Match (Name, Pattern : String; Want : Boolean) is
   begin
      Assert
        (Matches (Name, Pattern) = Want,
         """"
         & Name
         & """ against """
         & Pattern
         & """: expected "
         & Want'Image);
   end Assert_Match;

   procedure Assert_Any (Name, Patterns : String; Want : Boolean) is
   begin
      Assert
        (Matches_Any (Name, Patterns) = Want,
         """"
         & Name
         & """ against """
         & Patterns
         & """: expected "
         & Want'Image);
   end Assert_Any;

   --  The reference interpreter's own answers on its example names:
   --  case-sensitive, and anchored at both ends.
   procedure Test_Probed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Match ("Apples Apples Apples", "Apples*", True);
      Assert_Match ("Apples Apples Apples", "apples*", False);
      Assert_Match ("Apples Apples Apples", "Apples", False);
      Assert_Match ("Apples Apples Apples", "Apples Apples Apples", True);
      Assert_Match ("Apples and Bananas", "*Bananas", True);
      Assert_Match ("Apples and Bananas", "Apples?and?Banana?", True);
      Assert_Match ("Scenario Outline with ""apple""", "*""apple""", True);
      Assert_Match ("Scenario Outline with ""apple""", "*<item>*", False);
   end Test_Probed;

   procedure Test_Wildcards (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Match ("abc", "a?c", True);
      Assert_Match ("ac", "a?c", False);
      Assert_Match ("abc", "*", True);
      Assert_Match ("", "*", True);
      Assert_Match ("", "**", True);
      Assert_Match ("", "", True);
      Assert_Match ("a", "", False);
      Assert_Match ("", "?", False);
      Assert_Match ("abc", "a*b*c", True);
      Assert_Match ("abxc", "a*c", True);
      Assert_Match ("abxd", "a*c", False);
      Assert_Match ("ab", "a*b*", True);
      Assert_Match ("a*b", "a?b", True);
      Assert_Match ("mississippi", "m*iss*ppi", True);
      Assert_Match ("mississippi", "m*iss*x", False);
      Assert_Match ("abab", "*ab", True);
      Assert_Match ("aab", "*?b", True);
   end Test_Wildcards;

   --  A slice keeps its own bounds; the matcher must not assume 1.
   procedure Test_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Name    : constant String := "xxApplesxx";
      Pattern : constant String := "yyA*syy";
      List    : constant String := "zz:A*s:q";
   begin
      Assert
        (Matches (Name (3 .. 8), Pattern (3 .. 5)), "slices, not 1-based");
      Assert
        (not Matches (Name (3 .. 9), Pattern (3 .. 5)), "the slice's end");
      Assert (Matches_Any (Name (3 .. 8), List (4 .. 6)), "a sliced list");
      Assert
        (not Matches_Any (Name (3 .. 8), List (1 .. 3)),
         "a sliced list with a trailing empty alternative");
   end Test_Bounds;

   --  ':' separates alternatives; an empty list selects every name, and
   --  an empty alternative selects only the empty name.
   procedure Test_Alternatives (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Any ("Apples and Bananas", "zzz:Apples?and?Banana?", True);
      Assert_Any ("Apples", "zzz:", False);
      Assert_Any ("", "zzz:", True);
      Assert_Any ("x", "", True);
      Assert_Any ("", "", True);
      Assert_Any ("x", ":", False);
      Assert_Any ("", ":", True);
      Assert_Any ("b", "a:b:c", True);
      Assert_Any ("c", "a:b:c", True);
      Assert_Any ("d", "a:b:c", False);
      Assert_Any ("a", "a::", True);
      Assert_Any ("q", ":q", True);
   end Test_Alternatives;

   ---------------------------------------------------------------------
   --  Every name and pattern over a small alphabet, against the
   --  reference interpreter's recursive definition.
   ---------------------------------------------------------------------

   function Reference (Pattern, Name : String) return Boolean is
   begin
      if Pattern'Length = 0 then
         return Name'Length = 0;
      elsif Pattern (Pattern'First) = '*' then
         return
           Reference (Pattern (Pattern'First + 1 .. Pattern'Last), Name)
           or else (Name'Length > 0
                    and then Reference
                               (Pattern, Name (Name'First + 1 .. Name'Last)));
      elsif Pattern (Pattern'First) = '?' then
         return
           Name'Length > 0
           and then Reference
                      (Pattern (Pattern'First + 1 .. Pattern'Last),
                       Name (Name'First + 1 .. Name'Last));
      end if;
      return
        Name'Length > 0
        and then Pattern (Pattern'First) = Name (Name'First)
        and then Reference
                   (Pattern (Pattern'First + 1 .. Pattern'Last),
                    Name (Name'First + 1 .. Name'Last));
   end Reference;

   --  The Index-th string of Length characters over Alphabet.
   function Spelled
     (Alphabet : String; Length : Natural; Index : Natural) return String
   is
      Result : String (1 .. Length);
      Rest   : Natural := Index;
   begin
      for I in Result'Range loop
         Result (I) := Alphabet (Alphabet'First + Rest mod Alphabet'Length);
         Rest := Rest / Alphabet'Length;
      end loop;
      return Result;
   end Spelled;

   function Count_Of (Alphabet : String; Length : Natural) return Natural
   is (Alphabet'Length**Length);

   procedure Compare_All (Name : String; Checked : in out Natural) is
      Symbols : constant String := "ab*?";
   begin
      for Length in 0 .. 4 loop
         for Index in 0 .. Count_Of (Symbols, Length) - 1 loop
            declare
               Pattern : constant String := Spelled (Symbols, Length, Index);
            begin
               Assert
                 (Matches (Name, Pattern) = Reference (Pattern, Name),
                  """" & Name & """ against """ & Pattern & """");
               Checked := Checked + 1;
            end;
         end loop;
      end loop;
   end Compare_All;

   --  63 names (lengths 0 to 5 over two letters) times 341 patterns
   --  (lengths 0 to 4 over four symbols).
   Names_Compared    : constant := 63;
   Patterns_Compared : constant := 341;

   procedure Test_Differential (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Letters : constant String := "ab";
      Checked : Natural := 0;
   begin
      for Length in 0 .. 5 loop
         for Index in 0 .. Count_Of (Letters, Length) - 1 loop
            Compare_All (Spelled (Letters, Length, Index), Checked);
         end loop;
      end loop;
      Assert
        (Checked = Names_Compared * Patterns_Compared,
         "every pair, got" & Checked'Image);
   end Test_Differential;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Probed'Access, "the reference interpreter's probed answers");
      Register_Routine (T, Test_Wildcards'Access, "'*' and '?', anchored");
      Register_Routine (T, Test_Bounds'Access, "slices keep their bounds");
      Register_Routine
        (T, Test_Alternatives'Access, "':' alternatives and empty lists");
      Register_Routine
        (T, Test_Differential'Access, "every short pair, differentially");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Names (the -n wildcard matcher)"));

end Fabula_Names_Tests;
