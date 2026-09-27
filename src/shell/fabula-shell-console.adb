with Ada.Environment_Variables;
with Ada.IO_Exceptions;
with Ada.Text_IO.Text_Streams;
with Interfaces.C_Streams;

package body Fabula.Shell.Console
  with SPARK_Mode => Off
is

   ESC : constant Character := ASCII.ESC;

   --  The reference interpreter's palette, as its terminal output shows.
   function Code (S : Style) return String
   is (case S is
         when Plain              => "",
         when Passed             => ESC & "[32m",
         when Failed | Error     => ESC & "[31m",
         when Skipped            => ESC & "[38;2;100;149;237m",
         when Undefined          => ESC & "[33m",
         when Location | Verbose => ESC & "[90m");

   --  What isatty answers for a stream that is no terminal.
   Not_A_Terminal : constant Interfaces.C_Streams.int := 0;

   --  The variable that turns styling off, set to any value.
   No_Color_Variable : constant String := "NO_COLOR";

   function Current_Surroundings return Surroundings
   is ((Terminal =>
          Interfaces.C_Streams.isatty
            (Interfaces.C_Streams.fileno (Interfaces.C_Streams.stdout))
          /= Not_A_Terminal,
        No_Color => Ada.Environment_Variables.Exists (No_Color_Variable)));

   Colored : Boolean := Color_Allowed (Current_Surroundings);
   Broken  : Boolean := False;

   procedure Set_Color (On : Boolean) is
   begin
      Colored := On;
   end Set_Color;

   function Color return Boolean
   is (Colored);

   function Styled (Text : String; S : Style := Plain) return String
   is (if Colored and then S /= Plain then Code (S) & Text & Reset else Text);

   --  The text stream of the current output takes the bytes as they are,
   --  where Text_IO's own Put may re-encode an upper-half character.
   procedure Put (Text : String; S : Style := Plain) is
   begin
      String'Write
        (Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Current_Output),
         Styled (Text, S));
   exception
      when
        Ada.IO_Exceptions.Device_Error
        | Ada.IO_Exceptions.Use_Error
        | Ada.IO_Exceptions.Mode_Error
        | Ada.IO_Exceptions.Status_Error
      =>
         Broken := True;
   end Put;

   procedure New_Line is
   begin
      Put ([ASCII.LF]);
   end New_Line;

   procedure Put_Line (Text : String; S : Style := Plain) is
   begin
      Put (Text, S);
      New_Line;
   end Put_Line;

   function Write_Failed return Boolean
   is (Broken);

end Fabula.Shell.Console;
