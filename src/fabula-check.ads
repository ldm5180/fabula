--  Step and hook outcomes.  A check records into an Outcome; nothing
--  here raises.  The runner reads the outcome as data, and the
--  shell owns the only exception handler.
with Fabula.Limits;

package Fabula.Check
  with SPARK_Mode
is

   type Control is (Continue, Skip_Scenario, Ignore_Scenario, Fail_Scenario);

   type Outcome is record
      Passing : Boolean := True;
      Order   : Control := Continue;
      Msg     : String (1 .. Limits.Max_Message_Length) := [others => ' '];
      Msg_Len : Natural range 0 .. Limits.Max_Message_Length := 0;
   end record;

   procedure Reset (R : out Outcome);

   procedure Record_Failure (R : in out Outcome; Message : String);
   --  Sets Passing False; keeps the LAST message (truncated to fit).

   procedure Is_True
     (R : in out Outcome; Condition : Boolean; Message : String := "");
   procedure Is_False
     (R : in out Outcome; Condition : Boolean; Message : String := "");

   generic
      type Item is private;
      with function "=" (L, R : Item) return Boolean is <>;
      with function "<" (L, R : Item) return Boolean is <>;
      with function Image (I : Item) return String;
   package Compare is
      procedure Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "");
      procedure Not_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "");
      procedure Greater
        (R : in out Outcome; Got, Want : Item; Message : String := "");
      procedure Greater_Or_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "");
      procedure Less
        (R : in out Outcome; Got, Want : Item; Message : String := "");
      procedure Less_Or_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "");
   end Compare;

   --  Trimmed 'Image (the reference interpreter's formatter puts no
   --  leading blank on a non-negative value); feed the shipped Compare
   --  instances below.
   function Integer_Image (I : Integer) return String;
   function Long_Image (I : Long_Long_Integer) return String;
   function Real_Image (I : Long_Float) return String;

   --  Shipped instances (child packages, one line each):
   --  Fabula.Check.Ints (Integer), .Longs (Long_Long_Integer),
   --  .Reals (Long_Float), plus non-generic Text_Equal /
   --  Text_Not_Equal for String in this package.
   procedure Text_Equal
     (R : in out Outcome; Got, Want : String; Message : String := "");
   procedure Text_Not_Equal
     (R : in out Outcome; Got, Want : String; Message : String := "");

   --  Skip and Ignore set Order only, never Passing.
   procedure Skip (R : in out Outcome);
   procedure Ignore (R : in out Outcome);

   procedure Fail (R : in out Outcome; Message : String := "");
   --  Passing False AND Order Fail_Scenario.
   procedure Fail_Step (R : in out Outcome; Message : String := "");
   --  Passing False, Order stays Continue.

end Fabula.Check;
