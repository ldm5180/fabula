--  The proof closure.  Every core unit must be reachable from here;
--  tools/proof_closure_lint.py fails on any unit gnatprove did not
--  analyze.  A generic (Fabula.Tags.Eval, Fabula.Registry, Fabula.Run)
--  is analyzed only through a concrete instance, so one is
--  instantiated here.
with Fabula.Args;
with Fabula.Ast;
with Fabula.Check;
with Fabula.Cli;
with Fabula.Expand;
with Fabula.Expressions;
with Fabula.Frames;
with Fabula.Limits;
with Fabula.Names;
with Fabula.Numbers;
with Fabula.Parse;
with Fabula.Registry;
with Fabula.Results;
with Fabula.Run;
with Fabula.Scan;
with Fabula.Tags;
with Fabula.Texts;

package Fabula_Closure_Proof
  with SPARK_Mode
is
   Arena_Holds_A_Line : constant Boolean :=
     Fabula.Limits.Text_Arena_Bytes >= Fabula.Limits.Max_Line_Length;

   Feature_Line_Classifies : constant Boolean :=
     Fabula.Scan.Classify ("Feature: x").Class in Fabula.Scan.Feature_Header;

   Every_Argument_Has_A_Capture : constant Boolean :=
     Fabula.Expressions.Capture_Items'Length = Fabula.Limits.Max_Args_Per_Step;

   --  The one tag of the instance's tag set, and the whole expression
   --  the closure compiles.
   Closure_Tag : constant String := "@a";

   --  Fixes the instance's tag set to {Closure_Tag}; only gnatprove's
   --  analysis of the instance matters here, not the value it computes.
   function Closure_Has_Tag (Name : String) return Boolean
   is (Name = Closure_Tag);

   function Closure_Eval is new Fabula.Tags.Eval (Has_Tag => Closure_Has_Tag);

   --  Mirrors the real calling convention: check Valid before calling
   --  Eval.  Compile (Closure_Tag) is always valid, so the Then branch
   --  is the one actually taken; the Else branch exists only to give
   --  Error a call site here too.
   Closure_Tag_Expr : constant Fabula.Tags.Compiled :=
     Fabula.Tags.Compile (Closure_Tag);

   --  What Error answers for an expression it did not refuse.
   No_Error_Position : constant Natural := 0;

   Tag_Expr_Round_Trips : constant Boolean :=
     (if Fabula.Tags.Valid (Closure_Tag_Expr)
      then Closure_Eval (Closure_Tag_Expr)
      else Fabula.Tags.Error (Closure_Tag_Expr) > No_Error_Position);

   Empty_Slice_Is_Empty : constant Boolean :=
     Fabula.Ast.Length (Fabula.Ast.Empty_Slice) = Fabula.Ast.No_Characters;

   --  One parse of a two-line feature, as the shell will run it: proves
   --  Start, Feed and Finish callable under their contracts, and
   --  reaches the parser machine's sml instance (inside the private
   --  Fabula.Grammar) at the shipped capacities.
   procedure Closure_Parse
     (P : out Fabula.Parse.Parser; Doc : in out Fabula.Ast.Document);

   --  A second Integer instance of Compare, alongside the shipped
   --  Fabula.Check.Ints: belt and suspenders for the generic's proof
   --  coverage, since a bare child-unit instantiation needs its own
   --  `pragma SPARK_Mode;` (an aspect there is rejected) before
   --  gnatprove analyzes it rather than skipping it as Off.
   package Closure_Compare is new
     Fabula.Check.Compare
       (Item       => Integer,
        Image      => Fabula.Check.Integer_Image,
        Item_Reads => Fabula.Numbers.Integer_Reads);

   --  Reaches Closure_Compare's six comparisons, with a read on either
   --  side too, and the plain checks and scenario controls declared
   --  directly on Fabula.Check.
   procedure Closure_Check (R : in out Fabula.Check.Outcome);

   --  A SPARK step body's numeric reads, with no assumption: a capture
   --  through Args.Int and any text through Numbers.Parse_Integer.  It
   --  takes both branches of each result and reads Value only where Ok
   --  holds, so its proof shows a SPARK caller needs no exception
   --  contract.  Its assertions show the parser's contract fixes the
   --  exact result of a literal text.
   procedure Closure_Numbers
     (A     : Fabula.Args.List;
      Text  : String;
      R     : in out Fabula.Check.Outcome;
      Total : out Integer);

   --  One scenario's worth of counters, reaching the exit rule.
   procedure Closure_Results (C : in out Fabula.Results.Counts);

   --  A Frame's bounded fields, filled and read back.
   procedure Closure_Frame (F : in out Fabula.Frames.Frame);

   --  Bounded text: its contracts fix the exact text that Truncated,
   --  Append and Append_Truncated keep.  Kept is the final length.
   procedure Closure_Texts (Kept : out Natural);

   --  argv as the shell hands it over: a flag needing a value, a
   --  pre-merged --report-json=FILE, an unknown flag.  Reaches every
   --  Options_Result accessor and both refusal shapes.
   procedure Closure_Cli (Total : out Natural);

   --  A Registry instance over sample enums, with a step table and a
   --  hook table declared at library level, as a user declares them.
   type Closure_Step is (Count_Step, Word_Step);
   type Closure_Hook is (Fresh_Hook, Audit_Hook);

   type Closure_Context is record
      Count : Natural := Fabula.Results.Nothing_Counted;
   end record;

   package Closure_Registry is new
     Fabula.Registry
       (Step_Kind => Closure_Step,
        Hook_Kind => Closure_Hook,
        Context   => Closure_Context);
   use type Closure_Registry.Step_Row;
   use type Closure_Registry.Hook_Row;
   use type Closure_Registry.Hook_Phase;

   Closure_Steps : constant Closure_Registry.Step_Table :=
     [Closure_Registry.Step ("the count is {int}") >= Count_Step,
      Closure_Registry.Step ("a {word}") >= Word_Step];

   Closure_Hooks : constant Closure_Registry.Hook_Table :=
     [Closure_Registry.Before ("@fresh") >= Fresh_Hook,
      Closure_Registry.After >= Audit_Hook,
      Closure_Registry.Before_All >= Audit_Hook,
      Closure_Registry.After_All >= Audit_Hook,
      Closure_Registry.Before_Step >= Audit_Hook,
      Closure_Registry.After_Step >= Audit_Hook];

   --  Startup validation, then one lookup, as the runner will do them.
   procedure Closure_Lookup (Kind : out Closure_Step; Captures : out Natural);

   --  Every hook accessor the runner reads, over the whole table.
   procedure Closure_Hook_Walk (Tagged_Rows : out Natural);

   --  The first outline's concrete scenarios, as the runner will walk
   --  them: rows, name, line, tags and one step's expansion.
   procedure Closure_Expand (Doc : Fabula.Ast.Document; Total : out Natural);

   --  A List as the runner assembles one: a lookup's text and captures,
   --  a doc string and a table, one Examples row.  The shell makes Ref.
   procedure Closure_Assemble
     (Ref : Fabula.Args.Document_Access; A : out Fabula.Args.List);

   --  Every Args reader, each behind the guard its precondition names,
   --  as a step body calls them.
   procedure Closure_Read (A : Fabula.Args.List; Longest : out Natural);

   --  The name patterns of the -n option, alone and as a list.
   Closure_Names_Match : constant Boolean :=
     Fabula.Names.Matches ("a b", "a*")
     and then Fabula.Names.Matches_Any ("b", "a:?");

   --  The runner over the sample tables, as the binary instantiates it.
   package Closure_Run is new
     Fabula.Run
       (Reg   => Closure_Registry,
        Steps => Closure_Steps,
        Hooks => Closure_Hooks);

   --  One whole run as the shell drives it: every request answered,
   --  every notice read and resumed, one feature, one parse error.
   --  Closed counts the scenarios that closed.  The shell makes Ref.
   procedure Closure_Drive
     (Ref    : Fabula.Args.Document_Access;
      Counts : out Fabula.Results.Counts;
      Closed : out Natural);

end Fabula_Closure_Proof;
