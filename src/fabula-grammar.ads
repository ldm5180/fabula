--  The parser machine: its states, the line events it folds, the
--  guards that read a line or the working state, the commands its
--  transitions request, and the transition table that is the Gherkin
--  grammar.  Actions only write a command into the context's request
--  block; Fabula.Parse performs it against the document.
with Fabula.Ast;
with Fabula.Limits;
with Fabula.Line_Parts;
with Fabula.Scan;
with Sml.Machines;
with Sml.Request_Block;

private package Fabula.Grammar
  with SPARK_Mode
is

   use type Scan.Line_Class;

   --  Feature_Tags and Block_Tags hold a line of tags waiting for the
   --  header it belongs to; the tags themselves wait in Work.Pending.
   --  A *_Head state is a header's description, which runs until one
   --  of the lines that end it in the reference interpreter.
   type State is
     (Prologue,
      Feature_Tags,
      Feature_Head,
      Rule_Head,
      Background_Head,
      Scenario_Head,
      Outline_Head,
      In_Steps,
      In_Table,
      In_Doc,
      Block_Tags,
      Examples_Head,
      Examples_Rows,
      Failed,
      Done);

   --  One event per Fabula.Scan class (Description is E_Prose), except
   --  that blank and comment lines raise none outside a doc string,
   --  and inside one every line is E_Content or, when it holds a fence
   --  run anywhere, E_Fence.
   type Event_Kind is
     (E_Tags,
      E_Feature,
      E_Rule,
      E_Background,
      E_Scenario,
      E_Outline,
      E_Examples,
      E_Step,
      E_Row,
      E_Fence,
      E_Prose,
      E_Content,
      E_End_Of_Input);

   subtype Line_Length is Scan.Line_Length;

   --  The length of an event that carries no line, at end of input.
   No_Text : constant Line_Length := 0;

   --  A table's cell count before its first row sets it.
   No_Width : constant Line_Length := Line_Parts.No_Cells;

   --  A line event: a bounded copy of the line, its number, and its
   --  classification, whose slices lie inside the line.  End of input
   --  carries no line.
   type Event is record
      Kind   : Event_Kind := E_End_Of_Input;
      Number : Line_Number := No_Line;
      Length : Line_Length := No_Text;
      Text   : String (1 .. Limits.Max_Line_Length) := [others => ' '];
      Class  : Scan.Classification;
   end record
   with Dynamic_Predicate => Scan.Slices_Fit (Event.Class, Event.Length);

   function Line_Of (Evt : Event) return String
   is (Evt.Text (1 .. Evt.Length))
   with
     Post =>
       Line_Of'Result'First = First_Column
       and then Line_Of'Result'Length = Evt.Length;

   --  The event a line of Class raises outside a doc string.
   function Kind_For (Class : Scan.Line_Class) return Event_Kind
   with Pre => Class not in Scan.Blank | Scan.Comment;

   function Line_Event
     (Kind   : Event_Kind;
      Line   : String;
      Number : Source_Line;
      Class  : Scan.Classification) return Event
   with
     Pre  =>
       Line'First = First_Column
       and then Line'Length <= Limits.Max_Line_Length
       and then Scan.Slices_Fit (Class, Line'Length),
     Post =>
       Line_Event'Result.Kind = Kind
       and then Line_Event'Result.Number = Number;

   function End_Event (Number : Line_Number) return Event
   is ((Number => Number, others => <>));

   --  A table row's shape: whether it closes, and its cell count.  Any
   --  other line has the shape of no row.
   function Shape (Evt : Event) return Line_Parts.Row_Shape
   is (if Evt.Class.Class = Scan.Table_Row
       then
         Line_Parts.Measure_Row
           (Line_Of (Evt), Evt.Class.Body_First, Evt.Class.Body_Last)
       else (others => <>));

   type Guard_Kind is
     (Always,
      Well_Formed,     --  the tag line holds only tags
      Opens_Block,     --  the fence does not also close on its own line
      Step_One_Liner,  --  a clean one-line doc string for the last step
      Step_Block,      --  a doc-string block for the last step
      Starts_Table,    --  a closed first row for the last step's table
      Takes_Argument,  --  the last step has no doc string or table yet
      Closed_Row,      --  the row ends with an unescaped '|'
      Fits_Width,      --  ... and has the table's cell count
      After_Outline,   --  the newest scenario is an outline
      Step_Doc,        --  the open doc string belongs to a step
      Step_Doc_Ends,   --  ... and nothing follows its closing run
      Feature_Seen,    --  the Feature header has been read
      For_Feature,
      For_Rule,
      For_Background,
      For_Scenario,
      For_Outline,
      For_Examples);
   --  The For_* guards read Owner: the header state a doc string that
   --  a description swallowed returns to when it closes.

   type Command is
     (Nothing,
      Collect_Tags,
      Open_Feature,
      Open_Background,
      Open_Rule,
      Open_Scenario,
      Open_Outline,
      Open_Examples,
      Describe,
      Add_Step,
      Open_Table,
      Add_Table_Row,
      Add_Header_Row,
      Add_Example_Row,
      Add_Short_Doc,
      Open_Step_Doc,
      Absorb_Doc,
      Open_Stray_Doc,
      Add_Doc_Line,
      Refuse_Tags,
      Refuse_Ragged,
      Refuse_Open_Row,
      Refuse_Close_In_Feature,
      Refuse_Close_Before_Feature,
      Refuse_Open_Doc);

   package Req is new Sml.Request_Block (Command => Command, None => Nothing);

   --  The parser's working state, read by the guards.  Owner is the
   --  state an open doc string returns to: In_Steps for a step's own,
   --  a *_Head state for one a description swallowed, Failed for one
   --  that is refused when it closes.  Arrived_In is the state the
   --  current event arrived in, so a doc string can save it as Owner.
   type Work is record
      Requests        : Req.Block;
      Arrived_In      : State := Prologue;
      Owner           : State := Failed;
      Doc_Line        : Line_Number := No_Line;
      Takes_Argument  : Boolean := False;
      Width           : Line_Length := No_Width;
      Last_Is_Outline : Boolean := False;
      Feature_Seen    : Boolean := False;
      Described       : Ast.Block_Kind := Ast.Feature_Block;
      Pending         : Ast.Tag_Range;
   end record;

   function Kind_Of (Evt : Event) return Event_Kind
   is (Evt.Kind);

   function Evaluate (G : Guard_Kind; Ctx : Work; Evt : Event) return Boolean;

   --  Records A as the pending command; the machine does nothing else.
   procedure Execute (A : Command; Ctx : in out Work; Evt : Event);

   package SM is new
     Sml.Machines
       (State       => State,
        Event_Kind  => Event_Kind,
        Event       => Event,
        Context     => Work,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Command,
        Kind_Of     => Kind_Of,
        Evaluate    => Evaluate,
        Execute     => Execute);

   Rows : constant := 138;
   --  The transition table's length; a Parser embeds a machine of it.

   function Started return SM.Machine
   with
     Post =>
       Started'Result.Count = Rows
       and then SM.State_Of (Started'Result) = Prologue;

end Fabula.Grammar;
