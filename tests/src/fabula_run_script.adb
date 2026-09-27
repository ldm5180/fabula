with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Ast;
with Fabula.Parse;

package body Fabula_Run_Script is

   use Ada.Strings.Unbounded;

   Doc    : aliased Fabula.Ast.Document;
   Parser : Fabula.Parse.Parser;

   procedure Load (Source : Fabula_Fixtures.Lines) is
   begin
      Fabula_Fixtures.Parse_Lines (Source, Parser, Doc);
      Assert (not Fabula.Parse.Failed (Parser), "the fixture must parse");
   end Load;

   function Doc_Ref return Fabula.Args.Document_Access
   is (Doc'Access);

   --  The whole trace, one line each, for a failure message.
   function Image (T : Trace) return String is
      Result : Unbounded_String;
   begin
      for Line of T loop
         Append (Result, ASCII.LF & "   " & Line);
      end loop;
      return To_String (Result);
   end Image;

   procedure Assert_Trace (Got : Trace; Want : Fabula_Fixtures.Lines) is
      Common : constant Natural :=
        Natural'Min (Natural (Got.Length), Want'Length);
   begin
      for I in 1 .. Common loop
         Assert
           (Got (I) = To_String (Want (Want'First + I - 1)),
            "line"
            & I'Image
            & ": expected """
            & To_String (Want (Want'First + I - 1))
            & """, got """
            & Got (I)
            & """; whole trace:"
            & Image (Got));
      end loop;
      Assert
        (Natural (Got.Length) = Want'Length,
         "expected"
         & Want'Length'Image
         & " lines, got"
         & Got.Length'Image
         & "; whole trace:"
         & Image (Got));
   end Assert_Trace;

   function Lower (S : String) return String
   renames Ada.Characters.Handling.To_Lower;

   function Image (C : Fabula.Results.Status_Counts) return String
   is (C (Fabula.Results.Passed)'Image
       & C (Fabula.Results.Failed)'Image
       & C (Fabula.Results.Skipped)'Image
       & C (Fabula.Results.Undefined)'Image);

   function Image (C : Fabula.Results.Counts) return String
   is ("scenarios P/F/S/U"
       & Image (C.Scenarios)
       & ", steps P/F/S/U"
       & Image (C.Steps)
       & ", parse/hook errors"
       & C.Parse_Errors'Image
       & C.Hook_Errors'Image);

   procedure Assert_Counts (Got, Want : Fabula.Results.Counts) is
      use type Fabula.Results.Counts;
   begin
      Assert (Got = Want, "expected " & Image (Want) & ", got " & Image (Got));
   end Assert_Counts;

   package body Shell is

      use type Run.Command;
      use type Run.Step_Cause;

      function Status_Image (S : Fabula.Results.Status) return String
      is (Lower (S'Image));

      --  A failing outcome's message, after a colon; nothing otherwise.
      function Message (O : Fabula.Check.Outcome) return String
      is (if O.Passing then "" else ": " & O.Msg (1 .. O.Msg_Len));

      function Notice_Line
        (N : Run.Notice; F : Fabula.Frames.Frame) return String
      is (case N.Kind is
            when Run.Scenario_Opened  =>
              "open " & Fabula.Frames.Value (F.Scenario),
            when Run.Scenario_Entered =>
              "enter " & Fabula.Frames.Value (F.Scenario),
            when Run.Step_Closed      =>
              Status_Image (N.Status)
              & " "
              & Fabula.Frames.Value (F.Step)
              & (if N.Cause = Run.Too_Long_Expansion
                 then " (too long)"
                 else "")
              & Message (N.Outcome),
            when Run.Scenario_Closed  =>
              (if N.Dropped and then N.Entered
               then "drop after entry " & Fabula.Frames.Value (F.Scenario)
               elsif N.Dropped
               then "drop " & Fabula.Frames.Value (F.Scenario)
               else
                 "close "
                 & Status_Image (N.Status)
                 & " "
                 & Fabula.Frames.Value (F.Scenario)
                 & Message (N.Outcome)));

      procedure Answer_Hook (R : in out Run.Runner; Log : in out Trace) is
         Kind : constant Run.Reg.Hook_Kind := Run.Pending_Hook_Kind (R);
         Name : constant String := Lower (Kind'Image);
      begin
         case Run.Next_Request (R) is
            when Run.C_Before_All =>
               Log.Append ("before_all " & Name);

            when Run.C_After_All  =>
               Log.Append ("after_all " & Name);

            when others           =>
               Log.Append ("hook " & Name);
         end case;
         Run.Post_Hook_Result (R, Hook_Outcome (Kind, Run.Current_Frame (R)));
      end Answer_Hook;

      procedure Answer_Step (R : in out Run.Runner; Log : in out Trace) is
         Kind : constant Run.Reg.Step_Kind := Run.Pending_Step_Kind (R);
         Note : constant String :=
           Step_Note (Kind, Run.Step_Args (R), Run.Current_Frame (R));
      begin
         Log.Append
           ("step "
            & Lower (Kind'Image)
            & (if Note'Length = 0 then "" else " " & Note));
         Run.Post_Step_Result (R, Step_Outcome (Kind));
      end Answer_Step;

      --  A runner that never idles is a bug; the bound turns it into a
      --  failed test instead of a hung suite.
      Max_Moves : constant := 100_000;

      procedure Drain (R : in out Run.Runner; Log : in out Trace) is
      begin
         for Move in 1 .. Max_Moves loop
            Assert
              (not Run.Has_Notice (R)
               or else Run.Next_Request (R) = Run.C_None,
               "a request and a notice wait together:" & Image (Log));
            if Run.Has_Notice (R) then
               Log.Append
                 (Notice_Line (Run.Current_Notice (R), Run.Current_Frame (R)));
               Run.Resume (R);
            elsif Run.Next_Request (R) = Run.C_Step then
               Answer_Step (R, Log);
            elsif Run.Next_Request (R) /= Run.C_None then
               Answer_Hook (R, Log);
            else
               return;
            end if;
         end loop;
         Assert (False, "the runner never idled:" & Image (Log));
      end Drain;

      procedure Run_One
        (Source    : Fabula_Fixtures.Lines;
         Opts      : Run.Options;
         Selection : Run.Line_Selection;
         Log       : out Trace;
         R         : out Run.Runner) is
      begin
         Log := Traces.Empty_Vector;
         Load (Source);
         Run.Start_Run (R, Opts);
         Drain (R, Log);
         Assert (Run.Between_Features (R), "Before_All drains to idle");
         Run.Start_Feature (R, Doc_Ref, "f.feature", Selection);
         Drain (R, Log);
         Assert (Run.Between_Features (R), "the feature drains to idle");
         Run.Finish_Run (R);
         Drain (R, Log);
         Assert (Run.Run_Finished (R), "After_All drains to the end");
      end Run_One;

   end Shell;

end Fabula_Run_Script;
