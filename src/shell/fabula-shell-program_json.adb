with Sml.Machines.Operators;

with Fabula.Ast;
with Fabula.Check;
with Fabula.Expand;
with Fabula.Format;
with Fabula.Results;
with Fabula.Shell.Reports;

package body Fabula.Shell.Program_Json
  with SPARK_Mode => Off
is

   use type Fabula.Ast.Cell_Handle;
   use type Fabula.Ast.Examples_Row_Handle;
   use type Fabula.Ast.Row_Handle;
   use type Fabula.Cli.Report_Target;
   use type Fabula.Expand.Walk_Status;
   use type Fabula.Results.Status;
   use type Runner.Step_Cause;

   package Format renames Fabula.Format;

   Doc_Ref : Fabula.Args.Document_Access;
   Report  : Fabula.Shell.Reports.Report;

   procedure Set_Document (Doc : Fabula.Args.Document_Access) is
   begin
      Doc_Ref := Doc;
   end Set_Document;

   procedure Open_Target (Target : Fabula.Cli.Report_Target; File : String) is
      Status : Fabula.Shell.Reports.Status;
   begin
      --  --report-json= (fabula's own merged form) can name an empty
      --  file; the reference interpreter's own classification treats no
      --  value at all as stdout, so an empty one falls back the same way
      --  rather than opening an empty path and failing.
      if Target = Fabula.Cli.Json_File and then File'Length > 0 then
         Fabula.Shell.Reports.Open (Report, File, Status);
      else
         Fabula.Shell.Reports.Open_Console (Report, Status);
      end if;
   end Open_Target;

   ---------------------------------------------------------------------
   --  Chunk writes.  Every piece but the report's very last byte ends
   --  its own line; Fabula.Format's glue never adds one, by design (its
   --  own comment), so the caller joins.
   ---------------------------------------------------------------------

   Line_End : constant String := [ASCII.LF];

   procedure Write_Report (Chunk : String) is
      Status : Fabula.Shell.Reports.Status;
   begin
      Fabula.Shell.Reports.Write (Report, Chunk, Status);
   end Write_Report;

   procedure Write_Line (Chunk : String) is
   begin
      Write_Report (Chunk);
      Write_Report (Line_End);
   end Write_Line;

   --  A string field whose value is Raw, escaped.
   procedure Write_Text_Field
     (Key, Raw : String; Depth : Format.Depth_Value; More : Boolean) is
   begin
      Write_Line
        (Format.String_Field (Key, Format.Escape_Json (Raw), Depth, More));
   end Write_Text_Field;

   --  The "line" field of a feature, a scenario or a step: its line
   --  number, as a JSON number.
   function Line_Field
     (Line : Line_Number; Depth : Format.Depth_Value; More : Boolean)
      return String
   is (Format.Number_Field (Format.Line_Key, Natural (Line), Depth, More));

   ---------------------------------------------------------------------
   --  A scenario's id.
   ---------------------------------------------------------------------

   --  An outline row's 1-based position within its OWN Examples block;
   --  No_Occurrence for a plain scenario.  Uses the row's own position
   --  (Data_Row - Rows.First + 1) rather than a running count of
   --  scenarios actually seen -- a `:line` selection or a `-n` filter
   --  can run rows out of order or skip some outright, and a running
   --  count would number them by arrival, not by row.
   function Occurrence_For
     (Doc : Fabula.Ast.Document; Ref : Fabula.Expand.Example_Ref)
      return Natural
   is (if Ref.Status = Fabula.Expand.Row_Due
       then
         Natural
           (Ref.Data_Row - Fabula.Ast.Examples (Doc, Ref.Block).Rows.First)
         + 1
       else Format.No_Occurrence);

   function Rule_Name_Of (S : Fabula.Ast.Scenario_Handle) return String is
      Rule : constant Fabula.Ast.Rule_Handle :=
        Fabula.Ast.Scenario (Doc_Ref.all, S).Rule;
   begin
      if Rule not in 1 .. Fabula.Ast.Rule_Count (Doc_Ref.all) then
         return "";
      end if;
      return
        Fabula.Ast.Text
          (Doc_Ref.all, Fabula.Ast.Rule (Doc_Ref.all, Rule).Head.Name);
   end Rule_Name_Of;

   function Scenario_Id_Text
     (N    : Runner.Notice;
      Info : Fabula.Frames.Frame;
      Ref  : Fabula.Expand.Example_Ref) return String
   is (Format.Scenario_Id
         (Fabula.Ast.Text
            (Doc_Ref.all, Fabula.Ast.Feature (Doc_Ref.all).Head.Name),
          Rule_Name_Of (N.Scenario),
          Fabula.Frames.Value (Info.Scenario),
          Occurrence_For (Doc_Ref.all, Ref)));

   ---------------------------------------------------------------------
   --  Tags: a "tags" array of Count tags, the I-th one's text Tag_Text
   --  (I), or an empty array.
   ---------------------------------------------------------------------

   generic
      Count : Natural;
      with function Tag_Text (I : Positive) return String;
   procedure Write_Tag_Array (Depth : Format.Depth_Value; More : Boolean);

   procedure Write_Tag_Array (Depth : Format.Depth_Value; More : Boolean) is
   begin
      if Count = 0 then
         Write_Line (Format.Empty_Array_Field (Format.Tags_Key, Depth, More));
      else
         Write_Line (Format.Open_Array (Format.Tags_Key, Depth));
         for I in 1 .. Count loop
            Write_Line
              (Format.String_Item
                 (Format.Escape_Json (Tag_Text (I)), Depth + 1, I /= Count));
         end loop;
         Write_Line (Format.Close_Array (Depth, More));
      end if;
   end Write_Tag_Array;

   --  A scenario's effective tags.
   procedure Write_Scenario_Tags (Set : Fabula.Expand.Tag_Set) is
      function Tag_Text (I : Positive) return String
      is (Fabula.Ast.Text
            (Doc_Ref.all, Fabula.Ast.Tag (Doc_Ref.all, Set.Items (I))));

      procedure Write is new Write_Tag_Array (Set.Count, Tag_Text);
   begin
      Write (Format.Scenario_Fields_Depth, More => True);
   end Write_Scenario_Tags;

   --  The feature's own tags, up to the end of the tag pool.
   procedure Write_Feature_Tags is
      Tags : constant Fabula.Ast.Tag_Range :=
        Fabula.Ast.Feature (Doc_Ref.all).Tags;
      Live : constant Fabula.Ast.Tag_Range :=
        (First => Tags.First,
         Last  =>
           Fabula.Ast.Tag_Handle'Min
             (Tags.Last, Fabula.Ast.Tag_Count (Doc_Ref.all)));

      function Tag_Text (I : Positive) return String
      is (Fabula.Ast.Text
            (Doc_Ref.all,
             Fabula.Ast.Tag (Doc_Ref.all, Fabula.Ast.Tag_Pool.Nth (Live, I))));

      procedure Write is new
        Write_Tag_Array (Fabula.Ast.Tag_Pool.Width (Live), Tag_Text);
   begin
      Write (Format.Feature_Fields_Depth, More => True);
   end Write_Feature_Tags;

   ---------------------------------------------------------------------
   --  A step: arguments, keyword, line, match, name, result.
   ---------------------------------------------------------------------

   procedure Write_Cells_Of_Row
     (Doc      : Fabula.Ast.Document;
      Row      : Fabula.Ast.Row_Handle;
      Last_Row : Boolean)
   is
      Cells : constant Fabula.Ast.Cell_Range :=
        Fabula.Ast.Table_Row (Doc, Row).Cells;
   begin
      Write_Line (Format.Open_Object (Format.Row_Object_Depth));
      Write_Line
        (Format.Open_Array (Format.Cells_Key, Format.Row_Fields_Depth));
      for Cell in Cells.First .. Cells.Last loop
         exit when Cell not in 1 .. Fabula.Ast.Cell_Count (Doc);
         Write_Line
           (Format.String_Item
              (Format.Escape_Json
                 (Fabula.Ast.Text (Doc, Fabula.Ast.Cell (Doc, Cell))),
               Format.Cell_Item_Depth,
               Cell /= Cells.Last));
      end loop;
      Write_Line (Format.Close_Array (Format.Row_Fields_Depth, False));
      Write_Line (Format.Close_Object (Format.Row_Object_Depth, not Last_Row));
   end Write_Cells_Of_Row;

   procedure Write_Table_Rows
     (Doc : Fabula.Ast.Document; Rows : Fabula.Ast.Row_Range) is
   begin
      if Fabula.Ast.Row_Pool.Is_Empty (Rows) then
         Write_Line
           (Format.Empty_Array_Field
              (Format.Rows_Key, Format.Argument_Fields_Depth, False));
      else
         Write_Line
           (Format.Open_Array (Format.Rows_Key, Format.Argument_Fields_Depth));
         for Row in Rows.First .. Rows.Last loop
            exit when Row not in 1 .. Fabula.Ast.Table_Row_Count (Doc);
            Write_Cells_Of_Row (Doc, Row, Row = Rows.Last);
         end loop;
         Write_Line (Format.Close_Array (Format.Argument_Fields_Depth, False));
      end if;
   end Write_Table_Rows;

   procedure Write_Table_Argument
     (Doc : Fabula.Ast.Document; T : Fabula.Ast.Table_Handle) is
   begin
      Write_Line (Format.Open_Object (Format.Argument_Object_Depth));
      Write_Table_Rows (Doc, Fabula.Ast.Table (Doc, T).Rows);
      Write_Line (Format.Close_Object (Format.Argument_Object_Depth, False));
   end Write_Table_Argument;

   procedure Write_Doc_Argument
     (Doc        : Fabula.Ast.Document;
      D          : Fabula.Ast.Doc_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle)
   is
      Content : constant Format.Joined_Text :=
        Format.Doc_String_Content (Doc, D, Header_Row, Data_Row);
   begin
      Write_Line (Format.Open_Object (Format.Argument_Object_Depth));
      Write_Text_Field
        (Format.Content_Key,
         Format.Value (Content),
         Format.Argument_Fields_Depth,
         False);
      Write_Line (Format.Close_Object (Format.Argument_Object_Depth, False));
   end Write_Doc_Argument;

   --  What a step's "arguments" array holds.
   type Argument_Kind is (No_Argument, Table_Argument, Doc_Argument);

   --  The reference interpreter builds an unmatched outline row from its
   --  bare keyword/name/file/line alone, no table or doc string at all
   --  -- Suppressed forces the empty form regardless of what the AST
   --  step node holds.
   function Argument_Of
     (Doc        : Fabula.Ast.Document;
      Node       : Fabula.Ast.Step_Node;
      Suppressed : Boolean) return Argument_Kind
   is (if Suppressed
       then No_Argument
       elsif Node.Table in 1 .. Fabula.Ast.Table_Count (Doc)
       then Table_Argument
       elsif Node.Doc in 1 .. Fabula.Ast.Doc_String_Count (Doc)
       then Doc_Argument
       else No_Argument);

   procedure Write_Step_Arguments
     (Doc        : Fabula.Ast.Document;
      Step       : Fabula.Ast.Step_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle;
      Suppressed : Boolean)
   is
      Node : constant Fabula.Ast.Step_Node := Fabula.Ast.Step (Doc, Step);
   begin
      case Argument_Of (Doc, Node, Suppressed) is
         when No_Argument    =>
            Write_Line
              (Format.Empty_Array_Field
                 (Format.Arguments_Key, Format.Step_Fields_Depth, True));

         when Table_Argument =>
            Write_Line
              (Format.Open_Array
                 (Format.Arguments_Key, Format.Step_Fields_Depth));
            Write_Table_Argument (Doc, Node.Table);
            Write_Line (Format.Close_Array (Format.Step_Fields_Depth, True));

         when Doc_Argument   =>
            Write_Line
              (Format.Open_Array
                 (Format.Arguments_Key, Format.Step_Fields_Depth));
            Write_Doc_Argument (Doc, Node.Doc, Header_Row, Data_Row);
            Write_Line (Format.Close_Array (Format.Step_Fields_Depth, True));
      end case;
   end Write_Step_Arguments;

   --  The matched step's registered pattern text: the ruling for
   --  match.location (the oracle's own analogue -- a C++ source
   --  position -- has no fabula counterpart).  The runner keeps the
   --  match only while its request is pending, gone by Step_Closed, so
   --  this re-derives it from the notice's own resolved text: the same
   --  table and the same text always find the same row.  Empty for a
   --  skipped or undefined step (neither one ran, so neither has a
   --  match to report, whatever Reg.Find would find by text alone) --
   --  matching the oracle's own fallback.
   function Match_Location_Text
     (Status : Fabula.Results.Status; Info : Fabula.Frames.Frame) return String
   is
      Found : Reg.Match_Result;
   begin
      if Status not in Fabula.Results.Passed | Fabula.Results.Failed then
         return "";
      end if;
      Found := Reg.Find (Runner.Steps, Fabula.Frames.Value (Info.Step));
      return
        (if Found.Found
         then Reg.Pattern_Text (Runner.Steps, Found.Index)
         else "");
   end Match_Location_Text;

   procedure Write_Match (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      Write_Line
        (Format.Open_Named_Object
           (Format.Match_Key, Format.Step_Fields_Depth));
      Write_Text_Field
        (Format.Location_Key,
         Match_Location_Text (N.Status, Info),
         Format.Match_Result_Fields_Depth,
         False);
      Write_Line (Format.Close_Object (Format.Step_Fields_Depth, True));
   end Write_Match;

   --  A failed step's own message, or an undefined step's.
   function Error_Message_Of (N : Runner.Notice) return String
   is (if N.Status = Fabula.Results.Failed
       then Fabula.Check.Failure_Text (N.Outcome)
       elsif N.Cause = Runner.Too_Long_Expansion
       then Runner.Too_Long_Message
       else Format.Undefined_Step_Message)
   with Pre => N.Status in Fabula.Results.Failed | Fabula.Results.Undefined;

   procedure Write_Step_Result (N : Runner.Notice) is
   begin
      Write_Line
        (Format.Open_Named_Object
           (Format.Result_Key, Format.Step_Fields_Depth));
      if N.Status in Fabula.Results.Failed | Fabula.Results.Undefined then
         Write_Text_Field
           (Format.Error_Message_Key,
            Error_Message_Of (N),
            Format.Match_Result_Fields_Depth,
            True);
      end if;
      Write_Text_Field
        (Format.Status_Key,
         Format.Status_Name (N.Status),
         Format.Match_Result_Fields_Depth,
         False);
      Write_Line (Format.Close_Object (Format.Step_Fields_Depth, False));
   end Write_Step_Result;

   --  A step object, all but its closing brace, which waits for the
   --  next notice: it carries a comma when another step follows.
   procedure Write_Step_Body (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      Write_Line (Format.Open_Object (Format.Step_Object_Depth));
      Write_Step_Arguments
        (Doc_Ref.all,
         N.Step,
         Format.Header_Row_For (Doc_Ref.all, N.Scenario, N.Data_Row),
         N.Data_Row,
         Suppressed =>
           N.Status = Fabula.Results.Undefined
           and then N.Data_Row /= Fabula.Ast.No_Examples_Row);
      Write_Text_Field
        (Format.Keyword_Key,
         Format.Step_Keyword (Doc_Ref.all, N.Step),
         Format.Step_Fields_Depth,
         True);
      Write_Line (Line_Field (Info.Step_Line, Format.Step_Fields_Depth, True));
      Write_Match (N, Info);
      Write_Text_Field
        (Format.Name_Key,
         Fabula.Frames.Value (Info.Step),
         Format.Step_Fields_Depth,
         True);
      Write_Step_Result (N);
   end Write_Step_Body;

   procedure Close_Step (More : Boolean) is
   begin
      Write_Line (Format.Close_Object (Format.Step_Object_Depth, More));
   end Close_Step;

   ---------------------------------------------------------------------
   --  A scenario element.
   ---------------------------------------------------------------------

   --  description, id, keyword, line, name, then the open "steps" array:
   --  every field but tags and type, which Write_Element_Tail writes.
   procedure Write_Element_Head (N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
      Ref         : constant Fabula.Expand.Example_Ref :=
        Fabula.Expand.Locate_Row (Doc_Ref.all, N.Scenario, N.Data_Row);
      Description : constant Format.Joined_Text :=
        Format.Description_Content
          (Doc_Ref.all,
           Fabula.Ast.Scenario (Doc_Ref.all, N.Scenario).Head.Description);
   begin
      Write_Line (Format.Open_Object (Format.Scenario_Object_Depth));
      Write_Text_Field
        (Format.Description_Key,
         Format.Value (Description),
         Format.Scenario_Fields_Depth,
         True);
      Write_Text_Field
        (Format.Id_Key,
         Scenario_Id_Text (N, Info, Ref),
         Format.Scenario_Fields_Depth,
         True);
      Write_Text_Field
        (Format.Keyword_Key,
         Format.Scenario_Keyword (Doc_Ref.all, N.Scenario),
         Format.Scenario_Fields_Depth,
         True);
      Write_Line
        (Line_Field (Info.Scenario_Line, Format.Scenario_Fields_Depth, True));
      Write_Text_Field
        (Format.Name_Key,
         Fabula.Frames.Value (Info.Scenario),
         Format.Scenario_Fields_Depth,
         True);
      Write_Line
        (Format.Open_Array (Format.Steps_Key, Format.Scenario_Fields_Depth));
   end Write_Element_Head;

   --  The "steps" array's close, then tags and type, then the element's
   --  own close.  The reference interpreter writes the scenario's name
   --  as its "type".
   procedure Write_Element_Tail (N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
   begin
      Write_Line (Format.Close_Array (Format.Scenario_Fields_Depth, True));
      Write_Scenario_Tags
        (Fabula.Expand.Effective_Tags
           (Doc_Ref.all,
            N.Scenario,
            Fabula.Expand.Block_Of
              (Fabula.Expand.Locate_Row
                 (Doc_Ref.all, N.Scenario, N.Data_Row))));
      Write_Text_Field
        (Format.Type_Key,
         Fabula.Frames.Value (Info.Scenario),
         Format.Scenario_Fields_Depth,
         False);
      Write_Line (Format.Close_Object (Format.Scenario_Object_Depth, False));
   end Write_Element_Tail;

   ---------------------------------------------------------------------
   --  A feature and the whole report.
   ---------------------------------------------------------------------

   procedure Write_Feature_Head is
      Description : constant Format.Joined_Text :=
        Format.Description_Content
          (Doc_Ref.all, Fabula.Ast.Feature (Doc_Ref.all).Head.Description);
   begin
      Write_Line (Format.Open_Object (Format.Feature_Object_Depth));
      Write_Text_Field
        (Format.Description_Key,
         Format.Value (Description),
         Format.Feature_Fields_Depth,
         True);
      Write_Line
        (Format.Open_Array (Format.Elements_Key, Format.Feature_Fields_Depth));
   end Write_Feature_Head;

   procedure Write_Feature_Tail (Path : String) is
      Head : constant Fabula.Ast.Header :=
        Fabula.Ast.Feature (Doc_Ref.all).Head;
   begin
      Write_Line (Format.Close_Array (Format.Feature_Fields_Depth, True));
      Write_Text_Field
        (Format.Id_Key,
         Fabula.Ast.Text (Doc_Ref.all, Head.Name),
         Format.Feature_Fields_Depth,
         True);
      Write_Text_Field
        (Format.Keyword_Key,
         Fabula.Ast.Text (Doc_Ref.all, Head.Keyword),
         Format.Feature_Fields_Depth,
         True);
      Write_Line (Line_Field (Head.Line, Format.Feature_Fields_Depth, True));
      Write_Text_Field
        (Format.Name_Key,
         Fabula.Ast.Text (Doc_Ref.all, Head.Name),
         Format.Feature_Fields_Depth,
         True);
      Write_Feature_Tags;
      Write_Text_Field
        (Format.Uri_Key, Path, Format.Feature_Fields_Depth, False);
      Write_Line (Format.Close_Object (Format.Feature_Object_Depth, False));
   end Write_Feature_Tail;

   --  Last writes Closing, then the trailing newline a Json_Stdout
   --  target gets, and closes the report.
   procedure Finish_Report
     (Closing : String; Target : Fabula.Cli.Report_Target)
   is
      Status : Fabula.Shell.Reports.Status;
   begin
      Write_Report (Closing);
      if Target = Fabula.Cli.Json_Stdout then
         Write_Report (Line_End);
      end if;
      Fabula.Shell.Reports.Close (Report, Status);
   end Finish_Report;

   ---------------------------------------------------------------------
   --  The writer machine.  Its state is where the report stands, so it
   --  knows each comma and each bracket before it writes: whether a
   --  feature or an element is the first of its array, and whether a
   --  step's closing brace, which waits one notice, takes a comma.
   ---------------------------------------------------------------------

   type Writer_State is
     (No_Report,      --  nothing written yet
      Feature_Empty,  --  a feature's "elements" array open, empty
      In_Element,     --  a scenario element open, no step yet
      Step_Open,      --  a step written but for its closing brace
      After_Element,  --  an element closed, the array still open
      After_Feature,  --  a feature closed, the report still open
      Report_Closed);

   --  Each notice the report writes from, and the feature and report
   --  bounds the program marks.
   type Event_Kind is
     (E_Feature_Begun,
      E_Element_Entered,
      E_Step_Done,
      E_Element_Closed,
      E_Feature_Ended,
      E_Report_Closing);

   --  The notice and its frame for the element and step events, the
   --  path for E_Feature_Ended, the target for E_Report_Closing.
   type Event is record
      Kind   : Event_Kind := E_Report_Closing;
      Notice : Runner.Notice;
      Info   : Fabula.Frames.Frame;
      Path   : Fabula.Frames.Path_Text;
      Target : Fabula.Cli.Report_Target := Fabula.Cli.Json_Stdout;
   end record;

   type Guard_Kind is (Always);

   type Command is
     (Nothing,
      First_Feature,    --  "[", then the feature's head
      Next_Feature,     --  ",", then the feature's head
      First_Element,    --  the element's head
      Next_Element,     --  ",", then the element's head
      First_Step,       --  the step, its brace left open
      Next_Step,        --  "}," for the step before, then the step
      Close_Element,    --  the element's tail
      Close_Last_Step,  --  "}" for the last step, then the element's tail
      Close_Feature,    --  the feature's tail
      Close_Empty,      --  "[]", a report with no feature
      Close_Report);    --  "]"

   --  The machine's context: the command the last transition asked for.
   type Writer is record
      Pending : Command := Nothing;
   end record;

   function Kind_Of (Evt : Event) return Event_Kind
   is (Evt.Kind);

   --  Every row's guard is Always.
   function Evaluate (G : Guard_Kind; W : Writer; Evt : Event) return Boolean;

   --  Records A as the pending command; the machine does nothing else.
   procedure Execute (A : Command; W : in out Writer; Evt : Event);

   package SM is new
     Sml.Machines
       (State       => Writer_State,
        Event_Kind  => Event_Kind,
        Event       => Event,
        Context     => Writer,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Command,
        Kind_Of     => Kind_Of,
        Evaluate    => Evaluate,
        Execute     => Execute);

   package Row_Ops is new SM.Operators (Always => Always, Nothing => Nothing);
   use type Row_Ops.Ev, Row_Ops.Ev_Built, Row_Ops.Source;

   subtype Ev is Row_Ops.Ev;

   Feature_Begun   : constant Ev := (Kind => E_Feature_Begun);
   Element_Entered : constant Ev := (Kind => E_Element_Entered);
   Step_Done       : constant Ev := (Kind => E_Step_Done);
   Element_Closed  : constant Ev := (Kind => E_Element_Closed);
   Feature_Ended   : constant Ev := (Kind => E_Feature_Ended);
   Report_Closing  : constant Ev := (Kind => E_Report_Closing);

   Rows : constant := 14;

   --  Each row reads:  From + Event / Command >= To.  Every event the
   --  program sends in a state has a row there; an event with none is a
   --  defect in the writer, and Fire asserts it.  A scenario dropped
   --  before entry closes with no element open, so its two rows write
   --  nothing.
   --!format off
   Table : constant SM.Transition_Table (1 .. Rows) :=
     [
      --  A feature opens: the report's first, or one after another.
      No_Report     + Feature_Begun   / First_Feature   >= Feature_Empty,
      After_Feature + Feature_Begun   / Next_Feature    >= Feature_Empty,

      --  A scenario element opens: the feature's first, or a later one.
      Feature_Empty + Element_Entered / First_Element   >= In_Element,
      After_Element + Element_Entered / Next_Element    >= In_Element,

      --  A step: the element's first, or one after another.
      In_Element    + Step_Done       / First_Step      >= Step_Open,
      Step_Open     + Step_Done       / Next_Step       >= Step_Open,

      --  The element closes, with no step or after its last.
      In_Element    + Element_Closed  / Close_Element   >= After_Element,
      Step_Open     + Element_Closed  / Close_Last_Step >= After_Element,
      Feature_Empty + Element_Closed  / Nothing         >= Feature_Empty,
      After_Element + Element_Closed  / Nothing         >= After_Element,

      --  The feature closes, with or without an element.
      Feature_Empty + Feature_Ended   / Close_Feature   >= After_Feature,
      After_Element + Feature_Ended   / Close_Feature   >= After_Feature,

      --  The report closes, with or without a feature.
      No_Report     + Report_Closing  / Close_Empty     >= Report_Closed,
      After_Feature + Report_Closing  / Close_Report    >= Report_Closed];
   --!format on

   Machine : SM.Machine := SM.Make (Table, Initial => No_Report);
   State   : Writer;

   function Evaluate (G : Guard_Kind; W : Writer; Evt : Event) return Boolean
   is
      pragma Unreferenced (G, W, Evt);
   begin
      return True;
   end Evaluate;

   procedure Execute (A : Command; W : in out Writer; Evt : Event) is
      pragma Unreferenced (Evt);
   begin
      W.Pending := A;
   end Execute;

   --  Performs the command the transition just requested.
   procedure Perform (Cmd : Command; Evt : Event) is
   begin
      case Cmd is
         when Nothing         =>
            null;

         when First_Feature   =>
            Write_Line (Format.Report_Open);
            Write_Feature_Head;

         when Next_Feature    =>
            Write_Line (Format.Element_Separator);
            Write_Feature_Head;

         when First_Element   =>
            Write_Element_Head (Evt.Notice, Evt.Info);

         when Next_Element    =>
            Write_Line (Format.Element_Separator);
            Write_Element_Head (Evt.Notice, Evt.Info);

         when First_Step      =>
            Write_Step_Body (Evt.Notice, Evt.Info);

         when Next_Step       =>
            Close_Step (More => True);
            Write_Step_Body (Evt.Notice, Evt.Info);

         when Close_Element   =>
            Write_Element_Tail (Evt.Notice, Evt.Info);

         when Close_Last_Step =>
            Close_Step (More => False);
            Write_Element_Tail (Evt.Notice, Evt.Info);

         when Close_Feature   =>
            Write_Feature_Tail (Fabula.Frames.Value (Evt.Path));

         when Close_Empty     =>
            Finish_Report (Format.Empty_Report, Evt.Target);

         when Close_Report    =>
            Finish_Report (Format.Report_Close, Evt.Target);
      end case;
   end Perform;

   No_Row_Message : constant String :=
     "the JSON report has no row for this event in this state: ";

   --  One event through the machine, then its command.  An event with
   --  no row leaves Nothing pending, so even with assertions off it
   --  writes nothing.
   procedure Fire (Evt : Event) is
      Handled : Boolean;
   begin
      State.Pending := Nothing;
      SM.Process_Event (Machine, State, Evt, Handled);
      pragma Assert (Handled, No_Row_Message & Evt.Kind'Image);
      Perform (State.Pending, Evt);
   end Fire;

   ---------------------------------------------------------------------
   --  The program's calls, each one event.
   ---------------------------------------------------------------------

   procedure Begin_Feature is
   begin
      Fire ((Kind => E_Feature_Begun, others => <>));
   end Begin_Feature;

   procedure End_Feature (Path : String) is
   begin
      Fire
        ((Kind   => E_Feature_Ended,
          Path   => Fabula.Frames.To_Path (Path),
          others => <>));
   end End_Feature;

   procedure Fire_Notice
     (Kind : Event_Kind; N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      Fire ((Kind => Kind, Notice => N, Info => Info, others => <>));
   end Fire_Notice;

   --  Scenario_Opened writes nothing: a scenario may still be dropped
   --  before it enters.
   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      case N.Kind is
         when Runner.Scenario_Opened  =>
            null;

         when Runner.Scenario_Entered =>
            Fire_Notice (E_Element_Entered, N, Info);

         when Runner.Step_Closed      =>
            Fire_Notice (E_Step_Done, N, Info);

         when Runner.Scenario_Closed  =>
            Fire_Notice (E_Element_Closed, N, Info);
      end case;
   end On_Notice;

   procedure Close (Target : Fabula.Cli.Report_Target) is
   begin
      Fire ((Kind => E_Report_Closing, Target => Target, others => <>));
   end Close;

end Fabula.Shell.Program_Json;
