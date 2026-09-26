package body Fabula.Names
  with SPARK_Mode
is

   --  The pattern character at offset P stands for the name character
   --  at offset N.
   function Fits (Name, Pattern : String; N, P : Natural) return Boolean
   is (Pattern (Pattern'First + P) = '?'
       or else Pattern (Pattern'First + P) = Name (Name'First + N))
   with Pre => N < Name'Length and then P < Pattern'Length;

   --  Greedy, with one backtrack point: the latest '*'.  On a mismatch
   --  that '*' takes one more name character and the rest of the
   --  pattern is tried again from there; an earlier '*' never needs to
   --  move, because the later one can absorb whatever it would.  N and
   --  P count characters already consumed, so no bound is ever passed.
   --  Mark, then N, then P rises on every pass: the loop ends.
   function Matches (Name, Pattern : String) return Boolean is
      N    : Natural := 0;
      P    : Natural := 0;
      Star : Natural := 0;   --  1 + the offset of the latest '*', or 0
      Mark : Natural := 0;   --  how much of Name that '*' has taken so far
   begin
      while N < Name'Length loop
         pragma
           Loop_Invariant
             (P <= Pattern'Length and then Mark <= N and then Star <= P);
         pragma
           Loop_Variant (Increases => Mark, Increases => N, Increases => P);
         if P < Pattern'Length and then Pattern (Pattern'First + P) = '*' then
            P := P + 1;
            Star := P;
            Mark := N;
         elsif P < Pattern'Length and then Fits (Name, Pattern, N, P) then
            P := P + 1;
            N := N + 1;
         elsif Star /= 0 then
            P := Star;
            Mark := Mark + 1;
            N := Mark;
         else
            return False;
         end if;
      end loop;
      while P < Pattern'Length and then Pattern (Pattern'First + P) = '*' loop
         pragma Loop_Variant (Increases => P);
         P := P + 1;
      end loop;
      return P = Pattern'Length;
   end Matches;

   --  The alternative between offsets From (inclusive) and To
   --  (exclusive) of Patterns.
   function Alternative_Matches
     (Name, Patterns : String; From, To : Natural) return Boolean
   is (if From >= To
       then Name'Length = 0
       else
         Matches
           (Name,
            Patterns (Patterns'First + From .. Patterns'First + (To - 1))))
   with Pre => From <= To and then To <= Patterns'Length;

   function Matches_Any (Name, Patterns : String) return Boolean is
      From : Natural := 0;
   begin
      if Patterns'Length = 0 then
         return True;
      end if;
      for K in 0 .. Patterns'Length - 1 loop
         pragma Loop_Invariant (From <= K);
         if Patterns (Patterns'First + K) = ':' then
            if Alternative_Matches (Name, Patterns, From, K) then
               return True;
            end if;
            From := K + 1;
         end if;
      end loop;
      return Alternative_Matches (Name, Patterns, From, Patterns'Length);
   end Matches_Any;

end Fabula.Names;
