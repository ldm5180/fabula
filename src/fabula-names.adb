package body Fabula.Names
  with SPARK_Mode
is

   --  Offsets count characters from a text's first one, so the first
   --  character sits at this offset and nothing is consumed before it.
   First_Offset : constant := 0;

   --  The backtrack point before the pattern has shown an Any_Run.
   No_Star : constant := 0;

   --  The pattern character at offset P stands for the name character
   --  at offset N.
   function Fits (Name, Pattern : String; N, P : Natural) return Boolean
   is (Pattern (Pattern'First + P) = Any_Char
       or else Pattern (Pattern'First + P) = Name (Name'First + N))
   with Pre => N < Name'Length and then P < Pattern'Length;

   --  The offset of the first pattern character at or after From that
   --  is not an Any_Run; Pattern'Length when none is.
   function Skip_Stars (Pattern : String; From : Natural) return Natural
   with
     Pre  => From <= Pattern'Length,
     Post => Skip_Stars'Result in From .. Pattern'Length
   is
      P : Natural := From;
   begin
      while P < Pattern'Length and then Pattern (Pattern'First + P) = Any_Run
      loop
         pragma Loop_Invariant (P in From .. Pattern'Length - 1);
         pragma Loop_Variant (Increases => P);
         P := P + 1;
      end loop;
      return P;
   end Skip_Stars;

   --  Greedy, with one backtrack point: the latest Any_Run.  On a
   --  mismatch that Any_Run takes one more name character and the rest
   --  of the pattern is tried again from there; an earlier one never
   --  needs to move, because the later one can absorb whatever it would.
   --  N and P count characters already consumed, so no bound is ever
   --  passed.  Mark, then N, then P rises on every pass: the loop ends.
   function Matches (Name, Pattern : String) return Boolean is
      N    : Natural := First_Offset;
      P    : Natural := First_Offset;
      Star : Natural := No_Star;        --  1 + the latest Any_Run's offset
      Mark : Natural := First_Offset;   --  how much of Name it has taken
   begin
      while N < Name'Length loop
         pragma
           Loop_Invariant
             (P <= Pattern'Length and then Mark <= N and then Star <= P);
         pragma
           Loop_Variant (Increases => Mark, Increases => N, Increases => P);
         if P < Pattern'Length and then Pattern (Pattern'First + P) = Any_Run
         then
            P := P + 1;
            Star := P;
            Mark := N;
         elsif P < Pattern'Length and then Fits (Name, Pattern, N, P) then
            P := P + 1;
            N := N + 1;
         elsif Star /= No_Star then
            P := Star;
            Mark := Mark + 1;
            N := Mark;
         else
            return False;
         end if;
      end loop;
      return Skip_Stars (Pattern, P) = Pattern'Length;
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
      From : Natural := First_Offset;
   begin
      if Patterns'Length = 0 then
         return True;
      end if;
      for K in First_Offset .. Patterns'Length - 1 loop
         pragma Loop_Invariant (From <= K);
         if Patterns (Patterns'First + K) = Pattern_Separator then
            if Alternative_Matches (Name, Patterns, From, K) then
               return True;
            end if;
            From := K + 1;
         end if;
      end loop;
      return Alternative_Matches (Name, Patterns, From, Patterns'Length);
   end Matches_Any;

end Fabula.Names;
