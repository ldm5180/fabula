--  The shipped Integer instance of Fabula.Check.Compare.  The pragma
--  form is required here: the SPARK_Mode ASPECT is rejected on a
--  package instantiation, and without either gnatprove skips this
--  child unit as Off rather than analyzing it.
pragma SPARK_Mode;

package Fabula.Check.Ints is new
  Fabula.Check.Compare (Item => Integer, Image => Fabula.Check.Integer_Image);
