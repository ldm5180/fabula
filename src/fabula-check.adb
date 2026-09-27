package body Fabula.Check
  with SPARK_Mode
is

   --  The default messages, used whenever the caller's own Message is
   --  empty.  The two check messages are the reference interpreter's
   --  own words; the two scenario-control messages name the Ada
   --  operation that set the failure.
   Is_True_Default       : constant String :=
     "Expected given condition to be true, but it was false";
   Is_False_Default      : constant String :=
     "Expected given condition to be false, but it was true";
   Fail_Scenario_Default : constant String :=
     "Scenario set to failed with Fabula.Check.Fail";
   Fail_Step_Default     : constant String :=
     "Step set to failed with Fabula.Check.Fail_Step";

   --  Clears Passing and the message, leaving Order untouched: callers
   --  that also change Order (Fail) set it themselves right after.
   procedure Begin_Failure (R : in out Outcome) is
   begin
      R.Passing := False;
      R.Msg := [others => ' '];
      R.Msg_Len := 0;
   end Begin_Failure;

   --  Copies as much of Piece as still fits past R.Msg_Len; the rest is
   --  dropped.  The loop bound is R.Msg_Len itself, never an offset
   --  read off Piece, so this is safe for any Piece regardless of its
   --  own bounds.  The contract lets gnatprove verify this once and
   --  reuse it at every call site, rather than inlining and re-proving
   --  the loop at each one.
   procedure Append_Message (R : in out Outcome; Piece : String)
   with
     Pre  => R.Msg_Len <= Limits.Max_Message_Length,
     Post =>
       R.Msg_Len in R.Msg_Len'Old .. Limits.Max_Message_Length
       and then R.Passing = R.Passing'Old
       and then R.Order = R.Order'Old;

   procedure Append_Message (R : in out Outcome; Piece : String) is
   begin
      for J in Piece'Range loop
         pragma
           Loop_Invariant
             (R.Msg_Len in R.Msg_Len'Loop_Entry .. Limits.Max_Message_Length
                and then R.Passing = R.Passing'Loop_Entry
                and then R.Order = R.Order'Loop_Entry);
         exit when R.Msg_Len = Limits.Max_Message_Length;
         R.Msg_Len := R.Msg_Len + 1;
         R.Msg (R.Msg_Len) := Piece (J);
      end loop;
   end Append_Message;

   procedure Reset (R : out Outcome) is
   begin
      R :=
        (Passing => True,
         Order   => Continue,
         Msg     => [others => ' '],
         Msg_Len => 0);
   end Reset;

   procedure Record_Failure (R : in out Outcome; Message : String) is
   begin
      Begin_Failure (R);
      Append_Message (R, Message);
   end Record_Failure;

   procedure Is_True
     (R : in out Outcome; Condition : Boolean; Message : String := "") is
   begin
      if Condition then
         return;
      end if;
      Record_Failure
        (R, (if Message'Length > 0 then Message else Is_True_Default));
   end Is_True;

   procedure Is_False
     (R : in out Outcome; Condition : Boolean; Message : String := "") is
   begin
      if not Condition then
         return;
      end if;
      Record_Failure
        (R, (if Message'Length > 0 then Message else Is_False_Default));
   end Is_False;

   package body Compare is

      --  "Value {} is not equal to {}"
      procedure Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if Got = Want then
            return;
         end if;
         if Message'Length > 0 then
            Record_Failure (R, Message);
            return;
         end if;
         Begin_Failure (R);
         Append_Message (R, "Value ");
         Append_Message (R, Image (Got));
         Append_Message (R, " is not equal to ");
         Append_Message (R, Image (Want));
      end Equal;

      --  "Value {} is equal to {}"
      procedure Not_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if Got /= Want then
            return;
         end if;
         if Message'Length > 0 then
            Record_Failure (R, Message);
            return;
         end if;
         Begin_Failure (R);
         Append_Message (R, "Value ");
         Append_Message (R, Image (Got));
         Append_Message (R, " is equal to ");
         Append_Message (R, Image (Want));
      end Not_Equal;

      --  "Value {} is not greater than {}"
      --  Got > Want, expressed with the two formal operators as
      --  Want < Got.
      procedure Greater
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if Want < Got then
            return;
         end if;
         if Message'Length > 0 then
            Record_Failure (R, Message);
            return;
         end if;
         Begin_Failure (R);
         Append_Message (R, "Value ");
         Append_Message (R, Image (Got));
         Append_Message (R, " is not greater than ");
         Append_Message (R, Image (Want));
      end Greater;

      --  "Value {} is not greater than or equal to {}"
      --  Got >= Want, expressed as not (Got < Want).
      procedure Greater_Or_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if not (Got < Want) then
            return;
         end if;
         if Message'Length > 0 then
            Record_Failure (R, Message);
            return;
         end if;
         Begin_Failure (R);
         Append_Message (R, "Value ");
         Append_Message (R, Image (Got));
         Append_Message (R, " is not greater than or equal to ");
         Append_Message (R, Image (Want));
      end Greater_Or_Equal;

      --  "Value {} is not less than {}"
      procedure Less
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if Got < Want then
            return;
         end if;
         if Message'Length > 0 then
            Record_Failure (R, Message);
            return;
         end if;
         Begin_Failure (R);
         Append_Message (R, "Value ");
         Append_Message (R, Image (Got));
         Append_Message (R, " is not less than ");
         Append_Message (R, Image (Want));
      end Less;

      --  "Value {} is not less than or equal to {}"
      --  Got <= Want, expressed as not (Want < Got).
      procedure Less_Or_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if not (Want < Got) then
            return;
         end if;
         if Message'Length > 0 then
            Record_Failure (R, Message);
            return;
         end if;
         Begin_Failure (R);
         Append_Message (R, "Value ");
         Append_Message (R, Image (Got));
         Append_Message (R, " is not less than or equal to ");
         Append_Message (R, Image (Want));
      end Less_Or_Equal;

      procedure Fail_Read
        (R     : in out Outcome;
         Error : Numbers.Read_Error;
         What  : String := "Value") is
      begin
         Begin_Failure (R);
         Append_Message (R, (if What'Length > 0 then What else "Value"));
         Append_Message (R, " is not a valid ");
         Append_Message (R, Item_Reads.Name);
         Append_Message (R, ": ");
         Append_Message (R, Numbers.Reason (Error));
      end Fail_Read;

      --  A comparison with a read on one side: a good read goes through
      --  Plain, the plain comparison, so both share one message path.
      generic
         with
           procedure Plain
             (R : in out Outcome; Got, Want : Item; Message : String);
      procedure Want_Read
        (R : in out Outcome; Got : Item; Want : Read; Message : String);

      procedure Want_Read
        (R : in out Outcome; Got : Item; Want : Read; Message : String) is
      begin
         if Want.Ok then
            Plain (R, Got, Want.Value, Message);
         else
            Fail_Read (R, Want.Error);
         end if;
      end Want_Read;

      generic
         with
           procedure Plain
             (R : in out Outcome; Got, Want : Item; Message : String);
      procedure Got_Read
        (R : in out Outcome; Got : Read; Want : Item; Message : String);

      procedure Got_Read
        (R : in out Outcome; Got : Read; Want : Item; Message : String) is
      begin
         if Got.Ok then
            Plain (R, Got.Value, Want, Message);
         else
            Fail_Read (R, Got.Error);
         end if;
      end Got_Read;

      procedure Equal_Want is new Want_Read (Equal);
      procedure Not_Equal_Want is new Want_Read (Not_Equal);
      procedure Greater_Want is new Want_Read (Greater);
      procedure Greater_Or_Equal_Want is new Want_Read (Greater_Or_Equal);
      procedure Less_Want is new Want_Read (Less);
      procedure Less_Or_Equal_Want is new Want_Read (Less_Or_Equal);

      procedure Equal_Got is new Got_Read (Equal);
      procedure Not_Equal_Got is new Got_Read (Not_Equal);
      procedure Greater_Got is new Got_Read (Greater);
      procedure Greater_Or_Equal_Got is new Got_Read (Greater_Or_Equal);
      procedure Less_Got is new Got_Read (Less);
      procedure Less_Or_Equal_Got is new Got_Read (Less_Or_Equal);

      procedure Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "")
      renames Equal_Want;
      procedure Not_Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "")
      renames Not_Equal_Want;
      procedure Greater
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "")
      renames Greater_Want;
      procedure Greater_Or_Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "")
      renames Greater_Or_Equal_Want;
      procedure Less
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "")
      renames Less_Want;
      procedure Less_Or_Equal
        (R : in out Outcome; Got : Item; Want : Read; Message : String := "")
      renames Less_Or_Equal_Want;

      procedure Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "")
      renames Equal_Got;
      procedure Not_Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "")
      renames Not_Equal_Got;
      procedure Greater
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "")
      renames Greater_Got;
      procedure Greater_Or_Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "")
      renames Greater_Or_Equal_Got;
      procedure Less
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "")
      renames Less_Got;
      procedure Less_Or_Equal
        (R : in out Outcome; Got : Read; Want : Item; Message : String := "")
      renames Less_Or_Equal_Got;

   end Compare;

   --  Trims the leading blank the reference interpreter's own formatter
   --  never adds -- checked on the character itself, never on I's
   --  sign, since -0.0 compares >= 0.0 yet 'Image still gives it a
   --  real '-' (Real_Image's reason for being this way).  The loop
   --  invariant relates Len to the loop index J, not to Raw's own
   --  bounds, so this cannot overflow.
   function Integer_Image (I : Integer) return String is
      Raw    : constant String := Integer'Image (I);
      Result : String (1 .. Raw'Length) := [others => ' '];
      Len    : Natural := 0;
   begin
      for J in Raw'Range loop
         pragma Loop_Invariant (Len <= J - Raw'First);
         if J = Raw'First and then Raw (J) = ' ' then
            null;
         else
            Len := Len + 1;
            Result (Len) := Raw (J);
         end if;
      end loop;
      return Result (1 .. Len);
   end Integer_Image;

   function Long_Image (I : Long_Long_Integer) return String is
      Raw    : constant String := Long_Long_Integer'Image (I);
      Result : String (1 .. Raw'Length) := [others => ' '];
      Len    : Natural := 0;
   begin
      for J in Raw'Range loop
         pragma Loop_Invariant (Len <= J - Raw'First);
         if J = Raw'First and then Raw (J) = ' ' then
            null;
         else
            Len := Len + 1;
            Result (Len) := Raw (J);
         end if;
      end loop;
      return Result (1 .. Len);
   end Long_Image;

   --  -0.0 = 0.0 under "=" and "<", but the reference interpreter's
   --  formatter still prints its sign (confirmed against this GNAT:
   --  Long_Float'Image (-0.0) = "-0.0...E+00", not " 0.0...E+00"), so
   --  checking the character, not I's sign, is what keeps it.
   function Real_Image (I : Long_Float) return String is
      Raw    : constant String := Long_Float'Image (I);
      Result : String (1 .. Raw'Length) := [others => ' '];
      Len    : Natural := 0;
   begin
      for J in Raw'Range loop
         pragma Loop_Invariant (Len <= J - Raw'First);
         if J = Raw'First and then Raw (J) = ' ' then
            null;
         else
            Len := Len + 1;
            Result (Len) := Raw (J);
         end if;
      end loop;
      return Result (1 .. Len);
   end Real_Image;

   procedure Text_Equal
     (R : in out Outcome; Got, Want : String; Message : String := "") is
   begin
      if Got = Want then
         return;
      end if;
      if Message'Length > 0 then
         Record_Failure (R, Message);
         return;
      end if;
      Begin_Failure (R);
      Append_Message (R, "Value ");
      Append_Message (R, Got);
      Append_Message (R, " is not equal to ");
      Append_Message (R, Want);
   end Text_Equal;

   procedure Text_Not_Equal
     (R : in out Outcome; Got, Want : String; Message : String := "") is
   begin
      if Got /= Want then
         return;
      end if;
      if Message'Length > 0 then
         Record_Failure (R, Message);
         return;
      end if;
      Begin_Failure (R);
      Append_Message (R, "Value ");
      Append_Message (R, Got);
      Append_Message (R, " is equal to ");
      Append_Message (R, Want);
   end Text_Not_Equal;

   procedure Skip (R : in out Outcome) is
   begin
      R.Order := Skip_Scenario;
   end Skip;

   procedure Ignore (R : in out Outcome) is
   begin
      R.Order := Ignore_Scenario;
   end Ignore;

   procedure Fail (R : in out Outcome; Message : String := "") is
   begin
      Record_Failure
        (R, (if Message'Length > 0 then Message else Fail_Scenario_Default));
      R.Order := Fail_Scenario;
   end Fail;

   procedure Fail_Step (R : in out Outcome; Message : String := "") is
   begin
      Record_Failure
        (R, (if Message'Length > 0 then Message else Fail_Step_Default));
   end Fail_Step;

end Fabula.Check;
