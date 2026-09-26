--  Scratch files for the shell tests, all under tests/obj, which git
--  ignores.  The suite runs from the crate root.

package Fabula_Shell_Scratch is

   Root : constant String := "tests/obj/shell_scratch";

   --  Root/Name as an empty directory: made afresh, whatever was there.
   function Fresh_Dir (Name : String) return String;

   --  Writes Content to Path byte for byte, creating or emptying it.
   procedure Write_File (Path : String; Content : String);

   --  Path's whole content, byte for byte.
   function Read_File (Path : String) return String;

   --  What Action writes to the current output, byte for byte.  The
   --  output is restored even when Action raises.
   function Capture (Action : not null access procedure) return String;

end Fabula_Shell_Scratch;
