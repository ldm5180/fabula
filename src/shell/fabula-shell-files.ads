--  Feature files: finding them beneath a path, and reading one into the
--  Document the runner walks.  An argument may end in line selections,
--  as in "a.feature:4:10".  Every call reports a typed status; nothing
--  raises to the caller.
with Fabula.Args;
with Fabula.Frames;
with Fabula.Limits;
with Fabula.Parse;

package Fabula.Shell.Files
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------
   --  Arguments.  Each trailing group of digits after a ':' is one
   --  selected line, read from the right until a group holds anything
   --  but digits; the rest is the path.
   ---------------------------------------------------------------------

   subtype Line_Count is Natural range 0 .. Limits.Max_Line_Selections;
   type Line_Array is array (1 .. Limits.Max_Line_Selections) of Positive;

   --  Distinct line numbers, in no particular order; none selects every
   --  scenario.
   type Line_Numbers is record
      Count : Line_Count := 0;
      Lines : Line_Array := [others => 1];
   end record;

   function Selects (L : Line_Numbers; Line : Positive) return Boolean
   is (for some I in 1 .. L.Count => L.Lines (I) = Line);

   type Search_Status is
     (Found,
      Bad_Line_Number,   --  an empty group, a zero, or past Positive'Last
      Too_Many_Lines,    --  more distinct lines than Max_Line_Selections
      Path_Too_Long,     --  a path longer than Max_Path_Length
      Missing,           --  nothing exists at the path
      Not_Feature,       --  a file whose name does not end in ".feature"
      Too_Many_Files,    --  more files than Max_Features_Per_Run
      Too_Deep,          --  directories nested past Max_Search_Depth
      Unreadable);       --  a directory that cannot be listed

   type Target is record
      Status : Search_Status := Found;
      Path   : Frames.Path_Text;
      Lines  : Line_Numbers;
   end record;

   --  The path and the line selections of one argument.  Status is
   --  Found, Bad_Line_Number, Too_Many_Lines or Path_Too_Long.
   function Split (Argument : String) return Target;

   ---------------------------------------------------------------------
   --  Discovery.
   ---------------------------------------------------------------------

   type Feature_File is record
      Path  : Frames.Path_Text;
      Lines : Line_Numbers;
   end record;

   subtype File_Count is Natural range 0 .. Limits.Max_Features_Per_Run;
   type File_Array is array (1 .. Limits.Max_Features_Per_Run) of Feature_File;

   --  The run's feature files in running order.  About 200 KB: keep one
   --  at library level, never on a task's stack.
   type File_List is record
      Count : File_Count := 0;
      Files : File_Array;
   end record;

   --  Appends the feature files Argument names.  A file passes through
   --  with its line selections.  A directory gives every file beneath
   --  it whose name ends in ".feature", taking each directory's entries
   --  in byte order and walking a subdirectory where its name sorts;
   --  line selections on a directory are dropped, as the reference
   --  interpreter drops them.  On any status but Found, List is left as
   --  it was.
   procedure Discover
     (Argument : String; List : in out File_List; Status : out Search_Status);

   ---------------------------------------------------------------------
   --  Loading.
   ---------------------------------------------------------------------

   type Load_Status is
     (Loaded,       --  the Document holds the whole file
      Refused,      --  the parser refused it: Refusal says where and why
      Too_Long,     --  a line is longer than Max_Line_Length; none is cut
      Empty,        --  the file holds no bytes
      Unreadable);  --  the file cannot be opened or read to its end

   subtype Text_Length is Natural range 0 .. Limits.Max_Line_Length;

   --  For Refused and Too_Long, Line is the offending line's number and
   --  Text (1 .. Len) its text as written, less a final CR, up to
   --  Max_Line_Length characters.
   type Load_Result is record
      Status  : Load_Status := Unreadable;
      Refusal : Parse.Refusal;
      Line    : Natural := 0;
      Text    : String (1 .. Limits.Max_Line_Length) := [others => ' '];
      Len     : Text_Length := 0;
   end record;

   function Line_Text (R : Load_Result) return String
   is (R.Text (1 .. R.Len));

   --  Parses the file at Path into the Document, one Feed per line; a
   --  CR that ends a line is dropped, so CRLF reads as LF.  Unless the
   --  status is Loaded the Document is no whole feature and must not be
   --  run.  The runner reads the Document through a reference, so call
   --  Load only while the runner is between features.
   procedure Load (Path : String; Result : out Load_Result);

   --  The Document the last Load filled, as the runner takes it.
   function Document return Args.Document_Access;

end Fabula.Shell.Files;
