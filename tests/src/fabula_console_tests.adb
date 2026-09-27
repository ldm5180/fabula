with Ada.Environment_Variables;

with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Shell.Console; use Fabula.Shell.Console;

with Fabula_Shell_Scratch;

package body Fabula_Console_Tests is

   use AUnit.Test_Cases.Registration;

   package Env renames Ada.Environment_Variables;

   ESC : constant Character := ASCII.ESC;

   --  The codes the reference interpreter prints, read off a run of its
   --  example binary on a terminal.
   function Probed (S : Style) return String
   is (case S is
         when Plain              => "",
         when Passed             => ESC & "[32m",
         when Failed | Error     => ESC & "[31m",
         when Skipped            => ESC & "[38;2;100;149;237m",
         when Undefined          => ESC & "[33m",
         when Location | Verbose => ESC & "[90m");

   --  Shows escapes as <ESC> so a failure message stays readable.
   function Visible (S : String) return String is
   begin
      for I in S'Range loop
         if S (I) = ESC then
            return
              S (S'First .. I - 1) & "<ESC>" & Visible (S (I + 1 .. S'Last));
         end if;
      end loop;
      return S;
   end Visible;

   procedure Assert_Text (Got, Want, What : String) is
   begin
      Assert
        (Got = Want,
         What
         & ": expected """
         & Visible (Want)
         & """, got """
         & Visible (Got)
         & """");
   end Assert_Text;

   procedure Test_Codes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for S in Style loop
         Assert_Text (Code (S), Probed (S), S'Image);
      end loop;
      Assert_Text (Reset, ESC & "[0m", "Reset");
   end Test_Codes;

   --  With styling off, no style adds a code.
   procedure Check_Styling_Off is
   begin
      Set_Color (False);
      for S in Style loop
         Assert_Text (Styled ("x", S), "x", S'Image & " with styling off");
      end loop;
   end Check_Styling_Off;

   procedure Test_Styled (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Was : constant Boolean := Color;
   begin
      Set_Color (True);
      for S in Passed .. Style'Last loop
         Assert_Text
           (Styled ("x", S), Probed (S) & "x" & ESC & "[0m", S'Image);
      end loop;
      Assert_Text (Styled ("x", Plain), "x", "Plain never styles");
      Check_Styling_Off;
      Set_Color (Was);
   end Test_Styled;

   --  NO_COLOR set to anything, the empty value included, turns styling
   --  off; unset, it leaves the terminal to decide.
   procedure Test_No_Color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Had   : constant Boolean := Env.Exists ("NO_COLOR");
      Value : constant String := (if Had then Env.Value ("NO_COLOR") else "");
   begin
      Env.Set ("NO_COLOR", "");
      Assert (Env.Exists ("NO_COLOR"), "the platform keeps an empty variable");
      Assert (Current_Surroundings.No_Color, "an empty NO_COLOR counts");
      Env.Set ("NO_COLOR", "1");
      Assert (Current_Surroundings.No_Color, "NO_COLOR=1 counts");
      Env.Clear ("NO_COLOR");
      Assert (not Current_Surroundings.No_Color, "an unset NO_COLOR");
      if Had then
         Env.Set ("NO_COLOR", Value);
      end if;
      Assert (Color_Allowed ((Terminal => True, No_Color => False)), "tty");
      Assert
        (not Color_Allowed ((Terminal => True, No_Color => True)),
         "tty with NO_COLOR");
      Assert
        (not Color_Allowed ((Terminal => False, No_Color => False)), "a pipe");
      Assert
        (not Color_Allowed ((Terminal => False, No_Color => True)),
         "a pipe with NO_COLOR");
   end Test_No_Color;

   --  Two bytes of UTF-8 text, written as they are.
   Accented : constant String :=
     Character'Val (16#C3#) & Character'Val (16#A9#);

   procedure Write_Sample is
   begin
      Set_Color (True);
      Put ("[   PASSED    ] a" & Accented, Passed);
      Put ("  f.feature:3", Location);
      New_Line;
      Set_Color (False);
      Put ("b", Failed);
      New_Line;
   end Write_Sample;

   procedure Test_Put (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Was : constant Boolean := Color;
      Got : constant String :=
        Fabula_Shell_Scratch.Capture (Write_Sample'Access);
   begin
      Set_Color (Was);
      Assert_Text
        (Got,
         ESC
         & "[32m[   PASSED    ] a"
         & Accented
         & ESC
         & "[0m"
         & ESC
         & "[90m  f.feature:3"
         & ESC
         & "[0m"
         & ASCII.LF
         & "b"
         & ASCII.LF,
         "the captured bytes");
      Assert (not Write_Failed, "every write succeeded");
   end Test_Put;

   procedure Write_Lines is
   begin
      Set_Color (True);
      Put_Line ("a", Failed);
      Put_Line ("b");
      Set_Color (False);
      Put_Line ("c", Error);
   end Write_Lines;

   --  A line is its styled text, then an unstyled line feed.
   procedure Test_Put_Line (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Was : constant Boolean := Color;
      Got : constant String :=
        Fabula_Shell_Scratch.Capture (Write_Lines'Access);
   begin
      Set_Color (Was);
      Assert_Text
        (Got,
         ESC
         & "[31ma"
         & ESC
         & "[0m"
         & ASCII.LF
         & "b"
         & ASCII.LF
         & "c"
         & ASCII.LF,
         "the captured lines");
   end Test_Put_Line;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Put_Line'Access, "Put_Line ends a line");
      Register_Routine (T, Test_Codes'Access, "the probed style codes");
      Register_Routine (T, Test_Styled'Access, "styling on and off");
      Register_Routine (T, Test_No_Color'Access, "the NO_COLOR rule");
      Register_Routine (T, Test_Put'Access, "Put writes byte for byte");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Shell.Console"));

end Fabula_Console_Tests;
