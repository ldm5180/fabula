with AUnit.Assertions;  use AUnit.Assertions;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Fabula.Check;   use Fabula.Check;
with Fabula.Check.Ints;
with Fabula.Check.Longs;
with Fabula.Check.Reals;
with Fabula.Limits;
with Fabula.Numbers; use Fabula.Numbers;

package body Fabula_Check_Tests is

   use AUnit.Test_Cases.Registration;

   function Msg (R : Outcome) return String
   is (Failure_Text (R));

   --  A Compare instance whose Image counts its calls: a comparison
   --  images its values only when it failed and the caller gave no
   --  Message of its own.
   Image_Calls : Natural := 0;

   function Counted_Image (I : Integer) return String is
   begin
      Image_Calls := Image_Calls + 1;
      return Integer_Image (I);
   end Counted_Image;

   package Counted is new
     Fabula.Check.Compare
       (Integer,
        Image      => Counted_Image,
        Item_Reads => Integer_Reads);

   procedure Test_Lazy_Image (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Image_Calls := 0;
      Counted.Equal (R, 1, 1);
      Counted.Not_Equal (R, 1, 2);
      Counted.Greater (R, 2, 1);
      Counted.Greater_Or_Equal (R, 1, 1);
      Counted.Less (R, 1, 2);
      Counted.Less_Or_Equal (R, 1, 1);
      Assert (Image_Calls = 0, "a passing comparison images nothing");
      Counted.Equal (R, 1, 2, "custom");
      Counted.Not_Equal (R, 1, 1, "custom");
      Counted.Greater (R, 1, 2, "custom");
      Counted.Greater_Or_Equal (R, 1, 2, "custom");
      Counted.Less (R, 2, 1, "custom");
      Counted.Less_Or_Equal (R, 2, 1, "custom");
      Assert
        (Image_Calls = 0,
         "a failed comparison with a Message images nothing, got"
         & Image_Calls'Image);
      Assert (Msg (R) = "custom", "the Message is the failure text");
      Counted.Equal (R, 1, 2);
      Assert
        (Image_Calls = 2,
         "a failed comparison without a Message images Got and Want, got"
         & Image_Calls'Image);
      Assert (Msg (R) = "Value 1 is not equal to 2", "the default message");
   end Test_Lazy_Image;

   procedure Test_Equal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Equal (R, 5, 5);
      Assert (R.Passing, "5 = 5 must pass");

      Reset (R);
      Fabula.Check.Ints.Equal (R, 5, 7);
      Assert (not R.Passing, "5 = 7 must fail");
      Assert
        (Msg (R) = "Value 5 is not equal to 7",
         "default equal message, got """ & Msg (R) & """");

      Reset (R);
      Fabula.Check.Ints.Equal (R, -5, 7);
      Assert (not R.Passing, "-5 = 7 must fail");
      Assert
        (Msg (R) = "Value -5 is not equal to 7",
         "a negative Got keeps its sign, got """ & Msg (R) & """");
   end Test_Equal;

   procedure Test_Not_Equal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Not_Equal (R, 5, 7);
      Assert (R.Passing, "5 /= 7 must pass");

      Reset (R);
      Fabula.Check.Ints.Not_Equal (R, 5, 5);
      Assert (not R.Passing, "5 /= 5 must fail");
      Assert
        (Msg (R) = "Value 5 is equal to 5",
         "default not-equal message, got """ & Msg (R) & """");
   end Test_Not_Equal;

   procedure Test_Greater (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Greater (R, 7, 5);
      Assert (R.Passing, "7 > 5 must pass");

      Reset (R);
      Fabula.Check.Ints.Greater (R, 5, 7);
      Assert (not R.Passing, "5 > 7 must fail");
      Assert
        (Msg (R) = "Value 5 is not greater than 7",
         "default greater message, got """ & Msg (R) & """");

      Reset (R);
      Fabula.Check.Ints.Greater (R, 5, 5);
      Assert (not R.Passing, "5 > 5 must fail");
   end Test_Greater;

   procedure Test_Greater_Or_Equal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Greater_Or_Equal (R, 5, 5);
      Assert (R.Passing, "5 >= 5 must pass");

      Reset (R);
      Fabula.Check.Ints.Greater_Or_Equal (R, 7, 5);
      Assert (R.Passing, "7 >= 5 must pass");

      Reset (R);
      Fabula.Check.Ints.Greater_Or_Equal (R, 4, 5);
      Assert (not R.Passing, "4 >= 5 must fail");
      Assert
        (Msg (R) = "Value 4 is not greater than or equal to 5",
         "default greater-or-equal message, got """ & Msg (R) & """");
   end Test_Greater_Or_Equal;

   procedure Test_Less (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Less (R, 4, 5);
      Assert (R.Passing, "4 < 5 must pass");

      Reset (R);
      Fabula.Check.Ints.Less (R, 5, 4);
      Assert (not R.Passing, "5 < 4 must fail");
      Assert
        (Msg (R) = "Value 5 is not less than 4",
         "default less message, got """ & Msg (R) & """");

      Reset (R);
      Fabula.Check.Ints.Less (R, 5, 5);
      Assert (not R.Passing, "5 < 5 must fail");
      Assert
        (Msg (R) = "Value 5 is not less than 5",
         "equal values fail Less too, got """ & Msg (R) & """");
   end Test_Less;

   procedure Test_Less_Or_Equal (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Less_Or_Equal (R, 5, 5);
      Assert (R.Passing, "5 <= 5 must pass");

      Reset (R);
      Fabula.Check.Ints.Less_Or_Equal (R, 4, 5);
      Assert (R.Passing, "4 <= 5 must pass");

      Reset (R);
      Fabula.Check.Ints.Less_Or_Equal (R, 6, 5);
      Assert (not R.Passing, "6 <= 5 must fail");
      Assert
        (Msg (R) = "Value 6 is not less than or equal to 5",
         "default less-or-equal message, got """ & Msg (R) & """");
   end Test_Less_Or_Equal;

   --  Reaches the shipped Longs and Reals instances at runtime, and
   --  covers the negative-zero edge: -0.0 compares equal to 0.0, but
   --  its own Image must keep the sign the reference interpreter's
   --  formatter puts there, never confusing it with the leading blank
   --  a non-negative value gets trimmed of.
   procedure Test_Longs_And_Reals (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R        : Outcome;
      Neg_Zero : constant String := Long_Float'Image (-0.0);
      One_Raw  : constant String := Long_Float'Image (1.0);
      One      : constant String :=
        One_Raw (One_Raw'First + 1 .. One_Raw'Last);
   begin
      Fabula.Check.Longs.Equal (R, 5, 5);
      Assert (R.Passing, "Longs.Equal (5, 5) must pass");

      Reset (R);
      Fabula.Check.Longs.Equal (R, 5, 7);
      Assert (not R.Passing, "Longs.Equal (5, 7) must fail");
      Assert
        (Msg (R) = "Value 5 is not equal to 7",
         "Longs default equal message, got """ & Msg (R) & """");

      Reset (R);
      Fabula.Check.Reals.Equal (R, 1.0, 1.0);
      Assert (R.Passing, "Reals.Equal (1.0, 1.0) must pass");

      Reset (R);
      Fabula.Check.Reals.Equal (R, -0.0, 1.0);
      Assert (not R.Passing, "Reals.Equal (-0.0, 1.0) must fail");
      Assert
        (Msg (R) = "Value " & Neg_Zero & " is not equal to " & One,
         "a negative-zero Got keeps its sign, got """ & Msg (R) & """");
   end Test_Longs_And_Reals;

   --  A long default comparison message (built from Text_Equal's own
   --  Got/Want, not a custom Message) truncates at the same cap a
   --  short one does; the kept text is the exact prefix.
   procedure Test_Compare_Truncation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R    : Outcome;
      Got  : constant String := 300 * 'a';
      Want : constant String := 300 * 'b';
      Full : constant String := "Value " & Got & " is not equal to " & Want;
   begin
      Text_Equal (R, Got, Want);
      Assert (not R.Passing, "unequal long text must fail");
      Assert
        (Msg (R)'Length = Fabula.Limits.Max_Message_Length,
         "a long default message truncates to the cap, got"
         & Msg (R)'Length'Image);
      Assert
        (Msg (R)
         = Full
             (Full'First .. Full'First + Fabula.Limits.Max_Message_Length - 1),
         "the truncated message keeps the exact prefix of the full text");
   end Test_Compare_Truncation;

   procedure Test_Custom_Message (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Equal (R, 1, 2, "boxes must match");
      Assert (not R.Passing, "a custom-message check still fails");
      Assert
        (Msg (R) = "boxes must match",
         "a non-empty Message replaces the default, got """ & Msg (R) & """");
   end Test_Custom_Message;

   procedure Test_Last_Failure_Wins
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Equal (R, 1, 2);
      Fabula.Check.Ints.Equal (R, 3, 4);
      Assert (not R.Passing, "two failures still leave Passing False");
      Assert
        (Msg (R) = "Value 3 is not equal to 4",
         "the LAST failure's message wins, got """ & Msg (R) & """");
   end Test_Last_Failure_Wins;

   procedure Test_Truncation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R    : Outcome;
      Long : constant String := 600 * 'x';
   begin
      Fail (R, Long);
      Assert
        (Msg (R)'Length = Fabula.Limits.Max_Message_Length,
         "a message over the cap truncates to the cap, got"
         & Msg (R)'Length'Image);
      Assert
        (Msg (R)
         = Long
             (Long'First .. Long'First + Fabula.Limits.Max_Message_Length - 1),
         "the truncated message keeps its FIRST Max_Message_Length characters");
   end Test_Truncation;

   procedure Test_Is_True (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Is_True (R, True);
      Assert (R.Passing, "Is_True (True) must pass");

      Reset (R);
      Is_True (R, False);
      Assert (not R.Passing, "Is_True (False) must fail");
      Assert
        (Msg (R) = "Expected given condition to be true, but it was false",
         "default Is_True message, got """ & Msg (R) & """");

      Reset (R);
      Is_True (R, False, "the box must be open");
      Assert (Msg (R) = "the box must be open", "Is_True custom message");
   end Test_Is_True;

   procedure Test_Is_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Is_False (R, False);
      Assert (R.Passing, "Is_False (False) must pass");

      Reset (R);
      Is_False (R, True);
      Assert (not R.Passing, "Is_False (True) must fail");
      Assert
        (Msg (R) = "Expected given condition to be false, but it was true",
         "default Is_False message, got """ & Msg (R) & """");

      Reset (R);
      Is_False (R, True, "the box must be closed");
      Assert (Msg (R) = "the box must be closed", "Is_False custom message");
   end Test_Is_False;

   procedure Test_Text_Equal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Text_Equal (R, "abc", "abc");
      Assert (R.Passing, "equal text must pass");

      Reset (R);
      Text_Equal (R, "abc", "xyz");
      Assert (not R.Passing, "unequal text must fail");
      Assert
        (Msg (R) = "Value abc is not equal to xyz",
         "default Text_Equal message, got """ & Msg (R) & """");
   end Test_Text_Equal;

   procedure Test_Text_Not_Equal (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Text_Not_Equal (R, "abc", "xyz");
      Assert (R.Passing, "unequal text must pass Text_Not_Equal");

      Reset (R);
      Text_Not_Equal (R, "abc", "abc");
      Assert (not R.Passing, "equal text must fail Text_Not_Equal");
      Assert
        (Msg (R) = "Value abc is equal to abc",
         "default Text_Not_Equal message, got """ & Msg (R) & """");
   end Test_Text_Not_Equal;

   procedure Test_Skip_Ignore (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Skip (R);
      Assert (R.Passing, "Skip on a passing outcome keeps Passing True");
      Assert (R.Order = Skip_Scenario, "Skip sets Order to Skip_Scenario");

      Reset (R);
      Ignore (R);
      Assert (R.Passing, "Ignore on a passing outcome keeps Passing True");
      Assert
        (R.Order = Ignore_Scenario, "Ignore sets Order to Ignore_Scenario");
   end Test_Skip_Ignore;

   procedure Test_Fail (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fail (R);
      Assert (not R.Passing, "Fail sets Passing False");
      Assert (R.Order = Fail_Scenario, "Fail sets Order to Fail_Scenario");
      Assert
        (Msg (R) = "Scenario set to failed with Fabula.Check.Fail",
         "default Fail message, got """ & Msg (R) & """");

      Reset (R);
      Fail (R, "abandon ship");
      Assert (Msg (R) = "abandon ship", "Fail custom message");
      Assert (R.Order = Fail_Scenario, "Fail with a message still sets Order");
   end Test_Fail;

   procedure Test_Fail_Step (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fail_Step (R);
      Assert (not R.Passing, "Fail_Step sets Passing False");
      Assert (R.Order = Continue, "Fail_Step leaves Order at Continue");
      Assert
        (Msg (R) = "Step set to failed with Fabula.Check.Fail_Step",
         "default Fail_Step message, got """ & Msg (R) & """");

      Reset (R);
      Fail_Step (R, "one row short");
      Assert (Msg (R) = "one row short", "Fail_Step custom message");
      Assert
        (R.Order = Continue, "Fail_Step with a message still keeps Continue");
   end Test_Fail_Step;

   --  A good read compares like its value; the read may stand on either
   --  side.
   procedure Test_Good_Reads (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Equal (R, 3, Parse_Integer ("3"));
      Fabula.Check.Ints.Equal (R, Parse_Integer ("3"), 3);
      Fabula.Check.Longs.Less
        (R, Parse_Long ("9000000000"), Long_Long_Integer'Last);
      Fabula.Check.Reals.Greater (R, 2.0, Parse_Real ("1.5"));
      Assert (R.Passing, "good reads that compare true must pass");

      Fabula.Check.Ints.Equal (R, 3, Parse_Integer ("4"));
      Assert
        (Msg (R) = "Value 3 is not equal to 4",
         "a good read keeps the plain message, got """ & Msg (R) & """");

      Reset (R);
      Fabula.Check.Ints.Greater (R, Parse_Integer ("2"), 5);
      Assert
        (Msg (R) = "Value 2 is not greater than 5",
         "a good Got read keeps its place, got """ & Msg (R) & """");

      Reset (R);
      Fabula.Check.Ints.Equal (R, 1, Parse_Integer ("2"), "boxes must match");
      Assert
        (Msg (R) = "boxes must match",
         "a good read keeps the custom message, got """ & Msg (R) & """");
   end Test_Good_Reads;

   --  R failed with message Want and kept Order at Continue; What names
   --  the check.  Resets R for the next one.
   procedure Expect (R : in out Outcome; Want : String; What : String) is
   begin
      Assert (not R.Passing, What & " must fail");
      Assert (Msg (R) = Want, What & ": got """ & Msg (R) & """");
      Assert (R.Order = Continue, What & " leaves Order at Continue");
      Reset (R);
   end Expect;

   --  A failed read fails the check with the target type and the reason,
   --  on every comparison and on either side.
   procedure Test_Failed_Reads (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bad_Int : constant String :=
        "Value is not a valid Integer: malformed text";
      Big_Int : constant String :=
        "Value is not a valid Integer: out of range";
      Seven   : constant Integer_Reads.Read := Parse_Integer ("seven");
      R       : Outcome;
   begin
      Fabula.Check.Ints.Equal (R, 7, Seven);
      Expect (R, Bad_Int, "Equal, Want read");
      Fabula.Check.Ints.Equal (R, Seven, 7);
      Expect (R, Bad_Int, "Equal, Got read");
      Fabula.Check.Ints.Not_Equal (R, 7, Seven);
      Expect (R, Bad_Int, "Not_Equal, Want read");
      Fabula.Check.Ints.Not_Equal (R, Seven, 7);
      Expect (R, Bad_Int, "Not_Equal, Got read");
      Fabula.Check.Ints.Greater (R, 7, Seven);
      Expect (R, Bad_Int, "Greater, Want read");
      Fabula.Check.Ints.Greater (R, Seven, 7);
      Expect (R, Bad_Int, "Greater, Got read");
      Fabula.Check.Ints.Greater_Or_Equal (R, 7, Seven);
      Expect (R, Bad_Int, "Greater_Or_Equal, Want read");
      Fabula.Check.Ints.Greater_Or_Equal (R, Seven, 7);
      Expect (R, Bad_Int, "Greater_Or_Equal, Got read");
      Fabula.Check.Ints.Less (R, 7, Seven);
      Expect (R, Bad_Int, "Less, Want read");
      Fabula.Check.Ints.Less (R, Seven, 7);
      Expect (R, Bad_Int, "Less, Got read");
      Fabula.Check.Ints.Less_Or_Equal (R, 7, Seven);
      Expect (R, Bad_Int, "Less_Or_Equal, Want read");
      Fabula.Check.Ints.Less_Or_Equal (R, Seven, 7);
      Expect (R, Bad_Int, "Less_Or_Equal, Got read");

      Fabula.Check.Ints.Equal (R, 7, Parse_Integer ("99999999999"));
      Expect (R, Big_Int, "an out-of-range read");
      Fabula.Check.Ints.Less (R, Parse_Integer ("99999999999"), 7);
      Expect (R, Big_Int, "an out-of-range Got read");
      Fabula.Check.Longs.Less (R, Parse_Long ("x"), 5);
      Expect
        (R,
         "Value is not a valid Long_Long_Integer: malformed text",
         "Longs names its type");
      Fabula.Check.Reals.Greater (R, 1.0, Parse_Real ("1e3"));
      Expect
        (R,
         "Value is not a valid Long_Float: malformed text",
         "Reals names its type");
   end Test_Failed_Reads;

   --  A failed read under a caller's Message puts the Message first, then
   --  ": ", then the read failure; with no Message the read failure
   --  stands alone.  A good read keeps the Message alone.
   procedure Test_Failed_Read_Context
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Bad_Int : constant String :=
        "Value is not a valid Integer: malformed text";
      Big_Int : constant String :=
        "Value is not a valid Integer: out of range";
      Seven   : constant Integer_Reads.Read := Parse_Integer ("seven");
      Huge    : constant Integer_Reads.Read := Parse_Integer ("99999999999");
      Context : constant String := "boxes must match";
      R       : Outcome;
   begin
      Fabula.Check.Ints.Equal (R, 7, Seven, Context);
      Expect (R, Context & ": " & Bad_Int, "a malformed Want read, Message");
      Fabula.Check.Ints.Greater (R, Seven, 7, Context);
      Expect (R, Context & ": " & Bad_Int, "a malformed Got read, Message");
      Fabula.Check.Ints.Less_Or_Equal (R, 7, Huge, Context);
      Expect (R, Context & ": " & Big_Int, "an out-of-range Want, Message");
      Fabula.Check.Ints.Not_Equal (R, Huge, 7, Context);
      Expect (R, Context & ": " & Big_Int, "an out-of-range Got, Message");
      Fabula.Check.Reals.Greater (R, 1.0, Parse_Real ("1e3"), Context);
      Expect
        (R,
         Context & ": Value is not a valid Long_Float: malformed text",
         "Reals, Message");

      Fabula.Check.Ints.Equal (R, 7, Seven);
      Expect (R, Bad_Int, "a failed Want read, no Message");
      Fabula.Check.Ints.Less (R, Huge, 7, "");
      Expect (R, Big_Int, "a failed Got read, empty Message");

      Fabula.Check.Ints.Equal (R, 1, Parse_Integer ("2"), Context);
      Expect (R, Context, "a good Want read that mismatches, Message");
      Fabula.Check.Ints.Greater (R, Parse_Integer ("1"), 2, Context);
      Expect (R, Context, "a good Got read that mismatches, Message");
   end Test_Failed_Read_Context;

   --  A Message and a failed read that together pass the cap truncate
   --  there, keeping the exact prefix of the combined text.
   procedure Test_Failed_Read_Truncation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cap     : constant Positive := Fabula.Limits.Max_Message_Length;
      Context : constant String := (Cap - 5) * 'm';
      Full    : constant String :=
        Context & ": Value is not a valid Integer: malformed text";
      Longer  : constant String := 2 * Context;
      R       : Outcome;
   begin
      Fabula.Check.Ints.Equal (R, Parse_Integer ("seven"), 7, Context);
      Assert (not R.Passing, "a failed read under a long Message must fail");
      Assert
        (Msg (R)'Length = Cap,
         "the combined message truncates to the cap, got"
         & Msg (R)'Length'Image);
      Assert
        (Msg (R) = Full (Full'First .. Full'First + Cap - 1),
         "the truncated message keeps the exact prefix of the combined text");

      Reset (R);
      Fabula.Check.Ints.Equal (R, 7, Parse_Integer ("seven"), Longer);
      Assert
        (Msg (R) = Longer (Longer'First .. Longer'First + Cap - 1),
         "a Message over the cap alone keeps its first Cap characters");
   end Test_Failed_Read_Truncation;

   --  A step body that tests Ok itself fails the step on the same message
   --  path, naming what did not read; the instance supplies the type.
   procedure Test_Fail_Read (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fabula.Check.Ints.Fail_Read (R, Out_Of_Range, "The item count");
      Expect
        (R,
         "The item count is not a valid Integer: out of range",
         "Fail_Read names what did not read");
      Fabula.Check.Reals.Fail_Read (R, Malformed);
      Expect
        (R,
         "Value is not a valid Long_Float: malformed text",
         "Fail_Read says Value by default");
      Fabula.Check.Ints.Fail_Read (R, Malformed, "");
      Expect
        (R,
         "Value is not a valid Integer: malformed text",
         "an empty What says Value");
   end Test_Fail_Read;

   procedure Test_Reset (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Outcome;
   begin
      Fail (R, "x");
      Reset (R);
      Assert (R.Passing, "Reset restores Passing True");
      Assert (R.Order = Continue, "Reset restores Order Continue");
      Assert (Msg (R) = "", "Reset clears the message");
   end Test_Reset;

   ---------------------------------------------------------------------

   procedure Add_Comparison_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Equal'Access, "Equal both directions");
      Register_Routine (T, Test_Not_Equal'Access, "Not_Equal both directions");
      Register_Routine (T, Test_Greater'Access, "Greater both directions");
      Register_Routine
        (T, Test_Greater_Or_Equal'Access, "Greater_Or_Equal both directions");
      Register_Routine (T, Test_Less'Access, "Less both directions");
      Register_Routine
        (T, Test_Less_Or_Equal'Access, "Less_Or_Equal both directions");
      Register_Routine
        (T, Test_Longs_And_Reals'Access, "Longs and Reals, incl. -0.0");
      Register_Routine
        (T,
         Test_Compare_Truncation'Access,
         "a long default message truncates");
      Register_Routine
        (T, Test_Custom_Message'Access, "a custom message replaces default");
      Register_Routine
        (T, Test_Last_Failure_Wins'Access, "the last failure message wins");
      Register_Routine
        (T, Test_Truncation'Access, "a message truncates at the cap");
      Register_Routine (T, Test_Is_True'Access, "Is_True default and custom");
      Register_Routine
        (T, Test_Is_False'Access, "Is_False default and custom");
      Register_Routine (T, Test_Text_Equal'Access, "Text_Equal on String");
      Register_Routine
        (T, Test_Text_Not_Equal'Access, "Text_Not_Equal on String");
      Register_Routine
        (T, Test_Lazy_Image'Access, "Image runs only for a default message");
   end Add_Comparison_Tests;

   procedure Add_Control_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Skip_Ignore'Access, "Skip and Ignore keep Passing True");
      Register_Routine (T, Test_Fail'Access, "Fail sets Order Fail_Scenario");
      Register_Routine
        (T, Test_Fail_Step'Access, "Fail_Step leaves Order at Continue");
      Register_Routine (T, Test_Reset'Access, "Reset restores defaults");
   end Add_Control_Tests;

   procedure Add_Read_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Good_Reads'Access, "a good read compares like its value");
      Register_Routine
        (T, Test_Failed_Reads'Access, "a failed read names type and reason");
      Register_Routine
        (T,
         Test_Failed_Read_Context'Access,
         "a failed read follows the caller's Message");
      Register_Routine
        (T,
         Test_Failed_Read_Truncation'Access,
         "a Message and a failed read truncate at the cap");
      Register_Routine
        (T, Test_Fail_Read'Access, "Fail_Read: one message for a bad read");
   end Add_Read_Tests;

   ---------------------------------------------------------------------

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Add_Comparison_Tests (T);
      Add_Control_Tests (T);
      Add_Read_Tests (T);
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Check (outcomes and scenario control)"));

end Fabula_Check_Tests;
