with Ada.Strings.Unbounded;

with Fabula.Ast;
with Fabula.Check;
with Fabula.Expand;
with Fabula.Format;
with Fabula.Shell.Console;

package body Fabula.Shell.Program_Console
  with SPARK_Mode => Off
is

   use type Fabula.Ast.Examples_Row_Handle;
   use type Fabula.Check.Control;
   use type Fabula.Cli.Log_Level;
   use type Fabula.Results.Status;

   package Console renames Fabula.Shell.Console;
   package Format renames Fabula.Format;

   Doc_Ref         : Fabula.Args.Document_Access;
   Log             : Fabula.Cli.Log_Level := Fabula.Cli.Normal;
   Filter_Active   : Boolean := False;
   Dry_Run_Active  : Boolean := False;
   Compiled_Filter : Fabula.Tags.Compiled;
   Tag_Expr_Text   : Ada.Strings.Unbounded.Unbounded_String;
   Failed          : Format.Failed_Store := Format.Empty_Failed_Store;

   Current_Tag_Set : Fabula.Expand.Tag_Set;

   function Filter_Has_Tag (Name : String) return Boolean
   is (Fabula.Expand.Contains (Doc_Ref.all, Current_Tag_Set, Name));

   function Filter_Eval is new Fabula.Tags.Eval (Has_Tag => Filter_Has_Tag);

   procedure Set_Document (Doc : Fabula.Args.Document_Access) is
   begin
      Doc_Ref := Doc;
   end Set_Document;

   procedure Set_Log_Level (Level : Fabula.Cli.Log_Level) is
   begin
      Log := Level;
   end Set_Log_Level;

   procedure Set_Dry_Run (Dry_Run : Boolean) is
   begin
      Dry_Run_Active := Dry_Run;
   end Set_Dry_Run;

   function Verbose_Active return Boolean
   is (Log = Fabula.Cli.Verbose);

   --  -q hides the headers, the step lines and the blank; -v, which
   --  wins over -q, never does.
   function Suppressed return Boolean
   is (Log = Fabula.Cli.Quiet);

   procedure Set_Filter
     (Has_Filter : Boolean; Filter : Fabula.Tags.Compiled; Tag_Expr : String)
   is
   begin
      Filter_Active := Has_Filter;
      Compiled_Filter := Filter;
      Tag_Expr_Text := Ada.Strings.Unbounded.To_Unbounded_String (Tag_Expr);
   end Set_Filter;

   function Role_Style (Role : Format.Role) return Console.Style
   is (case Role is
         when Format.Plain     => Console.Plain,
         when Format.Passed    => Console.Passed,
         when Format.Failed    => Console.Failed,
         when Format.Skipped   => Console.Skipped,
         when Format.Undefined => Console.Undefined,
         when Format.Location  => Console.Location,
         when Format.Error     => Console.Error);

   ---------------------------------------------------------------------
   --  A step's table and doc string.
   ---------------------------------------------------------------------

   procedure Render_Table
     (Doc        : Fabula.Ast.Document;
      T          : Fabula.Ast.Table_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle) is
   begin
      if T not in 1 .. Fabula.Ast.Table_Count (Doc) then
         return;
      end if;
      declare
         Widths : constant Format.Column_Widths :=
           Format.Table_Widths (Doc, T, Header_Row, Data_Row);
         Rows   : constant Fabula.Ast.Row_Range :=
           Fabula.Ast.Table (Doc, T).Rows;
      begin
         for Row in Rows.First .. Rows.Last loop
            exit when Row not in 1 .. Fabula.Ast.Table_Row_Count (Doc);
            Console.Put_Line
              (Format.Table_Row_Text (Doc, Row, Header_Row, Data_Row, Widths));
         end loop;
      end;
   end Render_Table;

   --  Nothing prints for a doc string with no content lines, not even
   --  its fences.
   procedure Render_Doc_String
     (Doc        : Fabula.Ast.Document;
      D          : Fabula.Ast.Doc_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle) is
   begin
      if D not in 1 .. Fabula.Ast.Doc_String_Count (Doc)
        or else Fabula.Ast.Doc_Line_Pool.Is_Empty
                  (Fabula.Ast.Doc_String (Doc, D).Lines)
      then
         return;
      end if;
      declare
         Lines : constant Fabula.Ast.Doc_Line_Range :=
           Fabula.Ast.Doc_String (Doc, D).Lines;
      begin
         Console.Put_Line (Format.Doc_Fence_Text);
         for L in Lines.First .. Lines.Last loop
            exit when L not in 1 .. Fabula.Ast.Doc_Line_Count (Doc);
            Console.Put_Line
              (Format.Doc_Content_Text (Doc, L, Header_Row, Data_Row));
         end loop;
         Console.Put_Line (Format.Doc_Fence_Text);
      end;
   end Render_Doc_String;

   procedure Render_Step_Arguments
     (Doc        : Fabula.Ast.Document;
      Step       : Fabula.Ast.Step_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle) is
   begin
      if Step not in 1 .. Fabula.Ast.Step_Count (Doc) then
         return;
      end if;
      Render_Table
        (Doc, Fabula.Ast.Step (Doc, Step).Table, Header_Row, Data_Row);
      Render_Doc_String
        (Doc, Fabula.Ast.Step (Doc, Step).Doc, Header_Row, Data_Row);
   end Render_Step_Arguments;

   ---------------------------------------------------------------------
   --  One notice at a time (docs/report_wiring.md items 1-8).
   ---------------------------------------------------------------------

   procedure Print_Failure_Message (Outcome : Fabula.Check.Outcome) is
   begin
      Console.Put_Line (Fabula.Check.Failure_Text (Outcome), Console.Error);
   end Print_Failure_Message;

   procedure On_Scenario_Opened (Info : Fabula.Frames.Frame) is
   begin
      if not Verbose_Active then
         return;
      end if;
      Console.Put_Line (Format.Verbose_Separator, Console.Verbose);
      Console.Put_Line
        (Format.Verbose_Scenario_Start
           (Fabula.Frames.Value (Info.Scenario),
            Fabula.Frames.Value (Info.File),
            Info.Scenario_Line),
         Console.Verbose);
   end On_Scenario_Opened;

   --  What the verbose tag check separates two tags with.
   Tag_Separator : constant String := " ";

   function Tags_Text (Set : Fabula.Expand.Tag_Set) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for I in 1 .. Set.Count loop
         Ada.Strings.Unbounded.Append
           (Result,
            (if I = Set.Items'First then "" else Tag_Separator)
            & Fabula.Ast.Text
                (Doc_Ref.all, Fabula.Ast.Tag (Doc_Ref.all, Set.Items (I))));
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Tags_Text;

   --  The verbose tag-check line, or its no-filter analogue.  Reaches
   --  Fabula.Expand/Fabula.Tags directly: the runner's own effective
   --  tag set is private, but both are public library units.
   procedure Print_Tag_Check
     (S        : Fabula.Ast.Scenario_Handle;
      Data_Row : Fabula.Ast.Examples_Row_Handle) is
   begin
      if not Filter_Active then
         Console.Put_Line (Format.No_Tags_Given, Console.Verbose);
         return;
      end if;
      Current_Tag_Set :=
        Fabula.Expand.Effective_Tags
          (Doc_Ref.all,
           S,
           Fabula.Expand.Block_Of
             (Fabula.Expand.Locate_Row (Doc_Ref.all, S, Data_Row)));
      Console.Put_Line
        (Format.Verbose_Tag_Check
           (Tags_Text (Current_Tag_Set),
            Ada.Strings.Unbounded.To_String (Tag_Expr_Text),
            Filter_Eval (Compiled_Filter)),
         Console.Verbose);
   end Print_Tag_Check;

   --  -v's lines as a scenario enters: its tag check, and the skip line
   --  for -d, the one Skip trigger the shell can see ahead of the
   --  scenario's own header line (Set_Dry_Run's own comment covers the
   --  hook-triggered gap).
   procedure Print_Verbose_Entry (N : Runner.Notice) is
   begin
      Print_Tag_Check (N.Scenario, N.Data_Row);
      if Dry_Run_Active then
         Console.Put_Line (Format.Verbose_Skip, Console.Verbose);
      end if;
   end Print_Verbose_Entry;

   procedure Print_Scenario_Header
     (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      if Suppressed then
         return;
      end if;
      Console.Put
        (Format.Header_Text
           (Format.Scenario_Keyword (Doc_Ref.all, N.Scenario),
            Fabula.Frames.Value (Info.Scenario)));
      Console.Put_Line
        (Format.Location_Text
           (Fabula.Frames.Value (Info.File), Info.Scenario_Line),
         Console.Location);
   end Print_Scenario_Header;

   procedure On_Scenario_Entered
     (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      if Verbose_Active then
         Print_Verbose_Entry (N);
      end if;
      Print_Scenario_Header (N, Info);
   end On_Scenario_Entered;

   procedure Print_Step_Line
     (Doc : Fabula.Ast.Document; N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
   begin
      Console.Put
        (Format.Bracket_Label (N.Status),
         Role_Style (Format.Style_Of (N.Status)));
      Console.Put
        (Format.Step_Text
           (Format.Step_Keyword (Doc, N.Step),
            Fabula.Frames.Value (Info.Step)));
      Console.Put_Line
        (Format.Location_Text
           (Fabula.Frames.Value (Info.File), Info.Step_Line),
         Console.Location);
      --  The reference interpreter builds an unmatched outline row from
      --  its bare keyword/name/file/line alone, no table or doc string
      --  -- undefined never prints an argument on an outline row.
      if N.Status /= Fabula.Results.Undefined
        or else N.Data_Row = Fabula.Ast.No_Examples_Row
      then
         Render_Step_Arguments
           (Doc,
            N.Step,
            Format.Header_Row_For (Doc, N.Scenario, N.Data_Row),
            N.Data_Row);
      end if;
   end Print_Step_Line;

   --  A failed step's own message, printed above its step line; a
   --  scenario's failure prints once the scenario closes.
   procedure Print_Step_Failure (Outcome : Fabula.Check.Outcome) is
   begin
      if not Outcome.Passing
        and then Outcome.Order /= Fabula.Check.Fail_Scenario
        and then Fabula.Check.Failure_Text (Outcome)'Length > 0
      then
         Print_Failure_Message (Outcome);
      end if;
   end Print_Step_Failure;

   procedure On_Step_Closed (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      if Suppressed then
         return;
      end if;
      Print_Step_Failure (N.Outcome);
      Print_Step_Line (Doc_Ref.all, N, Info);
   end On_Step_Closed;

   --  "[VERBOSE] Scenario end" + separator + ONE blank: the reference
   --  interpreter's own end-of-scenario print, embedded in every verbose
   --  completion, kept, dropped after entry, or dropped before it --
   --  its own separator print double-newlines.
   procedure Print_Verbose_End_Block is
   begin
      Console.Put_Line (Format.Verbose_End, Console.Verbose);
      Console.Put_Line (Format.Verbose_Separator, Console.Verbose);
      Console.New_Line;
   end Print_Verbose_End_Block;

   --  The verbose end block, in the oracle's own order ("Scenario end",
   --  separator, blank -- THEN the pre-existing blank, never before
   --  it), plus that trailing blank -- shared by a normal close and a
   --  post-entry Dropped close, since both leave the same thing open:
   --  the header (and, in -v, the tag check) already printed.  -q
   --  prints neither.
   procedure Print_Scenario_End is
   begin
      case Log is
         when Fabula.Cli.Verbose =>
            Print_Verbose_End_Block;
            Console.New_Line;

         when Fabula.Cli.Normal  =>
            Console.New_Line;

         when Fabula.Cli.Quiet   =>
            null;
      end case;
   end Print_Scenario_End;

   --  A scenario dropped before entry (a -t filter or a before-hook
   --  Ignore) still gets its own verbose tag-check, "ignored" line and
   --  end block in the oracle -- printed here from the same
   --  Print_Tag_Check the kept path uses.  A before-hook's explicit
   --  Ignore short-circuits the oracle's own tag check when no -t is
   --  given; the notice does not say which drop it was, so fabula
   --  always prints the check -- a known, disclosed gap, not a
   --  byte-for-byte match there.
   procedure Print_Dropped_Before_Entry
     (S        : Fabula.Ast.Scenario_Handle;
      Data_Row : Fabula.Ast.Examples_Row_Handle) is
   begin
      Print_Tag_Check (S, Data_Row);
      Console.Put_Line (Format.Verbose_Ignore, Console.Verbose);
      Print_Verbose_End_Block;
   end Print_Dropped_Before_Entry;

   --  A dropped scenario is ignored and counts nowhere: it never
   --  touches the failure bookkeeping.
   procedure Close_Dropped (N : Runner.Notice) is
   begin
      if N.Entered then
         Print_Scenario_End;
      elsif Verbose_Active then
         Print_Dropped_Before_Entry (N.Scenario, N.Data_Row);
      end if;
   end Close_Dropped;

   --  A scenario's own failure, printed once it closes.
   procedure Print_Scenario_Failure (Outcome : Fabula.Check.Outcome) is
   begin
      if Outcome.Order = Fabula.Check.Fail_Scenario
        and then Fabula.Check.Failure_Text (Outcome)'Length > 0
      then
         Print_Failure_Message (Outcome);
      end if;
   end Print_Scenario_Failure;

   --  A failed scenario joins the failed-scenarios trailer.
   procedure Record_Failed (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      if N.Status = Fabula.Results.Failed then
         Format.Add_Failed
           (Failed,
            Fabula.Frames.Value (Info.Scenario),
            Fabula.Frames.Value (Info.File),
            Info.Scenario_Line);
      end if;
   end Record_Failed;

   procedure On_Scenario_Closed (N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
   begin
      if N.Dropped then
         Close_Dropped (N);
      else
         Print_Scenario_Failure (N.Outcome);
         Print_Scenario_End;
         Record_Failed (N, Info);
      end if;
   end On_Scenario_Closed;

   procedure Begin_Feature (Path : String) is
      Head : constant Fabula.Ast.Header :=
        Fabula.Ast.Feature (Doc_Ref.all).Head;
   begin
      if Suppressed then
         return;
      end if;
      Console.Put
        (Format.Header_Text
           (Fabula.Ast.Text (Doc_Ref.all, Head.Keyword),
            Fabula.Ast.Text (Doc_Ref.all, Head.Name)));
      Console.Put_Line
        (Format.Location_Text (Path, Head.Line), Console.Location);
      Console.New_Line;
   end Begin_Feature;

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      case N.Kind is
         when Runner.Scenario_Opened  =>
            On_Scenario_Opened (Info);

         when Runner.Scenario_Entered =>
            On_Scenario_Entered (N, Info);

         when Runner.Step_Closed      =>
            On_Step_Closed (N, Info);

         when Runner.Scenario_Closed  =>
            On_Scenario_Closed (N, Info);
      end case;
   end On_Notice;

   --  Every failed scenario's name and place, under its header; nothing
   --  when none failed.
   procedure Print_Failed_Trailer is
   begin
      if not Format.Has_Failures (Failed) then
         return;
      end if;
      Console.Put_Line (Format.Failed_Scenarios_Header, Console.Error);
      for I in 1 .. Format.Failed_Count (Failed) loop
         Console.Put (Format.Failed_Name (Failed, I), Console.Failed);
         Console.Put_Line
           (Format.Location_Text
              (Format.Failed_File (Failed, I), Format.Failed_Line (Failed, I)),
            Console.Location);
      end loop;
   end Print_Failed_Trailer;

   procedure Print_Trailer_And_Summaries (Counts : Fabula.Results.Counts) is
   begin
      Print_Failed_Trailer;
      Console.New_Line;   --  the report-level blank, unconditional
      Console.Put_Line (Format.Scenarios_Summary (Counts));
      Console.Put_Line (Format.Steps_Summary (Counts));
   end Print_Trailer_And_Summaries;

end Fabula.Shell.Program_Console;
