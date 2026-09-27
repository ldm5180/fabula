--  The box world: the reference interpreter's own example, ported step
--  for step.  Each scenario gets one fresh Box_Context record, which
--  holds the box and a note.
with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;

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

   type Item_Text is record
      Data : String (1 .. Max_Item_Length) := [others => ' '];
      Len  : Natural range 0 .. Max_Item_Length := 0;
   end record;

   type Item_List is array (1 .. Max_Items) of Item_Text;

   --  The box, plus Note: one text value that holds either the customs
   --  declaration's content type or the shipping label.  No scenario
   --  needs both at once.
   type Box_Context is record
      Has_Label  : Boolean := False;
      Label      : String (1 .. Max_Label_Length) := [others => ' '];
      Label_Len  : Natural range 0 .. Max_Label_Length := 0;
      Items      : Item_List;
      Item_Count : Natural range 0 .. Max_Items := 0;
      Weight     : Natural := 0;
      Is_Open    : Boolean := True;
      Note       : String (1 .. Max_Note_Length) := [others => ' '];
      Note_Len   : Natural range 0 .. Max_Note_Length := 0;
   end record;

   package Steps is new
     Fabula.Registry
       (Step_Kind => Step_Kind,
        Hook_Kind => Hook_Kind,
        Context   => Box_Context);

   use Steps;

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
