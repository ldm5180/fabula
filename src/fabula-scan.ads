--  Classifies one raw feature-file line.  Pure and stateless: the
--  parser machine owns document context and may override a class
--  (every line inside a doc string is content).
with Fabula.Limits;

package Fabula.Scan
  with Pure, SPARK_Mode
is

   type Line_Class is
     (Blank,
      Comment,
      Tag_Line,
      Feature_Header,
      Rule_Header,
      Background_Header,
      Scenario_Header,
      Outline_Header,
      Examples_Header,
      Step_Line,
      Table_Row,
      Doc_Fence,
      Description);

   type Step_Keyword is (K_Given, K_When, K_Then, K_And, K_But, K_Star);

   --  K's spelling as written in a step line: "Given", "When", "Then",
   --  "And", "But", "*". The one place this table lives, for any
   --  caller that must print a step's keyword back out.
   function Spelling (K : Step_Keyword) return String
   with Post => Spelling'Result'Length > 0;

   ---------------------------------------------------------------------
   --  Gherkin's grammar tokens, named once for every unit that reads or
   --  writes feature-file text.
   ---------------------------------------------------------------------

   Tag_Mark : constant Character := '@';
   --  Starts a tag: `@smoke`.

   Cell_Separator : constant Character := '|';
   --  Opens, separates and closes the cells of a table row.

   Escape_Mark : constant Character := '\';
   --  Inside a cell, makes the Cell_Separator after it part of the text.

   Cell_Quote : constant Character := '"';
   --  A step table's cell drops one pair of these around its text.

   Comment_Mark : constant Character := '#';
   --  Starts a comment line.

   Header_Colon : constant Character := ':';
   --  Ends a header's keyword: `Feature:`.

   Step_Bullet : constant Character := '*';
   --  Starts a step, as a keyword does: `* a step`.

   Quote_Fence    : constant Character := '"';
   Backtick_Fence : constant Character := '`';
   --  The two characters a doc-string fence is made of.

   Fence_Length : constant := 3;
   --  A doc-string fence is this many equal fence characters in a row.

   type Fence_Kind is (Quotes, Backticks);

   ---------------------------------------------------------------------
   --  Line positions.  Every slice of a scanned line, in the scanner,
   --  the line splitter, the parser and the step matcher, is typed by
   --  these two subtypes: a column is a character's index, or one past
   --  the last character where an empty slice starts; a length counts
   --  characters, and bounds a slice's last index.
   ---------------------------------------------------------------------

   subtype Line_Length is Natural range 0 .. Limits.Max_Line_Length;
   subtype Column is Positive range First_Column .. Limits.Max_Line_Length + 1;

   --  The bounds of an empty slice at the line's first column.
   Empty_First : constant Column := First_Column;
   Empty_Last  : constant Line_Length := Empty_First - 1;

   --  The indent of a line whose text starts at its first column.
   Flush_Left : constant Line_Length := 0;

   --  Slice bounds are indices into the classified line; First = 0
   --  with Last = -1 is impossible.  An empty payload is First = X,
   --  Last = X - 1 within the line's range, so callers slice
   --  unconditionally.
   type Classification (Class : Line_Class := Blank) is record
      Indent : Line_Length :=
        Flush_Left;   --  column of the first non-space char
      case Class is
         when Feature_Header
            | Rule_Header
            | Background_Header
            | Scenario_Header
            | Outline_Header
            | Examples_Header
         =>
            Title_First : Column := Empty_First;
            Title_Last  : Line_Length := Empty_Last;   --  title text, trimmed

         when Step_Line =>
            Keyword    : Step_Keyword := K_Star;
            Text_First : Column := Empty_First;
            Text_Last  : Line_Length := Empty_Last;    --  step text, trimmed

         when Tag_Line | Table_Row | Description =>
            Body_First : Column := Empty_First;
            Body_Last  : Line_Length := Empty_Last;    --  trimmed line body

         when Doc_Fence =>
            Fence      : Fence_Kind := Quotes;
            Type_First : Column := Empty_First;
            Type_Last  : Line_Length :=
              Empty_Last;    --  content type, right-trimmed

         when Blank | Comment =>
            null;
      end case;
   end record;

   --  C's payload lies inside a line of Length characters.  A title,
   --  step text or content type may be empty, one past the line's end;
   --  a tag line's, table row's or description's body is never empty and
   --  starts right after the indent.
   function Slices_Fit
     (C : Classification; Length : Line_Length) return Boolean
   is (C.Indent <= Length
       and then (case C.Class is
                   when Feature_Header
                      | Rule_Header
                      | Background_Header
                      | Scenario_Header
                      | Outline_Header
                      | Examples_Header                    =>
                     C.Title_First <= Length + 1
                     and then C.Title_Last <= Length
                     and then C.Title_Last >= C.Title_First - 1,
                   when Step_Line                          =>
                     C.Text_First <= Length + 1
                     and then C.Text_Last <= Length
                     and then C.Text_Last >= C.Text_First - 1,
                   when Tag_Line | Table_Row | Description =>
                     C.Body_First <= Length
                     and then C.Body_Last <= Length
                     and then C.Body_Last >= C.Body_First
                     and then C.Body_First = C.Indent + 1,
                   when Doc_Fence                          =>
                     C.Type_First <= Length + 1
                     and then C.Type_Last <= Length
                     and then C.Type_Last >= C.Type_First - 1,
                   when Blank | Comment                    => True));

   function Classify (Line : String) return Classification
   with
     Pre  =>
       Line'Length <= Limits.Max_Line_Length
       and then Line'First = First_Column,
     Post =>
       Slices_Fit (Classify'Result, Line'Length)
       and then (if Classify'Result.Class = Table_Row
                 then Line (Classify'Result.Body_First) = Cell_Separator);

end Fabula.Scan;
