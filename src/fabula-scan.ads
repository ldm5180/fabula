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

   type Fence_Kind is (Quotes, Backticks);

   subtype Length is Natural range 0 .. Limits.Max_Line_Length;

   --  Slice bounds are indices into the classified line; First = 0
   --  with Last = -1 is impossible.  An empty payload is First = X,
   --  Last = X - 1 within the line's range, so callers slice
   --  unconditionally.
   type Classification (Class : Line_Class := Blank) is record
      Indent : Length := 0;   --  column of the first non-space char
      case Class is
         when Feature_Header
            | Rule_Header
            | Background_Header
            | Scenario_Header
            | Outline_Header
            | Examples_Header
         =>
            Title_First : Positive := 1;
            Title_Last  : Natural := 0;   --  title text, trimmed

         when Step_Line =>
            Keyword    : Step_Keyword := K_Star;
            Text_First : Positive := 1;
            Text_Last  : Natural := 0;    --  step text, trimmed

         when Tag_Line | Table_Row | Description =>
            Body_First : Positive := 1;
            Body_Last  : Natural := 0;    --  trimmed line body

         when Doc_Fence =>
            Fence      : Fence_Kind := Quotes;
            Type_First : Positive := 1;
            Type_Last  : Natural := 0;    --  content type, right-trimmed

         when Blank | Comment =>
            null;
      end case;
   end record;

   function Classify (Line : String) return Classification
   with
     Pre  => Line'Length <= Limits.Max_Line_Length and then Line'First = 1,
     Post =>
       (case Classify'Result.Class is
          when Feature_Header
             | Rule_Header
             | Background_Header
             | Scenario_Header
             | Outline_Header
             | Examples_Header        =>
            Classify'Result.Title_First <= Line'Last + 1
            and then Classify'Result.Title_Last <= Line'Last
            and then Classify'Result.Title_Last
                     >= Classify'Result.Title_First - 1,
          when Step_Line              =>
            Classify'Result.Text_First <= Line'Last + 1
            and then Classify'Result.Text_Last <= Line'Last
            and then Classify'Result.Text_Last
                     >= Classify'Result.Text_First - 1,
          when Tag_Line | Description =>
            Classify'Result.Body_First <= Line'Last + 1
            and then Classify'Result.Body_Last <= Line'Last
            and then Classify'Result.Body_Last >= Classify'Result.Body_First
            and then Classify'Result.Body_First = Classify'Result.Indent + 1,
          when Table_Row              =>
            Classify'Result.Body_First <= Line'Last + 1
            and then Classify'Result.Body_Last <= Line'Last
            and then Classify'Result.Body_Last >= Classify'Result.Body_First
            and then Classify'Result.Body_First = Classify'Result.Indent + 1
            and then Line (Classify'Result.Body_First) = '|',
          when Doc_Fence              =>
            Classify'Result.Type_First <= Line'Last + 1
            and then Classify'Result.Type_Last <= Line'Last
            and then Classify'Result.Type_Last
                     >= Classify'Result.Type_First - 1,
          when Blank | Comment        => True)
       and then Classify'Result.Indent <= Line'Length;

end Fabula.Scan;
