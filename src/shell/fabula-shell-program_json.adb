with Fabula.Ast;
with Fabula.Expand;
with Fabula.Format;
with Fabula.Results;
with Fabula.Scan;

package body Fabula.Shell.Program_Json
  with SPARK_Mode => Off
is

   use type Fabula.Ast.Cell_Handle;
   use type Fabula.Ast.Doc_Handle;
   use type Fabula.Ast.Examples_Handle;
   use type Fabula.Ast.Examples_Row_Handle;
   use type Fabula.Ast.Row_Handle;
   use type Fabula.Ast.Rule_Handle;
   use type Fabula.Ast.Table_Handle;
   use type Fabula.Ast.Tag_Handle;
   use type Fabula.Results.Status;
   use type Runner.Step_Cause;

   Doc_Ref : Fabula.Args.Document_Access;
   Report  : Fabula.Shell.Reports.Report;

   Any_Feature_Written       : Boolean := False;
   First_Scenario_In_Feature : Boolean := True;
   --  Scenario_Closed carries no word of whether this scenario was ever
   --  entered -- a -t-filtered drop and an after-hook Ignore look
   --  identical on the notice.  Set True only by
   --  On_Scenario_Entered, so On_Scenario_Closed can tell them apart.
   Scenario_Is_Entered       : Boolean := False;
   --  A step's own closing brace is deferred one notice, so it can carry
   --  the right trailing comma (another step follows) or none (nothing
   --  does) without ever guessing ahead -- the same close-out fires
   --  whether the scenario ends normally or is dropped mid-steps.
   Step_Close_Pending        : Boolean := False;

   procedure Set_Document (Doc : Fabula.Args.Document_Access) is
   begin
      Doc_Ref := Doc;
   end Set_Document;

   procedure Open_Target
     (File     : String;
      Has_File : Boolean;
      Status   : out Fabula.Shell.Reports.Status) is
   begin
      --  --report-json= (fabula's own merged form) can set Has_File with
      --  an empty value; the reference interpreter's own classification
      --  treats no value at all as stdout, so an empty one falls back
      --  the same way rather than opening an empty path and failing.
      if Has_File and then File'Length > 0 then
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

   procedure Write_Report (Chunk : String) is
      Status : Fabula.Shell.Reports.Status;
   begin
      Fabula.Shell.Reports.Write (Report, Chunk, Status);
   end Write_Report;

   procedure Write_Line (Chunk : String) is
   begin
      Write_Report (Chunk);
      Write_Report ([1 => ASCII.LF]);
   end Write_Line;

   function Status_Word (S : Fabula.Results.Status) return String
   is (case S is
         when Fabula.Results.Passed    => "passed",
         when Fabula.Results.Failed    => "failed",
         when Fabula.Results.Skipped   => "skipped",
         when Fabula.Results.Undefined => "undefined");

   ---------------------------------------------------------------------
   --  The Examples block and header row an outline row belongs to, and
   --  its 1-based occurrence within that block.  Both 0 for a plain
   --  scenario or a stale row -- never read past a pool.
   ---------------------------------------------------------------------

   procedure Locate_Row
     (Doc        : Fabula.Ast.Document;
      S          : Fabula.Ast.Scenario_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle;
      Header_Row : out Fabula.Ast.Examples_Row_Handle;
      Block      : out Fabula.Ast.Examples_Handle)
   is
      Scn : Fabula.Ast.Scenario_Node;
   begin
      Header_Row := 0;
      Block := 0;
      if Data_Row = 0 or else S not in 1 .. Fabula.Ast.Scenario_Count (Doc)
      then
         return;
      end if;
      Scn := Fabula.Ast.Scenario (Doc, S);
      for E in Scn.Examples.First .. Scn.Examples.Last loop
         exit when E not in 1 .. Fabula.Ast.Examples_Count (Doc);
         if Data_Row
            in Fabula.Ast.Examples (Doc, E).Rows.First
             .. Fabula.Ast.Examples (Doc, E).Rows.Last
         then
            Header_Row := Fabula.Ast.Examples (Doc, E).Header_Row;
            Block := E;
            return;
         end if;
      end loop;
   end Locate_Row;

   function Header_Row_For
     (Doc      : Fabula.Ast.Document;
      S        : Fabula.Ast.Scenario_Handle;
      Data_Row : Fabula.Ast.Examples_Row_Handle)
      return Fabula.Ast.Examples_Row_Handle
   is
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Block      : Fabula.Ast.Examples_Handle;
   begin
      Locate_Row (Doc, S, Data_Row, Header_Row, Block);
      return Header_Row;
   end Header_Row_For;

   --  An outline row's 1-based position within its OWN Examples block;
   --  0 for a plain scenario.  Uses the row's own position
   --  (Data_Row - Rows.First + 1) rather than a
   --  running count of scenarios actually seen -- a `:line` selection or
   --  a `-n` filter can run rows out of order or skip some outright, and
   --  a running count would number them by arrival, not by row.
   function Occurrence_For
     (Doc      : Fabula.Ast.Document;
      Block    : Fabula.Ast.Examples_Handle;
      Data_Row : Fabula.Ast.Examples_Row_Handle) return Natural is
   begin
      if Block = 0 or else Block not in 1 .. Fabula.Ast.Examples_Count (Doc)
      then
         return 0;
      end if;
      return
        Natural (Data_Row - Fabula.Ast.Examples (Doc, Block).Rows.First) + 1;
   end Occurrence_For;

   function Scenario_Keyword_Text
     (Doc : Fabula.Ast.Document; S : Fabula.Ast.Scenario_Handle) return String
   is
   begin
      if S not in 1 .. Fabula.Ast.Scenario_Count (Doc) then
         return "";
      end if;
      return Fabula.Ast.Text (Doc, Fabula.Ast.Scenario (Doc, S).Head.Keyword);
   end Scenario_Keyword_Text;

   function Step_Keyword_Text
     (Doc : Fabula.Ast.Document; Step : Fabula.Ast.Step_Handle) return String
   is
   begin
      if Step not in 1 .. Fabula.Ast.Step_Count (Doc) then
         return "";
      end if;
      return Fabula.Scan.Spelling (Fabula.Ast.Step (Doc, Step).Keyword);
   end Step_Keyword_Text;

   function Rule_Name_Of (S : Fabula.Ast.Scenario_Handle) return String is
      Rule : constant Fabula.Ast.Rule_Handle :=
        Fabula.Ast.Scenario (Doc_Ref.all, S).Rule;
   begin
      if Rule = 0 or else Rule > Fabula.Ast.Rule_Count (Doc_Ref.all) then
         return "";
      end if;
      return
        Fabula.Ast.Text
          (Doc_Ref.all, Fabula.Ast.Rule (Doc_Ref.all, Rule).Head.Name);
   end Rule_Name_Of;

   function Scenario_Id_Text
     (N     : Runner.Notice;
      Info  : Fabula.Frames.Frame;
      Block : Fabula.Ast.Examples_Handle) return String is
   begin
      return
        Fabula.Format.Escape_Json
          (Fabula.Format.Scenario_Id
             (Fabula.Ast.Text
                (Doc_Ref.all, Fabula.Ast.Feature (Doc_Ref.all).Head.Name),
              Rule_Name_Of (N.Scenario),
              Fabula.Frames.Value (Info.Scenario),
              Occurrence_For (Doc_Ref.all, Block, N.Data_Row)));
   end Scenario_Id_Text;

   ---------------------------------------------------------------------
   --  Tags.
   ---------------------------------------------------------------------

   procedure Write_Tags_From_Set
     (Set   : Fabula.Expand.Tag_Set;
      Depth : Fabula.Format.Depth_Value;
      More  : Boolean) is
   begin
      if Set.Count = 0 then
         Write_Line (Fabula.Format.Empty_Array_Field ("tags", Depth, More));
         return;
      end if;
      Write_Line (Fabula.Format.Open_Array ("tags", Depth));
      for I in 1 .. Set.Count loop
         Write_Line
           (Fabula.Format.String_Item
              (Fabula.Format.Escape_Json
                 (Fabula.Ast.Text
                    (Doc_Ref.all,
                     Fabula.Ast.Tag (Doc_Ref.all, Set.Items (I)))),
               Depth + 1,
               I /= Set.Count));
      end loop;
      Write_Line (Fabula.Format.Close_Array (Depth, More));
   end Write_Tags_From_Set;

   procedure Write_Tags_From_Range
     (Doc   : Fabula.Ast.Document;
      Tags  : Fabula.Ast.Tag_Range;
      Depth : Fabula.Format.Depth_Value;
      More  : Boolean) is
   begin
      if Tags.Last < Tags.First then
         Write_Line (Fabula.Format.Empty_Array_Field ("tags", Depth, More));
         return;
      end if;
      Write_Line (Fabula.Format.Open_Array ("tags", Depth));
      for I in Tags.First .. Tags.Last loop
         exit when I not in 1 .. Fabula.Ast.Tag_Count (Doc);
         Write_Line
           (Fabula.Format.String_Item
              (Fabula.Format.Escape_Json
                 (Fabula.Ast.Text (Doc, Fabula.Ast.Tag (Doc, I))),
               Depth + 1,
               I /= Tags.Last));
      end loop;
      Write_Line (Fabula.Format.Close_Array (Depth, More));
   end Write_Tags_From_Range;

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
      Write_Line (Fabula.Format.Open_Object (Fabula.Format.Row_Object_Depth));
      Write_Line
        (Fabula.Format.Open_Array ("cells", Fabula.Format.Row_Fields_Depth));
      for Cell in Cells.First .. Cells.Last loop
         exit when Cell not in 1 .. Fabula.Ast.Cell_Count (Doc);
         Write_Line
           (Fabula.Format.String_Item
              (Fabula.Format.Escape_Json
                 (Fabula.Ast.Text (Doc, Fabula.Ast.Cell (Doc, Cell))),
               Fabula.Format.Cell_Item_Depth,
               Cell /= Cells.Last));
      end loop;
      Write_Line
        (Fabula.Format.Close_Array (Fabula.Format.Row_Fields_Depth, False));
      Write_Line
        (Fabula.Format.Close_Object
           (Fabula.Format.Row_Object_Depth, not Last_Row));
   end Write_Cells_Of_Row;

   procedure Write_Table_Argument
     (Doc : Fabula.Ast.Document; T : Fabula.Ast.Table_Handle)
   is
      Rows : constant Fabula.Ast.Row_Range := Fabula.Ast.Table (Doc, T).Rows;
   begin
      Write_Line
        (Fabula.Format.Open_Object (Fabula.Format.Argument_Object_Depth));
      if Rows.Last < Rows.First then
         Write_Line
           (Fabula.Format.Empty_Array_Field
              ("rows", Fabula.Format.Argument_Fields_Depth, False));
      else
         Write_Line
           (Fabula.Format.Open_Array
              ("rows", Fabula.Format.Argument_Fields_Depth));
         for Row in Rows.First .. Rows.Last loop
            exit when Row not in 1 .. Fabula.Ast.Table_Row_Count (Doc);
            Write_Cells_Of_Row (Doc, Row, Row = Rows.Last);
         end loop;
         Write_Line
           (Fabula.Format.Close_Array
              (Fabula.Format.Argument_Fields_Depth, False));
      end if;
      Write_Line
        (Fabula.Format.Close_Object
           (Fabula.Format.Argument_Object_Depth, False));
   end Write_Table_Argument;

   procedure Write_Doc_Argument
     (Doc        : Fabula.Ast.Document;
      D          : Fabula.Ast.Doc_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle)
   is
      Content : constant Fabula.Format.Joined_Text :=
        Fabula.Format.Doc_String_Content (Doc, D, Header_Row, Data_Row);
   begin
      Write_Line
        (Fabula.Format.Open_Object (Fabula.Format.Argument_Object_Depth));
      Write_Line
        (Fabula.Format.String_Field
           ("content",
            Fabula.Format.Escape_Json (Fabula.Format.Value (Content)),
            Fabula.Format.Argument_Fields_Depth,
            False));
      Write_Line
        (Fabula.Format.Close_Object
           (Fabula.Format.Argument_Object_Depth, False));
   end Write_Doc_Argument;

   --  The reference interpreter builds an unmatched outline row from its
   --  bare keyword/name/file/line alone, no table or doc string at all
   --  -- Suppressed forces the empty form regardless of what the AST
   --  step node holds.
   procedure Write_Step_Arguments
     (Doc        : Fabula.Ast.Document;
      Step       : Fabula.Ast.Step_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle;
      Suppressed : Boolean := False)
   is
      Node : constant Fabula.Ast.Step_Node := Fabula.Ast.Step (Doc, Step);
   begin
      if Suppressed then
         Write_Line
           (Fabula.Format.Empty_Array_Field
              ("arguments", Fabula.Format.Step_Fields_Depth, True));
         return;
      end if;
      if Node.Table /= 0 and then Node.Table <= Fabula.Ast.Table_Count (Doc)
      then
         Write_Line
           (Fabula.Format.Open_Array
              ("arguments", Fabula.Format.Step_Fields_Depth));
         Write_Table_Argument (Doc, Node.Table);
         Write_Line
           (Fabula.Format.Close_Array (Fabula.Format.Step_Fields_Depth, True));
      elsif Node.Doc /= 0
        and then Node.Doc <= Fabula.Ast.Doc_String_Count (Doc)
      then
         Write_Line
           (Fabula.Format.Open_Array
              ("arguments", Fabula.Format.Step_Fields_Depth));
         Write_Doc_Argument (Doc, Node.Doc, Header_Row, Data_Row);
         Write_Line
           (Fabula.Format.Close_Array (Fabula.Format.Step_Fields_Depth, True));
      else
         Write_Line
           (Fabula.Format.Empty_Array_Field
              ("arguments", Fabula.Format.Step_Fields_Depth, True));
      end if;
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
      if Found.Found then
         return Reg.Pattern_Text (Runner.Steps, Found.Index);
      end if;
      return "";
   end Match_Location_Text;

   procedure Write_Step_Result (N : Runner.Notice) is
   begin
      Write_Line
        (Fabula.Format.Open_Named_Object
           ("result", Fabula.Format.Step_Fields_Depth));
      if N.Status = Fabula.Results.Failed then
         Write_Line
           (Fabula.Format.String_Field
              ("error_message",
               Fabula.Format.Escape_Json
                 (N.Outcome.Msg (1 .. N.Outcome.Msg_Len)),
               Fabula.Format.Match_Result_Fields_Depth,
               True));
      elsif N.Status = Fabula.Results.Undefined then
         Write_Line
           (Fabula.Format.String_Field
              ("error_message",
               Fabula.Format.Escape_Json
                 (if N.Cause = Runner.Too_Long_Expansion
                  then Runner.Too_Long_Message
                  else "Undefined step"),
               Fabula.Format.Match_Result_Fields_Depth,
               True));
      end if;
      Write_Line
        (Fabula.Format.String_Field
           ("status",
            Status_Word (N.Status),
            Fabula.Format.Match_Result_Fields_Depth,
            False));
      Write_Line
        (Fabula.Format.Close_Object (Fabula.Format.Step_Fields_Depth, False));
   end Write_Step_Result;

   --  Closes the previously-opened step object, if one is pending, with
   --  the trailing comma now known: True when this step's own successor
   --  is about to open, False when nothing more will (scenario end or a
   --  Drop, normal or mid-steps).
   procedure Finish_Pending_Step (More : Boolean) is
   begin
      if Step_Close_Pending then
         Write_Line
           (Fabula.Format.Close_Object
              (Fabula.Format.Step_Object_Depth, More));
         Step_Close_Pending := False;
      end if;
   end Finish_Pending_Step;

   procedure On_Step_Closed (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      Finish_Pending_Step (More => True);
      Write_Line (Fabula.Format.Open_Object (Fabula.Format.Step_Object_Depth));
      Write_Step_Arguments
        (Doc_Ref.all,
         N.Step,
         Header_Row_For (Doc_Ref.all, N.Scenario, N.Data_Row),
         N.Data_Row,
         Suppressed =>
           N.Status = Fabula.Results.Undefined and then N.Data_Row /= 0);
      Write_Line
        (Fabula.Format.String_Field
           ("keyword",
            Fabula.Format.Escape_Json
              (Step_Keyword_Text (Doc_Ref.all, N.Step)),
            Fabula.Format.Step_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.Number_Field
           ("line", Info.Step_Line, Fabula.Format.Step_Fields_Depth, True));
      Write_Line
        (Fabula.Format.Open_Named_Object
           ("match", Fabula.Format.Step_Fields_Depth));
      Write_Line
        (Fabula.Format.String_Field
           ("location",
            Fabula.Format.Escape_Json (Match_Location_Text (N.Status, Info)),
            Fabula.Format.Match_Result_Fields_Depth,
            False));
      Write_Line
        (Fabula.Format.Close_Object (Fabula.Format.Step_Fields_Depth, True));
      Write_Line
        (Fabula.Format.String_Field
           ("name",
            Fabula.Format.Escape_Json (Fabula.Frames.Value (Info.Step)),
            Fabula.Format.Step_Fields_Depth,
            True));
      Write_Step_Result (N);
      Step_Close_Pending := True;
   end On_Step_Closed;

   ---------------------------------------------------------------------
   --  description, id, keyword, line, name, then the open "steps" array:
   --  every scenario field but tags and type, which close it out below.
   procedure Write_Scenario_Header
     (N     : Runner.Notice;
      Info  : Fabula.Frames.Frame;
      Block : Fabula.Ast.Examples_Handle)
   is
      Description : constant Fabula.Format.Joined_Text :=
        Fabula.Format.Description_Content
          (Doc_Ref.all,
           Fabula.Ast.Scenario (Doc_Ref.all, N.Scenario).Head.Description);
   begin
      Write_Line
        (Fabula.Format.String_Field
           ("description",
            Fabula.Format.Escape_Json (Fabula.Format.Value (Description)),
            Fabula.Format.Scenario_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.String_Field
           ("id",
            Scenario_Id_Text (N, Info, Block),
            Fabula.Format.Scenario_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.String_Field
           ("keyword",
            Fabula.Format.Escape_Json
              (Scenario_Keyword_Text (Doc_Ref.all, N.Scenario)),
            Fabula.Format.Scenario_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.Number_Field
           ("line",
            Info.Scenario_Line,
            Fabula.Format.Scenario_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.String_Field
           ("name",
            Fabula.Format.Escape_Json (Fabula.Frames.Value (Info.Scenario)),
            Fabula.Format.Scenario_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.Open_Array
           ("steps", Fabula.Format.Scenario_Fields_Depth));
   end Write_Scenario_Header;

   procedure On_Scenario_Entered
     (N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Block      : Fabula.Ast.Examples_Handle;
   begin
      Locate_Row (Doc_Ref.all, N.Scenario, N.Data_Row, Header_Row, Block);
      if First_Scenario_In_Feature then
         First_Scenario_In_Feature := False;
      else
         Write_Line (",");
      end if;
      Write_Line
        (Fabula.Format.Open_Object (Fabula.Format.Scenario_Object_Depth));
      Write_Scenario_Header (N, Info, Block);
      Step_Close_Pending := False;
      Scenario_Is_Entered := True;
   end On_Scenario_Entered;

   procedure On_Scenario_Closed (N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
      Header_Row  : Fabula.Ast.Examples_Row_Handle;
      Block       : Fabula.Ast.Examples_Handle;
      Was_Entered : constant Boolean := Scenario_Is_Entered;
   begin
      Scenario_Is_Entered := False;
      if N.Dropped and then not Was_Entered then
         return;   --  never entered; no JSON element was opened for it

      end if;
      --  An after-hook Ignore (or one mid-steps, via a Step_After hook)
      --  can drop a scenario whose element -- and some of its steps --
      --  already opened; Finish_Pending_Step closes whatever step is
      --  left hanging with no trailing comma, so the array and the
      --  element close out valid either way.
      Finish_Pending_Step (More => False);
      Write_Line
        (Fabula.Format.Close_Array
           (Fabula.Format.Scenario_Fields_Depth, True));
      Locate_Row (Doc_Ref.all, N.Scenario, N.Data_Row, Header_Row, Block);
      Write_Tags_From_Set
        (Fabula.Expand.Effective_Tags (Doc_Ref.all, N.Scenario, Block),
         Fabula.Format.Scenario_Fields_Depth,
         True);
      Write_Line
        (Fabula.Format.String_Field
           ("type",
            Fabula.Format.Escape_Json (Fabula.Frames.Value (Info.Scenario)),
            Fabula.Format.Scenario_Fields_Depth,
            False));
      Write_Line
        (Fabula.Format.Close_Object
           (Fabula.Format.Scenario_Object_Depth, False));
      pragma Unreferenced (Header_Row);
   end On_Scenario_Closed;

   ---------------------------------------------------------------------
   --  A feature and the whole report.
   ---------------------------------------------------------------------

   procedure Begin_Feature is
      Description : constant Fabula.Format.Joined_Text :=
        Fabula.Format.Description_Content
          (Doc_Ref.all, Fabula.Ast.Feature (Doc_Ref.all).Head.Description);
   begin
      if Any_Feature_Written then
         Write_Line (",");
      else
         Write_Line ("[");
         Any_Feature_Written := True;
      end if;
      First_Scenario_In_Feature := True;
      Write_Line (Fabula.Format.Open_Object (1));
      Write_Line
        (Fabula.Format.String_Field
           ("description",
            Fabula.Format.Escape_Json (Fabula.Format.Value (Description)),
            Fabula.Format.Feature_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.Open_Array
           ("elements", Fabula.Format.Feature_Fields_Depth));
   end Begin_Feature;

   procedure End_Feature (Path : String) is
      Head : constant Fabula.Ast.Header :=
        Fabula.Ast.Feature (Doc_Ref.all).Head;
   begin
      Write_Line
        (Fabula.Format.Close_Array (Fabula.Format.Feature_Fields_Depth, True));
      Write_Line
        (Fabula.Format.String_Field
           ("id",
            Fabula.Format.Escape_Json
              (Fabula.Ast.Text (Doc_Ref.all, Head.Name)),
            Fabula.Format.Feature_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.String_Field
           ("keyword",
            Fabula.Format.Escape_Json
              (Fabula.Ast.Text (Doc_Ref.all, Head.Keyword)),
            Fabula.Format.Feature_Fields_Depth,
            True));
      Write_Line
        (Fabula.Format.Number_Field
           ("line", Head.Line, Fabula.Format.Feature_Fields_Depth, True));
      Write_Line
        (Fabula.Format.String_Field
           ("name",
            Fabula.Format.Escape_Json
              (Fabula.Ast.Text (Doc_Ref.all, Head.Name)),
            Fabula.Format.Feature_Fields_Depth,
            True));
      Write_Tags_From_Range
        (Doc_Ref.all,
         Fabula.Ast.Feature (Doc_Ref.all).Tags,
         Fabula.Format.Feature_Fields_Depth,
         True);
      Write_Line
        (Fabula.Format.String_Field
           ("uri",
            Fabula.Format.Escape_Json (Path),
            Fabula.Format.Feature_Fields_Depth,
            False));
      Write_Line (Fabula.Format.Close_Object (1, False));
   end End_Feature;

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame) is
      use type Runner.Notice_Kind;
   begin
      case N.Kind is
         when Runner.Scenario_Opened  =>
            null;

         when Runner.Scenario_Entered =>
            On_Scenario_Entered (N, Info);

         when Runner.Step_Closed      =>
            On_Step_Closed (N, Info);

         when Runner.Scenario_Closed  =>
            On_Scenario_Closed (N, Info);
      end case;
   end On_Notice;

   procedure Close (Has_File : Boolean) is
      Status : Fabula.Shell.Reports.Status;
   begin
      if Any_Feature_Written then
         Write_Report ("]");
      else
         Write_Report ("[]");
      end if;
      if not Has_File then
         Write_Report ([1 => ASCII.LF]);
      end if;
      Fabula.Shell.Reports.Close (Report, Status);
   end Close;

end Fabula.Shell.Program_Json;
