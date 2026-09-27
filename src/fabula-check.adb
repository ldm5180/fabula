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

   --  A failed comparison, in the reference interpreter's words:
   --  "Value <Got> <relation> <Want>", the relation one of the phrases
   --  below.
   Mismatch_Prefix     : constant String := "Value ";
   Not_Equal_Phrase    : constant String := " is not equal to ";
   Equal_Phrase        : constant String := " is equal to ";
   Not_Greater_Phrase  : constant String := " is not greater than ";
   Not_At_Least_Phrase : constant String :=
     " is not greater than or equal to ";
   Not_Less_Phrase     : constant String := " is not less than ";
   Not_At_Most_Phrase  : constant String := " is not less than or equal to ";

   --  A failed read: "<What> is not a valid <type>: <reason>".
   Not_Valid_Phrase : constant String := " is not a valid ";
   Reason_Separator : constant String := ": ";

   --  The blank 'Image puts before a value with no minus sign.
   Sign_Blank : constant Character := ' ';

   --  Clears Passing and the message, leaving Order untouched: callers
   --  that also change Order (Fail) set it themselves right after.
   procedure Begin_Failure (R : in out Outcome)
   with Post => not R.Passing and then R.Order = R.Order'Old
   is
   begin
      R.Passing := False;
      R.Message := Texts.Empty (Limits.Max_Message_Length);
   end Begin_Failure;

   --  Copies as much of Piece as still fits after the message; the rest
   --  is dropped.
   procedure Append_Message (R : in out Outcome; Piece : String)
   with
     Post =>
       R.Passing = R.Passing'Old
       and then R.Order = R.Order'Old
       and then Texts.Length (R.Message) >= Texts.Length (R.Message'Old)
   is
   begin
      Texts.Append_Truncated (R.Message, Piece);
   end Append_Message;

   procedure Reset (R : out Outcome) is
   begin
      R := (others => <>);
   end Reset;

   procedure Record_Failure (R : in out Outcome; Message : String) is
   begin
      Begin_Failure (R);
      Append_Message (R, Message);
   end Record_Failure;

   --  The one message path of every failed comparison: the caller's
   --  own Message when it gives one, else "Value <Got> <Phrase> <Want>".
   --  Text_Equal passes its two texts as they are; a Compare instance
   --  computes the two images only when it reports the default message
   --  (Compare.Mismatch), so a caller's Message costs no Image call.
   procedure Report_Mismatch
     (R          : in out Outcome;
      Got_Image  : String;
      Phrase     : String;
      Want_Image : String;
      Message    : String) is
   begin
      if Message'Length > 0 then
         Record_Failure (R, Message);
      else
         Begin_Failure (R);
         Append_Message (R, Mismatch_Prefix);
         Append_Message (R, Got_Image);
         Append_Message (R, Phrase);
         Append_Message (R, Want_Image);
      end if;
   end Report_Mismatch;

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

      --  A failed comparison.  Got and Want are imaged only for the
      --  default message: Image is the caller's own function and may be
      --  costly, or raise, and a caller's Message does not need it.
      procedure Mismatch
        (R       : in out Outcome;
         Got     : Item;
         Want    : Item;
         Phrase  : String;
         Message : String) is
      begin
         if Message'Length > 0 then
            Record_Failure (R, Message);
         else
            Report_Mismatch (R, Image (Got), Phrase, Image (Want), "");
         end if;
      end Mismatch;

      procedure Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if not (Got = Want) then
            Mismatch (R, Got, Want, Not_Equal_Phrase, Message);
         end if;
      end Equal;

      procedure Not_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if Got = Want then
            Mismatch (R, Got, Want, Equal_Phrase, Message);
         end if;
      end Not_Equal;

      --  Got > Want, expressed with the two formal operators as
      --  Want < Got.
      procedure Greater
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if not (Want < Got) then
            Mismatch (R, Got, Want, Not_Greater_Phrase, Message);
         end if;
      end Greater;

      --  Got >= Want, expressed as not (Got < Want).
      procedure Greater_Or_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if Got < Want then
            Mismatch (R, Got, Want, Not_At_Least_Phrase, Message);
         end if;
      end Greater_Or_Equal;

      procedure Less
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if not (Got < Want) then
            Mismatch (R, Got, Want, Not_Less_Phrase, Message);
         end if;
      end Less;

      --  Got <= Want, expressed as not (Want < Got).
      procedure Less_Or_Equal
        (R : in out Outcome; Got, Want : Item; Message : String := "") is
      begin
         if Want < Got then
            Mismatch (R, Got, Want, Not_At_Most_Phrase, Message);
         end if;
      end Less_Or_Equal;

      procedure Fail_Read
        (R     : in out Outcome;
         Error : Numbers.Read_Error;
         What  : String := Unnamed_Value) is
      begin
         Begin_Failure (R);
         Append_Message (R, (if What'Length > 0 then What else Unnamed_Value));
         Append_Message (R, Not_Valid_Phrase);
         Append_Message (R, Item_Reads.Name);
         Append_Message (R, Reason_Separator);
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

   --  Raw re-based to start at 1, less the blank 'Image puts before a
   --  value with no minus sign (the reference interpreter's formatter
   --  puts none).  The blank is found on the character itself, never on
   --  the value's sign: -0.0 compares >= 0.0, yet its 'Image carries a
   --  real '-' (confirmed against this GNAT: Long_Float'Image (-0.0) =
   --  "-0.0...E+00"), which must stay.  The loop invariant relates Len
   --  to the loop index J, not to Raw's own bounds, so this cannot
   --  overflow.
   function Without_Leading_Blank (Raw : String) return String is
      Nothing_Kept : constant := 0;
      Result       : String (1 .. Raw'Length) := [others => Sign_Blank];
      Len          : Natural := Nothing_Kept;
   begin
      for J in Raw'Range loop
         pragma Loop_Invariant (Len <= J - Raw'First);
         if J /= Raw'First or else Raw (J) /= Sign_Blank then
            Len := Len + 1;
            Result (Len) := Raw (J);
         end if;
      end loop;
      return Result (1 .. Len);
   end Without_Leading_Blank;

   function Integer_Image (I : Integer) return String
   is (Without_Leading_Blank (Integer'Image (I)));

   function Long_Image (I : Long_Long_Integer) return String
   is (Without_Leading_Blank (Long_Long_Integer'Image (I)));

   function Real_Image (I : Long_Float) return String
   is (Without_Leading_Blank (Long_Float'Image (I)));

   procedure Text_Equal
     (R : in out Outcome; Got, Want : String; Message : String := "") is
   begin
      if Got /= Want then
         Report_Mismatch (R, Got, Not_Equal_Phrase, Want, Message);
      end if;
   end Text_Equal;

   procedure Text_Not_Equal
     (R : in out Outcome; Got, Want : String; Message : String := "") is
   begin
      if Got = Want then
         Report_Mismatch (R, Got, Equal_Phrase, Want, Message);
      end if;
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
