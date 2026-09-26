package body Fabula.Cli
  with SPARK_Mode
is

   procedure Set (A : out Arg_Text; Text : String) is
   begin
      A := (others => <>);
      for C of Text loop
         exit when A.Len = Limits.Max_Line_Length;
         A.Len := A.Len + 1;
         A.Data (A.Len) := C;
      end loop;
   end Set;

   ---------------------------------------------------------------------
   --  Refusals.  The first one sticks; the caller stops scanning there.
   ---------------------------------------------------------------------

   procedure Refuse
     (Result : in out Options_Result; Kind : Refusal_Kind; Token : String)
   with
     Pre  =>
       Kind /= None
       and then (if Refused (Result)
                 then Kind_Of (Refusal_Of (Result)) /= None),
     Post => Refused (Result) and then Kind_Of (Refusal_Of (Result)) /= None
   is
   begin
      if Result.Is_Refused then
         return;
      end if;
      Result.Is_Refused := True;
      Result.Refusal_Info.Kind := Kind;
      Result.Refusal_Info.Token_Len := 0;
      for C of Token loop
         exit when Result.Refusal_Info.Token_Len = Token_Length;
         Result.Refusal_Info.Token_Len := Result.Refusal_Info.Token_Len + 1;
         Result.Refusal_Info.Token (Result.Refusal_Info.Token_Len) := C;
      end loop;
   end Refuse;

   function Refusal_Text (R : Refusal) return String is
      Token : constant String := Token_Of (R);
   begin
      case Kind_Of (R) is
         when None                      =>
            return "";

         when Unknown_Option            =>
            return "Unknown option: '" & Token & "'";

         when Missing_Value             =>
            return "Missing value for '" & Token & "'";

         when Tag_Expression_Too_Long   =>
            return "Tag expression too long: '" & Token & "'";

         when Name_Patterns_Too_Long    =>
            return "-n patterns too long: '" & Token & "'";

         when Report_Json_Path_Too_Long =>
            return "--report-json path too long: '" & Token & "'";

         when Exclude_Path_Too_Long     =>
            return "--exclude-file path too long: '" & Token & "'";

         when Too_Many_Excludes         =>
            return "Too many --exclude-file flags";

         when Too_Many_Positionals      =>
            return "Too many file or directory arguments";
      end case;
   end Refusal_Text;

   ---------------------------------------------------------------------
   --  Bounded stores: one flag's value, one exclude suffix, one path.
   ---------------------------------------------------------------------

   procedure Set_Tag_Expr (Result : in out Options_Result; Text : String)
   with
     Pre  => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None),
     Post => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None)
   is
   begin
      if Text'Length > Limits.Max_Tag_Expr_Length then
         Refuse (Result, Tag_Expression_Too_Long, Text);
      else
         Result.Tag_Expr (1 .. Text'Length) := Text;
         Result.Tag_Expr_Len := Text'Length;
      end if;
   end Set_Tag_Expr;

   procedure Set_Names (Result : in out Options_Result; Text : String)
   with
     Pre  => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None),
     Post => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None)
   is
   begin
      if Text'Length > Limits.Max_Name_Filter_Length then
         Refuse (Result, Name_Patterns_Too_Long, Text);
      else
         Result.Names (1 .. Text'Length) := Text;
         Result.Names_Len := Text'Length;
      end if;
   end Set_Names;

   procedure Add_Exclude (Result : in out Options_Result; Text : String)
   with
     Pre  => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None),
     Post => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None)
   is
      Index : Positive;
   begin
      if Text'Length > Limits.Max_Path_Length then
         Refuse (Result, Exclude_Path_Too_Long, Text);
      elsif Result.Exclude_List_Count = Limits.Max_Cli_Excludes then
         Refuse (Result, Too_Many_Excludes, Text);
      else
         Result.Exclude_List_Count := Result.Exclude_List_Count + 1;
         Index := Result.Exclude_List_Count;
         Result.Exclude_List (Index).Data (1 .. Text'Length) := Text;
         Result.Exclude_List (Index).Len := Text'Length;
      end if;
   end Add_Exclude;

   procedure Add_Positional (Result : in out Options_Result; Text : String)
   with
     Pre  => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None),
     Post => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None)
   is
   begin
      if Result.Positional_List_Count = Limits.Max_Cli_Positionals then
         Refuse (Result, Too_Many_Positionals, Text);
      else
         Result.Positional_List_Count := Result.Positional_List_Count + 1;
         Set (Result.Positional_List (Result.Positional_List_Count), Text);
      end if;
   end Add_Positional;

   procedure Handle_Report_Json_Value
     (Result : in out Options_Result; Text : String)
   with
     Pre  => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None),
     Post => (if Refused (Result) then Kind_Of (Refusal_Of (Result)) /= None)
   is
   begin
      Result.Is_Report_Json := True;
      if Text'Length > Limits.Max_Path_Length then
         Refuse (Result, Report_Json_Path_Too_Long, Text);
      else
         Result.Report_Json_File_Set := True;
         Result.Report_Json_File (1 .. Text'Length) := Text;
         Result.Report_Json_File_Len := Text'Length;
      end if;
   end Handle_Report_Json_Value;

   ---------------------------------------------------------------------
   --  Value-taking flags: the next argv token is the value, whatever it
   --  looks like -- the frozen matrix takes it unconditionally.
   ---------------------------------------------------------------------

   procedure Take_Value
     (Args   : Arg_List;
      I      : in out Positive;
      Flag   : String;
      Result : in out Options_Result;
      Text   : out Arg_Text)
   with
     Pre  =>
       I in Args'Range
       and then Args'Last < Positive'Last
       and then not Result.Is_Refused,
     Post =>
       I >= I'Old
       and then I <= Args'Last
       and then (if Refused (Result)
                 then Kind_Of (Refusal_Of (Result)) /= None)
   is
   begin
      Text := (others => <>);
      if I = Args'Last then
         Refuse (Result, Missing_Value, Flag);
      else
         Text := Args (I + 1);
         I := I + 1;
      end if;
   end Take_Value;

   procedure Handle_Tag_Expr
     (Args : Arg_List; I : in out Positive; Result : in out Options_Result)
   with
     Pre  =>
       I in Args'Range
       and then Args'Last < Positive'Last
       and then not Result.Is_Refused,
     Post =>
       I > I'Old
       and then I <= Args'Last + 1
       and then (if Refused (Result)
                 then Kind_Of (Refusal_Of (Result)) /= None)
   is
      Flag : constant String := Value (Args (I));
      Text : Arg_Text;
   begin
      Take_Value (Args, I, Flag, Result, Text);
      if not Result.Is_Refused then
         Set_Tag_Expr (Result, Value (Text));
      end if;
      I := I + 1;
   end Handle_Tag_Expr;

   procedure Handle_Names
     (Args : Arg_List; I : in out Positive; Result : in out Options_Result)
   with
     Pre  =>
       I in Args'Range
       and then Args'Last < Positive'Last
       and then not Result.Is_Refused,
     Post =>
       I > I'Old
       and then I <= Args'Last + 1
       and then (if Refused (Result)
                 then Kind_Of (Refusal_Of (Result)) /= None)
   is
      Flag : constant String := Value (Args (I));
      Text : Arg_Text;
   begin
      Take_Value (Args, I, Flag, Result, Text);
      if not Result.Is_Refused then
         Set_Names (Result, Value (Text));
      end if;
      I := I + 1;
   end Handle_Names;

   procedure Handle_Exclude
     (Args : Arg_List; I : in out Positive; Result : in out Options_Result)
   with
     Pre  =>
       I in Args'Range
       and then Args'Last < Positive'Last
       and then not Result.Is_Refused,
     Post =>
       I > I'Old
       and then I <= Args'Last + 1
       and then (if Refused (Result)
                 then Kind_Of (Refusal_Of (Result)) /= None)
   is
      Flag : constant String := Value (Args (I));
      Text : Arg_Text;
   begin
      Take_Value (Args, I, Flag, Result, Text);
      if not Result.Is_Refused then
         Add_Exclude (Result, Value (Text));
      end if;
      I := I + 1;
   end Handle_Exclude;

   ---------------------------------------------------------------------
   --  One token, of any shape.
   ---------------------------------------------------------------------

   Report_Json_Prefix : constant String := "--report-json=";

   function Starts_With (Text, Prefix : String) return Boolean
   is (Text'Length >= Prefix'Length
       and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix)
   with
     Pre =>
       Text'First = 1
       and then Prefix'First = 1
       and then Prefix'Length <= Limits.Max_Line_Length;

   procedure Handle_Token
     (Args : Arg_List; I : in out Positive; Result : in out Options_Result)
   with
     Pre  =>
       I in Args'Range
       and then Args'Last < Positive'Last
       and then not Result.Is_Refused,
     Post =>
       I > I'Old
       and then I <= Args'Last + 1
       and then (if Refused (Result)
                 then Kind_Of (Refusal_Of (Result)) /= None)
   is
      Text : constant String := Value (Args (I));
   begin
      if Text = "-h" or else Text = "--help" then
         Result.Is_Help := True;
         I := I + 1;
      elsif Text = "-q" or else Text = "--quiet" then
         Result.Is_Quiet := True;
         I := I + 1;
      elsif Text = "-v" or else Text = "--verbose" then
         Result.Is_Verbose := True;
         I := I + 1;
      elsif Text = "-d" or else Text = "--dry-run" then
         Result.Is_Dry_Run := True;
         I := I + 1;
      elsif Text = "-c" or else Text = "--continue-on-failure" then
         Result.Is_Continue := True;
         I := I + 1;
      elsif Text = "-t" or else Text = "--tags" then
         Handle_Tag_Expr (Args, I, Result);
      elsif Text = "-n" or else Text = "--name" then
         Handle_Names (Args, I, Result);
      elsif Text = "--exclude-file" then
         Handle_Exclude (Args, I, Result);
      elsif Text = "--report-json" then
         Result.Is_Report_Json := True;
         I := I + 1;
      elsif Starts_With (Text, Report_Json_Prefix) then
         Handle_Report_Json_Value
           (Result,
            Text (Text'First + Report_Json_Prefix'Length .. Text'Last));
         I := I + 1;
      elsif Text'Length > 0 and then Text (Text'First) = '-' then
         Refuse (Result, Unknown_Option, Text);
         I := I + 1;
      else
         Add_Positional (Result, Text);
         I := I + 1;
      end if;
   end Handle_Token;

   procedure Parse (Args : Arg_List; Result : out Options_Result) is
      I : Positive := Args'First;
   begin
      Result := (others => <>);
      if Args'Length = 0 then
         Result.Is_Help := True;
         return;
      end if;
      --  -h/--help wins over any other argument, a refusal included,
      --  wherever it sits in argv -- the reference interpreter checks
      --  it before parsing anything else, so a bad flag earlier in the
      --  line never hides it.
      for J in Args'Range loop
         if Value (Args (J)) in "-h" | "--help" then
            Result.Is_Help := True;
            return;
         end if;
      end loop;
      while I <= Args'Last loop
         pragma
           Loop_Invariant
             (I in Args'First .. Args'Last + 1 and then not Result.Is_Refused);
         pragma Loop_Variant (Increases => I);
         Handle_Token (Args, I, Result);
         exit when Result.Is_Refused;
      end loop;
   end Parse;

end Fabula.Cli;
