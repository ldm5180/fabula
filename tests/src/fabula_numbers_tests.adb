with AUnit.Assertions; use AUnit.Assertions;

with Fabula.Numbers; use Fabula.Numbers;

package body Fabula_Numbers_Tests is

   use AUnit.Test_Cases.Registration;
   use type Integer_Reads.Read;
   use type Long_Reads.Read;
   use type Real_Reads.Read;

   function Image (R : Integer_Reads.Read) return String
   is (if R.Ok then "Ok" & R.Value'Image else R.Error'Image);

   function Image (R : Long_Reads.Read) return String
   is (if R.Ok then "Ok" & R.Value'Image else R.Error'Image);

   function Image (R : Real_Reads.Read) return String
   is (if R.Ok then "Ok" & R.Value'Image else R.Error'Image);

   procedure Expect_Integer (Text : String; Want : Integer_Reads.Read) is
      Got : constant Integer_Reads.Read := Parse_Integer (Text);
   begin
      Assert
        (Got = Want,
         "Parse_Integer ("""
         & Text
         & """): want "
         & Image (Want)
         & ", got "
         & Image (Got));
   end Expect_Integer;

   procedure Expect_Long (Text : String; Want : Long_Reads.Read) is
      Got : constant Long_Reads.Read := Parse_Long (Text);
   begin
      Assert
        (Got = Want,
         "Parse_Long ("""
         & Text
         & """): want "
         & Image (Want)
         & ", got "
         & Image (Got));
   end Expect_Long;

   procedure Expect_Real (Text : String; Want : Real_Reads.Read) is
      Got : constant Real_Reads.Read := Parse_Real (Text);
   begin
      Assert
        (Got = Want,
         "Parse_Real ("""
         & Text
         & """): want "
         & Image (Want)
         & ", got "
         & Image (Got));
   end Expect_Real;

   --  Text that both integer parsers must call Malformed.
   procedure Expect_Malformed_Integer (Text : String) is
   begin
      Expect_Integer (Text, Integer_Reads.Failure (Malformed));
      Expect_Long (Text, Long_Reads.Failure (Malformed));
   end Expect_Malformed_Integer;

   Four_Hundred_Nines : constant String (1 .. 400) := [others => '9'];
   Four_Hundred_Zeros : constant String (1 .. 400) := [others => '0'];

   Big_Long : constant Long_Long_Integer := 9_000_000_000;

   --  One past each end of Integer, as Long_Long_Integer values.
   Below_Integer : constant Long_Long_Integer :=
     Long_Long_Integer (Integer'First) - 1;
   Above_Integer : constant Long_Long_Integer :=
     Long_Long_Integer (Integer'Last) + 1;

   ---------------------------------------------------------------------
   --  Integers.
   ---------------------------------------------------------------------

   procedure Test_Integer_Values (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Integer ("0", Integer_Reads.Success (0));
      Expect_Integer ("-0", Integer_Reads.Success (0));
      Expect_Integer ("007", Integer_Reads.Success (7));
      Expect_Integer ("42", Integer_Reads.Success (42));
      Expect_Integer ("-42", Integer_Reads.Success (-42));
      Expect_Integer (Four_Hundred_Zeros & "7", Integer_Reads.Success (7));
      Expect_Long ("-42", Long_Reads.Success (-42));
      Expect_Long ("9000000000", Long_Reads.Success (Big_Long));
   end Test_Integer_Values;

   procedure Test_Integer_Edges (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Integer ("-2147483648", Integer_Reads.Success (Integer'First));
      Expect_Integer ("2147483647", Integer_Reads.Success (Integer'Last));
      Expect_Integer ("-2147483649", Integer_Reads.Failure (Out_Of_Range));
      Expect_Integer ("2147483648", Integer_Reads.Failure (Out_Of_Range));
      Expect_Long ("-2147483649", Long_Reads.Success (Below_Integer));
      Expect_Long ("2147483648", Long_Reads.Success (Above_Integer));
   end Test_Integer_Edges;

   procedure Test_Long_Edges (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Long
        ("-9223372036854775808", Long_Reads.Success (Long_Long_Integer'First));
      Expect_Long
        ("9223372036854775807", Long_Reads.Success (Long_Long_Integer'Last));
      Expect_Long ("-9223372036854775809", Long_Reads.Failure (Out_Of_Range));
      Expect_Long ("9223372036854775808", Long_Reads.Failure (Out_Of_Range));
      Expect_Integer
        ("9223372036854775807", Integer_Reads.Failure (Out_Of_Range));
      Expect_Integer
        ("-9223372036854775809", Integer_Reads.Failure (Out_Of_Range));
   end Test_Long_Edges;

   procedure Test_Long_Text (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Integer
        (Four_Hundred_Nines, Integer_Reads.Failure (Out_Of_Range));
      Expect_Long (Four_Hundred_Nines, Long_Reads.Failure (Out_Of_Range));
      Expect_Long
        ("-" & Four_Hundred_Nines, Long_Reads.Failure (Out_Of_Range));
   end Test_Long_Text;

   procedure Test_Malformed_Integers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Malformed_Integer ("");
      Expect_Malformed_Integer ("-");
      Expect_Malformed_Integer ("+5");
      Expect_Malformed_Integer (" 12");
      Expect_Malformed_Integer ("12 ");
      Expect_Malformed_Integer ("1_000");
      Expect_Malformed_Integer ("16#FF#");
      Expect_Malformed_Integer ("1E3");
      Expect_Malformed_Integer ("1.5");
      Expect_Malformed_Integer ("seven");
      Expect_Malformed_Integer ("--5");
      Expect_Malformed_Integer ("5-");
      Expect_Malformed_Integer (Four_Hundred_Nines & "x");
   end Test_Malformed_Integers;

   --  A slice keeps the bounds it had in its source string.
   procedure Test_Shifted_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Line    : constant String := "count: -42 items, weight: 1.25";
      Shifted : constant String (100 .. 102) := "097";
   begin
      Expect_Integer (Line (8 .. 10), Integer_Reads.Success (-42));
      Expect_Long (Line (8 .. 10), Long_Reads.Success (-42));
      Expect_Real (Line (27 .. 30), Real_Reads.Success (1.25));
      Expect_Integer (Shifted, Integer_Reads.Success (97));
      Expect_Integer (Line (1 .. 5), Integer_Reads.Failure (Malformed));
   end Test_Shifted_Bounds;

   ---------------------------------------------------------------------
   --  Reals.
   ---------------------------------------------------------------------

   procedure Test_Real_Values (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Real ("5", Real_Reads.Success (5.0));
      Expect_Real ("-7", Real_Reads.Success (-7.0));
      Expect_Real (".5", Real_Reads.Success (0.5));
      Expect_Real ("-.5", Real_Reads.Success (-0.5));
      Expect_Real ("-1.25", Real_Reads.Success (-1.25));
      Expect_Real ("0.0", Real_Reads.Success (0.0));
   end Test_Real_Values;

   procedure Test_Real_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Real
        ("1" & Four_Hundred_Zeros, Real_Reads.Failure (Out_Of_Range));
      Expect_Real
        ("-1" & Four_Hundred_Zeros, Real_Reads.Failure (Out_Of_Range));
      Expect_Real ("0." & Four_Hundred_Zeros & "1", Real_Reads.Success (0.0));
   end Test_Real_Overflow;

   procedure Test_Malformed_Reals (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Real ("5.", Real_Reads.Failure (Malformed));
      Expect_Real ("1e3", Real_Reads.Failure (Malformed));
      Expect_Real ("inf", Real_Reads.Failure (Malformed));
      Expect_Real ("nan", Real_Reads.Failure (Malformed));
      Expect_Real ("", Real_Reads.Failure (Malformed));
      Expect_Real ("-", Real_Reads.Failure (Malformed));
      Expect_Real ("+1.0", Real_Reads.Failure (Malformed));
      Expect_Real (".", Real_Reads.Failure (Malformed));
      Expect_Real ("1.2.3", Real_Reads.Failure (Malformed));
      Expect_Real (" 1.5", Real_Reads.Failure (Malformed));
      Expect_Real ("1-5", Real_Reads.Failure (Malformed));
   end Test_Malformed_Reals;

   ---------------------------------------------------------------------
   --  The result record.
   ---------------------------------------------------------------------

   procedure Test_Value_Or (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Integer_Reads.Value_Or (Parse_Integer ("5"), 3) = 5,
         "a good read gives its value");
      Assert
        (Integer_Reads.Value_Or (Parse_Integer ("five"), 3) = 3,
         "a failed read gives the default");
      Assert
        (Long_Reads.Value_Or (Parse_Long ("99999999999999999999"), -1) = -1,
         "an out-of-range read gives the default");
      Assert
        (Real_Reads.Value_Or (Parse_Real ("2.5"), 0.0) = 2.5,
         "a good real read gives its value");
   end Test_Value_Or;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Integer_Values'Access, "integers: signs and leading zeros");
      Register_Routine
        (T, Test_Integer_Edges'Access, "Integer'First, 'Last and one past");
      Register_Routine
        (T, Test_Long_Edges'Access, "Long_Long_Integer'First, 'Last and past");
      Register_Routine
        (T, Test_Long_Text'Access, "400 digits are out of range");
      Register_Routine
        (T, Test_Malformed_Integers'Access, "integers: the strict grammar");
      Register_Routine
        (T, Test_Shifted_Bounds'Access, "text whose 'First is not 1");
      Register_Routine
        (T, Test_Real_Values'Access, "reals: the {float} capture grammar");
      Register_Routine
        (T, Test_Real_Overflow'Access, "reals: overflow is out of range");
      Register_Routine
        (T, Test_Malformed_Reals'Access, "reals: the strict grammar");
      Register_Routine
        (T, Test_Value_Or'Access, "Value_Or on good and failed reads");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Numbers (numeric text to results)"));

end Fabula_Numbers_Tests;
