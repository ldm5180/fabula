--  Decimal text to numbers, for the numeric readers of Fabula.Args.
--  The bodies stay outside the proof (design decision D7): proving
--  decimal text conversion is not in scope for this version.  The
--  conversions receive arbitrary text the user chose to read as a
--  number; a bad read raises Constraint_Error, which the shell turns
--  into a failed step.

private package Fabula.Args.Numbers
  with SPARK_Mode
is

   function To_Integer (Image : String) return Integer;

   function To_Long (Image : String) return Long_Long_Integer;

   function To_Real (Image : String) return Long_Float;

end Fabula.Args.Numbers;
