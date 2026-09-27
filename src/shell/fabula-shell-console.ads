--  Styled writing to the console: the current output, which is standard
--  output unless the program redirects it.  A style is one of the
--  colors the reference interpreter prints with.  Styling is on only
--  when standard output is a terminal and NO_COLOR is unset.  What to
--  print, and at which verbosity, is the caller's choice.

package Fabula.Shell.Console
  with SPARK_Mode => Off
is

   --  The roles the reference interpreter colors.  Plain carries no
   --  code: feature and scenario headers and the summary text print
   --  plain.
   type Style is
     (Plain,
      Passed,      --  green
      Failed,      --  red
      Skipped,     --  cornflower blue
      Undefined,   --  yellow
      Location,    --  gray: the "  file:line" after a header or a step
      Error,       --  red: errors and failed checks
      Verbose);    --  gray

   --  The escape sequence that opens S; "" for Plain.
   function Code (S : Style) return String;

   --  The escape sequence that closes every other style.
   Reset : constant String := ASCII.ESC & "[0m";

   --  Where the program runs.  No_Color is True when NO_COLOR is set to
   --  any value, the empty one included, as the reference interpreter
   --  reads it.
   type Surroundings is record
      Terminal : Boolean := False;   --  standard output is a terminal
      No_Color : Boolean := False;
   end record;

   function Current_Surroundings return Surroundings;

   function Color_Allowed (S : Surroundings) return Boolean
   is (S.Terminal and then not S.No_Color);

   --  Styling starts as Color_Allowed (Current_Surroundings) at
   --  elaboration; Set_Color overrides it.
   procedure Set_Color (On : Boolean);
   function Color return Boolean;

   --  Text between S's code and Reset while styling is on; Text alone
   --  otherwise, and always for Plain.
   function Styled (Text : String; S : Style := Plain) return String;

   --  Writes Styled (Text, S) byte for byte: no encoding, no line
   --  tracking.  A failed write sets Write_Failed.
   procedure Put (Text : String; S : Style := Plain);
   procedure New_Line;

   --  Put (Text, S), then an unstyled New_Line.
   procedure Put_Line (Text : String; S : Style := Plain);

   --  Whether any write has failed since elaboration.
   function Write_Failed return Boolean;

end Fabula.Shell.Console;
