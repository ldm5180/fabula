--  Text of a bounded length: room for Capacity characters, of which the
--  first Length hold the text.  Every object is constrained to one
--  capacity, which its owner names after a Fabula.Limits constant.
--  Text is added in two ways, named apart because they behave apart:
--  Truncated and Append_Truncated keep what fits and drop the rest;
--  Append takes a piece whole or refuses it, and a refusal sticks.
--  The type is private, so only these operations set the text and its
--  length never passes the capacity.
with Fabula.Limits;

package Fabula.Texts
  with Pure, SPARK_Mode
is

   Empty_Length : constant Natural := 0;

   type Bounded_Text (Capacity : Positive) is private
   with Default_Initial_Condition => Length (Bounded_Text) = Empty_Length;

   --  One scanned line's worth of text.
   subtype Line_Text is Bounded_Text (Limits.Max_Line_Length);

   function Length (T : Bounded_Text) return Natural
   with Post => Length'Result <= T.Capacity;

   function Value (T : Bounded_Text) return String
   with
     Post =>
       Value'Result'First = Positive'First
       and then Value'Result'Length = Length (T)
       and then Value'Result'Length <= T.Capacity;

   --  S's first N characters.
   function Prefix (S : String; N : Natural) return String
   is (if N = Empty_Length then "" else S (S'First .. S'First + (N - 1)))
   with Pre => N <= S'Length, Post => Prefix'Result'Length = N;

   function Empty (Capacity : Positive) return Bounded_Text
   with
     Post =>
       Empty'Result.Capacity = Capacity
       and then Length (Empty'Result) = Empty_Length;

   --  Source's first Capacity characters, or all of Source when it is
   --  shorter.
   function Truncated
     (Source : String; Capacity : Positive) return Bounded_Text
   with
     Post =>
       Truncated'Result.Capacity = Capacity
       and then Length (Truncated'Result)
                = Natural'Min (Source'Length, Capacity)
       and then Value (Truncated'Result)
                = Prefix (Source, Length (Truncated'Result));

   --  Appends as much of Piece as still fits; the rest is dropped.
   procedure Append_Truncated (T : in out Bounded_Text; Piece : String)
   with
     Post =>
       Length (T) >= Length (T'Old)
       and then Length (T)
                = Length (T'Old)
                  + Natural'Min (Piece'Length, T.Capacity - Length (T'Old))
       and then Value (T)
                = Value (T'Old)
                  & Prefix
                      (Piece,
                       Natural'Min
                         (Piece'Length, T.Capacity - Length (T'Old)));

   --  Appends Piece whole while Ok holds and Piece fits.  A piece that
   --  does not fit leaves T as it is and sets Ok False, and nothing is
   --  appended once Ok is False.
   procedure Append
     (T : in out Bounded_Text; Piece : String; Ok : in out Boolean)
   with
     Post =>
       Ok = (Ok'Old and then Piece'Length <= T.Capacity - Length (T'Old))
       and then Value (T) = Value (T'Old) & (if Ok then Piece else "");

private

   --  A discriminant cannot bound a scalar component, so the predicate
   --  holds Len to Capacity; only this package writes either component.
   type Bounded_Text (Capacity : Positive) is record
      Len  : Natural := Empty_Length;
      Data : String (1 .. Capacity) := [others => ' '];
   end record
   with Dynamic_Predicate => Bounded_Text.Len <= Bounded_Text.Capacity;

   function Length (T : Bounded_Text) return Natural
   is (T.Len);

   function Value (T : Bounded_Text) return String
   is (T.Data (1 .. T.Len));

   function Empty (Capacity : Positive) return Bounded_Text
   is ((Capacity => Capacity, Len => Empty_Length, Data => [others => ' ']));

end Fabula.Texts;
