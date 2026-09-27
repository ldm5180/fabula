with Ada.Text_IO;

with Fabula.Check.Ints;
with Fabula.Numbers;

package body Box_Steps
  with SPARK_Mode => Off
is

   --  A number read from the step text: a value, or the reason there is
   --  none.  Value may be read only where Ok holds; a step fails a read
   --  that did not succeed with Fabula.Check.Ints.Fail_Read.
   subtype Number is Fabula.Numbers.Integer_Reads.Read;

   ---------------------------------------------------------------------
   --  The box.
   ---------------------------------------------------------------------

   --  Adds Count copies of Item.  A count that did not read fails the
   --  step and adds nothing.
   procedure Add_Items
     (Ctx   : in out Box_Context;
      R     : in out Fabula.Check.Outcome;
      Item  : String;
      Count : Number)
   is
      Len : constant Natural := Natural'Min (Item'Length, Max_Item_Length);
   begin
      if not Count.Ok then
         Fabula.Check.Ints.Fail_Read (R, Count.Error, "The item count");
         return;
      end if;
      for I in 1 .. Count.Value loop
         exit when Ctx.Item_Count = Max_Items;
         Ctx.Item_Count := Ctx.Item_Count + 1;
         Ctx.Items (Ctx.Item_Count).Data (1 .. Len) :=
           Item (Item'First .. Item'First + Len - 1);
         Ctx.Items (Ctx.Item_Count).Len := Len;
      end loop;
   end Add_Items;

   function Item_Value (I : Item_Text) return String
   is (I.Data (1 .. I.Len));

   function Item_At (Ctx : Box_Context; Index : Integer) return String is
   begin
      if Index not in 1 .. Ctx.Item_Count then
         return "";
      end if;
      return Item_Value (Ctx.Items (Index));
   end Item_At;

   function Count_Of (Ctx : Box_Context; Item : String) return Natural is
      Total : Natural := 0;
   begin
      for I in 1 .. Ctx.Item_Count loop
         if Item_Value (Ctx.Items (I)) = Item then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Count_Of;

   function Contains (Ctx : Box_Context; Item : String) return Boolean
   is (Count_Of (Ctx, Item) > 0);

   --  The reference interpreter's own labeled-box constructor takes its
   --  label only the first time --
   --  a later call, even with a different label, returns the box
   --  already built and ignores the new argument.  Ported as a guard,
   --  not a fabula-side reinterpretation: fabula's one flat Box_Context
   --  has no other way to express "already built".
   procedure Set_Label (Ctx : in out Box_Context; Value : String) is
      Len : constant Natural := Natural'Min (Value'Length, Max_Label_Length);
   begin
      if Ctx.Has_Label then
         return;
      end if;
      Ctx.Label (1 .. Len) := Value (Value'First .. Value'First + Len - 1);
      Ctx.Label_Len := Len;
      Ctx.Has_Label := True;
   end Set_Label;

   function Note_Value (Ctx : Box_Context) return String
   is (Ctx.Note (1 .. Ctx.Note_Len));

   procedure Set_Note (Ctx : in out Box_Context; Value : String) is
      Len : constant Natural := Natural'Min (Value'Length, Max_Note_Length);
   begin
      Ctx.Note (1 .. Len) := Value (Value'First .. Value'First + Len - 1);
      Ctx.Note_Len := Len;
   end Set_Note;

   function Trimmed (N : Integer) return String is
      Image : constant String := N'Image;
   begin
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trimmed;

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

   --  The step with no assertion at all: it prints its two coordinates,
   --  or fails when one of them did not read.
   procedure Print_Coordinates_Of
     (A : Fabula.Args.List; R : in out Fabula.Check.Outcome)
   is
      X : constant Number := Fabula.Args.Int (A, 1);
      Y : constant Number := Fabula.Args.Int (A, 2);
   begin
      if not X.Ok then
         Fabula.Check.Ints.Fail_Read (R, X.Error, "The x coordinate");
      elsif not Y.Ok then
         Fabula.Check.Ints.Fail_Read (R, Y.Error, "The y coordinate");
      else
         Ada.Text_IO.Put_Line
           ("given coordinates x="
            & Trimmed (X.Value)
            & " y="
            & Trimmed (Y.Value));
      end if;
   end Print_Coordinates_Of;

   --  Init_Box through Print_Coordinates: the box's own state, and the
   --  one step with no assertion at all (a side-effecting print).  The
   --  three doc-string steps fail when the step has none, since reading
   --  one that is not there is a precondition failure.
   procedure Execute_Setup
     (S   : Setup_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
      if S in Init_Labeled_Box | Take_Customs_Declaration | Take_Shipping_Label
        and then not Fabula.Args.Has_Doc (A)
      then
         Fabula.Check.Fail_Step (R, "The step needs a doc string");
         return;
      end if;
      case S is
         when Init_Box                       =>
            Fabula.Check.Ints.Equal (R, Ctx.Item_Count, 0);

         when Init_Labeled_Box               =>
            Set_Label (Ctx, Fabula.Args.Doc_String (A));

         when Take_Customs_Declaration       =>
            Set_Note (Ctx, Fabula.Args.Doc_Type (A));

         when Check_Customs_Declaration_Type =>
            Fabula.Check.Text_Equal
              (R, Fabula.Args.Text (A, 1), Note_Value (Ctx));

         when Take_Shipping_Label            =>
            Set_Note (Ctx, Fabula.Args.Doc_String (A));

         when Check_Shipping_Label           =>
            Fabula.Check.Text_Equal
              (R, Fabula.Args.Text (A, 1), Note_Value (Ctx));

         when Add_Item                       =>
            Add_Items
              (Ctx, R, Fabula.Args.Text (A, 2), Fabula.Args.Int (A, 1));

         when Print_Coordinates              =>
            Print_Coordinates_Of (A, R);
      end case;
   end Execute_Setup;

   --  What a table step's table lacks, as a failure message; "" when the
   --  step can read it.  Each test is a precondition of the Fabula.Args
   --  table view that the step uses.
   function Table_Problem (S : Table_Kind; A : Fabula.Args.List) return String
   is
   begin
      if not Fabula.Args.Has_Table (A) then
         return "The step needs a data table";
      end if;
      case S is
         when Add_Items_Raw      =>
            if Fabula.Args.Col_Count (A) < 2 then
               return "The table needs an item and a count in each row";
            end if;

         when Add_Items_Hashes   =>
            if not (Fabula.Args.Has_Column (A, "ITEM")
                    and then Fabula.Args.Has_Column (A, "QUANTITY"))
            then
               return "The table needs ITEM and QUANTITY columns";
            end if;

         when Add_Item_Rows_Hash =>
            if Fabula.Args.Col_Count (A) /= 2
              or else not (Fabula.Args.Has_Pair (A, "ITEM")
                           and then Fabula.Args.Has_Pair (A, "QUANTITY"))
            then
               return "The table needs ITEM and QUANTITY rows";
            end if;
      end case;
      return "";
   end Table_Problem;

   --  Add_Items_Raw through Add_Item_Rows_Hash: the three table-reading
   --  steps.  A table cell is text, so each count is parsed here.  The
   --  steps fill a copy of the box and keep it only when every count
   --  read, so a table with one bad count adds nothing.
   procedure Execute_Table
     (S   : Table_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome)
   is
      Problem : constant String := Table_Problem (S, A);
      Box     : Box_Context := Ctx;
   begin
      if Problem'Length > 0 then
         Fabula.Check.Fail_Step (R, Problem);
         return;
      end if;
      case S is
         when Add_Items_Raw      =>
            for Row in 1 .. Fabula.Args.Row_Count (A) loop
               Add_Items
                 (Box,
                  R,
                  Fabula.Args.Cell (A, Row, 1),
                  Fabula.Args.Cell_Int (A, Row, 2));
            end loop;

         when Add_Items_Hashes   =>
            for Row in 1 .. Fabula.Args.Row_Count (A) - 1 loop
               Add_Items
                 (Box,
                  R,
                  Fabula.Args.Hash_Value (A, Row, "ITEM"),
                  Fabula.Numbers.Parse_Integer
                    (Fabula.Args.Hash_Value (A, Row, "QUANTITY")));
            end loop;

         when Add_Item_Rows_Hash =>
            Add_Items
              (Box,
               R,
               Fabula.Args.Pair_Value (A, "ITEM"),
               Fabula.Numbers.Parse_Integer
                 (Fabula.Args.Pair_Value (A, "QUANTITY")));
      end case;
      if R.Passing then
         Ctx := Box;
      end if;
   end Execute_Table;

   --  Check_Labeled through Check_Count_Alt: every remaining assertion.
   procedure Execute_Check
     (S   : Check_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
      case S is
         when Check_Labeled   =>
            Fabula.Check.Is_False (R, Ctx.Label_Len = 0);

         when Check_Item_At   =>
            declare
               Index : constant Number := Fabula.Args.Int (A, 1);
            begin
               if Index.Ok then
                  Fabula.Check.Text_Equal
                    (R, Fabula.Args.Text (A, 2), Item_At (Ctx, Index.Value));
               else
                  Fabula.Check.Ints.Fail_Read
                    (R, Index.Error, "The item index");
               end if;
            end;

         when Check_Count     =>
            Fabula.Check.Ints.Equal
              (R, Ctx.Item_Count, Fabula.Args.Int (A, 1));

         when Check_Contains  =>
            Fabula.Check.Is_True (R, Contains (Ctx, Fabula.Args.Word (A, 1)));

         when Check_Count_Alt =>
            Fabula.Check.Ints.Equal
              (R,
               Fabula.Args.Int (A, 1),
               Count_Of (Ctx, Fabula.Args.Text (A, 2)));

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
            Fabula.Check.Fail
              (R,
               "Example of Fabula.Check.Fail to bring a scenario to "
               & "fail before running it");

         when Fail_After       =>
            Fabula.Check.Fail
              (R,
               "Example of Fabula.Check.Fail to bring a scenario to "
               & "fail after running it");

         when Close_Box        =>
            Ctx.Is_Open := False;

         when Ship_Box         =>
            Ada.Text_IO.Put_Line ("The box is shipped! ");

         when Ignore_After_Tag =>
            Fabula.Check.Ignore (R);
      end case;
   end Run_Hook;

end Box_Steps;
