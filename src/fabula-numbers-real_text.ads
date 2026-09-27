--  The one conversion outside the proof: decimal text to Long_Float.
--  Proving a correctly rounded decimal-to-binary conversion is out of
--  scope, so the body uses the language's own Value attribute and is
--  SPARK_Mode Off.  It never raises: Parse_Real checks the grammar
--  first, an overflow to infinity fails 'Valid and is Out_Of_Range, and
--  a handler catches any Constraint_Error as a safety net.

private package Fabula.Numbers.Real_Text
  with SPARK_Mode
is

   function To_Real (Text : String) return Real_Reads.Read
   with
     Pre  => Is_Real_Text (Text),
     Post => To_Real'Result.Ok or else To_Real'Result.Error = Out_Of_Range;

end Fabula.Numbers.Real_Text;
