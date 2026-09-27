with AUnit.Assertions;      use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Fabula.Tags; use Fabula.Tags;

package body Fabula_Tags_Tests is

   use AUnit.Test_Cases.Registration;

   function "+" (Source : String) return Unbounded_String
   renames To_Unbounded_String;

   --  A tag-set fixture: up to three tags, unused slots left null.  A
   --  real tag name is never empty, so a null slot never matches.
   Fixture_Width : constant := 3;
   type Fixture_Slots is array (1 .. Fixture_Width) of Unbounded_String;

   No_Tags : constant Fixture_Slots := [others => Null_Unbounded_String];

   function One (A : String) return Fixture_Slots
   is ([1 => +A, others => Null_Unbounded_String]);

   function Two (A : String; B : String) return Fixture_Slots
   is ([1 => +A, 2 => +B, others => Null_Unbounded_String]);

   Current_Fixture : Fixture_Slots := No_Tags;

   function Fixture_Has_Tag (Name : String) return Boolean is
   begin
      for Slot of Current_Fixture loop
         if To_String (Slot) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Fixture_Has_Tag;

   function Test_Eval is new Fabula.Tags.Eval (Has_Tag => Fixture_Has_Tag);

   type Case_Record is record
      Expr   : Unbounded_String;
      Tags   : Fixture_Slots;
      Expect : Boolean;
   end record;

   type Case_Array is array (Positive range <>) of Case_Record;

   type Refusal_Record is record
      Expr  : Unbounded_String;
      Error : Positive;
   end record;

   type Refusal_Array is array (Positive range <>) of Refusal_Record;

   --  1. A single tag against {@a}, {}, {@b}.
   Single_Tag_Cases : constant Case_Array :=
     [(+"@a", One ("@a"), True),
      (+"@a", No_Tags, False),
      (+"@a", One ("@b"), False)];

   --  2. `@a or @b and @c` = `@a or (@b and @c)`.
   Precedence_Cases : constant Case_Array :=
     [(+"@a or @b and @c", One ("@a"), True),
      (+"@a or @b and @c", One ("@b"), False),
      (+"@a or @b and @c", Two ("@b", "@c"), True)];

   --  3. `not` binds tighter than `and`: `not @a and @b` means
   --  `(not @a) and @b`, which differs from `not (@a and @b)`.  Both
   --  agree at {@b} (True either way); {@a} is where they actually
   --  disagree, so the test can tell a correct parse from one that
   --  drops the parentheses.
   Not_Precedence_Cases : constant Case_Array :=
     [(+"not @a and @b", One ("@b"), True),
      (+"not (@a and @b)", One ("@b"), True),
      (+"not @a and @b", One ("@a"), False),
      (+"not (@a and @b)", One ("@a"), True)];

   --  4. `or` and `xor` associate left at the same level:
   --  `@a or @b xor @c` = `(@a or @b) xor @c`.
   Left_Assoc_Cases : constant Case_Array :=
     [(+"@a or @b xor @c", One ("@a"), True),
      (+"@a or @b xor @c", Two ("@a", "@c"), False),
      (+"@a or @b xor @c", No_Tags, False)];

   --  5. Double negation.
   Double_Negation_Cases : constant Case_Array :=
     [(+"not not @a", One ("@a"), True), (+"not not @a", No_Tags, False)];

   --  6. Parentheses group; a redundant pair changes nothing.
   Parentheses_Cases : constant Case_Array :=
     [(+"((@a))", One ("@a"), True),
      (+"((@a))", No_Tags, False),
      (+"(@a or @b) and @c", Two ("@a", "@c"), True),
      (+"(@a or @b) and @c", One ("@a"), False),
      (+"(@a or @b) and @c", One ("@c"), False),
      (+"(@a or @b) and @c", Two ("@b", "@c"), True)];

   --  7. An untagged scenario supplies the empty set.
   Empty_Set_Cases : constant Case_Array :=
     [(+"not @wip", No_Tags, True), (+"@a or @b", No_Tags, False)];

   --  8. Tag characters: '-', '.', '_' are all valid inside a name.
   --  The malformed sibling, a bare '@', is in Refusal_Cases.
   Tag_Character_Cases : constant Case_Array :=
     [(+"@smoke-1", One ("@smoke-1"), True),
      (+"@smoke-1", No_Tags, False),
      (+"@a.b", One ("@a.b"), True),
      (+"@x_y", One ("@x_y"), True)];

   --  33 tags joined by 32 "or": the output holds 64 tokens when the
   --  last "or" is still pending, so unwinding it runs out of room.
   Full_Or_Chain : constant String := "@a" & To_String (32 * " or @a");

   --  9. Refusals, each with the position of the failing token.
   --  Parentheses group one expression, never nothing, so "()" and
   --  "(not)" refuse the same way a trailing operator does, at the
   --  closing ")"; "@a and (" refuses at the dangling "(" itself (8),
   --  not at the "and" that last set the wait position (4), and an
   --  embedded LF between two tags refuses as adjacency, the same as
   --  a space would.  The three Full_Or_Chain rows refuse at the last
   --  "or" (190, or 191 after a leading "("): its unwinding overflows
   --  the output before the end, a group's ")" or a stray ")" is read.
   Refusal_Cases : constant Refusal_Array :=
     [(+"@a and", 4),
      (+"and @a", 1),
      (+"@a @b", 4),
      (+"(@a", 1),
      (+"@a)", 3),
      (+"not", 1),
      (+"plain", 1),
      (+"@a or or @b", 7),
      (+"", 1),
      (+"@", 1),
      (+"()", 2),
      (+"(not)", 5),
      (+"@a and (", 8),
      (65 * "(", 65),
      (+("@a" & ASCII.LF & "@b"), 4),
      (+Full_Or_Chain, 190),
      (+("(" & Full_Or_Chain & ")"), 191),
      (+(Full_Or_Chain & ")"), 190)];

   procedure Check (Expr : String; Tags : Fixture_Slots; Expect : Boolean) is
      Result : constant Compiled := Compile (Expr);
   begin
      Assert (Valid (Result), "expression """ & Expr & """ must compile");
      Current_Fixture := Tags;
      Assert
        (Test_Eval (Result) = Expect,
         "expression """ & Expr & """: expected " & Expect'Image);
   end Check;

   procedure Run_Cases (Cases : Case_Array) is
   begin
      for C of Cases loop
         Check (To_String (C.Expr), C.Tags, C.Expect);
      end loop;
   end Run_Cases;

   procedure Check_Refused (Expr : String; Error_At : Positive) is
      Result : constant Compiled := Compile (Expr);
   begin
      Assert
        (not Valid (Result), "expression """ & Expr & """ must be refused");
      Assert
        (Error (Result) = Error_At,
         "expression """
         & Expr
         & """: expected error at "
         & Error_At'Image
         & ", got "
         & Error (Result)'Image);
   end Check_Refused;

   procedure Run_Refusals (Cases : Refusal_Array) is
   begin
      for C of Cases loop
         Check_Refused (To_String (C.Expr), C.Error);
      end loop;
   end Run_Refusals;

   procedure Test_Single_Tag (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Single_Tag_Cases);
   end Test_Single_Tag;

   procedure Test_Precedence (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Precedence_Cases);
   end Test_Precedence;

   procedure Test_Not_Precedence (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run_Cases (Not_Precedence_Cases);
   end Test_Not_Precedence;

   procedure Test_Left_Association
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run_Cases (Left_Assoc_Cases);
   end Test_Left_Association;

   procedure Test_Double_Negation (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run_Cases (Double_Negation_Cases);
   end Test_Double_Negation;

   procedure Test_Parentheses (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Parentheses_Cases);
   end Test_Parentheses;

   procedure Test_Empty_Set (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Cases (Empty_Set_Cases);
   end Test_Empty_Set;

   procedure Test_Tag_Characters (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Run_Cases (Tag_Character_Cases);
   end Test_Tag_Characters;

   procedure Test_Refusals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Run_Refusals (Refusal_Cases);
   end Test_Refusals;

   --  10. More tokens than Max_Tag_Expr_Tokens holds must refuse, not
   --  crash; exactly the capacity must still compile.  A leading
   --  "not" makes the total token count even (32 tags, 31 "or", one
   --  "not"), landing the boundary exactly on the shipped capacity.
   --  One_Too_Many adds a second leading "not" -- one more token, not
   --  a whole "or @a" pair -- so it lands exactly one over, at 65,
   --  the precise boundary rather than overshooting it.
   procedure Test_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Repeats      : constant := 31;
      Or_Chain     : constant String := To_String (Repeats * " or @a");
      At_Capacity  : constant String := "not @a" & Or_Chain;
      One_Too_Many : constant String := "not not @a" & Or_Chain;
   begin
      Assert
        (Valid (Compile (At_Capacity)),
         "an expression at exactly Max_Tag_Expr_Tokens must compile");
      Assert
        (not Valid (Compile (One_Too_Many)),
         "an expression one token over Max_Tag_Expr_Tokens must be"
         & " refused, not crash");
   end Test_Overflow;

   --  11. Blank names the expressions Compile refuses as "no
   --  expression": empty, or only the six whitespace characters.
   procedure Test_Blank (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Six_Blanks : constant String :=
        " " & ASCII.HT & ASCII.LF & ASCII.VT & ASCII.FF & ASCII.CR;
   begin
      Assert (Blank (""), "the empty expression is blank");
      Assert (Blank (Six_Blanks), "the six whitespace characters are blank");
      Assert (not Blank (" @a "), "a tag is not blank");
      Assert (not Blank ("("), "a parenthesis is not blank");
      Assert
        (not Blank ([1 => ASCII.NUL]), "a control character is not blank");
      Assert
        (not Valid (Compile (Six_Blanks))
         and then Error (Compile (Six_Blanks)) = 1,
         "Compile refuses a blank expression at position 1");
   end Test_Blank;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Single_Tag'Access, "a single tag");
      Register_Routine (T, Test_Precedence'Access, "and binds over or");
      Register_Routine
        (T, Test_Not_Precedence'Access, "not binds over and, parens differ");
      Register_Routine
        (T, Test_Left_Association'Access, "or/xor associate left");
      Register_Routine (T, Test_Double_Negation'Access, "not not @a");
      Register_Routine (T, Test_Parentheses'Access, "parenthesized groups");
      Register_Routine
        (T, Test_Empty_Set'Access, "an untagged scenario is the empty set");
      Register_Routine
        (T, Test_Tag_Characters'Access, "tag characters -, ., _");
      Register_Routine
        (T, Test_Refusals'Access, "malformed expressions with positions");
      Register_Routine (T, Test_Overflow'Access, "token capacity");
      Register_Routine (T, Test_Blank'Access, "blank expressions");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String
   is (AUnit.Format ("Fabula.Tags (tag expressions)"));

end Fabula_Tags_Tests;
