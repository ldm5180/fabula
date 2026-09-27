--  The shipped Long_Long_Integer instance of Fabula.Check.Compare.
--  See Fabula.Check.Ints for why this needs the pragma, not the
--  aspect, form of SPARK_Mode.
pragma SPARK_Mode;

with Fabula.Numbers;

package Fabula.Check.Longs is new
  Fabula.Check.Compare
    (Item       => Long_Long_Integer,
     Image      => Fabula.Check.Long_Image,
     Item_Reads => Fabula.Numbers.Long_Reads);
