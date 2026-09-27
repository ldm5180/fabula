--  Step and hook outcomes.  A check records into an Outcome; nothing
--  here raises.  The runner reads the outcome as data, and the
--  shell owns the only exception handler.
with Fabula.Limits;
with Fabula.Numbers;
with Fabula.Texts;

package Fabula.Check
  with SPARK_Mode
is

   type Control is (Continue, Skip_Scenario, Ignore_Scenario, Fail_Scenario);

   subtype Message_Text is Texts.Bounded_Text (Limits.Max_Message_Length);

   type Outcome is record
      Passing : Boolean := True;
      Order   : Control := Continue;
      Message : Message_Text;
   end record;

   --  The message of the last failure; "" while none was recorded.
   function Failure_Text (R : Outcome) return String
   is (Texts.Value (R.Message));

   procedure Reset (R : out Outcome);

   procedure Record_Failure (R : in out Outcome; Message : String);
   --  Sets Passing False; keeps the LAST message (truncated to fit).

   --  What a failed read calls the value it could not read, unless the
   --  caller names it.
   Unnamed_Value : constant String := "Value";

   procedure Is_True
     (R : in out Outcome; Condition : Boolean; Message : String := "");
   procedure Is_False
     (R : in out Outcome; Condition : Boolean; Message : String := "");

   --  Each comparison also takes a numeric read on either side, as
   --  Fabula.Args and Fabula.Numbers return it.  A good read compares
   --  exactly as its value does, Message included.  A failed read fails
   --  the check through Fail_Read, for example "Value is not a valid
   --  Integer: malformed text", and that message replaces Message: the
   --  comparison Message describes never took place.
   --
   --  Using Compare for a type of your own takes one Reads instance:
   --    package Money_Reads is new Fabula.Numbers.Reads (Money, "Money");
   --    package Money_Checks is new Fabula.Check.Compare
   --      (Money, Image => Money_Image, Item_Reads => Money_Reads);
   generic
      type Item is private;
      with function "=" (L, R : Item) return Boolean is <>;
      with function "<" (L, R : Item) return Boolean is <>;
      with function Image (I : Item) return String;
      with package Item_Reads is new
        Numbers.Reads (Value_Type => Item, others => <>);
   package Compare is
      subtype Read is Item_Reads.Read;

      --  Fails R for a read that did not succeed: "<What> is not a valid
      --  <type>: <reason>", where the type is Item_Reads.Name.  An empty
      --  What reads as "Value".  The comparisons below use it for a
      --  failed read; a step body that tests Ok itself calls it too, so
      --  every failed read speaks the same way.
      procedure Fail_Read
        (R     : in out Outcome;
         Error : Numbers.Read_Error;
         What  : String := Unnamed_Value);

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

      procedure Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "");
      procedure Not_Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "");
      procedure Greater
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "");
      procedure Greater_Or_Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "");
      procedure Less
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "");
      procedure Less_Or_Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "");

      procedure Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "");
      procedure Not_Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "");
      procedure Greater
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "");
      procedure Greater_Or_Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "");
      procedure Less
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "");
      procedure Less_Or_Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "");
   end Compare;

   --  Trimmed 'Image (the reference interpreter's formatter puts no
   --  leading blank on a non-negative value); feed the shipped Compare
   --  instances below.
   function Integer_Image (I : Integer) return String;
   function Long_Image (I : Long_Long_Integer) return String;
   function Real_Image (I : Long_Float) return String;

   --  Shipped instances (child packages, one instantiation each):
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
