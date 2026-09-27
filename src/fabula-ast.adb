package body Fabula.Ast
  with SPARK_Mode
is

   --  Whether Doc holds a node of each kind a builder appends to, and the
   --  most recent one when it does.

   function Has_Rule (Doc : Document) return Boolean
   is (Rule_Pool.Has_Newest (Doc.Rules_Used));

   function Newest_Rule (Doc : Document) return Rule_Index
   is (Rule_Pool.Newest (Doc.Rules_Used))
   with Pre => Has_Rule (Doc);

   function Has_Scenario (Doc : Document) return Boolean
   is (Scenario_Pool.Has_Newest (Doc.Scenarios_Used));

   function Newest_Scenario (Doc : Document) return Scenario_Index
   is (Scenario_Pool.Newest (Doc.Scenarios_Used))
   with Pre => Has_Scenario (Doc);

   function Has_Examples (Doc : Document) return Boolean
   is (Examples_Pool.Has_Newest (Doc.Blocks_Used));

   function Newest_Examples (Doc : Document) return Examples_Index
   is (Examples_Pool.Newest (Doc.Blocks_Used))
   with Pre => Has_Examples (Doc);

   function Has_Step (Doc : Document) return Boolean
   is (Step_Pool.Has_Newest (Doc.Steps_Used));

   function Newest_Step (Doc : Document) return Step_Index
   is (Step_Pool.Newest (Doc.Steps_Used))
   with Pre => Has_Step (Doc);

   function Has_Table (Doc : Document) return Boolean
   is (Table_Pool.Has_Newest (Doc.Tables_Used));

   function Newest_Table (Doc : Document) return Table_Index
   is (Table_Pool.Newest (Doc.Tables_Used))
   with Pre => Has_Table (Doc);

   function Has_Table_Row (Doc : Document) return Boolean
   is (Row_Pool.Has_Newest (Doc.Rows_Used));

   function Newest_Table_Row (Doc : Document) return Row_Index
   is (Row_Pool.Newest (Doc.Rows_Used))
   with Pre => Has_Table_Row (Doc);

   function Has_Examples_Row (Doc : Document) return Boolean
   is (Examples_Row_Pool.Has_Newest (Doc.Example_Rows_Used));

   function Newest_Examples_Row (Doc : Document) return Examples_Row_Index
   is (Examples_Row_Pool.Newest (Doc.Example_Rows_Used))
   with Pre => Has_Examples_Row (Doc);

   function Has_Doc_String (Doc : Document) return Boolean
   is (Doc_Pool.Has_Newest (Doc.Docs_Used));

   function Newest_Doc_String (Doc : Document) return Doc_Index
   is (Doc_Pool.Newest (Doc.Docs_Used))
   with Pre => Has_Doc_String (Doc);

   function Text (Doc : Document; S : Slice) return String is
      Result : constant String (1 .. Length (S)) :=
        Doc.Arena (S.First .. S.Last);
   begin
      return Result;
   end Text;

   procedure Clear (Doc : in out Document) is
   begin
      Doc.Used := No_Characters;
      Doc.The_Feature := (others => <>);
      Doc.The_Background := (others => <>);
      Doc.Rules_Used := Rule_Pool.None;
      Doc.Scenarios_Used := Scenario_Pool.None;
      Doc.Steps_Used := Step_Pool.None;
      Doc.Tags_Used := Tag_Pool.None;
      Doc.Tables_Used := Table_Pool.None;
      Doc.Rows_Used := Row_Pool.None;
      Doc.Cells_Used := Cell_Pool.None;
      Doc.Docs_Used := Doc_Pool.None;
      Doc.Doc_Lines_Used := Doc_Line_Pool.None;
      Doc.Blocks_Used := Examples_Pool.None;
      Doc.Example_Rows_Used := Examples_Row_Pool.None;
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
      if Ok then
         Doc.Scenarios_Used := Doc.Scenarios_Used + 1;
         Doc.Scenarios (Doc.Scenarios_Used) :=
           (Kind   => Kind,
            Head   => Head,
            Tags   => Tags,
            Rule   => Doc.Rules_Used,
            others => <>);
         if Has_Rule (Doc) then
            Doc.Rules (Newest_Rule (Doc)).Scenarios :=
              Scenario_Pool.Extended
                (Doc.Rules (Newest_Rule (Doc)).Scenarios, Doc.Scenarios_Used);
         end if;
      end if;
   end Add_Scenario;

   procedure Add_Examples
     (Doc : in out Document; Head : Header; Tags : Tag_Range; Ok : out Boolean)
   is
   begin
      Ok := Doc.Blocks_Used < Examples_Handle'Last;
      if Ok then
         Doc.Blocks_Used := Doc.Blocks_Used + 1;
         Doc.Blocks (Doc.Blocks_Used) :=
           (Head => Head, Tags => Tags, others => <>);
         if Has_Scenario (Doc) then
            Doc.Scenarios (Newest_Scenario (Doc)).Examples :=
              Examples_Pool.Extended
                (Doc.Scenarios (Newest_Scenario (Doc)).Examples,
                 Doc.Blocks_Used);
         end if;
      end if;
   end Add_Examples;

   --  The description a Describe call extends: the most recent node of
   --  the target kind, or the empty slice while no such node exists.
   function Description_Of (Doc : Document; Target : Block_Kind) return Slice
   is (case Target is
         when Feature_Block    => Doc.The_Feature.Head.Description,
         when Background_Block => Doc.The_Background.Head.Description,
         when Rule_Block       =>
           (if Has_Rule (Doc)
            then Doc.Rules (Newest_Rule (Doc)).Head.Description
            else Empty_Slice),
         when Scenario_Block   =>
           (if Has_Scenario (Doc)
            then Doc.Scenarios (Newest_Scenario (Doc)).Head.Description
            else Empty_Slice),
         when Examples_Block   =>
           (if Has_Examples (Doc)
            then Doc.Blocks (Newest_Examples (Doc)).Head.Description
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
            if Has_Rule (Doc) then
               Doc.Rules (Newest_Rule (Doc)).Head.Description := Value;
            end if;

         when Scenario_Block   =>
            if Has_Scenario (Doc) then
               Doc.Scenarios (Newest_Scenario (Doc)).Head.Description := Value;
            end if;

         when Examples_Block   =>
            if Has_Examples (Doc) then
               Doc.Blocks (Newest_Examples (Doc)).Head.Description := Value;
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
      Fresh   : constant Boolean := Is_Empty (Current);
      Added   : Slice;
   begin
      Append_Text
        (Doc, (if Fresh then Source else ASCII.LF & Source), Added, Ok);
      --  Current ends right before Added in the arena: the caller
      --  appends nothing else between two lines of one description.
      if Ok and then not Is_Empty (Added) then
         Set_Description
           (Doc,
            Target,
            (if Fresh
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
         Pending := Tag_Pool.Extended (Pending, Doc.Tags_Used);
      end if;
   end Add_Tag;

   procedure Add_Step
     (Doc     : in out Document;
      Keyword : Scan.Step_Keyword;
      Text    : Slice;
      Line    : Line_Number;
      Ok      : out Boolean) is
   begin
      Ok := Doc.Steps_Used < Step_Handle'Last;
      if Ok then
         Doc.Steps_Used := Doc.Steps_Used + 1;
         Doc.Steps (Doc.Steps_Used) :=
           (Keyword => Keyword, Text => Text, Line => Line, others => <>);
         if Has_Scenario (Doc) then
            Doc.Scenarios (Newest_Scenario (Doc)).Steps :=
              Step_Pool.Extended
                (Doc.Scenarios (Newest_Scenario (Doc)).Steps, Doc.Steps_Used);
         else
            Doc.The_Background.Steps :=
              Step_Pool.Extended (Doc.The_Background.Steps, Doc.Steps_Used);
         end if;
      end if;
   end Add_Step;

   procedure Add_Table (Doc : in out Document; Ok : out Boolean) is
   begin
      Ok := Doc.Tables_Used < Table_Handle'Last;
      if Ok then
         Doc.Tables_Used := Doc.Tables_Used + 1;
         Doc.Tables (Doc.Tables_Used) := (Rows => <>);
         if Has_Step (Doc) then
            Doc.Steps (Newest_Step (Doc)).Table := Doc.Tables_Used;
         end if;
      end if;
   end Add_Table;

   procedure Add_Table_Row
     (Doc : in out Document; Line : Line_Number; Ok : out Boolean) is
   begin
      Ok := Doc.Rows_Used < Row_Handle'Last;
      if Ok then
         Doc.Rows_Used := Doc.Rows_Used + 1;
         Doc.Rows (Doc.Rows_Used) := (Cells => <>, Line => Line);
         if Has_Table (Doc) then
            Doc.Tables (Newest_Table (Doc)).Rows :=
              Row_Pool.Extended
                (Doc.Tables (Newest_Table (Doc)).Rows, Doc.Rows_Used);
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
         if Has_Table_Row (Doc) then
            Doc.Rows (Newest_Table_Row (Doc)).Cells :=
              Cell_Pool.Extended
                (Doc.Rows (Newest_Table_Row (Doc)).Cells, Doc.Cells_Used);
         end if;
      end if;
   end Add_Table_Cell;

   --  Block B with Row added: its header while it has none, else its
   --  newest data row.
   function With_Row
     (B : Examples_Node; Row : Examples_Row_Index) return Examples_Node
   is (if B.Header_Row = No_Examples_Row
       then (B with delta Header_Row => Row)
       else (B with delta Rows => Examples_Row_Pool.Extended (B.Rows, Row)));

   procedure Add_Examples_Row
     (Doc : in out Document; Line : Line_Number; Ok : out Boolean) is
   begin
      Ok := Doc.Example_Rows_Used < Examples_Row_Handle'Last;
      if Ok then
         Doc.Example_Rows_Used := Doc.Example_Rows_Used + 1;
         Doc.Example_Rows (Doc.Example_Rows_Used) :=
           (Cells => <>, Line => Line);
         if Has_Examples (Doc) then
            Doc.Blocks (Newest_Examples (Doc)) :=
              With_Row
                (Doc.Blocks (Newest_Examples (Doc)), Doc.Example_Rows_Used);
         end if;
      end if;
   end Add_Examples_Row;

   procedure Add_Examples_Cell
     (Doc : in out Document; Text : Slice; Ok : out Boolean) is
   begin
      Ok := Doc.Cells_Used < Cell_Handle'Last;
      if Ok then
         Doc.Cells_Used := Doc.Cells_Used + 1;
         Doc.Cells (Doc.Cells_Used) := Text;
         if Has_Examples_Row (Doc) then
            Doc.Example_Rows (Newest_Examples_Row (Doc)).Cells :=
              Cell_Pool.Extended
                (Doc.Example_Rows (Newest_Examples_Row (Doc)).Cells,
                 Doc.Cells_Used);
         end if;
      end if;
   end Add_Examples_Cell;

   procedure Add_Doc_String
     (Doc          : in out Document;
      Fence        : Scan.Fence_Kind;
      Content_Type : Slice;
      Line         : Line_Number;
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
         if Has_Step (Doc) then
            Doc.Steps (Newest_Step (Doc)).Doc := Doc.Docs_Used;
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
         if Has_Doc_String (Doc) then
            Doc.Docs (Newest_Doc_String (Doc)).Lines :=
              Doc_Line_Pool.Extended
                (Doc.Docs (Newest_Doc_String (Doc)).Lines, Doc.Doc_Lines_Used);
         end if;
      end if;
   end Add_Doc_Line;

end Fabula.Ast;
