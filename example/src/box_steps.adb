with Ada.Strings.Fixed;
with Ada.Text_IO;

with Fabula.Check.Ints;
with Fabula.Numbers;

package body Box_Steps
  with SPARK_Mode => Off
is

   package Texts renames Fabula.Texts;

   --  A number read from the step text: a value, or the reason there is
   --  none.  Value may be read only where Ok holds; a step fails a read
   --  that did not succeed with Fabula.Check.Ints.Fail_Read.
   subtype Number is Fabula.Numbers.Integer_Reads.Read;

   ---------------------------------------------------------------------
   --  The box.
   ---------------------------------------------------------------------

   --  Puts Count copies of Item in the box, as many as it holds; none
   --  for a count below one.
   procedure Put_Items
     (Ctx : in out Box_Context; Item : String; Count : Integer) is
   begin
      for I in 1 .. Count loop
         exit when Ctx.Item_Count = Max_Items;
         Ctx.Item_Count := Ctx.Item_Count + 1;
         Ctx.Items (Ctx.Item_Count) := Texts.Truncated (Item, Max_Item_Length);
      end loop;
   end Put_Items;

   --  What a failed read of an item count names.
   Item_Count_Name : constant String := "The item count";

   --  Adds Count copies of Item.  A count that did not read fails the
   --  step and adds nothing.
   procedure Add_Items
     (Ctx   : in out Box_Context;
      R     : in out Fabula.Check.Outcome;
      Item  : String;
      Count : Number) is
   begin
      if Count.Ok then
         Put_Items (Ctx, Item, Count.Value);
      else
         Fabula.Check.Ints.Fail_Read (R, Count.Error, Item_Count_Name);
      end if;
   end Add_Items;

   function Item_At (Ctx : Box_Context; Index : Integer) return String
   is (if Index in 1 .. Ctx.Item_Count
       then Texts.Value (Ctx.Items (Index))
       else "");

   function Count_Of (Ctx : Box_Context; Item : String) return Natural is
      Total : Natural := No_Items;
   begin
      for I in 1 .. Ctx.Item_Count loop
         if Texts.Value (Ctx.Items (I)) = Item then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Count_Of;

   function Contains (Ctx : Box_Context; Item : String) return Boolean
   is (Count_Of (Ctx, Item) > No_Items);

   --  The reference interpreter's own labeled-box constructor takes its
   --  label only the first time --
   --  a later call, even with a different label, returns the box
   --  already built and ignores the new argument.  Ported as a guard,
   --  not a fabula-side reinterpretation: fabula's one flat Box_Context
   --  has no other way to express "already built".
   procedure Set_Label (Ctx : in out Box_Context; Value : String) is
   begin
      if Ctx.Has_Label then
         return;
      end if;
      Ctx.Label := Texts.Truncated (Value, Max_Label_Length);
      Ctx.Has_Label := True;
   end Set_Label;

   function Note_Value (Ctx : Box_Context) return String
   is (Texts.Value (Ctx.Note));

   procedure Set_Note (Ctx : in out Box_Context; Value : String) is
   begin
      Ctx.Note := Texts.Truncated (Value, Max_Note_Length);
   end Set_Note;

   --  N as the reference interpreter prints it, with no leading blank.
   function Trimmed (N : Integer) return String
   is (Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left));

   ---------------------------------------------------------------------
   --  Steps.  The six two-argument asserts keep the reference
   --  interpreter's own positional argument order: four are expected-
   --  first (Check_Customs_Declaration_Type, Check_Shipping_Label,
   --  Check_Item_At, Check_Count_Alt); Init_Box and Check_Count are
   --  actual-first, ported unchanged.
   ---------------------------------------------------------------------

   subtype Setup_Kind is Step_Kind range Init_Box .. Print_Coordinates;
   subtype Table_Kind is Step_Kind range Add_Items_Raw .. Add_Item_Rows_Hash;
   subtype Check_Kind is Step_Kind range Check_Labeled .. Check_Count_Alt;

   --  Each capture is read by its role name, next to its pattern in the
   --  spec (Count_Capture, Item_Capture ...).

   X_Name      : constant String := "The x coordinate";
   Y_Name      : constant String := "The y coordinate";
   Index_Name  : constant String := "The item index";
   X_Lead      : constant String := "given coordinates x=";
   Y_Lead      : constant String := " y=";
   No_Doc_Text : constant String := "The step needs a doc string";

   --  The step with no assertion at all: it prints its two coordinates,
   --  or fails when one of them did not read.
   procedure Print_Coordinates_Of
     (A : Fabula.Args.List; R : in out Fabula.Check.Outcome)
   is
      X : constant Number := Fabula.Args.Int (A, X_Capture);
      Y : constant Number := Fabula.Args.Int (A, Y_Capture);
   begin
      if not X.Ok then
         Fabula.Check.Ints.Fail_Read (R, X.Error, X_Name);
      elsif not Y.Ok then
         Fabula.Check.Ints.Fail_Read (R, Y.Error, Y_Name);
      else
         Ada.Text_IO.Put_Line
           (X_Lead & Trimmed (X.Value) & Y_Lead & Trimmed (Y.Value));
      end if;
   end Print_Coordinates_Of;

   --  Init_Box through Print_Coordinates, once the doc string a step
   --  needs is there: the box's own state, and the one step with no
   --  assertion at all (a side-effecting print).
   procedure Set_Up
     (S   : Setup_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
      case S is
         when Init_Box                       =>
            Fabula.Check.Ints.Equal (R, Ctx.Item_Count, No_Items);

         when Init_Labeled_Box               =>
            Set_Label (Ctx, Fabula.Args.Doc_String (A));

         when Take_Customs_Declaration       =>
            Set_Note (Ctx, Fabula.Args.Doc_Type (A));

         when Check_Customs_Declaration_Type =>
            Fabula.Check.Text_Equal
              (R, Fabula.Args.Text (A, Expected_Capture), Note_Value (Ctx));

         when Take_Shipping_Label            =>
            Set_Note (Ctx, Fabula.Args.Doc_String (A));

         when Check_Shipping_Label           =>
            Fabula.Check.Text_Equal
              (R, Fabula.Args.Text (A, Expected_Capture), Note_Value (Ctx));

         when Add_Item                       =>
            Add_Items
              (Ctx,
               R,
               Fabula.Args.Text (A, Item_Capture),
               Fabula.Args.Int (A, Count_Capture));

         when Print_Coordinates              =>
            Print_Coordinates_Of (A, R);
      end case;
   end Set_Up;

   --  The three doc-string steps fail when the step has none, since
   --  reading one that is not there is a precondition failure.
   subtype Doc_String_Kind is Setup_Kind
   with
     Static_Predicate =>
       Doc_String_Kind
       in Init_Labeled_Box | Take_Customs_Declaration | Take_Shipping_Label;

   procedure Execute_Setup
     (S   : Setup_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
      if S in Doc_String_Kind and then not Fabula.Args.Has_Doc (A) then
         Fabula.Check.Fail_Step (R, No_Doc_Text);
      else
         Set_Up (S, Ctx, A, R);
      end if;
   end Execute_Setup;

   ---------------------------------------------------------------------
   --  Tables.  A raw table holds an item and its count in each row; a
   --  hashes table names its columns in a header row; a rows_hash table
   --  holds one key and its value in each row.
   ---------------------------------------------------------------------

   Item_Column  : constant := 1;
   Count_Column : constant := 2;
   Pair_Width   : constant := 2;   --  a key, then its value

   Item_Key     : constant String := "ITEM";
   Quantity_Key : constant String := "QUANTITY";

   No_Table_Text : constant String := "The step needs a data table";
   Raw_Text      : constant String :=
     "The table needs an item and a count in each row";
   Columns_Text  : constant String :=
     "The table needs ITEM and QUANTITY columns";
   Pairs_Text    : constant String := "The table needs ITEM and QUANTITY rows";

   --  What a table step's table lacks, as a failure message; "" when the
   --  step can read it.  Each test is a precondition of the Fabula.Args
   --  table view that the step uses.
   function Table_Problem (S : Table_Kind; A : Fabula.Args.List) return String
   is
   begin
      if not Fabula.Args.Has_Table (A) then
         return No_Table_Text;
      end if;
      case S is
         when Add_Items_Raw      =>
            if Fabula.Args.Col_Count (A) < Count_Column then
               return Raw_Text;
            end if;

         when Add_Items_Hashes   =>
            if not (Fabula.Args.Has_Column (A, Item_Key)
                    and then Fabula.Args.Has_Column (A, Quantity_Key))
            then
               return Columns_Text;
            end if;

         when Add_Item_Rows_Hash =>
            if Fabula.Args.Col_Count (A) /= Pair_Width
              or else not (Fabula.Args.Has_Pair (A, Item_Key)
                           and then Fabula.Args.Has_Pair (A, Quantity_Key))
            then
               return Pairs_Text;
            end if;
      end case;
      return "";
   end Table_Problem;

   --  A table cell is text, so each count is parsed here.
   procedure Add_Table_Items
     (S   : Table_Kind;
      Box : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
      case S is
         when Add_Items_Raw      =>
            for Row in 1 .. Fabula.Args.Row_Count (A) loop
               Add_Items
                 (Box,
                  R,
                  Fabula.Args.Cell (A, Row, Item_Column),
                  Fabula.Args.Cell_Int (A, Row, Count_Column));
            end loop;

         when Add_Items_Hashes   =>
            --  The header row names the columns; each row after it
            --  holds one item.
            for Row in 1 .. Fabula.Args.Row_Count (A) - 1 loop
               Add_Items
                 (Box,
                  R,
                  Fabula.Args.Hash_Value (A, Row, Item_Key),
                  Fabula.Numbers.Parse_Integer
                    (Fabula.Args.Hash_Value (A, Row, Quantity_Key)));
            end loop;

         when Add_Item_Rows_Hash =>
            Add_Items
              (Box,
               R,
               Fabula.Args.Pair_Value (A, Item_Key),
               Fabula.Numbers.Parse_Integer
                 (Fabula.Args.Pair_Value (A, Quantity_Key)));
      end case;
   end Add_Table_Items;

   --  Fills a copy of the box and keeps it only when every count read,
   --  so a table with one bad count adds nothing.
   procedure Fill_From_Table
     (S   : Table_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome)
   is
      Box : Box_Context := Ctx;
   begin
      Add_Table_Items (S, Box, A, R);
      if R.Passing then
         Ctx := Box;
      end if;
   end Fill_From_Table;

   --  Add_Items_Raw through Add_Item_Rows_Hash: the three table-reading
   --  steps.
   procedure Execute_Table
     (S   : Table_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome)
   is
      Problem : constant String := Table_Problem (S, A);
   begin
      if Problem'Length > 0 then
         Fabula.Check.Fail_Step (R, Problem);
      else
         Fill_From_Table (S, Ctx, A, R);
      end if;
   end Execute_Table;

   ---------------------------------------------------------------------
   --  Checks.
   ---------------------------------------------------------------------

   procedure Check_Item_At_Index
     (Ctx : Box_Context; A : Fabula.Args.List; R : in out Fabula.Check.Outcome)
   is
      Index : constant Number := Fabula.Args.Int (A, Index_Capture);
   begin
      if Index.Ok then
         Fabula.Check.Text_Equal
           (R, Fabula.Args.Text (A, Item_Capture), Item_At (Ctx, Index.Value));
      else
         Fabula.Check.Ints.Fail_Read (R, Index.Error, Index_Name);
      end if;
   end Check_Item_At_Index;

   --  Check_Labeled through Check_Count_Alt: every remaining assertion.
   procedure Execute_Check
     (S   : Check_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
      case S is
         when Check_Labeled   =>
            Fabula.Check.Is_False
              (R, Texts.Length (Ctx.Label) = Texts.Empty_Length);

         when Check_Item_At   =>
            Check_Item_At_Index (Ctx, A, R);

         when Check_Count     =>
            Fabula.Check.Ints.Equal
              (R, Ctx.Item_Count, Fabula.Args.Int (A, Count_Capture));

         when Check_Contains  =>
            Fabula.Check.Is_True
              (R, Contains (Ctx, Fabula.Args.Word (A, Sought_Capture)));

         when Check_Count_Alt =>
            Fabula.Check.Ints.Equal
              (R,
               Fabula.Args.Int (A, Count_Capture),
               Count_Of (Ctx, Fabula.Args.Text (A, Item_Capture)));

      end case;
   end Execute_Check;

   procedure Execute
     (S    : Step_Kind;
      Ctx  : in out Box_Context;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      pragma Unreferenced (Info);
   begin
      case S is
         when Setup_Kind =>
            Execute_Setup (S, Ctx, A, R);

         when Table_Kind =>
            Execute_Table (S, Ctx, A, R);

         when Check_Kind =>
            Execute_Check (S, Ctx, A, R);
      end case;
   end Execute;

   ---------------------------------------------------------------------
   --  Hooks.
   ---------------------------------------------------------------------

   Fail_Before_Text : constant String :=
     "Example of Fabula.Check.Fail to bring a scenario to "
     & "fail before running it";
   Fail_After_Text  : constant String :=
     "Example of Fabula.Check.Fail to bring a scenario to "
     & "fail after running it";
   Shipped_Text     : constant String := "The box is shipped! ";

   procedure Run_Hook
     (H    : Hook_Kind;
      Ctx  : in out Box_Context;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      pragma Unreferenced (Info);
   begin
      case H is
         when Skip_On_Tag      =>
            Fabula.Check.Skip (R);

         when Ignore_On_Tag    =>
            Fabula.Check.Ignore (R);

         when Fail_Before      =>
            Fabula.Check.Fail (R, Fail_Before_Text);

         when Fail_After       =>
            Fabula.Check.Fail (R, Fail_After_Text);

         when Close_Box        =>
            Ctx.Is_Open := False;

         when Ship_Box         =>
            Ada.Text_IO.Put_Line (Shipped_Text);

         when Ignore_After_Tag =>
            Fabula.Check.Ignore (R);
      end case;
   end Run_Hook;

end Box_Steps;
