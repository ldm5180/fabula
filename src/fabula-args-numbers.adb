--  Outside the proof by design: the language's own 'Value
--  conversions, which raise on text that is out of range or not a
--  number.  The one waived unit in tools/proof-waivers.
pragma SPARK_Mode (Off);

package body Fabula.Args.Numbers is

   function To_Integer (Image : String) return Integer
   is (Integer'Value (Image));

   function To_Long (Image : String) return Long_Long_Integer
   is (Long_Long_Integer'Value (Image));

   function To_Real (Image : String) return Long_Float
   is (Long_Float'Value (Image));

end Fabula.Args.Numbers;
