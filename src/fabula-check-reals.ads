--  The shipped Long_Float instance of Fabula.Check.Compare.  See
--  Fabula.Check.Ints for why this needs the pragma, not the aspect,
--  form of SPARK_Mode.
pragma SPARK_Mode;

package Fabula.Check.Reals is new
  Fabula.Check.Compare (Item => Long_Float, Image => Fabula.Check.Real_Image);
