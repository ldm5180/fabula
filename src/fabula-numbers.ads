--  Decimal text to numbers.  A read returns a result: a value, or the
--  reason there is none.  Nothing here raises, so a SPARK caller
--  proves both branches, and reads Value only where Ok holds.
--
--  The grammars are the capture grammars of Fabula.Expressions:
--    an integer is  -?[0-9]+
--    a real is      -?[0-9]*\.?[0-9]+   (every integer is one too)
--  Any other text is Malformed: blanks, a plus sign, underscores, based
--  literals, exponents, "5.", "inf", "nan" and the empty text.  Text in
--  the grammar whose value the type cannot hold is Out_Of_Range.

package Fabula.Numbers
  with SPARK_Mode
is

   --  The ghost decimal value below exists for the proof only.  At run
   --  time it would recurse once per digit, and the postconditions and
   --  the loop invariant that use it would make a parse quadratic in the
   --  length of the text.  So a build with contracts on skips them.
   --  gnatprove ignores this policy: it still proves every contract here,
   --  and a caller's proof still sees every postcondition.  Preconditions
   --  stay checked at run time.
   pragma
     Assertion_Policy
       (Ghost => Ignore, Post => Ignore, Loop_Invariant => Ignore);

   type Read_Error is (Malformed, Out_Of_Range);

   --  The reason in words, for a failure message.
   function Reason (E : Read_Error) return String
   is (case E is
         when Malformed    => "malformed text",
         when Out_Of_Range => "out of range");

   --  A read of one value type.  Ok is the discriminant, so reading
   --  Value from a failed read is a proof failure in a SPARK caller,
   --  and a discriminant check at run time.
   generic
      type Value_Type is private;
      Type_Name : String;
   package Reads is

      type Read (Ok : Boolean := False) is record
         case Ok is
            when True =>
               Value : Value_Type;

            when False =>
               Error : Read_Error;
         end case;
      end record;

      function Success (V : Value_Type) return Read
      is ((Ok => True, Value => V));

      function Failure (E : Read_Error) return Read
      is ((Ok => False, Error => E));

      function Value_Or (R : Read; Default : Value_Type) return Value_Type
      is (if R.Ok then R.Value else Default);

      --  The value type's own name, for a failure message.
      function Name return String
      is (Type_Name);

   end Reads;

   --  Each value type's own name, as a failure message spells it.
   Integer_Name : constant String := "Integer";
   Long_Name    : constant String := "Long_Long_Integer";
   Real_Name    : constant String := "Long_Float";

   package Integer_Reads is new Reads (Integer, Integer_Name);
   package Long_Reads is new Reads (Long_Long_Integer, Long_Name);
   package Real_Reads is new Reads (Long_Float, Real_Name);

   ---------------------------------------------------------------------
   --  The grammars.
   ---------------------------------------------------------------------

   Minus_Sign    : constant Character := '-';
   Decimal_Point : constant Character := '.';

   --  The base of a decimal numeral, and the values its digits stand for.
   Radix : constant := 10;
   subtype Digit_Number is Natural range 0 .. Radix - 1;

   function Is_Digit (C : Character) return Boolean
   is (C in Decimal_Digit);

   --  -?[0-9]+ : an optional minus sign, then one or more digits.
   function Is_Integer_Text (Text : String) return Boolean
   is (Text'Length > 0
       and then Is_Digit (Text (Text'Last))
       and then (for all I in Text'Range =>
                   Is_Digit (Text (I))
                   or else (I = Text'First and then Text (I) = Minus_Sign)));

   --  -?[0-9]*\.?[0-9]+ : an optional minus sign, then digits with at
   --  most one point, and a digit last.
   function Is_Real_Text (Text : String) return Boolean
   is (Text'Length > 0
       and then Is_Digit (Text (Text'Last))
       and then (for all I in Text'Range =>
                   Is_Digit (Text (I))
                   or else (I = Text'First and then Text (I) = Minus_Sign)
                   or else (Text (I) = Decimal_Point
                            and then (for all J in Text'Range =>
                                        (if J /= I
                                         then Text (J) /= Decimal_Point)))));

   function Digit_Value (C : Character) return Digit_Number
   is (Character'Pos (C) - Character'Pos (Decimal_Digit'First))
   with Pre => Is_Digit (C);

   --  Where the digits of an integer text start: after its sign.
   function First_Digit (Text : String) return Positive
   is (if Text (Text'First) = Minus_Sign then Text'First + 1 else Text'First)
   with Pre => Is_Integer_Text (Text);

   ---------------------------------------------------------------------
   --  The decimal value of an integer text, for the contracts only.
   --  It is computed in the 128-bit integer type, which holds every
   --  step of it with no overflow.
   ---------------------------------------------------------------------

   subtype Wide_Integer is Long_Long_Long_Integer;

   --  The magnitude of no digits at all.
   No_Magnitude : constant Wide_Integer := 0;

   --  One past the largest magnitude a Long_Long_Integer holds (that of
   --  Long_Long_Integer'First).  A magnitude that reaches it stays
   --  there, so the digits of a text of any length fit.
   Past_Long : constant Wide_Integer :=
     -Wide_Integer (Long_Long_Integer'First) + 1;

   --  The digits Text (From .. Last) as a number, capped at Past_Long.
   function Magnitude
     (Text : String; From : Positive; Last : Natural) return Wide_Integer
   is (if Last < From
       then No_Magnitude
       else
         Wide_Integer'Min
           (Magnitude (Text, From, Last - 1)
            * Radix
            + Wide_Integer (Digit_Value (Text (Last))),
            Past_Long))
   with
     Ghost,
     Pre                =>
       From >= Text'First
       and then Last <= Text'Last
       and then (for all I in From .. Last => Is_Digit (Text (I))),
     Post               => Magnitude'Result in No_Magnitude .. Past_Long,
     Subprogram_Variant => (Decreases => Last);

   --  The signed decimal value of an integer text, capped as Magnitude
   --  is: exact whenever a Long_Long_Integer can hold it.
   function Decimal_Value (Text : String) return Wide_Integer
   is (if Text (Text'First) = Minus_Sign
       then -Magnitude (Text, First_Digit (Text), Text'Last)
       else Magnitude (Text, First_Digit (Text), Text'Last))
   with Ghost, Pre => Is_Integer_Text (Text);

   ---------------------------------------------------------------------
   --  The parsers.  Text may have any bounds and any length.
   ---------------------------------------------------------------------

   function Parse_Long (Text : String) return Long_Reads.Read
   with
     Post =>
       (not Parse_Long'Result.Ok and then Parse_Long'Result.Error = Malformed)
       = not Is_Integer_Text (Text)
       and then (if Parse_Long'Result.Ok
                 then
                   Wide_Integer (Parse_Long'Result.Value)
                   = Decimal_Value (Text))
       and then (not Parse_Long'Result.Ok
                 and then Parse_Long'Result.Error = Out_Of_Range)
                = (Is_Integer_Text (Text)
                   and then Decimal_Value (Text)
                            not in Wide_Integer (Long_Long_Integer'First)
                                 .. Wide_Integer (Long_Long_Integer'Last));

   function Parse_Integer (Text : String) return Integer_Reads.Read
   with
     Post =>
       (not Parse_Integer'Result.Ok
        and then Parse_Integer'Result.Error = Malformed)
       = not Is_Integer_Text (Text)
       and then (if Parse_Integer'Result.Ok
                 then
                   Wide_Integer (Parse_Integer'Result.Value)
                   = Decimal_Value (Text))
       and then (not Parse_Integer'Result.Ok
                 and then Parse_Integer'Result.Error = Out_Of_Range)
                = (Is_Integer_Text (Text)
                   and then Decimal_Value (Text)
                            not in Wide_Integer (Integer'First)
                                 .. Wide_Integer (Integer'Last));

   --  The grammar check is proved; the conversion itself is not (see
   --  Fabula.Numbers.Real_Text).  A value too large for Long_Float is
   --  Out_Of_Range.
   function Parse_Real (Text : String) return Real_Reads.Read
   with
     Post =>
       (not Parse_Real'Result.Ok and then Parse_Real'Result.Error = Malformed)
       = not Is_Real_Text (Text);

end Fabula.Numbers;
