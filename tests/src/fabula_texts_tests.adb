with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Texts; use Fabula.Texts;

package body Fabula_Texts_Tests is

   use AUnit.Test_Cases.Registration;

   subtype Five is Bounded_Text (5);

   procedure Test_Truncated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Source : constant String (3 .. 9) := "abcdefg";
      Short  : constant Five := Truncated ("abc", 5);
      Long   : constant Five := Truncated (Source, 5);
      None   : constant Five := Truncated ("", 5);
   begin
      Assert (Value (Short) = "abc", "a text that fits is kept whole");
      Assert (Length (Short) = 3, "its length is its own");
      Assert (Value (Long) = "abcde", "a longer text keeps its first five");
      Assert (Value (Long)'First = 1, "the value starts at 1");
      Assert (Length (Long) = 5, "a truncated text fills its capacity");
      Assert (Value (None) = "", "the empty text stays empty");
      Assert (Value (Empty (5)) = "", "Empty holds no text");
      Assert (Empty (5).Capacity = 5, "Empty keeps its capacity");
   end Test_Truncated;

   procedure Test_Append_Truncated
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Text : Five := Empty (5);
   begin
      Append_Truncated (Text, "ab");
      Assert (Value (Text) = "ab", "a piece that fits is appended");
      Append_Truncated (Text, "cdefg");
      Assert (Value (Text) = "abcde", "the rest of a long piece is dropped");
      Append_Truncated (Text, "h");
      Assert (Value (Text) = "abcde", "a full text takes nothing more");
   end Test_Append_Truncated;

   procedure Test_Append (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Text : Five := Empty (5);
      Ok   : Boolean := True;
   begin
      Append (Text, "abc", Ok);
      Assert (Ok and then Value (Text) = "abc", "a piece that fits");
      Append (Text, "def", Ok);
      Assert (not Ok, "a piece that does not fit refuses");
      Assert
        (Value (Text) = "abc", "a refused piece leaves the text as it is");
      Append (Text, "d", Ok);
      Assert (not Ok, "the refusal is sticky");
      Assert (Value (Text) = "abc", "nothing is appended after a refusal");
   end Test_Append;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Truncated'Access, "Truncated keeps what fits");
      Register_Routine
        (T, Test_Append_Truncated'Access, "Append_Truncated drops the rest");
      Register_Routine
        (T, Test_Append'Access, "Append refuses whole, and stays refused");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Texts (bounded text)"));

end Fabula_Texts_Tests;
