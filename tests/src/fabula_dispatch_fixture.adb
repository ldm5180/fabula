with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Fabula.Check.Ints;
with Fabula.Numbers;
with Fabula.Results;

package body Fabula_Dispatch_Fixture is

   function Lower (S : String) return String
   renames Ada.Characters.Handling.To_Lower;

   function Trimmed (N : Natural) return String
   is (Trim (N'Image, Left));

   procedure Execute
     (S    : Tally_Step;
      Ctx  : in out Tally_Context;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      pragma Unreferenced (Info);
      Name : constant String := "step " & Lower (S'Image);
   begin
      case S is
         when Pass            =>
            Log.Append (Name);

         when Count           =>
            Ctx.Items := Ctx.Items + 1;
            Log.Append (Name & " " & Trimmed (Ctx.Items));

         when Raise_Message   =>
            Log.Append (Name);
            raise Constraint_Error with "boom";

         when Raise_Bare      =>
            Log.Append (Name);
            Ada.Exceptions.Raise_Exception (Bare_Error'Identity, "");

         when Read_Number     =>
            Log.Append (Name);
            declare
               Number : constant Fabula.Numbers.Integer_Reads.Read :=
                 Fabula.Args.Int (A, 1);
            begin
               Fabula.Check.Ints.Greater_Or_Equal (R, Number, 0);
               if Number.Ok and then Number.Value >= 0 then
                  Ctx.Items := Number.Value;
               end if;
            end;

         when Fail_And_Raise  =>
            Log.Append (Name);
            Fabula.Check.Fail (R, "failed first");
            raise Constraint_Error with "late boom";

         when Count_And_Raise =>
            Ctx.Items := Ctx.Items + 1;
            Log.Append (Name & " " & Trimmed (Ctx.Items));
            raise Constraint_Error with "counted boom";
      end case;
   end Execute;

   procedure Run_Hook
     (H    : Tally_Hook;
      Ctx  : in out Tally_Context;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      pragma Unreferenced (Info, R);
      Name : constant String := "hook " & Lower (H'Image);
   begin
      case H is
         when Run_Open | Open_Count =>
            Ctx.Items := Ctx.Items + 1;
            Log.Append (Name & " " & Trimmed (Ctx.Items));

         when Run_Close             =>
            Log.Append (Name & " " & Trimmed (Ctx.Items));

         when Run_Raise             =>
            Log.Append (Name);
            raise Constraint_Error with "run boom";

         when Open_Raise            =>
            Log.Append (Name);
            raise Constraint_Error with "hook boom";
      end case;
   end Run_Hook;

   function Status_Image (S : Fabula.Results.Status) return String
   is (Lower (S'Image));

   --  A failing outcome's message, after a colon; nothing otherwise.
   function Message (O : Fabula.Check.Outcome) return String
   is (if O.Passing then "" else ": " & Fabula.Check.Failure_Text (O));

   --  One notice, named from the frame the drive loop hands over.
   generic
      with package Run is new Fabula.Run (<>);
   procedure Trace (N : Run.Notice; Info : Fabula.Frames.Frame);

   procedure Trace (N : Run.Notice; Info : Fabula.Frames.Frame) is
      Scenario : constant String := Fabula.Frames.Value (Info.Scenario);
   begin
      case N.Kind is
         when Run.Scenario_Opened  =>
            Log.Append ("open " & Scenario);

         when Run.Scenario_Entered =>
            Log.Append ("enter " & Scenario);

         when Run.Step_Closed      =>
            Log.Append
              (Status_Image (N.Status)
               & " "
               & Fabula.Frames.Value (Info.Step)
               & Message (N.Outcome));

         when Run.Scenario_Closed  =>
            Log.Append
              (if N.Dropped
               then "drop " & Scenario
               else
                 "close "
                 & Status_Image (N.Status)
                 & " "
                 & Scenario
                 & Message (N.Outcome));
      end case;
   end Trace;

   procedure Trace_Counting is new Trace (Counting_Run);
   procedure Trace_Raising is new Trace (Raising_Run);

   procedure Counting_Notice
     (N : Counting_Run.Notice; Info : Fabula.Frames.Frame) is
   begin
      Trace_Counting (N, Info);
   end Counting_Notice;

   procedure Raising_Notice
     (N : Raising_Run.Notice; Info : Fabula.Frames.Frame) is
   begin
      Trace_Raising (N, Info);
   end Raising_Notice;

end Fabula_Dispatch_Fixture;
