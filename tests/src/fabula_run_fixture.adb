with Ada.Characters.Handling;
with Ada.Strings.Fixed;

package body Fabula_Run_Fixture is

   use Fabula.Check;

   function Lower (S : String) return String
   renames Ada.Characters.Handling.To_Lower;

   function Step_Holds (F : Fabula.Frames.Frame; Word : String) return Boolean
   is (Ada.Strings.Fixed.Index (Fabula.Frames.Value (F.Step), Word) /= 0);

   function Hook_Outcome
     (Kind : Box_Hook; Frame : Fabula.Frames.Frame) return Outcome
   is
      Failure : constant String := Lower (Kind'Image) & " failed";
      Result  : Outcome;
   begin
      case Kind is
         when Start_Fail | End_Fail | Open_Check | Close_Check =>
            Is_True (Result, False, Failure);

         when Open_Skip | Close_Skip                           =>
            Skip (Result);

         when Open_Ignore | Close_Ignore                       =>
            Ignore (Result);

         when Open_Fail | Close_Fail                           =>
            Fail (Result, Failure);

         when Step_In_Guard                                    =>
            if Step_Holds (Frame, "guarded") then
               Fail_Step (Result, "guard failed");
            end if;

         when Step_Out_Watch                                   =>
            if Step_Holds (Frame, "watched") then
               Is_True (Result, False, "watch failed");
            end if;

         when Step_In_Control                                  =>
            if Step_Holds (Frame, "skipping") then
               Skip (Result);
            elsif Step_Holds (Frame, "doomed") then
               Fail (Result, Failure);
            end if;

         when others                                           =>
            null;
      end case;
      return Result;
   end Hook_Outcome;

   function Step_Outcome (Kind : Box_Step) return Outcome is
      Result : Outcome;
   begin
      case Kind is
         when Fail_Check     =>
            Is_True (Result, False, "checked");

         when Call_Skip      =>
            Skip (Result);

         when Call_Ignore    =>
            Ignore (Result);

         when Call_Fail      =>
            Fail (Result, "failed scenario");

         when Call_Fail_Step =>
            Fail_Step (Result, "failed step");

         when others         =>
            null;
      end case;
      return Result;
   end Step_Outcome;

   function Trimmed (N : Natural) return String
   is (Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left));

   function Step_Note
     (Kind : Box_Step; A : Fabula.Args.List; F : Fabula.Frames.Frame)
      return String is
   begin
      case Kind is
         when Place      =>
            return
              Trimmed (Fabula.Args.Int (A, 1))
              & " "
              & Fabula.Args.Word (A, 2)
              & " @"
              & Trimmed (F.Scenario_Line)
              & ":"
              & Trimmed (F.Step_Line);

         when Read_Doc   =>
            return Fabula.Args.Doc_String (A);

         when Read_Table =>
            return Fabula.Args.Cell (A, 1, 2);

         when others     =>
            return "";
      end case;
   end Step_Note;

end Fabula_Run_Fixture;
