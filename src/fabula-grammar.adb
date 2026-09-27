with Sml.Machines.Operators;

package body Fabula.Grammar
  with SPARK_Mode
is

   package Parts renames Fabula.Line_Parts;

   package Op is new SM.Operators (Always => Always, Nothing => Nothing);
   use type Op.Ev, Op.Ev_Guard, Op.Ev_Built, Op.Source;

   subtype Ev is Op.Ev;

   Tags         : constant Ev := (Kind => E_Tags);
   Feature      : constant Ev := (Kind => E_Feature);
   Rule         : constant Ev := (Kind => E_Rule);
   Background   : constant Ev := (Kind => E_Background);
   Scenario     : constant Ev := (Kind => E_Scenario);
   Outline      : constant Ev := (Kind => E_Outline);
   Examples     : constant Ev := (Kind => E_Examples);
   Step         : constant Ev := (Kind => E_Step);
   Row          : constant Ev := (Kind => E_Row);
   Fence        : constant Ev := (Kind => E_Fence);
   Prose        : constant Ev := (Kind => E_Prose);
   Content      : constant Ev := (Kind => E_Content);
   End_Of_Input : constant Ev := (Kind => E_End_Of_Input);

   --  Each row reads:  From + Event (Guard) / Command >= To.  Rows for
   --  one state are tried top to bottom; a line no row takes is the
   --  state's refusal.  Blocks follow the state order.  Every step
   --  writes Arrived_In and the request; the line above each block
   --  names the other Work fields its commands write in Fabula.Parse.
   --!format off
   Table : constant SM.Transition_Table (1 .. Rows) :=
     [
      --  Before the Feature header: one tag line, then the header.
      --  Writes: Pending, Described, Feature_Seen, Owner, Doc_Line.
      Prologue     + Tags (Well_Formed)  / Collect_Tags   >= Feature_Tags,
      Prologue     + Tags                / Refuse_Tags    >= Failed,
      Prologue     + Feature             / Open_Feature   >= Feature_Head,
      Prologue     + Fence (Opens_Block) / Open_Stray_Doc >= In_Doc,
      Feature_Tags + Feature             / Open_Feature   >= Feature_Head,
      Feature_Tags + Fence (Opens_Block) / Open_Stray_Doc >= In_Doc,

      --  The feature's description ends at a tag, background, rule,
      --  scenario or outline line; every other line extends it.
      --  Writes: Pending, Described, Last_Is_Outline, Owner, Doc_Line.
      Feature_Head + Tags (Well_Formed)  / Collect_Tags    >= Block_Tags,
      Feature_Head + Tags                / Refuse_Tags     >= Failed,
      Feature_Head + Background          / Open_Background >= Background_Head,
      Feature_Head + Rule                / Open_Rule       >= Rule_Head,
      Feature_Head + Scenario            / Open_Scenario   >= Scenario_Head,
      Feature_Head + Outline             / Open_Outline    >= Outline_Head,
      Feature_Head + Feature             / Describe        >= Feature_Head,
      Feature_Head + Examples            / Describe        >= Feature_Head,
      Feature_Head + Step                / Describe        >= Feature_Head,
      Feature_Head + Row                 / Describe        >= Feature_Head,
      Feature_Head + Prose               / Describe        >= Feature_Head,
      Feature_Head + Fence (Opens_Block) / Absorb_Doc      >= In_Doc,
      Feature_Head + Fence                                 >= Feature_Head,
      Feature_Head + End_Of_Input                          >= Done,

      --  A rule's description ends at a tag, scenario or outline line;
      --  end of input before one is the state's refusal.
      --  Writes: Pending, Described, Last_Is_Outline, Owner, Doc_Line.
      Rule_Head + Tags (Well_Formed)  / Collect_Tags  >= Block_Tags,
      Rule_Head + Tags                / Refuse_Tags   >= Failed,
      Rule_Head + Scenario            / Open_Scenario >= Scenario_Head,
      Rule_Head + Outline             / Open_Outline  >= Outline_Head,
      Rule_Head + Feature             / Describe      >= Rule_Head,
      Rule_Head + Rule                / Describe      >= Rule_Head,
      Rule_Head + Background          / Describe      >= Rule_Head,
      Rule_Head + Examples            / Describe      >= Rule_Head,
      Rule_Head + Step                / Describe      >= Rule_Head,
      Rule_Head + Row                 / Describe      >= Rule_Head,
      Rule_Head + Prose               / Describe      >= Rule_Head,
      Rule_Head + Fence (Opens_Block) / Absorb_Doc    >= In_Doc,
      Rule_Head + Fence                               >= Rule_Head,

      --  A background, scenario or outline description ends at its
      --  first step, or at a tag, scenario, outline or rule line (an
      --  outline's also at an Examples line).  Each of those lines
      --  takes the row it takes after a step, so a block with no steps
      --  stays a block.  A Feature or Background line extends the
      --  description, as in the official Gherkin grammar, and so does
      --  an Examples line under a background.
      --  Writes: Takes_Argument, Owner, Doc_Line, Pending, Described,
      --  Last_Is_Outline.
      Background_Head + Step                / Add_Step      >= In_Steps,
      Background_Head + Tags (Well_Formed)  / Collect_Tags  >= Block_Tags,
      Background_Head + Tags                / Refuse_Tags   >= Failed,
      Background_Head + Scenario            / Open_Scenario >= Scenario_Head,
      Background_Head + Outline             / Open_Outline  >= Outline_Head,
      Background_Head + Rule                / Open_Rule     >= Rule_Head,
      Background_Head + Feature             / Describe      >= Background_Head,
      Background_Head + Background          / Describe      >= Background_Head,
      Background_Head + Examples            / Describe      >= Background_Head,
      Background_Head + Row                 / Describe      >= Background_Head,
      Background_Head + Prose               / Describe      >= Background_Head,
      Background_Head + Fence (Opens_Block) / Absorb_Doc    >= In_Doc,
      Background_Head + Fence                               >= Background_Head,
      Background_Head + End_Of_Input                        >= Done,

      --  An Examples line under a plain scenario is refused, as after
      --  a step.
      --  Writes: Takes_Argument, Owner, Doc_Line, Pending, Described,
      --  Last_Is_Outline.
      Scenario_Head + Step                / Add_Step      >= In_Steps,
      Scenario_Head + Tags (Well_Formed)  / Collect_Tags  >= Block_Tags,
      Scenario_Head + Tags                / Refuse_Tags   >= Failed,
      Scenario_Head + Scenario            / Open_Scenario >= Scenario_Head,
      Scenario_Head + Outline             / Open_Outline  >= Outline_Head,
      Scenario_Head + Rule                / Open_Rule     >= Rule_Head,
      Scenario_Head + Feature             / Describe      >= Scenario_Head,
      Scenario_Head + Background          / Describe      >= Scenario_Head,
      Scenario_Head + Row                 / Describe      >= Scenario_Head,
      Scenario_Head + Prose               / Describe      >= Scenario_Head,
      Scenario_Head + Fence (Opens_Block) / Absorb_Doc    >= In_Doc,
      Scenario_Head + Fence                               >= Scenario_Head,
      Scenario_Head + End_Of_Input                        >= Done,

      --  Writes: Takes_Argument, Owner, Doc_Line, Pending, Described,
      --  Last_Is_Outline.
      Outline_Head + Step                     / Add_Step      >= In_Steps,
      Outline_Head + Tags (Well_Formed)       / Collect_Tags  >= Block_Tags,
      Outline_Head + Tags                     / Refuse_Tags   >= Failed,
      Outline_Head + Scenario                 / Open_Scenario >= Scenario_Head,
      Outline_Head + Outline                  / Open_Outline  >= Outline_Head,
      Outline_Head + Rule                     / Open_Rule     >= Rule_Head,
      Outline_Head + Examples (After_Outline) / Open_Examples >= Examples_Head,
      Outline_Head + Feature                  / Describe      >= Outline_Head,
      Outline_Head + Background               / Describe      >= Outline_Head,
      Outline_Head + Row                      / Describe      >= Outline_Head,
      Outline_Head + Prose                    / Describe      >= Outline_Head,
      Outline_Head + Fence (Opens_Block)      / Absorb_Doc    >= In_Doc,
      Outline_Head + Fence                                    >= Outline_Head,
      Outline_Head + End_Of_Input                             >= Done,

      --  After a step: more steps, one argument for the last step (a
      --  doc string or a table), or the next block.
      --  Writes: Takes_Argument, Width, Owner, Doc_Line, Pending,
      --  Described, Last_Is_Outline.
      In_Steps + Step                     / Add_Step        >= In_Steps,
      In_Steps + Fence (Step_One_Liner)   / Add_Short_Doc   >= In_Steps,
      In_Steps + Fence (Step_Block)       / Open_Step_Doc   >= In_Doc,
      In_Steps + Fence (Opens_Block)      / Open_Stray_Doc  >= In_Doc,
      In_Steps + Row (Starts_Table)       / Open_Table      >= In_Table,
      In_Steps + Row (Takes_Argument)     / Refuse_Open_Row >= Failed,
      In_Steps + Tags (Well_Formed)       / Collect_Tags    >= Block_Tags,
      In_Steps + Tags                     / Refuse_Tags     >= Failed,
      In_Steps + Scenario                 / Open_Scenario   >= Scenario_Head,
      In_Steps + Outline                  / Open_Outline    >= Outline_Head,
      In_Steps + Rule                     / Open_Rule       >= Rule_Head,
      In_Steps + Examples (After_Outline) / Open_Examples   >= Examples_Head,
      In_Steps + End_Of_Input                               >= Done,

      --  A step's table: rows of one width; blank lines do not end it.
      --  Writes: Takes_Argument, Owner, Doc_Line, Pending, Described,
      --  Last_Is_Outline.
      In_Table + Row (Fits_Width)         / Add_Table_Row   >= In_Table,
      In_Table + Row (Closed_Row)         / Refuse_Ragged   >= Failed,
      In_Table + Row                      / Refuse_Open_Row >= Failed,
      In_Table + Step                     / Add_Step        >= In_Steps,
      In_Table + Fence (Opens_Block)      / Open_Stray_Doc  >= In_Doc,
      In_Table + Tags (Well_Formed)       / Collect_Tags    >= Block_Tags,
      In_Table + Tags                     / Refuse_Tags     >= Failed,
      In_Table + Scenario                 / Open_Scenario   >= Scenario_Head,
      In_Table + Outline                  / Open_Outline    >= Outline_Head,
      In_Table + Rule                     / Open_Rule       >= Rule_Head,
      In_Table + Examples (After_Outline) / Open_Examples   >= Examples_Head,
      In_Table + End_Of_Input                               >= Done,

      --  One tag line, then the scenario, outline or Examples it tags.
      --  Writes: Pending, Described, Last_Is_Outline, Owner, Doc_Line.
      Block_Tags + Scenario                 / Open_Scenario  >= Scenario_Head,
      Block_Tags + Outline                  / Open_Outline   >= Outline_Head,
      Block_Tags + Examples (After_Outline) / Open_Examples  >= Examples_Head,
      Block_Tags + Fence (Opens_Block)      / Open_Stray_Doc >= In_Doc,

      --  An Examples description ends at the table's first row, or at
      --  a tag, Examples, scenario, outline or rule line.  Each of
      --  those lines takes the row it takes after a data row, so a
      --  block with no rows stays a block.  A Feature, Background or
      --  step line extends the description.
      --  Writes: Width, Owner, Doc_Line, Pending, Described,
      --  Last_Is_Outline.
      Examples_Head + Row (Closed_Row)    / Add_Header_Row  >= Examples_Rows,
      Examples_Head + Row                 / Refuse_Open_Row >= Failed,
      Examples_Head + Tags (Well_Formed)  / Collect_Tags    >= Block_Tags,
      Examples_Head + Tags                / Refuse_Tags     >= Failed,
      Examples_Head + Examples            / Open_Examples   >= Examples_Head,
      Examples_Head + Scenario            / Open_Scenario   >= Scenario_Head,
      Examples_Head + Outline             / Open_Outline    >= Outline_Head,
      Examples_Head + Rule                / Open_Rule       >= Rule_Head,
      Examples_Head + Feature             / Describe        >= Examples_Head,
      Examples_Head + Background          / Describe        >= Examples_Head,
      Examples_Head + Step                / Describe        >= Examples_Head,
      Examples_Head + Prose               / Describe        >= Examples_Head,
      Examples_Head + Fence (Opens_Block) / Absorb_Doc      >= In_Doc,
      Examples_Head + Fence                                 >= Examples_Head,
      Examples_Head + End_Of_Input                          >= Done,

      --  Writes: Pending, Described, Last_Is_Outline, Owner, Doc_Line.
      Examples_Rows + Row (Fits_Width)    / Add_Example_Row >= Examples_Rows,
      Examples_Rows + Row (Closed_Row)    / Refuse_Ragged   >= Failed,
      Examples_Rows + Row                 / Refuse_Open_Row >= Failed,
      Examples_Rows + Tags (Well_Formed)  / Collect_Tags    >= Block_Tags,
      Examples_Rows + Tags                / Refuse_Tags     >= Failed,
      Examples_Rows + Examples            / Open_Examples   >= Examples_Head,
      Examples_Rows + Scenario            / Open_Scenario   >= Scenario_Head,
      Examples_Rows + Outline             / Open_Outline    >= Outline_Head,
      Examples_Rows + Rule                / Open_Rule       >= Rule_Head,
      Examples_Rows + Fence (Opens_Block) / Open_Stray_Doc  >= In_Doc,
      Examples_Rows + End_Of_Input                          >= Done,

      --  Inside a doc string every line is content until a fence run;
      --  the Owner guards resume the state the doc string interrupted.
      --  Writes: no Work field.
      In_Doc + Content (Step_Doc)     / Add_Doc_Line    >= In_Doc,
      In_Doc + Content                                  >= In_Doc,
      In_Doc + Fence (Step_Doc_Ends)                    >= In_Steps,
      In_Doc + Fence (For_Feature)                      >= Feature_Head,
      In_Doc + Fence (For_Rule)                         >= Rule_Head,
      In_Doc + Fence (For_Background)                   >= Background_Head,
      In_Doc + Fence (For_Scenario)                     >= Scenario_Head,
      In_Doc + Fence (For_Outline)                      >= Outline_Head,
      In_Doc + Fence (For_Examples)                     >= Examples_Head,
      --  A fence no owner takes refuses by where the file is: after
      --  the Feature header, or before it.
      In_Doc + Fence (Feature_Seen) / Refuse_Close_In_Feature     >= Failed,
      In_Doc + Fence                / Refuse_Close_Before_Feature >= Failed,
      In_Doc + End_Of_Input         / Refuse_Open_Doc             >= Failed];
   --!format on

   function Started return SM.Machine
   is (SM.Make (Table, Initial => Prologue));

   function Kind_For (Class : Scan.Line_Class) return Event_Kind
   is (case Class is
         when Scan.Tag_Line             => E_Tags,
         when Scan.Feature_Header       => E_Feature,
         when Scan.Rule_Header          => E_Rule,
         when Scan.Background_Header    => E_Background,
         when Scan.Scenario_Header      => E_Scenario,
         when Scan.Outline_Header       => E_Outline,
         when Scan.Examples_Header      => E_Examples,
         when Scan.Step_Line            => E_Step,
         when Scan.Table_Row            => E_Row,
         when Scan.Doc_Fence            => E_Fence,
         when Scan.Description          => E_Prose,
         when Scan.Blank | Scan.Comment => E_Prose);

   function Line_Event
     (Kind   : Event_Kind;
      Line   : String;
      Number : Source_Line;
      Class  : Scan.Classification) return Event
   is
      Result : Event :=
        (Kind   => Kind,
         Number => Number,
         Length => Line'Length,
         Text   => <>,
         Class  => Class);
   begin
      Result.Text (1 .. Line'Length) := Line;
      return Result;
   end Line_Event;

   ---------------------------------------------------------------------
   --  Guards.  Each reads the event's own line; a guard asked about a
   --  line of the wrong class answers False.
   ---------------------------------------------------------------------

   function Tags_Ok (Evt : Event) return Boolean
   is (Evt.Class.Class = Scan.Tag_Line
       and then Parts.Tags_Well_Formed
                  (Line_Of (Evt), Evt.Class.Body_First, Evt.Class.Body_Last));

   --  The first fence run after an opening fence's own three
   --  characters, or No_Position when the opening line does not close
   --  itself.
   function Closing_Run (Evt : Event) return Natural
   is (if Evt.Class.Class = Scan.Doc_Fence
       then
         Parts.Fence_Run
           (Line_Of (Evt), Evt.Class.Type_First, Evt.Class.Type_Last)
       else Parts.No_Position);

   function Opens (Evt : Event) return Boolean
   is (Evt.Class.Class = Scan.Doc_Fence
       and then Closing_Run (Evt) = Parts.No_Position);

   --  A one-line doc string with nothing after its closing run (the
   --  type slice is right-trimmed, so the run must end it).
   function Clean_One_Liner (Evt : Event) return Boolean
   is (Evt.Class.Class = Scan.Doc_Fence
       and then Closing_Run (Evt) /= Parts.No_Position
       and then Closing_Run (Evt) + (Scan.Fence_Length - 1)
                = Evt.Class.Type_Last);

   --  Inside a doc string: the line's first fence run has only blanks
   --  after it, so the closing line holds nothing else.
   function Clean_Close (Evt : Event) return Boolean
   is (declare
         Run : constant Natural :=
           Parts.Fence_Run (Line_Of (Evt), First_Column, Evt.Length);
       begin
         Run /= Parts.No_Position
         and then Parts.Only_Blank
                    (Line_Of (Evt), Run + Scan.Fence_Length, Evt.Length));

   function Evaluate (G : Guard_Kind; Ctx : Work; Evt : Event) return Boolean
   is (case G is
         when Always         => True,
         when Well_Formed    => Tags_Ok (Evt),
         when Opens_Block    => Opens (Evt),
         when Step_One_Liner =>
           Ctx.Takes_Argument and then Clean_One_Liner (Evt),
         when Step_Block     => Ctx.Takes_Argument and then Opens (Evt),
         when Starts_Table   =>
           Ctx.Takes_Argument and then Shape (Evt).Terminated,
         when Takes_Argument => Ctx.Takes_Argument,
         when Closed_Row     => Shape (Evt).Terminated,
         when Fits_Width     =>
           Shape (Evt).Terminated and then Shape (Evt).Cells = Ctx.Width,
         when After_Outline  => Ctx.Last_Is_Outline,
         when Step_Doc       => Ctx.Owner = In_Steps,
         when Step_Doc_Ends  =>
           Ctx.Owner = In_Steps and then Clean_Close (Evt),
         when Feature_Seen   => Ctx.Feature_Seen,
         when For_Feature    => Ctx.Owner = Feature_Head,
         when For_Rule       => Ctx.Owner = Rule_Head,
         when For_Background => Ctx.Owner = Background_Head,
         when For_Scenario   => Ctx.Owner = Scenario_Head,
         when For_Outline    => Ctx.Owner = Outline_Head,
         when For_Examples   => Ctx.Owner = Examples_Head);

   procedure Execute (A : Command; Ctx : in out Work; Evt : Event) is
      pragma Unreferenced (Evt);
   begin
      Ctx.Requests.Pending := A;
   end Execute;

end Fabula.Grammar;
