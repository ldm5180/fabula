package body Fabula.Searches
  with SPARK_Mode
is

   function Find_First (First : Positive; Last : Integer) return Natural is
   begin
      for I in First .. Last loop
         pragma Loop_Invariant (for all J in First .. I - 1 => not Holds (J));
         if Holds (I) then
            return I;
         end if;
      end loop;
      return Not_Found;
   end Find_First;

end Fabula.Searches;
