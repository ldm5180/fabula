--  Where the JSON report goes: a file written chunk by chunk, or the
--  console when no file is named.  Each call says how it went; nothing
--  raises to the caller.
private with Ada.Streams.Stream_IO;

package Fabula.Shell.Reports
  with SPARK_Mode => Off
is

   type Status is
     (Ok,
      Open_Failed,    --  the file could not be created
      Write_Failed,   --  a write, or the close that flushes it, failed
      Already_Open,   --  Open or Open_Console on a report still open
      Not_Open);      --  Write or Close with no report open

   type Report is limited private;

   function Is_Open (R : Report) return Boolean;

   --  Creates the file at Path, or empties the one there.  An empty Path
   --  is Open_Failed: the language would make it a temporary file.
   procedure Open (R : in out Report; Path : String; Result : out Status);

   --  Sends the chunks to the console, unstyled.
   procedure Open_Console (R : in out Report; Result : out Status);

   --  Appends Chunk as it is: no line ends added, none translated.
   procedure Write (R : in out Report; Chunk : String; Result : out Status);

   --  Closes the file, or stops sending to the console.
   procedure Close (R : in out Report; Result : out Status);

private

   type Target is (Nowhere, To_File, To_Console);

   type Report is limited record
      Where : Target := Nowhere;
      File  : Ada.Streams.Stream_IO.File_Type;
   end record;

   function Is_Open (R : Report) return Boolean
   is (R.Where /= Nowhere);

end Fabula.Shell.Reports;
