with Ada.Strings.Unbounded;

with Fabula.Ast;
with Fabula.Check;
with Fabula.Expand;
with Fabula.Format;
with Fabula.Scan;
with Fabula.Shell.Console;

package body Fabula.Shell.Program_Console
  with SPARK_Mode => Off
is

   use type Fabula.Ast.Doc_Handle;
   use type Fabula.Ast.Doc_Line_Handle;
   use type Fabula.Ast.Examples_Row_Handle;
   use type Fabula.Ast.Step_Handle;
   use type Fabula.Ast.Table_Handle;
   use type Fabula.Results.Status;

   Doc_Ref         : Fabula.Args.Document_Access;
   Quiet_Active    : Boolean := False;
   Verbose_Active  : Boolean := False;
   Filter_Active   : Boolean := False;
   Dry_Run_Active  : Boolean := False;
   Compiled_Filter : Fabula.Tags.Compiled;
   Tag_Expr_Text   : Ada.Strings.Unbounded.Unbounded_String;
   Failed          : Fabula.Format.Failed_Store :=
     Fabula.Format.Empty_Failed_Store;

   Current_Tag_Set : Fabula.Expand.Tag_Set;

   function Filter_Has_Tag (Name : String) return Boolean
   is (Fabula.Expand.Contains (Doc_Ref.all, Current_Tag_Set, Name));

   function Filter_Eval is new Fabula.Tags.Eval (Has_Tag => Filter_Has_Tag);

   procedure Set_Document (Doc : Fabula.Args.Document_Access) is
   begin
      Doc_Ref := Doc;
   end Set_Document;

   procedure Set_Quiet (Quiet : Boolean) is
   begin
      Quiet_Active := Quiet;
   end Set_Quiet;

   procedure Set_Verbose (Verbose : Boolean) is
   begin
      Verbose_Active := Verbose;
   end Set_Verbose;

   procedure Set_Dry_Run (Dry_Run : Boolean) is
   begin
      Dry_Run_Active := Dry_Run;
   end Set_Dry_Run;

   --  The reference interpreter runs one log level, set by -q then
   --  unconditionally overwritten by -v
   --  when both are given -- so -v always wins, not just for the
   --  step-level assertion message but for everything -q would else
   --  hide (the feature/scenario headers, the step lines, the blank).
   function Suppressed return Boolean
   is (Quiet_Active and then not Verbose_Active);

   procedure Set_Filter
     (Has_Filter : Boolean; Filter : Fabula.Tags.Compiled; Tag_Expr : String)
   is
   begin
      Filter_Active := Has_Filter;
      Compiled_Filter := Filter;
      Tag_Expr_Text := Ada.Strings.Unbounded.To_Unbounded_String (Tag_Expr);
   end Set_Filter;

   ---------------------------------------------------------------------
   --  Small conversions and lookups.
   ---------------------------------------------------------------------

   function Role_Style
     (Role : Fabula.Format.Role) return Fabula.Shell.Console.Style
   is (case Role is
         when Fabula.Format.Plain     => Fabula.Shell.Console.Plain,
         when Fabula.Format.Passed    => Fabula.Shell.Console.Passed,
         when Fabula.Format.Failed    => Fabula.Shell.Console.Failed,
         when Fabula.Format.Skipped   => Fabula.Shell.Console.Skipped,
         when Fabula.Format.Undefined => Fabula.Shell.Console.Undefined,
         when Fabula.Format.Location  => Fabula.Shell.Console.Location,
         when Fabula.Format.Error     => Fabula.Shell.Console.Error);

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

   --  The Examples block a concrete outline row belongs to, and that
   --  block's header row; both 0 for a plain scenario or a stale row --
   --  never read past a pool.
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

   ---------------------------------------------------------------------
   --  A step's table and doc string.
   ---------------------------------------------------------------------

   procedure Render_Table
     (Doc        : Fabula.Ast.Document;
      T          : Fabula.Ast.Table_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle) is
   begin
      if T = 0 or else T > Fabula.Ast.Table_Count (Doc) then
         return;
      end if;
      declare
         Widths : constant Fabula.Format.Column_Widths :=
           Fabula.Format.Table_Widths (Doc, T, Header_Row, Data_Row);
         Rows   : constant Fabula.Ast.Row_Range :=
           Fabula.Ast.Table (Doc, T).Rows;
      begin
         for Row in Rows.First .. Rows.Last loop
            exit when Row not in 1 .. Fabula.Ast.Table_Row_Count (Doc);
            Fabula.Shell.Console.Put
              (Fabula.Format.Table_Row_Text
                 (Doc, Row, Header_Row, Data_Row, Widths));
            Fabula.Shell.Console.New_Line;
         end loop;
      end;
   end Render_Table;

   procedure Render_Doc_String
     (Doc        : Fabula.Ast.Document;
      D          : Fabula.Ast.Doc_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle) is
   begin
      if D = 0 or else D > Fabula.Ast.Doc_String_Count (Doc) then
         return;
      end if;
      declare
         Node : constant Fabula.Ast.Doc_String_Node :=
           Fabula.Ast.Doc_String (Doc, D);
      begin
         if Node.Lines.Last < Node.Lines.First then
            return;   --  zero content lines: nothing prints, not the fences

         end if;
         Fabula.Shell.Console.Put (Fabula.Format.Doc_Fence_Text);
         Fabula.Shell.Console.New_Line;
         for L in Node.Lines.First .. Node.Lines.Last loop
            exit when L not in 1 .. Fabula.Ast.Doc_Line_Count (Doc);
            Fabula.Shell.Console.Put
              (Fabula.Format.Doc_Content_Text (Doc, L, Header_Row, Data_Row));
            Fabula.Shell.Console.New_Line;
         end loop;
         Fabula.Shell.Console.Put (Fabula.Format.Doc_Fence_Text);
         Fabula.Shell.Console.New_Line;
      end;
   end Render_Doc_String;

   procedure Render_Step_Arguments
     (Doc        : Fabula.Ast.Document;
      Step       : Fabula.Ast.Step_Handle;
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Data_Row   : Fabula.Ast.Examples_Row_Handle) is
   begin
      if Step = 0 or else Step > Fabula.Ast.Step_Count (Doc) then
         return;
      end if;
      declare
         Node : constant Fabula.Ast.Step_Node := Fabula.Ast.Step (Doc, Step);
      begin
         Render_Table (Doc, Node.Table, Header_Row, Data_Row);
         Render_Doc_String (Doc, Node.Doc, Header_Row, Data_Row);
      end;
   end Render_Step_Arguments;

   ---------------------------------------------------------------------
   --  One notice at a time (docs/report_wiring.md items 1-8).
   ---------------------------------------------------------------------

   procedure Print_Failure_Message (Outcome : Fabula.Check.Outcome) is
   begin
      Fabula.Shell.Console.Put
        (Outcome.Msg (1 .. Outcome.Msg_Len), Fabula.Shell.Console.Error);
      Fabula.Shell.Console.New_Line;
   end Print_Failure_Message;

   procedure On_Scenario_Opened (Info : Fabula.Frames.Frame) is
   begin
      if not Verbose_Active then
         return;
      end if;
      Fabula.Shell.Console.Put
        (Fabula.Format.Verbose_Separator, Fabula.Shell.Console.Verbose);
      Fabula.Shell.Console.New_Line;
      Fabula.Shell.Console.Put
        (Fabula.Format.Verbose_Scenario_Start
           (Fabula.Frames.Value (Info.Scenario),
            Fabula.Frames.Value (Info.File),
            Info.Scenario_Line),
         Fabula.Shell.Console.Verbose);
      Fabula.Shell.Console.New_Line;
   end On_Scenario_Opened;

   function Tags_Text (Set : Fabula.Expand.Tag_Set) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for I in 1 .. Set.Count loop
         if I > 1 then
            Ada.Strings.Unbounded.Append (Result, " ");
         end if;
         Ada.Strings.Unbounded.Append
           (Result,
            Fabula.Ast.Text
              (Doc_Ref.all, Fabula.Ast.Tag (Doc_Ref.all, Set.Items (I))));
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Tags_Text;

   --  The verbose tag-check line, or its no-filter analogue.  Reaches
   --  Fabula.Expand/Fabula.Tags directly: the runner's own effective
   --  tag set is private, but both are public library units.
   procedure Print_Tag_Check
     (S        : Fabula.Ast.Scenario_Handle;
      Data_Row : Fabula.Ast.Examples_Row_Handle)
   is
      Header_Row : Fabula.Ast.Examples_Row_Handle;
      Block      : Fabula.Ast.Examples_Handle;
   begin
      if not Filter_Active then
         Fabula.Shell.Console.Put
           (Fabula.Format.No_Tags_Given, Fabula.Shell.Console.Verbose);
         Fabula.Shell.Console.New_Line;
         return;
      end if;
      Locate_Row (Doc_Ref.all, S, Data_Row, Header_Row, Block);
      Current_Tag_Set := Fabula.Expand.Effective_Tags (Doc_Ref.all, S, Block);
      Fabula.Shell.Console.Put
        (Fabula.Format.Verbose_Tag_Check
           (Tags_Text (Current_Tag_Set),
            Ada.Strings.Unbounded.To_String (Tag_Expr_Text),
            Filter_Eval (Compiled_Filter)),
         Fabula.Shell.Console.Verbose);
      Fabula.Shell.Console.New_Line;
   end Print_Tag_Check;

   procedure On_Scenario_Entered
     (N : Runner.Notice; Info : Fabula.Frames.Frame) is
   begin
      if Verbose_Active then
         Print_Tag_Check (N.Scenario, N.Data_Row);
         --  -d is the one Skip trigger the shell can see ahead of the
         --  scenario's own header line (Set_Dry_Run's own comment covers
         --  the hook-triggered gap).
         if Dry_Run_Active then
            Fabula.Shell.Console.Put
              (Fabula.Format.Verbose_Skip, Fabula.Shell.Console.Verbose);
            Fabula.Shell.Console.New_Line;
         end if;
      end if;
      if Suppressed then
         return;
      end if;
      Fabula.Shell.Console.Put
        (Fabula.Format.Header_Text
           (Scenario_Keyword_Text (Doc_Ref.all, N.Scenario),
            Fabula.Frames.Value (Info.Scenario)));
      Fabula.Shell.Console.Put
        (Fabula.Format.Location_Text
           (Fabula.Frames.Value (Info.File), Info.Scenario_Line),
         Fabula.Shell.Console.Location);
      Fabula.Shell.Console.New_Line;
   end On_Scenario_Entered;

   procedure Print_Step_Line
     (Doc : Fabula.Ast.Document; N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
   begin
      Fabula.Shell.Console.Put
        (Fabula.Format.Bracket_Label (N.Status),
         Role_Style (Fabula.Format.Style_Of (N.Status)));
      Fabula.Shell.Console.Put
        (Fabula.Format.Step_Text
           (Step_Keyword_Text (Doc, N.Step), Fabula.Frames.Value (Info.Step)));
      Fabula.Shell.Console.Put
        (Fabula.Format.Location_Text
           (Fabula.Frames.Value (Info.File), Info.Step_Line),
         Fabula.Shell.Console.Location);
      Fabula.Shell.Console.New_Line;
      --  The reference interpreter builds an unmatched outline row from
      --  its bare keyword/name/file/line alone, no table or doc string
      --  -- undefined never prints an argument on an outline row.
      if N.Status /= Fabula.Results.Undefined or else N.Data_Row = 0 then
         Render_Step_Arguments
           (Doc,
            N.Step,
            Header_Row_For (Doc, N.Scenario, N.Data_Row),
            N.Data_Row);
      end if;
   end Print_Step_Line;

   procedure On_Step_Closed (N : Runner.Notice; Info : Fabula.Frames.Frame) is
      use type Fabula.Check.Control;
   begin
      if not N.Outcome.Passing
        and then N.Outcome.Order /= Fabula.Check.Fail_Scenario
        and then N.Outcome.Msg_Len > 0
        and then not Suppressed
      then
         Print_Failure_Message (N.Outcome);
      end if;
      if not Suppressed then
         Print_Step_Line (Doc_Ref.all, N, Info);
      end if;
   end On_Step_Closed;

   --  "[VERBOSE] Scenario end" + separator + ONE blank: the reference
   --  interpreter's own end-of-scenario print, embedded in every verbose
   --  completion, kept, dropped after entry, or dropped before it --
   --  its own separator print double-newlines.
   procedure Print_Verbose_End_Block is
   begin
      Fabula.Shell.Console.Put
        (Fabula.Format.Verbose_End, Fabula.Shell.Console.Verbose);
      Fabula.Shell.Console.New_Line;
      Fabula.Shell.Console.Put
        (Fabula.Format.Verbose_Separator, Fabula.Shell.Console.Verbose);
      Fabula.Shell.Console.New_Line;
      Fabula.Shell.Console.New_Line;
   end Print_Verbose_End_Block;

   --  The verbose end block, in the oracle's own order ("Scenario end",
   --  separator, blank -- THEN the pre-existing unconditional blank,
   --  never before it), plus that trailing blank -- shared by a normal
   --  close and a post-entry
   --  Dropped close, since both leave the same thing open: the header
   --  (and, in -v, the tag check) already printed.
   procedure Print_Scenario_End is
   begin
      if Verbose_Active then
         Print_Verbose_End_Block;
      end if;
      if not Suppressed then
         Fabula.Shell.Console.New_Line;   --  unconditional

      end if;
   end Print_Scenario_End;

   --  A scenario dropped before entry (a -t filter or a before-hook
   --  Ignore) still gets its own verbose
   --  tag-check, "ignored" line and end block in the oracle -- printed
   --  here from the same Print_Tag_Check the kept path uses, since the
   --  notice carries no word of which drop it was.  A before-hook's
   --  explicit Ignore short-circuits the oracle's own tag check when no
   --  -t is given; fabula cannot tell that case from a real tag mismatch
   --  from the notice alone, so it always prints the check -- a known,
   --  disclosed gap, not a byte-for-byte match there.
   procedure Print_Dropped_Before_Entry
     (S        : Fabula.Ast.Scenario_Handle;
      Data_Row : Fabula.Ast.Examples_Row_Handle) is
   begin
      Print_Tag_Check (S, Data_Row);
      Fabula.Shell.Console.Put
        (Fabula.Format.Verbose_Ignore, Fabula.Shell.Console.Verbose);
      Fabula.Shell.Console.New_Line;
      Print_Verbose_End_Block;
   end Print_Dropped_Before_Entry;

   procedure On_Scenario_Closed (N : Runner.Notice; Info : Fabula.Frames.Frame)
   is
      use type Fabula.Check.Control;
   begin
      if N.Dropped then
         --  a dropped scenario never touches the failure bookkeeping
         --  below: it is ignored and counts nowhere.
         if N.Entered then
            Print_Scenario_End;
         elsif Verbose_Active then
            Print_Dropped_Before_Entry (N.Scenario, N.Data_Row);
         end if;
         return;
      end if;
      if N.Outcome.Order = Fabula.Check.Fail_Scenario
        and then N.Outcome.Msg_Len > 0
      then
         Print_Failure_Message (N.Outcome);
      end if;
      Print_Scenario_End;
      if N.Status = Fabula.Results.Failed then
         Fabula.Format.Add_Failed
           (Failed,
            Fabula.Frames.Value (Info.Scenario),
            Fabula.Frames.Value (Info.File),
            Info.Scenario_Line);
      end if;
   end On_Scenario_Closed;

   procedure Begin_Feature (Path : String) is
      Head : constant Fabula.Ast.Header :=
        Fabula.Ast.Feature (Doc_Ref.all).Head;
   begin
      if Suppressed then
         return;
      end if;
      Fabula.Shell.Console.Put
        (Fabula.Format.Header_Text
           (Fabula.Ast.Text (Doc_Ref.all, Head.Keyword),
            Fabula.Ast.Text (Doc_Ref.all, Head.Name)));
      Fabula.Shell.Console.Put
        (Fabula.Format.Location_Text (Path, Head.Line),
         Fabula.Shell.Console.Location);
      Fabula.Shell.Console.New_Line;
      Fabula.Shell.Console.New_Line;
   end Begin_Feature;

   procedure On_Notice (N : Runner.Notice; Info : Fabula.Frames.Frame) is
      use type Runner.Notice_Kind;
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

   procedure Print_Trailer_And_Summaries (Counts : Fabula.Results.Counts) is
   begin
      if Fabula.Format.Has_Failures (Failed) then
         Fabula.Shell.Console.Put
           (Fabula.Format.Failed_Scenarios_Header, Fabula.Shell.Console.Error);
         Fabula.Shell.Console.New_Line;
         for I in 1 .. Fabula.Format.Failed_Count (Failed) loop
            Fabula.Shell.Console.Put
              (Fabula.Format.Failed_Name (Failed, I),
               Fabula.Shell.Console.Failed);
            Fabula.Shell.Console.Put
              (Fabula.Format.Location_Text
                 (Fabula.Format.Failed_File (Failed, I),
                  Fabula.Format.Failed_Line (Failed, I)),
               Fabula.Shell.Console.Location);
            Fabula.Shell.Console.New_Line;
         end loop;
      end if;
      Fabula
        .Shell
        .Console
        .New_Line;   --  the report-level blank, unconditional
      Fabula.Shell.Console.Put (Fabula.Format.Scenarios_Summary (Counts));
      Fabula.Shell.Console.New_Line;
      Fabula.Shell.Console.Put (Fabula.Format.Steps_Summary (Counts));
      Fabula.Shell.Console.New_Line;
   end Print_Trailer_And_Summaries;

end Fabula.Shell.Program_Console;
