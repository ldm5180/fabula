--  Outside the proof by design; the one waived unit in
--  tools/proof-waivers.  The text already passed the real-number
--  grammar, so it is a well-formed decimal.  On a value too large for
--  Long_Float, GNAT's 'Value returns an infinity, which is not 'Valid:
--  that is Out_Of_Range.  A value too small reads as zero, which is not
--  an error.  No grammar-valid text is known to make 'Value raise; the
--  handler is a safety net, so the function never raises whatever the
--  run-time does, and it too answers Out_Of_Range.

package body Fabula.Numbers.Real_Text
  with SPARK_Mode => Off
is

   function To_Real (Text : String) return Real_Reads.Read is
   begin
      declare
         Value : constant Long_Float := Long_Float'Value (Text);
      begin
         if Value'Valid then
            return Real_Reads.Success (Value);
         end if;
         return Real_Reads.Failure (Out_Of_Range);
      end;
   exception
      when Constraint_Error =>
         return Real_Reads.Failure (Out_Of_Range);
   end To_Real;

end Fabula.Numbers.Real_Text;
