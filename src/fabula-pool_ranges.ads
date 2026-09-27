--  The index arithmetic that every pool of a parsed document shares.  A
--  pool numbers its members from None + 1 up to Handle'Last; None names
--  no member, and it is also the count of an empty pool.  A range of
--  members is First .. Last, empty when Last < First.  The capacity is
--  the handle type's own range, which Fabula.Limits sets.

generic
   type Handle is range <>;
package Fabula.Pool_Ranges with Pure, SPARK_Mode is

   None : constant Handle := Handle'First;

   subtype Index is Handle range None + 1 .. Handle'Last;

   --  The width of a range that holds no member.
   No_Members : constant Natural := 0;

   type Pool_Range is record
      First : Index := Index'First;
      Last  : Handle := None;
   end record;

   Empty : constant Pool_Range := (First => Index'First, Last => None);

   function Is_Empty (R : Pool_Range) return Boolean
   is (R.Last < R.First);

   --  A pool's count after one add that took place when Added: one more
   --  than Before, else Before.
   function Count_After (Before : Handle; Added : Boolean) return Handle'Base
   is (if Added then Before + 1 else Before);

   --  Whether H names a member of a pool that holds Used members.
   function Is_Live (H : Handle; Used : Handle) return Boolean
   is (H in Index'First .. Used);

   --  Whether a pool of Used members holds any member.
   function Has_Newest (Used : Handle) return Boolean
   is (Used in Index);

   --  The newest member of a pool of Used members.
   function Newest (Used : Handle) return Index
   is (Used)
   with Pre => Has_Newest (Used);

   --  R widened to cover I, its pool's newest member; an empty R becomes
   --  I alone.  Children are appended right after one another, so the
   --  widened range stays contiguous.
   function Extended (R : Pool_Range; I : Index) return Pool_Range
   is (if Is_Empty (R)
       then (First => I, Last => I)
       else (First => R.First, Last => I))
   with Post => Extended'Result.Last = I;

   --  How many members R holds.
   function Width (R : Pool_Range) return Natural
   is (if Is_Empty (R) then No_Members else Natural (R.Last - R.First) + 1);

   --  R's member number N, counted from 1.
   function Nth (R : Pool_Range; N : Positive) return Index
   is (R.First + Handle (N - 1))
   with Pre => N <= Width (R);

   --  Whether R is empty or lies inside a pool of Used members.
   function Inside (R : Pool_Range; Used : Handle) return Boolean
   is (Is_Empty (R) or else R.Last <= Used);

   --  How many members R holds when it lies inside a pool of Used
   --  members; No_Members when it runs past the pool.
   function Span (R : Pool_Range; Used : Handle) return Natural
   is (if Inside (R, Used) then Width (R) else No_Members);

end Fabula.Pool_Ranges;
