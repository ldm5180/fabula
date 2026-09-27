with Fabula.Line_Parts;
with Fabula.Scan;

package body Fabula.Parse
  with SPARK_Mode
is

   package G renames Fabula.Grammar;
   package Parts renames Fabula.Line_Parts;

   use type Fabula.Scan.Line_Class;
   use type G.State;
   use type G.Command;

   type Table_Kind is (Step_Table, Examples_Table);

   function Stopped (P : Parser) return Boolean
   is (P.Error.Kind /= None or else G.SM.State_Of (P.Machine) = G.Done);

   --  The first refusal sticks; later ones are dropped.
   procedure Refuse (P : in out Parser; Kind : Error_Kind; Line : Line_Number)
   is
   begin
      if P.Error.Kind = None then
         P.Error := (Kind => Kind, Line => Line);
      end if;
   end Refuse;

   procedure Check (P : in out Parser; Ok : Boolean; Line : Line_Number) is
   begin
      if not Ok then
         Refuse (P, Pool_Exhausted, Line);
      end if;
   end Check;

   --  What a line no transition takes means, by the state it met.
   function Unhandled (S : G.State) return Error_Kind
   is (case S is
         when G.Prologue | G.Feature_Tags => Expected_Feature,
         when others                      => Expected_Scenario);

   ---------------------------------------------------------------------
   --  Sticky arena writes.  Each is Fabula.Ast's own write, made only
   --  while Ok holds.  Ok is the sticky flag: once one write finds its
   --  arena or pool full it stays False and every later write of the
   --  same command is skipped, so a command reads as a straight run of
   --  writes and Check reports the failure once, at the end.
   ---------------------------------------------------------------------

   procedure Append_Text
     (Doc    : in out Fabula.Ast.Document;
      Source : String;
      Result : out Fabula.Ast.Slice;
      Ok     : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      Result := Fabula.Ast.Empty_Slice;
      if Ok then
         Fabula.Ast.Append_Text (Doc, Source, Result, Ok);
      end if;
   end Append_Text;

   procedure Add_Tag
     (Doc     : in out Fabula.Ast.Document;
      Text    : Fabula.Ast.Slice;
      Pending : in out Fabula.Ast.Tag_Range;
      Ok      : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if Ok then
         Fabula.Ast.Add_Tag (Doc, Text, Pending, Ok);
      end if;
   end Add_Tag;

   procedure Add_Step
     (Doc     : in out Fabula.Ast.Document;
      Keyword : Fabula.Scan.Step_Keyword;
      Text    : Fabula.Ast.Slice;
      Line    : Line_Number;
      Ok      : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if Ok then
         Fabula.Ast.Add_Step (Doc, Keyword, Text, Line, Ok);
      end if;
   end Add_Step;

   procedure Add_Doc_String
     (Doc   : in out Fabula.Ast.Document;
      Kind  : Fabula.Scan.Fence_Kind;
      CType : Fabula.Ast.Slice;
      Line  : Line_Number;
      Ok    : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if Ok then
         Fabula.Ast.Add_Doc_String (Doc, Kind, CType, Line, Ok);
      end if;
   end Add_Doc_String;

   procedure Add_Doc_Line
     (Doc  : in out Fabula.Ast.Document;
      Text : Fabula.Ast.Slice;
      Ok   : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if Ok then
         Fabula.Ast.Add_Doc_Line (Doc, Text, Ok);
      end if;
   end Add_Doc_Line;

   procedure Add_Table (Doc : in out Fabula.Ast.Document; Ok : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if Ok then
         Fabula.Ast.Add_Table (Doc, Ok);
      end if;
   end Add_Table;

   --  Appends a new row, numbered Line, to Kind's pool.
   procedure Append_Row
     (Doc  : in out Fabula.Ast.Document;
      Kind : Table_Kind;
      Line : Line_Number;
      Ok   : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if not Ok then
         return;
      end if;
      case Kind is
         when Step_Table     =>
            Fabula.Ast.Add_Table_Row (Doc, Line, Ok);

         when Examples_Table =>
            Fabula.Ast.Add_Examples_Row (Doc, Line, Ok);
      end case;
   end Append_Row;

   --  Adds Text as a cell of the newest row of Kind's pool.
   procedure Add_Cell
     (Doc  : in out Fabula.Ast.Document;
      Text : Fabula.Ast.Slice;
      Kind : Table_Kind;
      Ok   : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if not Ok then
         return;
      end if;
      case Kind is
         when Step_Table     =>
            Fabula.Ast.Add_Table_Cell (Doc, Text, Ok);

         when Examples_Table =>
            Fabula.Ast.Add_Examples_Cell (Doc, Text, Ok);
      end case;
   end Add_Cell;

   ---------------------------------------------------------------------
   --  Block headers.
   ---------------------------------------------------------------------

   function Is_Header (Evt : G.Event) return Boolean
   is (Evt.Class.Class
       in Fabula.Scan.Feature_Header .. Fabula.Scan.Examples_Header);

   --  The header's keyword, its colon dropped.
   function Keyword_Text (Evt : G.Event) return String
   is (declare
         Line : constant String := G.Line_Of (Evt);
         Key  : constant Parts.Span :=
           Parts.Keyword_Of
             (Line,
              Evt.Class.Indent + 1,
              Natural'Max (Evt.Class.Title_First - 1, Evt.Class.Indent));
       begin
         Line (Key.First .. Key.Last))
   with Pre => Is_Header (Evt);

   function Title_Text (Evt : G.Event) return String
   is (G.Line_Of (Evt) (Evt.Class.Title_First .. Evt.Class.Title_Last))
   with Pre => Is_Header (Evt);

   --  Appends the header's keyword and title.
   procedure Make_Head
     (Doc  : in out Fabula.Ast.Document;
      Evt  : G.Event;
      Head : out Fabula.Ast.Header;
      Ok   : in out Boolean) is
   begin
      Head := (Line => Evt.Number, others => <>);
      if Is_Header (Evt) then
         Append_Text (Doc, Keyword_Text (Evt), Head.Keyword, Ok);
         Append_Text (Doc, Title_Text (Evt), Head.Name, Ok);
      end if;
   end Make_Head;

   function Described_By (Cmd : G.Command) return Fabula.Ast.Block_Kind
   is (case Cmd is
         when G.Open_Background                => Fabula.Ast.Background_Block,
         when G.Open_Rule                      => Fabula.Ast.Rule_Block,
         when G.Open_Scenario | G.Open_Outline => Fabula.Ast.Scenario_Block,
         when G.Open_Examples                  => Fabula.Ast.Examples_Block,
         when others                           => Fabula.Ast.Feature_Block);

   --  Attaches a new block node; the pending tags go to it.
   procedure Attach
     (P    : in out Parser;
      Doc  : in out Fabula.Ast.Document;
      Cmd  : G.Command;
      Head : Fabula.Ast.Header;
      Ok   : in out Boolean)
   is
      Tags : constant Fabula.Ast.Tag_Range := P.Work.Pending;
   begin
      if not Ok then
         return;
      end if;
      case Cmd is
         when G.Open_Feature    =>
            Fabula.Ast.Set_Feature (Doc, Head, Tags);
            P.Work.Feature_Seen := True;

         when G.Open_Background =>
            Fabula.Ast.Set_Background (Doc, Head);

         when G.Open_Rule       =>
            Fabula.Ast.Add_Rule (Doc, Head, Ok);

         when G.Open_Scenario   =>
            Fabula.Ast.Add_Scenario (Doc, Fabula.Ast.Plain, Head, Tags, Ok);

         when G.Open_Outline    =>
            Fabula.Ast.Add_Scenario (Doc, Fabula.Ast.Outline, Head, Tags, Ok);

         when G.Open_Examples   =>
            Fabula.Ast.Add_Examples (Doc, Head, Tags, Ok);

         when others            =>
            null;
      end case;
   end Attach;

   procedure Open_Block
     (P   : in out Parser;
      Doc : in out Fabula.Ast.Document;
      Evt : G.Event;
      Cmd : G.Command)
   is
      Head : Fabula.Ast.Header;
      Ok   : Boolean := True;
   begin
      Make_Head (Doc, Evt, Head, Ok);
      Attach (P, Doc, Cmd, Head, Ok);
      P.Work.Pending := (others => <>);
      P.Work.Described := Described_By (Cmd);
      if Cmd in G.Open_Scenario | G.Open_Outline then
         P.Work.Last_Is_Outline := Cmd = G.Open_Outline;
      end if;
      Check (P, Ok, Evt.Number);
   end Open_Block;

   ---------------------------------------------------------------------
   --  Tags, descriptions and steps.
   ---------------------------------------------------------------------

   --  Appends every tag on the line, each with its '@'.
   procedure Collect_Tags
     (P : in out Parser; Doc : in out Fabula.Ast.Document; Evt : G.Event)
   is
      Line : constant String := G.Line_Of (Evt);
      Pos  : Positive;
      Tag  : Parts.Span;
      Text : Fabula.Ast.Slice;
      Ok   : Boolean := True;
   begin
      if Evt.Class.Class /= Fabula.Scan.Tag_Line then
         return;
      end if;
      Pos := Evt.Class.Body_First;
      while Ok and then Pos <= Evt.Class.Body_Last loop
         pragma Loop_Variant (Increases => Pos);
         Tag := Parts.Next_Tag (Line, Pos, Evt.Class.Body_Last);
         exit when Tag.Last < Tag.First;
         Append_Text (Doc, Line (Tag.First .. Tag.Last), Text, Ok);
         Add_Tag (Doc, Text, P.Work.Pending, Ok);
         Pos := Tag.Last + 1;
      end loop;
      Check (P, Ok, Evt.Number);
   end Collect_Tags;

   --  Extends the newest header's description with the trimmed line.
   procedure Describe
     (P : in out Parser; Doc : in out Fabula.Ast.Document; Evt : G.Event)
   is
      Line : constant String := G.Line_Of (Evt);
      Kept : constant Parts.Span :=
        Parts.Trimmed (Line, Line'First, Line'Last);
      Ok   : Boolean;
   begin
      Fabula.Ast.Describe
        (Doc, P.Work.Described, Line (Kept.First .. Kept.Last), Ok);
      Check (P, Ok, Evt.Number);
   end Describe;

   procedure Store_Step
     (P : in out Parser; Doc : in out Fabula.Ast.Document; Evt : G.Event)
   is
      Line : constant String := G.Line_Of (Evt);
      Text : Fabula.Ast.Slice;
      Ok   : Boolean := True;
   begin
      if Evt.Class.Class /= Fabula.Scan.Step_Line then
         return;
      end if;
      Append_Text
        (Doc, Line (Evt.Class.Text_First .. Evt.Class.Text_Last), Text, Ok);
      Add_Step (Doc, Evt.Class.Keyword, Text, Evt.Number, Ok);
      P.Work.Takes_Argument := True;
      Check (P, Ok, Evt.Number);
   end Store_Step;

   ---------------------------------------------------------------------
   --  Tables.
   ---------------------------------------------------------------------

   --  A cell's stored text: a step table drops one pair of surrounding
   --  quotes, an Examples table keeps the cell as written.
   function Stored
     (Line : String; Cell : Parts.Span; Kind : Table_Kind) return Parts.Span
   is (if Kind = Step_Table then Parts.Unquoted (Line, Cell) else Cell)
   with Pre => Parts.Is_Line (Line) and then Parts.Within (Line, Cell);

   --  Appends every cell of the row to the newest row of Kind's pool.
   procedure Add_Cells
     (Doc  : in out Fabula.Ast.Document;
      Evt  : G.Event;
      Kind : Table_Kind;
      Ok   : in out Boolean)
   is
      Line : constant String := G.Line_Of (Evt);
      Pos  : Positive;
      Next : Parts.Cell;
      Keep : Parts.Span;
      Text : Fabula.Ast.Slice;
   begin
      if Evt.Class.Class /= Fabula.Scan.Table_Row then
         return;
      end if;
      Pos := Evt.Class.Body_First + 1;
      while Ok and then Pos <= Evt.Class.Body_Last loop
         pragma Loop_Variant (Increases => Pos);
         Next := Parts.Next_Cell (Line, Pos, Evt.Class.Body_Last);
         exit when Next.Stop = Parts.No_Position;
         Keep := Stored (Line, Next.Text, Kind);
         Append_Text (Doc, Line (Keep.First .. Keep.Last), Text, Ok);
         Add_Cell (Doc, Text, Kind, Ok);
         Pos := Next.Stop + 1;
      end loop;
   end Add_Cells;

   --  A step's first table row opens its table; the step then takes no
   --  further argument.
   procedure Open_Step_Table
     (P   : in out Parser;
      Doc : in out Fabula.Ast.Document;
      Cmd : G.Command;
      Ok  : in out Boolean)
   with Post => (if not Ok'Old then not Ok)
   is
   begin
      if Cmd = G.Open_Table then
         Add_Table (Doc, Ok);
         P.Work.Takes_Argument := False;
      end if;
   end Open_Step_Table;

   --  A table's first row sets the cell count every later row must
   --  match.
   procedure Record_Width (P : in out Parser; Evt : G.Event; Cmd : G.Command)
   is
   begin
      if Cmd in G.Open_Table | G.Add_Header_Row then
         P.Work.Width := G.Shape (Evt).Cells;
      end if;
   end Record_Width;

   procedure Add_Row
     (P   : in out Parser;
      Doc : in out Fabula.Ast.Document;
      Evt : G.Event;
      Cmd : G.Command)
   is
      Kind : constant Table_Kind :=
        (if Cmd in G.Open_Table | G.Add_Table_Row
         then Step_Table
         else Examples_Table);
      Ok   : Boolean := True;
   begin
      Open_Step_Table (P, Doc, Cmd, Ok);
      Append_Row (Doc, Kind, Evt.Number, Ok);
      Add_Cells (Doc, Evt, Kind, Ok);
      Record_Width (P, Evt, Cmd);
      Check (P, Ok, Evt.Number);
   end Add_Row;

   ---------------------------------------------------------------------
   --  Doc strings.
   ---------------------------------------------------------------------

   --  Gives the last step a doc string whose content type is the text
   --  after the opening fence.
   procedure Store_Doc_String
     (P : in out Parser; Doc : in out Fabula.Ast.Document; Evt : G.Event)
   is
      Line  : constant String := G.Line_Of (Evt);
      CType : Fabula.Ast.Slice;
      Ok    : Boolean := True;
   begin
      P.Work.Takes_Argument := False;
      if Evt.Class.Class = Fabula.Scan.Doc_Fence then
         Append_Text
           (Doc,
            Line (Evt.Class.Type_First .. Evt.Class.Type_Last),
            CType,
            Ok);
         Add_Doc_String (Doc, Evt.Class.Fence, CType, Evt.Number, Ok);
      end if;
      Check (P, Ok, Evt.Number);
   end Store_Doc_String;

   procedure Store_Doc_Line
     (P : in out Parser; Doc : in out Fabula.Ast.Document; Evt : G.Event)
   is
      Line : constant String := G.Line_Of (Evt);
      Kept : constant Parts.Span :=
        Parts.Trimmed (Line, Line'First, Line'Last);
      Text : Fabula.Ast.Slice;
      Ok   : Boolean := True;
   begin
      Append_Text (Doc, Line (Kept.First .. Kept.Last), Text, Ok);
      Add_Doc_Line (Doc, Text, Ok);
      Check (P, Ok, Evt.Number);
   end Store_Doc_Line;

   --  A doc string opens: Owner is where the machine resumes when it
   --  closes; Line is where an unterminated one is reported.
   procedure Set_Owner (P : in out Parser; Owner : G.State; Line : Line_Number)
   is
   begin
      P.Work.Owner := Owner;
      P.Work.Doc_Line := Line;
   end Set_Owner;

   procedure Doc_Command
     (P   : in out Parser;
      Doc : in out Fabula.Ast.Document;
      Evt : G.Event;
      Cmd : G.Command) is
   begin
      case Cmd is
         when G.Add_Short_Doc | G.Open_Step_Doc =>
            Store_Doc_String (P, Doc, Evt);
            Set_Owner (P, G.In_Steps, Evt.Number);

         when G.Absorb_Doc                      =>
            Set_Owner (P, P.Work.Arrived_In, Evt.Number);

         when G.Add_Doc_Line                    =>
            Store_Doc_Line (P, Doc, Evt);

         when others                            =>
            Set_Owner (P, G.Failed, Evt.Number);
      end case;
   end Doc_Command;

   ---------------------------------------------------------------------
   --  Refusals and the engine.
   ---------------------------------------------------------------------

   procedure Refuse_Command (P : in out Parser; Evt : G.Event; Cmd : G.Command)
   is
   begin
      case Cmd is
         when G.Refuse_Tags                 =>
            Refuse (P, Tag_Line_Malformed, Evt.Number);

         when G.Refuse_Ragged               =>
            Refuse (P, Ragged_Table, Evt.Number);

         when G.Refuse_Open_Row             =>
            Refuse (P, Unterminated_Table_Row, Evt.Number);

         when G.Refuse_Close_In_Feature     =>
            Refuse (P, Expected_Scenario, Evt.Number);

         when G.Refuse_Close_Before_Feature =>
            Refuse (P, Expected_Feature, Evt.Number);

         when others                        =>
            Refuse (P, Unterminated_Doc_String, P.Work.Doc_Line);
      end case;
   end Refuse_Command;

   --  Performs the command the transition just requested.
   procedure Perform
     (P : in out Parser; Doc : in out Fabula.Ast.Document; Evt : G.Event)
   is
      Cmd : constant G.Command := P.Work.Requests.Pending;
   begin
      P.Work.Requests.Pending := G.Nothing;
      case Cmd is
         when G.Nothing                          =>
            null;

         when G.Collect_Tags                     =>
            Collect_Tags (P, Doc, Evt);

         when G.Open_Feature .. G.Open_Examples  =>
            Open_Block (P, Doc, Evt, Cmd);

         when G.Describe                         =>
            Describe (P, Doc, Evt);

         when G.Add_Step                         =>
            Store_Step (P, Doc, Evt);

         when G.Open_Table .. G.Add_Example_Row  =>
            Add_Row (P, Doc, Evt, Cmd);

         when G.Add_Short_Doc .. G.Add_Doc_Line  =>
            Doc_Command (P, Doc, Evt, Cmd);

         when G.Refuse_Tags .. G.Refuse_Open_Doc =>
            Refuse_Command (P, Evt, Cmd);
      end case;
   end Perform;

   --  One machine step: an event no row takes is the state's refusal.
   procedure Step
     (P : in out Parser; Doc : in out Fabula.Ast.Document; Evt : G.Event)
   is
      Handled : Boolean;
   begin
      P.Work.Arrived_In := G.SM.State_Of (P.Machine);
      P.Work.Requests.Pending := G.Nothing;
      G.SM.Process_Event (P.Machine, P.Work, Evt, Handled);
      if Handled then
         Perform (P, Doc, Evt);
      else
         Refuse (P, Unhandled (P.Work.Arrived_In), Evt.Number);
      end if;
   end Step;

   procedure Start (P : out Parser; Doc : in out Fabula.Ast.Document) is
   begin
      P :=
        (Machine   => G.Started,
         Work      => (others => <>),
         Error     => (others => <>),
         Last_Line => No_Line);
      Fabula.Ast.Clear (Doc);
   end Start;

   --  Inside a doc string the class is overridden: a line is content,
   --  or it closes the block when it holds a fence run anywhere.
   function Doc_Kind (Line : String) return G.Event_Kind
   is (if Parts.Fence_Run (Line, Line'First, Line'Length) /= Parts.No_Position
       then G.E_Fence
       else G.E_Content)
   with Pre => Parts.Is_Line (Line);

   procedure Feed
     (P      : in out Parser;
      Doc    : in out Fabula.Ast.Document;
      Line   : String;
      Number : Source_Line) is
   begin
      if Stopped (P) then
         return;
      end if;
      P.Last_Line := Number;
      declare
         Class : constant Fabula.Scan.Classification :=
           Fabula.Scan.Classify (Line);
      begin
         if G.SM.State_Of (P.Machine) = G.In_Doc then
            Step (P, Doc, G.Line_Event (Doc_Kind (Line), Line, Number, Class));
         elsif Class.Class not in Fabula.Scan.Blank | Fabula.Scan.Comment then
            Step
              (P,
               Doc,
               G.Line_Event (G.Kind_For (Class.Class), Line, Number, Class));
         end if;
      end;
   end Feed;

   procedure Finish (P : in out Parser; Doc : in out Fabula.Ast.Document) is
   begin
      if not Stopped (P) then
         --  An "at end" refusal names the file's true last line
         --  (P.Last_Line); the reference interpreter's own message names
         --  one past it (N+1) instead. A deliberate divergence, not a
         --  fix target.
         Step (P, Doc, G.End_Event (P.Last_Line));
      end if;
   end Finish;

end Fabula.Parse;
