--  The step cursor: an sml machine that walks one scenario's steps,
--  the background's first, then the scenario's own.  The machine owns
--  the cursor.  Its context holds the two step ranges, loaded once when
--  the scenario starts, and the current step.  Its guards read that
--  context and its actions move the step and say whether one was found,
--  so a caller only asks for the next step and reads the answer.
with Fabula.Ast;
with Sml.Machines;
with Sml.Machines.Bundled;

package Fabula.Step_Walk
  with SPARK_Mode
is

   use type Ast.Step_Handle;

   --  Which part of a scenario's steps the cursor is in: none has run
   --  yet, the background's, or the scenario's own.
   type Segment is (Not_Started, Background, Own);

   --  The cursor's one event: the runner wants the next step.
   type Event_Kind is (E_Next_Step);

   type Event is record
      Kind : Event_Kind := E_Next_Step;
   end record;

   type Guard_Kind is
     (Always,
      Has_Shared,    --  the background has steps
      Has_Mine,      --  the scenario has steps of its own
      Shared_Left,   --  a background step follows the current one
      Mine_Left);    --  one of the scenario's own steps follows it

   --  Where a move puts the cursor.  Each act but Nothing writes both
   --  the step and whether one was found.
   type Act is
     (Nothing,
      First_Shared,  --  the background's first step
      First_Mine,    --  the scenario's own first step
      Step_Ahead,    --  the step after the current one
      Run_Out);      --  no step follows: the cursor stays, none found

   --  The machine context.  Shared, Mine and Count are loaded once, when
   --  the scenario starts; Count is its document's step count.  Step
   --  and Found are the acts' own.  A found step always lies in the
   --  document.
   type Cursor is record
      Shared : Ast.Step_Range;
      Mine   : Ast.Step_Range;
      Count  : Ast.Step_Handle := Ast.No_Step;
      Step   : Ast.Step_Handle := Ast.No_Step;
      Found  : Boolean := False;
   end record
   with
     Dynamic_Predicate =>
       (if Cursor.Found then Cursor.Step in 1 .. Cursor.Count);

   function Kind_Of (Evt : Event) return Event_Kind
   is (Evt.Kind);

   function Evaluate
     (G : Guard_Kind; Ctx : Cursor; Evt : Event) return Boolean;

   --  Moves the cursor where A says.
   procedure Execute (A : Act; Ctx : in out Cursor; Evt : Event);

   package SM is new
     Sml.Machines
       (State       => Segment,
        Event_Kind  => Event_Kind,
        Event       => Event,
        Context     => Cursor,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Act,
        Kind_Of     => Kind_Of,
        Evaluate    => Evaluate,
        Execute     => Execute);

   package Bundle is new SM.Bundled;

   Rows : constant := 8;
   --  The transition table's length; a Walk embeds a machine of it.

   --  The machine and its cursor, in one object.
   subtype Walk is Bundle.Instance (Rows);

   --  A walk over Shared's steps, then Mine's, in a document of
   --  Step_Count steps; no step is found yet.
   function Started
     (Shared, Mine : Ast.Step_Range; Step_Count : Ast.Step_Handle) return Walk
   with
     Post =>
       Bundle.State_Of (Started'Result) = Not_Started
       and then not Started'Result.Ctx.Found;

   --  A walk with no step at all: every move finds none.
   function Empty return Walk
   is (Started (Ast.Step_Pool.Empty, Ast.Step_Pool.Empty, Ast.No_Step));

   --  Moves W to its next step; Found (W) says whether there was one.
   procedure Next (W : in out Walk);

   function State_Of (W : Walk) return Segment
   is (Bundle.State_Of (W));

   function Step_Of (W : Walk) return Ast.Step_Handle
   is (W.Ctx.Step);

   function Found (W : Walk) return Boolean
   is (W.Ctx.Found);

end Fabula.Step_Walk;
