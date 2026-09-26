with AUnit.Test_Cases;

with Fabula_Args_Tests;
with Fabula_Ast_Tests;
with Fabula_Check_Tests;
with Fabula_Console_Tests;
with Fabula_Corpus_Tests;
with Fabula_Dispatch_Tests;
with Fabula_Expand_Tests;
with Fabula_Expressions_Tests;
with Fabula_Files_Tests;
with Fabula_Frames_Tests;
with Fabula_Limits_Tests;
with Fabula_Names_Tests;
with Fabula_Parse_Tests;
with Fabula_Registry_Tests;
with Fabula_Reports_Tests;
with Fabula_Results_Tests;
with Fabula_Run_Select_Tests;
with Fabula_Run_Tests;
with Fabula_Scan_Tests;
with Fabula_Tags_Tests;

package body Fabula_Suite is

   --  Add_Test's second parameter is an anonymous access type, so each
   --  test case is allocated into a named Test_Case_Access constant
   --  first: allocating directly into an anonymous-access actual
   --  parameter is a distinct GNAT warning under -gnatwa.

   --  The proved core's tests.
   procedure Add_Core (Result : AUnit.Test_Suites.Access_Test_Suite) is
      Limits_Test      : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Limits_Tests.Test;
      Scan_Test        : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Scan_Tests.Test;
      Expressions_Test : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Expressions_Tests.Test;
      Tags_Test        : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Tags_Tests.Test;
      Ast_Test         : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Ast_Tests.Test;
      Parse_Test       : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Parse_Tests.Test;
      Corpus_Test      : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Corpus_Tests.Test;
      Check_Test       : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Check_Tests.Test;
      Results_Test     : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Results_Tests.Test;
      Frames_Test      : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Frames_Tests.Test;
      Registry_Test    : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Registry_Tests.Test;
      Expand_Test      : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Expand_Tests.Test;
      Args_Test        : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Args_Tests.Test;
      Names_Test       : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Names_Tests.Test;
      Run_Test         : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Run_Tests.Test;
      Run_Select_Test  : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Run_Select_Tests.Test;
   begin
      AUnit.Test_Suites.Add_Test (Result, Limits_Test);
      AUnit.Test_Suites.Add_Test (Result, Scan_Test);
      AUnit.Test_Suites.Add_Test (Result, Expressions_Test);
      AUnit.Test_Suites.Add_Test (Result, Tags_Test);
      AUnit.Test_Suites.Add_Test (Result, Ast_Test);
      AUnit.Test_Suites.Add_Test (Result, Parse_Test);
      AUnit.Test_Suites.Add_Test (Result, Corpus_Test);
      AUnit.Test_Suites.Add_Test (Result, Check_Test);
      AUnit.Test_Suites.Add_Test (Result, Results_Test);
      AUnit.Test_Suites.Add_Test (Result, Frames_Test);
      AUnit.Test_Suites.Add_Test (Result, Registry_Test);
      AUnit.Test_Suites.Add_Test (Result, Expand_Test);
      AUnit.Test_Suites.Add_Test (Result, Args_Test);
      AUnit.Test_Suites.Add_Test (Result, Names_Test);
      AUnit.Test_Suites.Add_Test (Result, Run_Test);
      AUnit.Test_Suites.Add_Test (Result, Run_Select_Test);
   end Add_Core;

   --  The shell's tests.
   procedure Add_Shell (Result : AUnit.Test_Suites.Access_Test_Suite) is
      Console_Test  : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Console_Tests.Test;
      Reports_Test  : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Reports_Tests.Test;
      Files_Test    : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Files_Tests.Test;
      Dispatch_Test : constant AUnit.Test_Cases.Test_Case_Access :=
        new Fabula_Dispatch_Tests.Test;
   begin
      AUnit.Test_Suites.Add_Test (Result, Console_Test);
      AUnit.Test_Suites.Add_Test (Result, Reports_Test);
      AUnit.Test_Suites.Add_Test (Result, Files_Test);
      AUnit.Test_Suites.Add_Test (Result, Dispatch_Test);
   end Add_Shell;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Add_Core (Result);
      Add_Shell (Result);
      return Result;
   end Suite;

end Fabula_Suite;
