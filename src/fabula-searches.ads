--  The one search every "the first position where ..." loop shares.

package Fabula.Searches
  with Pure, SPARK_Mode
is

   --  What a search returns when no position holds.
   Not_Found : constant Natural := 0;

   --  The first position in First .. Last where Holds is True, or
   --  Not_Found.  An empty run (Last < First) finds nothing.  Holds is
   --  called at every position from First up to the one it returns, so
   --  it must be total there: an actual guards its own index, as in
   --  (I in T'Range and then ...).
   generic
      with function Holds (I : Positive) return Boolean;
   function Find_First (First : Positive; Last : Integer) return Natural
   with
     Post =>
       (if Find_First'Result = Not_Found
        then (for all I in First .. Last => not Holds (I))
        else
          Find_First'Result in First .. Last
          and then Holds (Find_First'Result)
          and then (for all I in First .. Find_First'Result - 1 =>
                      not Holds (I)));

end Fabula.Searches;
