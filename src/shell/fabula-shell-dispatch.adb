with Ada.Exceptions;

with Fabula.Limits;

package body Fabula.Shell.Dispatch
  with SPARK_Mode => Off
is

   use type Runner.Notice_Kind;

   ---------------------------------------------------------------------
   --  The move bound.  A move resumes one notice or answers one request.
   --  Between two idles the runner walks at most one feature: one visit
   --  per plain scenario and per Examples row, each with three notices
   --  and its scenario hooks, and per step one notice, one request and
   --  its step hooks.  A hook row answers at most once per phase, and a
   --  scenario's steps, background included, are at most Max_Steps.
   ---------------------------------------------------------------------

   --  A scenario's own notices: opened, entered, closed.
   Scenario_Notices : constant := 3;

   --  A step's own moves: its request and its closing notice.
   Step_Moves : constant := 2;

   Hook_Rows : constant Long_Long_Integer := Runner.Hooks'Length;

   Per_Step : constant Long_Long_Integer := Step_Moves + Hook_Rows;

   Per_Scenario : constant Long_Long_Integer :=
     Scenario_Notices + Hook_Rows + Limits.Max_Steps * Per_Step;

   Max_Moves : constant Long_Long_Integer :=
     Hook_Rows
     + (Limits.Max_Scenarios + Limits.Max_Examples_Rows) * Per_Scenario;

   ---------------------------------------------------------------------
   --  User code.
   ---------------------------------------------------------------------

   --  The exception's message, or its name when the message is empty.
   function Message_Of (E : Ada.Exceptions.Exception_Occurrence) return String
   is (if Ada.Exceptions.Exception_Message (E) = ""
       then Ada.Exceptions.Exception_Name (E)
       else Ada.Exceptions.Exception_Message (E));

   --  An exception replaces whatever the body had recorded, so the
   --  outcome does not hang on how the compiler passed it.
   procedure Record_Exception
     (Outcome : in out Fabula.Check.Outcome;
      E       : Ada.Exceptions.Exception_Occurrence) is
   begin
      Fabula.Check.Reset (Outcome);
      Fabula.Check.Record_Failure (Outcome, Message_Of (E));
   end Record_Exception;

   --  Runs one call of user code on a copy of Ctx, which replaces Ctx
   --  only when the call returns: a raise rolls its edits back, however
   --  the compiler passed the context, and becomes the outcome.
   generic
      with
        procedure Call
          (R       : Runner.Runner;
           Work    : in out Reg.Context;
           Outcome : in out Fabula.Check.Outcome);
   procedure Contained_Call
     (R       : Runner.Runner;
      Ctx     : in out Reg.Context;
      Outcome : in out Fabula.Check.Outcome);

   procedure Contained_Call
     (R       : Runner.Runner;
      Ctx     : in out Reg.Context;
      Outcome : in out Fabula.Check.Outcome)
   is
      Work : Reg.Context := Ctx;
   begin
      Call (R, Work, Outcome);
      Ctx := Work;
   exception
      when E : others =>
         Record_Exception (Outcome, E);
   end Contained_Call;

   --  The pending step's body, with its arguments; Step_Args is copied
   --  once.
   procedure Execute_Pending_Step
     (R       : Runner.Runner;
      Work    : in out Reg.Context;
      Outcome : in out Fabula.Check.Outcome) is
   begin
      Execute
        (Runner.Pending_Step_Kind (R),
         Work,
         Runner.Step_Args (R),
         Runner.Current_Frame (R),
         Outcome);
   end Execute_Pending_Step;

   procedure Run_Pending_Hook
     (R       : Runner.Runner;
      Work    : in out Reg.Context;
      Outcome : in out Fabula.Check.Outcome) is
   begin
      Run_Hook
        (Runner.Pending_Hook_Kind (R),
         Work,
         Runner.Current_Frame (R),
         Outcome);
   end Run_Pending_Hook;

   procedure Call_Step is new Contained_Call (Execute_Pending_Step);
   procedure Call_Hook is new Contained_Call (Run_Pending_Hook);

   ---------------------------------------------------------------------
   --  One move each.
   ---------------------------------------------------------------------

   --  A context as its type initializes one.
   function Fresh return Reg.Context is
      Result : Reg.Context;
      pragma Warnings (Off, Result);  --  the Registry requires defaults
   begin
      return Result;
   end Fresh;

   procedure Pass_Notice (R : in out Runner.Runner; Ctx : in out Reg.Context)
   is
      N : constant Runner.Notice := Runner.Current_Notice (R);
   begin
      if N.Kind = Runner.Scenario_Opened then
         Ctx := Fresh;
      end if;
      On_Notice (N, Runner.Current_Frame (R));
      Runner.Resume (R);
   end Pass_Notice;

   procedure Answer_Step (R : in out Runner.Runner; Ctx : in out Reg.Context)
   is
      Outcome : Fabula.Check.Outcome;
   begin
      Call_Step (R, Ctx, Outcome);
      Runner.Post_Step_Result (R, Outcome);
   end Answer_Step;

   --  Runs the pending hook on Ctx and posts its outcome.
   procedure Answer_Hook (R : in out Runner.Runner; Ctx : in out Reg.Context)
   is
      Outcome : Fabula.Check.Outcome;
   begin
      Call_Hook (R, Ctx, Outcome);
      Runner.Post_Hook_Result (R, Outcome);
   end Answer_Hook;

   --  The messages of the core defects Drive raises on.
   Clash_Message : constant String := "a request and a notice wait together";
   Stuck_Message : constant String := "the runner stopped inside a feature";
   Bound_Message : constant String :=
     "the runner did not idle within its move bound";

   --  Each pass makes one move or ends the loop at an idle runner, and
   --  the runner's own cursors only move forward between two idles, so
   --  no correct runner needs more than Max_Moves passes.  The all-hooks
   --  run on the run's context, every other hook on the scenario's.
   procedure Drive
     (R       : in out Runner.Runner;
      Ctx     : in out Reg.Context;
      All_Ctx : in out Reg.Context) is
   begin
      for Move in 1 .. Max_Moves loop
         case Runner.Waiting_For (R) is
            when Runner.Notice_Wait   =>
               Pass_Notice (R, Ctx);

            when Runner.Step_Wait     =>
               Answer_Step (R, Ctx);

            when Runner.All_Hook_Wait =>
               Answer_Hook (R, All_Ctx);

            when Runner.Hook_Wait     =>
               Answer_Hook (R, Ctx);

            when Runner.Idle          =>
               return;

            when Runner.Clash         =>
               raise Program_Error with Clash_Message;

            when Runner.Stuck         =>
               raise Program_Error with Stuck_Message;
         end case;
      end loop;
      raise Program_Error with Bound_Message;
   end Drive;

   ---------------------------------------------------------------------
   --  Options.
   ---------------------------------------------------------------------

   function Selection
     (Lines : Fabula.Shell.Files.Line_Numbers) return Runner.Line_Selection
   is
      Result : Runner.Line_Selection := Runner.All_Lines;
   begin
      for I in 1 .. Lines.Count loop
         Runner.Add_Line (Result, Lines.Lines (I));
      end loop;
      return Result;
   end Selection;

end Fabula.Shell.Dispatch;
