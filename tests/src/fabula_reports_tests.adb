with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Shell.Console;
with Fabula.Shell.Reports; use Fabula.Shell.Reports;

with Fabula_Shell_Scratch; use Fabula_Shell_Scratch;

package body Fabula_Reports_Tests is

   use AUnit.Test_Cases.Registration;

   LF : constant Character := ASCII.LF;

   procedure Expect (Got, Want : Status; What : String) is
   begin
      Assert
        (Got = Want, What & ": expected " & Want'Image & ", got " & Got'Image);
   end Expect;

   --  Writes each chunk to R, expecting every write to succeed.
   procedure Write_All (R : in out Report; Chunks : String) is
      S : Status;
   begin
      for C of Chunks loop
         Write (R, [1 => C], S);
         Expect (S, Ok, "write " & C'Image);
      end loop;
   end Write_All;

   procedure Test_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Path : constant String := Fresh_Dir ("reports") & "/r.json";
      R    : Report;
      S    : Status;
   begin
      Open (R, Path, S);
      Expect (S, Ok, "open");
      Assert (Is_Open (R), "open after Open");
      Write (R, "[" & LF & "  {""a"": 1}", S);
      Expect (S, Ok, "the first chunk");
      Write_All (R, LF & "]");
      Close (R, S);
      Expect (S, Ok, "close");
      Assert (not Is_Open (R), "closed after Close");
      Assert
        (Read_File (Path) = "[" & LF & "  {""a"": 1}" & LF & "]",
         "the file holds the chunks as written, got """
         & Read_File (Path)
         & """");
   end Test_Round_Trip;

   procedure Test_Truncates (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Path : constant String := Fresh_Dir ("reports") & "/old.json";
      R    : Report;
      S    : Status;
   begin
      Write_File (Path, "an older and longer report");
      Open (R, Path, S);
      Expect (S, Ok, "open over an old file");
      Write (R, "new", S);
      Close (R, S);
      Assert (Read_File (Path) = "new", "the old content is gone");
   end Test_Truncates;

   procedure Test_Open_Failure (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Dir : constant String := Fresh_Dir ("reports");
      R   : Report;
      S   : Status;
   begin
      Open (R, Dir & "/no_such_dir/r.json", S);
      Expect (S, Open_Failed, "a missing directory");
      Assert (not Is_Open (R), "nothing open after a failed Open");
      Open (R, Dir, S);
      Expect (S, Open_Failed, "a directory as the file");
      Assert (not Is_Open (R), "still nothing open");
      Open (R, "", S);
      Expect (S, Open_Failed, "an empty path, which Create makes a temp file");
      Assert (not Is_Open (R), "no temp file stays open");
   end Test_Open_Failure;

   procedure Test_Misuse (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Path : constant String := Fresh_Dir ("reports") & "/r.json";
      R    : Report;
      S    : Status;
   begin
      Write (R, "x", S);
      Expect (S, Not_Open, "a write before Open");
      Close (R, S);
      Expect (S, Not_Open, "a close before Open");
      Open (R, Path, S);
      Open (R, Path, S);
      Expect (S, Already_Open, "a second Open");
      Open_Console (R, S);
      Expect (S, Already_Open, "Open_Console on an open report");
      Assert (Is_Open (R), "the first Open still holds");
      Close (R, S);
      Expect (S, Ok, "close");
      Close (R, S);
      Expect (S, Not_Open, "a second close");
   end Test_Misuse;

   Console_Report : Report;
   Console_Status : Status := Ok;

   --  Every step's status must be Ok; the first that is not is kept.
   procedure Keep (S : Status) is
   begin
      if Console_Status = Ok then
         Console_Status := S;
      end if;
   end Keep;

   procedure Write_To_Console is
      S : Status;
   begin
      Fabula.Shell.Console.Set_Color (True);
      Open_Console (Console_Report, S);
      Keep (S);
      Write (Console_Report, "[" & LF, S);
      Keep (S);
      Write (Console_Report, "]", S);
      Keep (S);
      Close (Console_Report, S);
      Keep (S);
   end Write_To_Console;

   --  With no file named, the chunks go to the console, never styled.
   procedure Test_Console (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Was : constant Boolean := Fabula.Shell.Console.Color;
      Got : constant String := Capture (Write_To_Console'Access);
   begin
      Fabula.Shell.Console.Set_Color (Was);
      Expect (Console_Status, Ok, "every console step");
      Assert (Got = "[" & LF & "]", "the console got """ & Got & """");
      Assert (not Is_Open (Console_Report), "closed after Close");
   end Test_Console;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Round_Trip'Access, "chunks reach the file as written");
      Register_Routine (T, Test_Truncates'Access, "Open empties an old file");
      Register_Routine
        (T, Test_Open_Failure'Access, "an unwritable path is Open_Failed");
      Register_Routine (T, Test_Misuse'Access, "calls out of order are typed");
      Register_Routine
        (T, Test_Console'Access, "no file: the console, unstyled");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Shell.Reports"));

end Fabula_Reports_Tests;
