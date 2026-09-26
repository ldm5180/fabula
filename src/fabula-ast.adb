package body Fabula.Ast
  with SPARK_Mode
is

   --  Widens a pool range to cover its newest member I; an empty range
   --  becomes I alone.  Children are appended right after one another,
   --  so the widened range stays contiguous.
   function Extended
     (R : Scenario_Range; I : Scenario_Index) return Scenario_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Extended (R : Step_Range; I : Step_Index) return Step_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Extended (R : Tag_Range; I : Tag_Index) return Tag_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Extended (R : Row_Range; I : Row_Index) return Row_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Extended (R : Cell_Range; I : Cell_Index) return Cell_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Extended
     (R : Doc_Line_Range; I : Doc_Line_Index) return Doc_Line_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Extended
     (R : Examples_Range; I : Examples_Index) return Examples_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Extended
     (R : Examples_Row_Range; I : Examples_Row_Index) return Examples_Row_Range
   is (if R.Last < R.First then (I, I) else (R.First, I));

   function Text (Doc : Document; S : Slice) return String is
      Result : constant String (1 .. Length (S)) :=
        Doc.Arena (S.First .. S.Last);
   begin
      return Result;
   end Text;

   procedure Clear (Doc : in out Document) is
   begin
      Doc.Used := 0;
      Doc.The_Feature := (others => <>);
      Doc.The_Background := (others => <>);
      Doc.Rules_Used := 0;
      Doc.Scenarios_Used := 0;
      Doc.Steps_Used := 0;
      Doc.Tags_Used := 0;
      Doc.Tables_Used := 0;
      Doc.Rows_Used := 0;
      Doc.Cells_Used := 0;
      Doc.Docs_Used := 0;
      Doc.Doc_Lines_Used := 0;
      Doc.Blocks_Used := 0;
      Doc.Example_Rows_Used := 0;
   end Clear;

   procedure Append_Text
     (Doc    : in out Document;
      Source : String;
      Result : out Slice;
      Ok     : out Boolean) is
   begin
      Result := Empty_Slice;
      Ok := Source'Length <= Limits.Text_Arena_Bytes - Doc.Used;
      if Ok and then Source'Length > 0 then
         Result := (First => Doc.Used + 1, Last => Doc.Used + Source'Length);
         Doc.Arena (Result.First .. Result.Last) := Source;
         Doc.Used := Result.Last;
      end if;
   end Append_Text;

   procedure Set_Feature
     (Doc : in out Document; Head : Header; Tags : Tag_Range) is
   begin
      Doc.The_Feature.Present := True;
      Doc.The_Feature.Head := Head;
      Doc.The_Feature.Tags := Tags;
   end Set_Feature;

   procedure Set_Background (Doc : in out Document; Head : Header) is
   begin
      Doc.The_Background := (Head => Head, Steps => <>);
      Doc.The_Feature.Has_Background := True;
   end Set_Background;

   procedure Add_Rule (Doc : in out Document; Head : Header; Ok : out Boolean)
   is
   begin
      Ok := Doc.Rules_Used < Rule_Handle'Last;
      if Ok then
         Doc.Rules_Used := Doc.Rules_Used + 1;
         Doc.Rules (Doc.Rules_Used) := (Head => Head, Scenarios => <>);
      end if;
   end Add_Rule;

   procedure Add_Scenario
     (Doc  : in out Document;
      Kind : Scenario_Kind;
      Head : Header;
      Tags : Tag_Range;
      Ok   : out Boolean) is
   begin
      Ok := Doc.Scenarios_Used < Scenario_Handle'Last;
      if not Ok then
         return;
      end if;
      Doc.Scenarios_Used := Doc.Scenarios_Used + 1;
      Doc.Scenarios (Doc.Scenarios_Used) :=
        (Kind   => Kind,
         Head   => Head,
         Tags   => Tags,
         Rule   => Doc.Rules_Used,
         others => <>);
      if Doc.Rules_Used > 0 then
         Doc.Rules (Doc.Rules_Used).Scenarios :=
           Extended (Doc.Rules (Doc.Rules_Used).Scenarios, Doc.Scenarios_Used);
      end if;
   end Add_Scenario;

   procedure Add_Examples
     (Doc : in out Document; Head : Header; Tags : Tag_Range; Ok : out Boolean)
   is
   begin
      Ok := Doc.Blocks_Used < Examples_Handle'Last;
      if not Ok then
         return;
      end if;
      Doc.Blocks_Used := Doc.Blocks_Used + 1;
      Doc.Blocks (Doc.Blocks_Used) :=
        (Head => Head, Tags => Tags, others => <>);
      if Doc.Scenarios_Used > 0 then
         Doc.Scenarios (Doc.Scenarios_Used).Examples :=
           Extended
             (Doc.Scenarios (Doc.Scenarios_Used).Examples, Doc.Blocks_Used);
      end if;
   end Add_Examples;

   --  The description a Describe call extends: the most recent node of
   --  the target kind, or the empty slice while no such node exists.
   function Description_Of (Doc : Document; Target : Block_Kind) return Slice
   is (case Target is
         when Feature_Block    => Doc.The_Feature.Head.Description,
         when Background_Block => Doc.The_Background.Head.Description,
         when Rule_Block       =>
           (if Doc.Rules_Used > 0
            then Doc.Rules (Doc.Rules_Used).Head.Description
            else Empty_Slice),
         when Scenario_Block   =>
           (if Doc.Scenarios_Used > 0
            then Doc.Scenarios (Doc.Scenarios_Used).Head.Description
            else Empty_Slice),
         when Examples_Block   =>
           (if Doc.Blocks_Used > 0
            then Doc.Blocks (Doc.Blocks_Used).Head.Description
            else Empty_Slice));

   procedure Set_Description
     (Doc : in out Document; Target : Block_Kind; Value : Slice) is
   begin
      case Target is
         when Feature_Block    =>
            Doc.The_Feature.Head.Description := Value;

         when Background_Block =>
            Doc.The_Background.Head.Description := Value;

         when Rule_Block       =>
            if Doc.Rules_Used > 0 then
               Doc.Rules (Doc.Rules_Used).Head.Description := Value;
            end if;

         when Scenario_Block   =>
            if Doc.Scenarios_Used > 0 then
               Doc.Scenarios (Doc.Scenarios_Used).Head.Description := Value;
            end if;

         when Examples_Block   =>
            if Doc.Blocks_Used > 0 then
               Doc.Blocks (Doc.Blocks_Used).Head.Description := Value;
            end if;
      end case;
   end Set_Description;

   procedure Describe
     (Doc    : in out Document;
      Target : Block_Kind;
      Source : String;
      Ok     : out Boolean)
   is
      Current : constant Slice := Description_Of (Doc, Target);
      Added   : Slice;
   begin
      if Length (Current) = 0 then
         Append_Text (Doc, Source, Added, Ok);
      else
         Append_Text (Doc, ASCII.LF & Source, Added, Ok);
      end if;
      --  Current ends right before Added in the arena: the caller
      --  appends nothing else between two lines of one description.
      if Ok and then Length (Added) > 0 then
         Set_Description
           (Doc,
            Target,
            (if Length (Current) = 0
             then Added
             else (First => Current.First, Last => Added.Last)));
      end if;
   end Describe;

   procedure Add_Tag
     (Doc     : in out Document;
      Text    : Slice;
      Pending : in out Tag_Range;
      Ok      : out Boolean) is
   begin
      Ok := Doc.Tags_Used < Tag_Handle'Last;
      if Ok then
         Doc.Tags_Used := Doc.Tags_Used + 1;
         Doc.Tags (Doc.Tags_Used) := Text;
         Pending := Extended (Pending, Doc.Tags_Used);
      end if;
   end Add_Tag;

   procedure Add_Step
     (Doc     : in out Document;
      Keyword : Scan.Step_Keyword;
      Text    : Slice;
      Line    : Natural;
      Ok      : out Boolean) is
   begin
      Ok := Doc.Steps_Used < Step_Handle'Last;
      if not Ok then
         return;
      end if;
      Doc.Steps_Used := Doc.Steps_Used + 1;
      Doc.Steps (Doc.Steps_Used) :=
        (Keyword => Keyword, Text => Text, Line => Line, others => <>);
      if Doc.Scenarios_Used > 0 then
         Doc.Scenarios (Doc.Scenarios_Used).Steps :=
           Extended (Doc.Scenarios (Doc.Scenarios_Used).Steps, Doc.Steps_Used);
      else
         Doc.The_Background.Steps :=
           Extended (Doc.The_Background.Steps, Doc.Steps_Used);
      end if;
   end Add_Step;

   procedure Add_Table (Doc : in out Document; Ok : out Boolean) is
   begin
      Ok := Doc.Tables_Used < Table_Handle'Last;
      if Ok then
         Doc.Tables_Used := Doc.Tables_Used + 1;
         Doc.Tables (Doc.Tables_Used) := (Rows => <>);
         if Doc.Steps_Used > 0 then
            Doc.Steps (Doc.Steps_Used).Table := Doc.Tables_Used;
         end if;
      end if;
   end Add_Table;

   procedure Add_Table_Row
     (Doc : in out Document; Line : Natural; Ok : out Boolean) is
   begin
      Ok := Doc.Rows_Used < Row_Handle'Last;
      if Ok then
         Doc.Rows_Used := Doc.Rows_Used + 1;
         Doc.Rows (Doc.Rows_Used) := (Cells => <>, Line => Line);
         if Doc.Tables_Used > 0 then
            Doc.Tables (Doc.Tables_Used).Rows :=
              Extended (Doc.Tables (Doc.Tables_Used).Rows, Doc.Rows_Used);
         end if;
      end if;
   end Add_Table_Row;

   procedure Add_Table_Cell
     (Doc : in out Document; Text : Slice; Ok : out Boolean) is
   begin
      Ok := Doc.Cells_Used < Cell_Handle'Last;
      if Ok then
         Doc.Cells_Used := Doc.Cells_Used + 1;
         Doc.Cells (Doc.Cells_Used) := Text;
         if Doc.Rows_Used > 0 then
            Doc.Rows (Doc.Rows_Used).Cells :=
              Extended (Doc.Rows (Doc.Rows_Used).Cells, Doc.Cells_Used);
         end if;
      end if;
   end Add_Table_Cell;

   procedure Add_Examples_Row
     (Doc : in out Document; Line : Natural; Ok : out Boolean) is
   begin
      Ok := Doc.Example_Rows_Used < Examples_Row_Handle'Last;
      if not Ok then
         return;
      end if;
      Doc.Example_Rows_Used := Doc.Example_Rows_Used + 1;
      Doc.Example_Rows (Doc.Example_Rows_Used) := (Cells => <>, Line => Line);
      if Doc.Blocks_Used = 0 then
         return;
      end if;
      if Doc.Blocks (Doc.Blocks_Used).Header_Row = 0 then
         Doc.Blocks (Doc.Blocks_Used).Header_Row := Doc.Example_Rows_Used;
      else
         Doc.Blocks (Doc.Blocks_Used).Rows :=
           Extended (Doc.Blocks (Doc.Blocks_Used).Rows, Doc.Example_Rows_Used);
      end if;
   end Add_Examples_Row;

   procedure Add_Examples_Cell
     (Doc : in out Document; Text : Slice; Ok : out Boolean) is
   begin
      Ok := Doc.Cells_Used < Cell_Handle'Last;
      if Ok then
         Doc.Cells_Used := Doc.Cells_Used + 1;
         Doc.Cells (Doc.Cells_Used) := Text;
         if Doc.Example_Rows_Used > 0 then
            Doc.Example_Rows (Doc.Example_Rows_Used).Cells :=
              Extended
                (Doc.Example_Rows (Doc.Example_Rows_Used).Cells,
                 Doc.Cells_Used);
         end if;
      end if;
   end Add_Examples_Cell;

   procedure Add_Doc_String
     (Doc          : in out Document;
      Fence        : Scan.Fence_Kind;
      Content_Type : Slice;
      Line         : Natural;
      Ok           : out Boolean) is
   begin
      Ok := Doc.Docs_Used < Doc_Handle'Last;
      if Ok then
         Doc.Docs_Used := Doc.Docs_Used + 1;
         Doc.Docs (Doc.Docs_Used) :=
           (Fence        => Fence,
            Content_Type => Content_Type,
            Line         => Line,
            Lines        => <>);
         if Doc.Steps_Used > 0 then
            Doc.Steps (Doc.Steps_Used).Doc := Doc.Docs_Used;
         end if;
      end if;
   end Add_Doc_String;

   procedure Add_Doc_Line
     (Doc : in out Document; Text : Slice; Ok : out Boolean) is
   begin
      Ok := Doc.Doc_Lines_Used < Doc_Line_Handle'Last;
      if Ok then
         Doc.Doc_Lines_Used := Doc.Doc_Lines_Used + 1;
         Doc.Doc_Lines (Doc.Doc_Lines_Used) := Text;
         if Doc.Docs_Used > 0 then
            Doc.Docs (Doc.Docs_Used).Lines :=
              Extended (Doc.Docs (Doc.Docs_Used).Lines, Doc.Doc_Lines_Used);
         end if;
      end if;
   end Add_Doc_Line;

end Fabula.Ast;
