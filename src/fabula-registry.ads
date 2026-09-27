--  The user's step and hook tables: pure data built with a small
--  operator DSL, checked once at startup, searched first row first.
--  A pattern or tag expression that refuses to compile is carried in
--  its row, never raised; the table-level checks report it by row.
--  Context is the user's per-scenario record: the runner and the
--  binary instantiate over this one package, so it travels here.
--  Every component of Context must carry a default, because the shell
--  starts each scenario from a default-initialized one.
with Fabula.Expressions;
with Fabula.Limits;
with Fabula.Searches;
with Fabula.Tags;

private with Fabula.Texts;

generic
   type Step_Kind is (<>);
   type Hook_Kind is (<>);
   type Context is private;
package Fabula.Registry with SPARK_Mode is

   --  The context under a name of its own, which the shell's drive loop
   --  reads through the instance; nothing in this package reads it.
   subtype Scenario_Context is Context;

   ---------------------------------------------------------------------
   --  Steps.  Table : constant Step_Table :=
   --    [Step ("I place {int} x {string} in it") >= Add_Item, ...];
   ---------------------------------------------------------------------

   type Step_Row is private;
   type Step_Table is array (Positive range <>) of Step_Row;

   --  A step row with Pattern compiled; ">=" then names its kind.  A
   --  pattern longer than Max_Pattern_Length gives a Refused row that
   --  keeps the pattern's first Max_Pattern_Length characters.
   function Step (Pattern : String) return Step_Row;

   function ">=" (L : Step_Row; R : Step_Kind) return Step_Row;

   ---------------------------------------------------------------------
   --  Hooks.  Before and After take an optional tag expression; an
   --  empty or all-blank one leaves the hook untagged, so it runs for
   --  every scenario.  The step and all-run hooks are always untagged.
   ---------------------------------------------------------------------

   type Hook_Row is private;
   type Hook_Table is array (Positive range <>) of Hook_Row;

   --  When a hook runs: once around the whole run, around each
   --  scenario, or around each step.
   type Hook_Phase is
     (Run_Start,        --  Before_All
      Run_End,          --  After_All
      Scenario_Start,   --  Before
      Scenario_End,     --  After
      Step_Start,       --  Before_Step
      Step_End);        --  After_Step

   function Before_All return Hook_Row;
   function After_All return Hook_Row;

   --  A hook around each scenario that Tag_Expr selects, compiled; a
   --  blank Tag_Expr selects every scenario.  A non-blank expression
   --  longer than Max_Tag_Expr_Length gives a Refused row that keeps
   --  its first Max_Tag_Expr_Length characters.
   function Before (Tag_Expr : String := "") return Hook_Row;
   function After (Tag_Expr : String := "") return Hook_Row;

   function Before_Step return Hook_Row;
   function After_Step return Hook_Row;

   function ">=" (L : Hook_Row; R : Hook_Kind) return Hook_Row;

   ---------------------------------------------------------------------
   --  Validation.  A row is bad when its pattern or tag expression
   --  refused to compile, or when it never met ">=" and so names no
   --  kind.  One bad row makes the whole table invalid; the binary
   --  refuses to run and names every bad row.
   ---------------------------------------------------------------------

   type Row_Status is (Row_Ok, Refused, Unbound);

   function Step_Status (T : Step_Table; Index : Positive) return Row_Status
   with Pre => Index in T'Range;

   function Hook_Status (T : Hook_Table; Index : Positive) return Row_Status
   with Pre => Index in T'Range;

   function Steps_Valid (T : Step_Table) return Boolean
   is (for all I in T'Range => Step_Status (T, I) = Row_Ok);

   function Hooks_Valid (T : Hook_Table) return Boolean
   is (for all I in T'Range => Hook_Status (T, I) = Row_Ok);

   --  A row index that names no row.
   No_Row : constant Natural := Searches.Not_Found;

   function First_Bad (T : Step_Table) return Natural
   with
     Post =>
       (First_Bad'Result = No_Row) = Steps_Valid (T)
       and then (if First_Bad'Result /= No_Row
                 then
                   First_Bad'Result in T'Range
                   and then Step_Status (T, First_Bad'Result) /= Row_Ok);
   --  No_Row when every row is good.

   function First_Bad_Hook (T : Hook_Table) return Natural
   with
     Post =>
       (First_Bad_Hook'Result = No_Row) = Hooks_Valid (T)
       and then (if First_Bad_Hook'Result /= No_Row
                 then
                   First_Bad_Hook'Result in T'Range
                   and then Hook_Status (T, First_Bad_Hook'Result) /= Row_Ok);

   --  The source text as the user wrote it, for the startup report.
   function Pattern_Text (T : Step_Table; Index : Positive) return String
   with Pre => Index in T'Range;

   function Tag_Expr_Text (T : Hook_Table; Index : Positive) return String
   with Pre => Index in T'Range;

   ---------------------------------------------------------------------
   --  Lookup.  Matching ignores the step keyword; when several rows
   --  match, the first one in the table wins, as the reference
   --  interpreter's registration order does.
   ---------------------------------------------------------------------

   type Match_Result is record
      Found    : Boolean := False;
      Index    : Natural := No_Row;          --  row index in the table
      Captures : Expressions.Capture_List;
   end record;

   function Find (T : Step_Table; Text : String) return Match_Result
   with
     Pre  =>
       Steps_Valid (T)
       and then Text'First = First_Column
       and then Text'Length <= Limits.Max_Line_Length,
     Post =>
       (if Find'Result.Found
        then
          Find'Result.Index in T'Range
          and then (for all I in 1 .. Find'Result.Captures.Count =>
                      Find'Result.Captures.Items (I).First <= Text'Length + 1
                      and then Find'Result.Captures.Items (I).Last
                               <= Text'Length
                      and then Find'Result.Captures.Items (I).Last
                               >= Find'Result.Captures.Items (I).First - 1)
        else
          Find'Result.Index = No_Row and then Find'Result.Captures.Count = 0);
   --  Captures are slices of Text, which the caller keeps alive while
   --  it reads them.

   function Kind_Of (T : Step_Table; Index : Positive) return Step_Kind
   with Pre => Index in T'Range;

   ---------------------------------------------------------------------
   --  Hook accessors for the runner.
   ---------------------------------------------------------------------

   function Kind_Of (T : Hook_Table; Index : Positive) return Hook_Kind
   with Pre => Index in T'Range;

   function Phase_Of (T : Hook_Table; Index : Positive) return Hook_Phase
   with Pre => Index in T'Range;

   function Has_Tag_Expr (T : Hook_Table; Index : Positive) return Boolean
   with Pre => Index in T'Range;

   function Tag_Expr (T : Hook_Table; Index : Positive) return Tags.Compiled
   with
     Pre  => Index in T'Range,
     Post =>
       (if Hook_Status (T, Index) = Row_Ok and then Has_Tag_Expr (T, Index)
        then Tags.Valid (Tag_Expr'Result));
   --  A good tagged row's expression is valid, so Tags.Eval accepts it.

private

   --  A row's source as written, its first characters when it is longer
   --  than the row keeps.
   subtype Pattern_Source is Texts.Bounded_Text (Limits.Max_Pattern_Length);
   subtype Tag_Expr_Source is Texts.Bounded_Text (Limits.Max_Tag_Expr_Length);

   --  Expressions.Valid (Pattern) is Compile's verdict; Bound records
   --  that ">=" named the kind.  Source keeps the pattern as written.
   type Step_Row is record
      Pattern : Expressions.Compiled;
      Bound   : Boolean := False;
      Kind    : Step_Kind := Step_Kind'First;
      Source  : Pattern_Source;
   end record;

   --  Has_Expr is False for an untagged hook, whose Expr is never
   --  read.  Source keeps the tag expression as written.
   type Hook_Row is record
      Phase    : Hook_Phase := Run_Start;
      Bound    : Boolean := False;
      Kind     : Hook_Kind := Hook_Kind'First;
      Has_Expr : Boolean := False;
      Expr     : Tags.Compiled;
      Source   : Tag_Expr_Source;
   end record;

   function Step_Status (T : Step_Table; Index : Positive) return Row_Status
   is (if not Expressions.Valid (T (Index).Pattern)
       then Refused
       elsif not T (Index).Bound
       then Unbound
       else Row_Ok);

   function Hook_Status (T : Hook_Table; Index : Positive) return Row_Status
   is (if T (Index).Has_Expr and then not Tags.Valid (T (Index).Expr)
       then Refused
       elsif not T (Index).Bound
       then Unbound
       else Row_Ok);

   function Kind_Of (T : Step_Table; Index : Positive) return Step_Kind
   is (T (Index).Kind);

   function Kind_Of (T : Hook_Table; Index : Positive) return Hook_Kind
   is (T (Index).Kind);

   function Phase_Of (T : Hook_Table; Index : Positive) return Hook_Phase
   is (T (Index).Phase);

   function Has_Tag_Expr (T : Hook_Table; Index : Positive) return Boolean
   is (T (Index).Has_Expr);

   function Tag_Expr (T : Hook_Table; Index : Positive) return Tags.Compiled
   is (T (Index).Expr);

end Fabula.Registry;
