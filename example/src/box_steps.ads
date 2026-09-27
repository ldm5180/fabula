--  The box world: the reference interpreter's own example, ported step
--  for step.  Each scenario gets one fresh Box_Context record, which
--  holds the box and a note.
with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;
with Fabula.Texts;

package Box_Steps
  with SPARK_Mode => Off
is

   type Step_Kind is
     (Init_Box,
      Init_Labeled_Box,
      Take_Customs_Declaration,
      Check_Customs_Declaration_Type,
      Take_Shipping_Label,
      Check_Shipping_Label,
      Add_Item,
      Print_Coordinates,
      Add_Items_Raw,
      Add_Items_Hashes,
      Add_Item_Rows_Hash,
      Check_Labeled,
      Check_Item_At,
      Check_Count,
      Check_Contains,
      Check_Count_Alt);

   type Hook_Kind is
     (Skip_On_Tag,
      Ignore_On_Tag,
      Fail_Before,
      Fail_After,
      Close_Box,
      Ship_Box,
      Ignore_After_Tag);

   Max_Items        : constant := 1_024;
   --  At 64 the port silently truncated the reference interpreter's
   --  100-item box scenario and failed it where the interpreter
   --  passes; the byte gate over that file caught the undercount.
   Max_Item_Length  : constant := 128;
   Max_Label_Length : constant := 128;
   Max_Note_Length  : constant := 2_048;

   subtype Item_Text is Fabula.Texts.Bounded_Text (Max_Item_Length);

   type Item_List is array (1 .. Max_Items) of Item_Text;

   --  How many items a box holds; an empty box holds none.
   subtype Item_Count_Range is Natural range 0 .. Max_Items;

   No_Items : constant Item_Count_Range := 0;

   --  The box, plus Note: one text value that holds either the customs
   --  declaration's content type or the shipping label.  No scenario
   --  needs both at once.  Has_Label says the labeled box was built; the
   --  label itself may still be empty.
   type Box_Context is record
      Has_Label  : Boolean := False;
      Label      : Fabula.Texts.Bounded_Text (Max_Label_Length);
      Items      : Item_List;
      Item_Count : Item_Count_Range := No_Items;
      --  No step reads it: it shows an After hook (Close_Box) that edits
      --  the scenario's context, as the reference interpreter's own box
      --  example does.
      Is_Open    : Boolean := True;
      Note       : Fabula.Texts.Bounded_Text (Max_Note_Length);
   end record;

   package Steps is new
     Fabula.Registry
       (Step_Kind => Step_Kind,
        Hook_Kind => Hook_Kind,
        Context   => Box_Context);

   use Steps;

   --  Where each value sits among a step's captures, named by its role
   --  in the patterns below; the body reads each capture by these names.
   --    "I place {int} x {string} in it":  a count, then an item
   Count_Capture    : constant := 1;
   Item_Capture     : constant := 2;
   --    "The {int}. item is {string}":  an index, then an item
   Index_Capture    : constant := 1;
   --    "... should be {string}", "... should equal {string}"
   Expected_Capture : constant := 1;
   --    "{word} is/are in the box"
   Sought_Capture   : constant := 1;
   --    "I have {int},{int} as coordinates"
   X_Capture        : constant := 1;
   Y_Capture        : constant := 2;
   --    "The box contains {int} item(s)" and "{int} item(s) is/are
   --    {string}" read Count_Capture, and the latter Item_Capture.

   Step_Defs : constant Steps.Step_Table :=
     [Step ("An empty box") >= Init_Box,
      Step ("An empty box with a label") >= Init_Labeled_Box,
      Step ("The box gets a customs declaration") >= Take_Customs_Declaration,
      Step ("The customs declaration content type should be {string}")
      >= Check_Customs_Declaration_Type,
      Step ("The box gets a shipping label") >= Take_Shipping_Label,
      Step ("The shipping label should equal {string}")
      >= Check_Shipping_Label,
      Step ("I place {int} x {string} in it") >= Add_Item,
      Step ("I have {int},{int} as coordinates") >= Print_Coordinates,
      Step ("I add all items with the raw function:") >= Add_Items_Raw,
      Step ("I add all items with the hashes function:") >= Add_Items_Hashes,
      Step ("I add the following item with the rows_hash function:")
      >= Add_Item_Rows_Hash,
      Step ("The box is labeled") >= Check_Labeled,
      Step ("The {int}. item is {string}") >= Check_Item_At,
      Step ("The box contains {int} item(s)") >= Check_Count,
      Step ("{word} is/are in the box") >= Check_Contains,
      Step ("{int} item(s) is/are {string}") >= Check_Count_Alt];

   Hook_Defs : constant Steps.Hook_Table :=
     [Before ("@skip") >= Skip_On_Tag,
      Before ("@ignore") >= Ignore_On_Tag,
      Before ("@will_fail_before") >= Fail_Before,
      After ("@will_fail_after") >= Fail_After,
      After >= Close_Box,
      After ("@ship or @important") >= Ship_Box,
      --  Not a port of the reference interpreter's own hooks -- an
      --  After hook that ignores, to drive the fixture for a scenario
      --  dropped once its steps already ran.
      After ("@ignore_after") >= Ignore_After_Tag];

   procedure Execute
     (S    : Step_Kind;
      Ctx  : in out Box_Context;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

   procedure Run_Hook
     (H    : Hook_Kind;
      Ctx  : in out Box_Context;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

end Box_Steps;
