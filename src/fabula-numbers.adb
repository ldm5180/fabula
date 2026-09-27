with Fabula.Numbers.Real_Text;

package body Fabula.Numbers
  with SPARK_Mode
is

   --  The same policy as the spec, for the same reason; the loop
   --  invariant below may not use the ignored ghost value under any
   --  other.
   pragma
     Assertion_Policy
       (Ghost => Ignore, Post => Ignore, Loop_Invariant => Ignore);

   function Digit_At (Text : String; I : Positive) return Long_Long_Integer
   is (Long_Long_Integer (Digit_Value (Text (I))))
   with
     Pre  => I in Text'Range and then Is_Digit (Text (I)),
     Post => Digit_At'Result in 0 .. 9;

   --  The digits accumulate as a negative number, the magnitude read so
   --  far negated: Long_Long_Integer'First has no positive twin, and
   --  this way it needs no special case.  Once the next digit would
   --  pass Long_Long_Integer'First the text is too big, and the loop
   --  reads no further digits.
   function Parse_Long (Text : String) return Long_Reads.Read is
      Negated : Long_Long_Integer := 0;
      Too_Big : Boolean := False;
   begin
      if not Is_Integer_Text (Text) then
         return Long_Reads.Failure (Malformed);
      end if;
      for I in First_Digit (Text) .. Text'Last loop
         pragma Loop_Invariant (Negated <= 0);
         pragma
           Loop_Invariant
             (if Too_Big
                then Magnitude (Text, First_Digit (Text), I - 1) = Past_Long
                else
                  Wide_Integer (Negated)
                  = -Magnitude (Text, First_Digit (Text), I - 1));
         --  The test is Negated * 10 - digit < Long_Long_Integer'First,
         --  rearranged so that no step overflows.
         if Too_Big then
            null;
         elsif Negated < (Long_Long_Integer'First + Digit_At (Text, I)) / 10
         then
            Too_Big := True;
         else
            Negated := Negated * 10 - Digit_At (Text, I);
         end if;
      end loop;
      if Too_Big then
         return Long_Reads.Failure (Out_Of_Range);
      elsif Text (Text'First) = '-' then
         return Long_Reads.Success (Negated);
      elsif Negated = Long_Long_Integer'First then
         return Long_Reads.Failure (Out_Of_Range);
      end if;
      return Long_Reads.Success (-Negated);
   end Parse_Long;

   function Parse_Integer (Text : String) return Integer_Reads.Read is
      Long : constant Long_Reads.Read := Parse_Long (Text);
   begin
      if not Long.Ok then
         return Integer_Reads.Failure (Long.Error);
      elsif Long.Value
            not in Long_Long_Integer (Integer'First)
                 .. Long_Long_Integer (Integer'Last)
      then
         return Integer_Reads.Failure (Out_Of_Range);
      end if;
      return Integer_Reads.Success (Integer (Long.Value));
   end Parse_Integer;

   function Parse_Real (Text : String) return Real_Reads.Read is
   begin
      if not Is_Real_Text (Text) then
         return Real_Reads.Failure (Malformed);
      end if;
      return Real_Text.To_Real (Text);
   end Parse_Real;

end Fabula.Numbers;
