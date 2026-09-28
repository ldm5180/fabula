with Sml.Machines.Operators;

package body Fabula.Step_Walk
  with SPARK_Mode
is

   package Op is new SM.Operators (Always => Always, Nothing => Nothing);
   use type Op.Ev, Op.Ev_Guard, Op.Ev_Built, Op.Source;

   subtype Ev is Op.Ev;

   Next_Step : constant Ev := (Kind => E_Next_Step);

   --  Each row reads:  From + Event (Guard) / Act >= To.  Rows for one
   --  state are tried top to bottom, and each state's last row has no
   --  guard, so every state takes the event: once no step follows, the
   --  cursor stays where it is and finds none.
   --!format off
   Table : constant SM.Transition_Table (1 .. Rows) :=
     [
      Not_Started + Next_Step (Has_Shared)  / First_Shared >= Background,
      Not_Started + Next_Step (Has_Mine)    / First_Mine   >= Own,
      Not_Started + Next_Step               / Run_Out      >= Not_Started,
      Background  + Next_Step (Shared_Left) / Step_Ahead   >= Background,
      Background  + Next_Step (Has_Mine)    / First_Mine   >= Own,
      Background  + Next_Step               / Run_Out      >= Background,
      Own         + Next_Step (Mine_Left)   / Step_Ahead   >= Own,
      Own         + Next_Step               / Run_Out      >= Own];
   --!format on

   ---------------------------------------------------------------------
   --  The machine's guards and acts.  A guard reads the cursor and an
   --  act writes it; which event arrived is the table's business, so
   --  neither reads Evt.
   ---------------------------------------------------------------------

   function Has_Steps (Steps : Ast.Step_Range) return Boolean
   is (not Ast.Step_Pool.Is_Empty (Steps));

   function Evaluate (G : Guard_Kind; Ctx : Cursor; Evt : Event) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      case G is
         when Always      =>
            return True;

         when Has_Shared  =>
            return Has_Steps (Ctx.Shared);

         when Has_Mine    =>
            return Has_Steps (Ctx.Mine);

         when Shared_Left =>
            return Ctx.Step < Ctx.Shared.Last;

         when Mine_Left   =>
            return Ctx.Step < Ctx.Mine.Last;
      end case;
   end Evaluate;

   --  The step after Step.  The last handle has none and stays; the
   --  guard on every Step_Ahead row has already ruled it out.
   function Following (Step : Ast.Step_Handle) return Ast.Step_Handle
   is (if Step < Ast.Step_Handle'Last then Step + 1 else Step);

   --  Ctx moved to Step, found when Step lies in the document.  The
   --  whole cursor is written at once, so its predicate holds.
   function Moved_To (Ctx : Cursor; Step : Ast.Step_Handle) return Cursor
   is ((Ctx with delta Step => Step, Found => Step in 1 .. Ctx.Count));

   procedure Execute (A : Act; Ctx : in out Cursor; Evt : Event) is
      pragma Unreferenced (Evt);
   begin
      case A is
         when Nothing      =>
            null;

         when First_Shared =>
            Ctx := Moved_To (Ctx, Ctx.Shared.First);

         when First_Mine   =>
            Ctx := Moved_To (Ctx, Ctx.Mine.First);

         when Step_Ahead   =>
            Ctx := Moved_To (Ctx, Following (Ctx.Step));

         when Run_Out      =>
            Ctx := (Ctx with delta Found => False);
      end case;
   end Execute;

   ---------------------------------------------------------------------
   --  The walk.
   ---------------------------------------------------------------------

   function Started
     (Shared, Mine : Ast.Step_Range; Step_Count : Ast.Step_Handle) return Walk
   is ((Count => Rows,
        M     => SM.Make (Table, Initial => Not_Started),
        Ctx   =>
          (Shared => Shared,
           Mine   => Mine,
           Count  => Step_Count,
           others => <>)));

   --  Whether a step was found is the cursor's to say, not the engine's.
   procedure Next (W : in out Walk) is
      Ignored_Handled : Boolean;  --  Every state takes the event
   begin
      Bundle.Process_Event (W, (Kind => E_Next_Step), Ignored_Handled);
   end Next;

end Fabula.Step_Walk;
