with Ada.Containers.Vectors;
with Ada.Text_IO; use Ada.Text_IO;

package body Fabula_Fixtures is

   use Ada.Strings.Unbounded;

   Corpus : constant String := "tests/data/cwt/parser/";

   package Line_Vectors is new
     Ada.Containers.Vectors (Positive, Unbounded_String);

   procedure Parse_Lines
     (Source : Lines;
      P      : out Fabula.Parse.Parser;
      Doc    : in out Fabula.Ast.Document) is
   begin
      Fabula.Parse.Start (P, Doc);
      for I in Source'Range loop
         Fabula.Parse.Feed (P, Doc, To_String (Source (I)), I);
      end loop;
      Fabula.Parse.Finish (P, Doc);
   end Parse_Lines;

   --  The file is read whole and closed before the first Feed.
   procedure Parse_Corpus
     (Name : String;
      P    : out Fabula.Parse.Parser;
      Doc  : in out Fabula.Ast.Document)
   is
      File : File_Type;
      Read : Line_Vectors.Vector;
   begin
      Open (File, In_File, Corpus & Name);
      while not End_Of_File (File) loop
         Read.Append (To_Unbounded_String (Get_Line (File)));
      end loop;
      Close (File);
      declare
         Source : Lines (1 .. Natural (Read.Length));
      begin
         for I in Source'Range loop
            Source (I) := Read (I);
         end loop;
         Parse_Lines (Source, P, Doc);
      end;
   end Parse_Corpus;

end Fabula_Fixtures;
