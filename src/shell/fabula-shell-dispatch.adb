with Ada.Exceptions;

with Fabula.Limits;

package body Fabula.Shell.Dispatch
  with SPARK_Mode => Off
is

   use type Runner.Command;
   use type Runner.Notice_Kind;

   ---------------------------------------------------------------------
   --  The move bound.  A move resumes one notice or answers one request.
   --  Between two idles the runner walks at most one feature: one visit
   --  per plain scenario and per Examples row, each with three notices
   --  and its scenario hooks, and per step one notice, one request and
   --  its step hooks.  A hook row answers at most once per phase, and a
   --  scenario's steps, background included, are at most Max_Steps.
   ---------------------------------------------------------------------

   Hook_Rows : constant Long_Long_Integer := Runner.Hooks'Length;

   Per_Step : constant Long_Long_Integer := 2 + Hook_Rows;

   Per_Scenario : constant Long_Long_Integer :=
     3 + Hook_Rows + Limits.Max_Steps * Per_Step;

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

   --  Runs the pending step's body on a copy of Ctx, which replaces Ctx
   --  only when the body returns: a raise rolls its edits back, however
   --  the compiler passed the context.  Step_Args is copied once.
   procedure Call_Step
     (R       : Runner.Runner;
      Ctx     : in out Reg.Context;
      Outcome : in out Fabula.Check.Outcome)
   is
      Work : Reg.Context := Ctx;
   begin
      Execute
        (Runner.Pending_Step_Kind (R),
         Work,
         Runner.Step_Args (R),
         Runner.Current_Frame (R),
         Outcome);
      Ctx := Work;
   exception
      when E : others =>
         Record_Exception (Outcome, E);
   end Call_Step;

   --  Runs the pending hook on a copy of Ctx, as Call_Step does.
   procedure Call_Hook
     (R       : Runner.Runner;
      Ctx     : in out Reg.Context;
      Outcome : in out Fabula.Check.Outcome)
   is
      Work : Reg.Context := Ctx;
   begin
      Run_Hook
        (Runner.Pending_Hook_Kind (R),
         Work,
         Runner.Current_Frame (R),
         Outcome);
      Ctx := Work;
   exception
      when E : others =>
         Record_Exception (Outcome, E);
   end Call_Hook;

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

   --  The all-hooks run on the run's context, every other hook on the
   --  scenario's.
   procedure Answer_Hook
     (R       : in out Runner.Runner;
      Ctx     : in out Reg.Context;
      All_Ctx : in out Reg.Context)
   is
      Outcome : Fabula.Check.Outcome;
   begin
      if Runner.Next_Request (R) in Runner.C_Before_All | Runner.C_After_All
      then
         Call_Hook (R, All_Ctx, Outcome);
      else
         Call_Hook (R, Ctx, Outcome);
      end if;
      Runner.Post_Hook_Result (R, Outcome);
   end Answer_Hook;

   --  Each pass makes one move or ends the loop at an idle runner, and
   --  the runner's own cursors only move forward between two idles, so
   --  no correct runner needs more than Max_Moves passes.
   procedure Drive
     (R       : in out Runner.Runner;
      Ctx     : in out Reg.Context;
      All_Ctx : in out Reg.Context) is
   begin
      for Move in 1 .. Max_Moves loop
         if Runner.Has_Notice (R)
           and then Runner.Next_Request (R) /= Runner.C_None
         then
            raise Program_Error with "a request and a notice wait together";
         elsif Runner.Has_Notice (R) then
            Pass_Notice (R, Ctx);
         elsif Runner.Next_Request (R) = Runner.C_Step then
            Answer_Step (R, Ctx);
         elsif Runner.Next_Request (R) /= Runner.C_None then
            Answer_Hook (R, Ctx, All_Ctx);
         elsif Runner.Between_Features (R) or else Runner.Run_Finished (R) then
            return;
         else
            raise Program_Error with "the runner stopped inside a feature";
         end if;
      end loop;
      raise Program_Error with "the runner did not idle within its move bound";
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

   procedure Set_Names
     (Opts : in out Runner.Options; Patterns : String; Fits : out Boolean) is
   begin
      Fits := Patterns'Length <= Limits.Max_Name_Filter_Length;
      if Fits then
         Runner.Set_Names (Opts, Patterns);
      end if;
   end Set_Names;

end Fabula.Shell.Dispatch;
