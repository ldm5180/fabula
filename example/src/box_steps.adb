with Ada.Text_IO;

with Fabula.Check.Ints;

package body Box_Steps
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------
   --  The box.
   ---------------------------------------------------------------------

   procedure Add_Items
     (Ctx : in out Box_Context; Item : String; Count : Natural)
   is
      Len : constant Natural := Natural'Min (Item'Length, Max_Item_Length);
   begin
      for I in 1 .. Count loop
         exit when Ctx.Item_Count = Max_Items;
         Ctx.Item_Count := Ctx.Item_Count + 1;
         Ctx.Items (Ctx.Item_Count).Data (1 .. Len) :=
           Item (Item'First .. Item'First + Len - 1);
         Ctx.Items (Ctx.Item_Count).Len := Len;
      end loop;
   end Add_Items;

   function Item_Value (I : Item_Text) return String
   is (I.Data (1 .. I.Len));

   function Item_At (Ctx : Box_Context; Index : Positive) return String is
   begin
      if Index > Ctx.Item_Count then
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
   subtype Check_Kind is Step_Kind range Add_Items_Raw .. Check_Count_Alt;

   --  Init_Box through Print_Coordinates: the box's own state, and the
   --  one step with no assertion at all (a side-effecting print).
   procedure Execute_Setup
     (S   : Setup_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
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
              (Ctx, Fabula.Args.Text (A, 2), Natural (Fabula.Args.Int (A, 1)));

         when Print_Coordinates              =>
            Ada.Text_IO.Put_Line
              ("given coordinates x="
               & Trimmed (Fabula.Args.Int (A, 1))
               & " y="
               & Trimmed (Fabula.Args.Int (A, 2)));
      end case;
   end Execute_Setup;

   --  Add_Items_Raw through Check_Count_Alt: the three table-reading
   --  steps, then every remaining assertion.
   procedure Execute_Check
     (S   : Check_Kind;
      Ctx : in out Box_Context;
      A   : Fabula.Args.List;
      R   : in out Fabula.Check.Outcome) is
   begin
      case S is
         when Add_Items_Raw      =>
            for Row in 1 .. Fabula.Args.Row_Count (A) loop
               Add_Items
                 (Ctx,
                  Fabula.Args.Cell (A, Row, 1),
                  Natural (Fabula.Args.Cell_Int (A, Row, 2)));
            end loop;

         when Add_Items_Hashes   =>
            for Row in 1 .. Fabula.Args.Row_Count (A) - 1 loop
               Add_Items
                 (Ctx,
                  Fabula.Args.Hash_Value (A, Row, "ITEM"),
                  Natural'Value (Fabula.Args.Hash_Value (A, Row, "QUANTITY")));
            end loop;

         when Add_Item_Rows_Hash =>
            Add_Items
              (Ctx,
               Fabula.Args.Pair_Value (A, "ITEM"),
               Natural'Value (Fabula.Args.Pair_Value (A, "QUANTITY")));

         when Check_Labeled      =>
            Fabula.Check.Is_False (R, Ctx.Label_Len = 0);

         when Check_Item_At      =>
            Fabula.Check.Text_Equal
              (R,
               Fabula.Args.Text (A, 2),
               Item_At (Ctx, Positive (Fabula.Args.Int (A, 1))));

         when Check_Count        =>
            Fabula.Check.Ints.Equal
              (R, Ctx.Item_Count, Fabula.Args.Int (A, 1));

         when Check_Contains     =>
            Fabula.Check.Is_True (R, Contains (Ctx, Fabula.Args.Word (A, 1)));

         when Check_Count_Alt    =>
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
         when Init_Box .. Print_Coordinates    =>
            Execute_Setup (S, Ctx, A, R);

         when Add_Items_Raw .. Check_Count_Alt =>
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
