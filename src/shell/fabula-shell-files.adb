with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;

with Fabula.Ast;
with Fabula.Cli;
with Fabula.Numbers;

package body Fabula.Shell.Files
  with SPARK_Mode => Off
is

   use Ada.Streams;
   use type Ada.Directories.File_Kind;

   ---------------------------------------------------------------------
   --  Split.
   ---------------------------------------------------------------------

   --  What separates a path from a line selection, and one selection
   --  from the next.
   Selection_Mark : constant String := ":";

   --  Where Index answers that no mark is left.
   No_Mark : constant Natural := 0;

   function All_Digits (S : String) return Boolean
   is (for all C of S => C in Decimal_Digit);

   --  Adds Line unless it is there already.
   procedure Add
     (L : in out Line_Numbers; Line : Source_Line; Status : out Search_Status)
   is
   begin
      Status := Found;
      if Selects (L, Line) then
         return;
      elsif L.Count = Limits.Max_Line_Selections then
         Status := Too_Many_Lines;
      else
         L.Count := L.Count + 1;
         L.Lines (L.Count) := Line;
      end if;
   end Add;

   --  One group of digits as a selected line: a number from 1 up to
   --  Positive'Last, else Bad_Line_Number (an empty group or a zero,
   --  or a number past Positive'Last).
   procedure Add_Group (Result : in out Target; Group : String) is
      Read : constant Numbers.Integer_Reads.Read :=
        Numbers.Parse_Integer (Group);
   begin
      if Read.Ok and then Read.Value in Positive then
         Add (Result.Lines, Source_Line (Read.Value), Result.Status);
      else
         Result.Status := Bad_Line_Number;
      end if;
   end Add_Group;

   --  Takes Argument's line selections, each group of digits after the
   --  last ':' up to Last, from the right, until a group holds anything
   --  but digits or a selection is refused.  Last ends at the path.
   procedure Take_Lines
     (Argument : String; Result : in out Target; Last : in out Natural)
   is
      Colon : Natural;
   begin
      loop
         Colon :=
           Ada.Strings.Fixed.Index
             (Argument (Argument'First .. Last),
              Selection_Mark,
              Ada.Strings.Backward);
         exit when
           Colon = No_Mark
           or else not All_Digits (Argument (Colon + 1 .. Last));
         Add_Group (Result, Argument (Colon + 1 .. Last));
         exit when Result.Status /= Found;
         Last := Colon - 1;
      end loop;
   end Take_Lines;

   --  The path part of an argument, when it fits.
   procedure Set_Path (Result : in out Target; Path : String) is
   begin
      if Path'Length > Limits.Max_Path_Length then
         Result.Status := Path_Too_Long;
      else
         Result.Path := Frames.To_Path (Path);
      end if;
   end Set_Path;

   function Split (Argument : String) return Target is
      Result : Target;
      Last   : Natural := Argument'Last;
   begin
      Take_Lines (Argument, Result, Last);
      if Result.Status = Found then
         Set_Path (Result, Argument (Argument'First .. Last));
      end if;
      return Result;
   end Split;

   ---------------------------------------------------------------------
   --  Discover.
   ---------------------------------------------------------------------

   package Name_Lists is new
     Ada.Containers.Indefinite_Vectors (Positive, String);
   package Name_Sorting is new Name_Lists.Generic_Sorting;

   Suffix : String renames Fabula.Cli.Feature_Suffix;

   --  The two entries every directory lists: itself and its parent.
   This_Directory   : constant String := ".";
   Parent_Directory : constant String := "..";

   --  The argument itself is the first level of a search.
   Top_Level : constant Positive := 1;

   --  A name with a stem before ".feature": the file ".feature" alone
   --  has no extension, as the reference interpreter reads names.
   function Is_Feature_Name (Name : String) return Boolean
   is (Name'Length > Suffix'Length
       and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix);

   --  Whether Path is a directory; False for a path that is gone.  The
   --  directory listing never yields a dangling link, so only a path
   --  removed during the search can be gone here.
   function Is_Directory (Path : String) return Boolean is
   begin
      return Ada.Directories.Kind (Path) = Ada.Directories.Directory;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         return False;
   end Is_Directory;

   --  Dir's entries but "." and "..", in byte order.
   function Entries (Dir : String) return Name_Lists.Vector is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Result : Name_Lists.Vector;
   begin
      Ada.Directories.Start_Search (Search, Dir, "");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            if Name /= This_Directory and then Name /= Parent_Directory then
               Result.Append (Name);
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      Name_Sorting.Sort (Result);
      return Result;
   end Entries;

   procedure Append
     (List   : in out File_List;
      Path   : String;
      Lines  : Line_Numbers;
      Status : out Search_Status) is
   begin
      if Path'Length > Limits.Max_Path_Length then
         Status := Path_Too_Long;
      elsif List.Count = Limits.Max_Features_Per_Run then
         Status := Too_Many_Files;
      else
         List.Count := List.Count + 1;
         List.Files (List.Count).Path := Frames.To_Path (Path);
         List.Files (List.Count).Lines := Lines;
         Status := Found;
      end if;
   end Append;

   procedure Walk
     (Dir    : String;
      Depth  : Positive;
      List   : in out File_List;
      Status : out Search_Status);

   --  One entry Name of Dir, which sits Depth levels down: a directory
   --  is walked, a feature file is kept, anything else is passed over.
   procedure Visit
     (Dir    : String;
      Name   : String;
      Depth  : Positive;
      List   : in out File_List;
      Status : in out Search_Status)
   is
      Path : constant String := Ada.Directories.Compose (Dir, Name);
   begin
      if Is_Directory (Path) then
         Walk (Path, Depth + 1, List, Status);
      elsif Is_Feature_Name (Name) then
         Append (List, Path, (others => <>), Status);
      end if;
   end Visit;

   --  Every feature file beneath Dir, which sits Depth levels down from
   --  the argument (the argument itself is Top_Level).
   procedure Walk
     (Dir    : String;
      Depth  : Positive;
      List   : in out File_List;
      Status : out Search_Status) is
   begin
      Status := (if Depth > Limits.Max_Search_Depth then Too_Deep else Found);
      if Status = Found then
         for Name of Entries (Dir) loop
            Visit (Dir, Name, Depth, List, Status);
            exit when Status /= Found;
         end loop;
      end if;
   end Walk;

   --  One argument's path: a directory is walked, a file passes through.
   procedure Search
     (Path   : String;
      Lines  : Line_Numbers;
      List   : in out File_List;
      Status : out Search_Status) is
   begin
      if not Ada.Directories.Exists (Path) then
         Status := Missing;
      elsif Is_Directory (Path) then
         Walk (Path, Top_Level, List, Status);
      elsif Is_Feature_Name (Ada.Directories.Simple_Name (Path)) then
         Append (List, Path, Lines, Status);
      else
         Status := Not_Feature;
      end if;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         Status := Missing;

      when Ada.IO_Exceptions.Use_Error =>
         Status := Unreadable;
   end Search;

   procedure Discover
     (Argument : String; List : in out File_List; Status : out Search_Status)
   is
      Parts : constant Target := Split (Argument);
      Kept  : constant File_Count := List.Count;
   begin
      Status := Parts.Status;
      if Status = Found then
         Search (Frames.Value (Parts.Path), Parts.Lines, List, Status);
         List.Count := (if Status = Found then List.Count else Kept);
      end if;
   end Discover;

   ---------------------------------------------------------------------
   --  Load.
   ---------------------------------------------------------------------

   Doc    : aliased Ast.Document;
   Parser : Parse.Parser;

   --  A chunk's first byte, and the last byte of a chunk not yet read.
   First_Byte : constant Stream_Element_Offset := 1;
   No_Bytes   : constant Stream_Element_Offset := 0;

   LF_Byte : constant Stream_Element := Character'Pos (ASCII.LF);

   --  A file read line by line; its bytes arrive a chunk at a time.
   --  Next past Last means the chunk is used up.
   type Reader is limited record
      File  : Stream_IO.File_Type;
      Chunk : Stream_Element_Array (First_Byte .. Read_Chunk_Bytes);
      Next  : Stream_Element_Offset := First_Byte;
      Last  : Stream_Element_Offset := No_Bytes;
   end record;

   type Line_Kind is (Whole, Overlong, Past_End);

   --  Room for one character past the longest line, so a line that ends
   --  in CR still fits before its CR is dropped.
   Buffer_Capacity : constant := Limits.Max_Line_Length + 1;

   --  One line, without its LF or the CR that ends it.  An Overlong line
   --  keeps its first characters; Past_End has none.
   type Line_Buffer is record
      Kind : Line_Kind := Past_End;
      Text : Texts.Bounded_Text (Buffer_Capacity);
   end record;

   --  What stops the bytes of a line: the end of the file, its LF, or a
   --  byte that finds the buffer full.
   type Line_Stop is (File_End, Line_Feed, Past_Capacity);

   function Used_Up (R : Reader) return Boolean
   is (R.Next > R.Last);

   --  After Refill: whether the file has no byte left.
   function At_File_End (R : Reader) return Boolean
   is (Used_Up (R));

   --  After Take_Run: whether the run stopped inside its chunk, at the
   --  line's LF or at the buffer's capacity.
   function Stopped_In_Chunk (R : Reader) return Boolean
   is (not Used_Up (R));

   --  Reads the next chunk once this one is used up.  At the end of the
   --  file the new chunk is empty, so it stays used up.
   procedure Refill (R : in out Reader) is
   begin
      if Used_Up (R) then
         Stream_IO.Read (R.File, R.Chunk, R.Last);
         R.Next := R.Chunk'First;
      end if;
   end Refill;

   --  The chunk's next LF, or one past the chunk's last byte when no LF
   --  is left in it.
   function Next_LF (R : Reader) return Stream_Element_Offset is
   begin
      for I in R.Next .. R.Last loop
         if R.Chunk (I) = LF_Byte then
            return I;
         end if;
      end loop;
      return R.Last + 1;
   end Next_LF;

   --  The chunk's next Count bytes, a character for each byte: no bytes
   --  are decoded.
   function Run (R : Reader; Count : Natural) return String
   is ([for I in 1 .. Count =>
          Character'Val (R.Chunk (R.Next + Stream_Element_Offset (I - 1)))]);

   --  Appends the chunk's bytes up to the line's LF, the chunk's end or
   --  the buffer's capacity, whichever comes first, in one run.
   procedure Take_Run (R : in out Reader; Line : in out Line_Buffer) is
      Room  : constant Natural := Buffer_Capacity - Texts.Length (Line.Text);
      Count : constant Natural :=
        Natural'Min (Natural (Next_LF (R) - R.Next), Room);
   begin
      Texts.Append_Truncated (Line.Text, Run (R, Count));
      R.Next := R.Next + Stream_Element_Offset (Count);
   end Take_Run;

   --  Takes the line's runs, a chunk at a time, until one stops short of
   --  its chunk's end or the file ends.
   procedure Take_Runs (R : in out Reader; Line : in out Line_Buffer) is
   begin
      loop
         Refill (R);
         exit when At_File_End (R);
         Take_Run (R, Line);
         exit when Stopped_In_Chunk (R);
      end loop;
   end Take_Runs;

   --  What stopped the line Take_Runs just read.
   function Stop_Of (R : Reader) return Line_Stop
   is (if Used_Up (R)
       then File_End
       elsif R.Chunk (R.Next) = LF_Byte
       then Line_Feed
       else Past_Capacity);

   --  Drops the CR that ends Line, so a CRLF file reads as its LF copy.
   procedure Strip_Trailing_CR (Line : in out Line_Buffer) is
      Text : constant String := Texts.Value (Line.Text);
      Last : constant Natural := Text'Length;
   begin
      if Last > Texts.Empty_Length and then Text (Last) = ASCII.CR then
         Line.Text :=
           Texts.Truncated (Texts.Prefix (Text, Last - 1), Buffer_Capacity);
      end if;
   end Strip_Trailing_CR;

   --  A line that ended at its LF or at the end of the file: its final CR
   --  dropped, it is Overlong when the rest does not fit.
   procedure Close (Line : in out Line_Buffer) is
   begin
      Strip_Trailing_CR (Line);
      Line.Kind :=
        (if Texts.Length (Line.Text) > Limits.Max_Line_Length
         then Overlong
         else Whole);
   end Close;

   --  Sets the kind of the line Take_Runs just read, and passes over the
   --  byte that stopped it.  The end of the file before any byte is
   --  Past_End.  A byte that finds the buffer full makes the line
   --  Overlong, its text kept as read; the rest of the line stays unread.
   procedure End_Line (R : in out Reader; Line : in out Line_Buffer) is
   begin
      case Stop_Of (R) is
         when File_End      =>
            if Texts.Length (Line.Text) = Texts.Empty_Length then
               Line.Kind := Past_End;
            else
               Close (Line);
            end if;

         when Line_Feed     =>
            R.Next := R.Next + 1;
            Close (Line);

         when Past_Capacity =>
            R.Next := R.Next + 1;
            Line.Kind := Overlong;
      end case;
   end End_Line;

   procedure Read_Line (R : in out Reader; Line : out Line_Buffer) is
   begin
      Line.Text := Texts.Empty (Buffer_Capacity);
      Take_Runs (R, Line);
      End_Line (R, Line);
   end Read_Line;

   procedure Keep_Text (Result : in out Load_Result; Line : Line_Buffer) is
   begin
      Result.Text :=
        Texts.Truncated (Texts.Value (Line.Text), Limits.Max_Line_Length);
   end Keep_Text;

   Too_Many_Lines_Message : constant String := "more lines than it counts";

   --  Feeds R's lines to the parser until the end of the file, a
   --  refusal, or a line too long to feed; Line_Count counts the lines
   --  read.
   procedure Feed_Lines
     (R : in out Reader; Result : in out Load_Result; Line_Count : out Natural)
   is
      Line : Line_Buffer;
   begin
      Line_Count := 0;
      loop
         Read_Line (R, Line);
         exit when Line.Kind = Past_End;
         if Line_Count = Positive'Last then
            raise Ada.IO_Exceptions.Data_Error with Too_Many_Lines_Message;
         end if;
         Line_Count := Line_Count + 1;
         if Line.Kind = Overlong then
            Result.Status := Too_Long;
            Result.Line := Line_Number (Line_Count);
            Keep_Text (Result, Line);
            return;
         end if;
         Parse.Feed
           (Parser, Doc, Texts.Value (Line.Text), Source_Line (Line_Count));
         exit when Parse.Failed (Parser);
      end loop;
   end Feed_Lines;

   procedure Close_If_Open (R : in out Reader) is
   begin
      if Stream_IO.Is_Open (R.File) then
         Stream_IO.Close (R.File);
      end if;
   end Close_If_Open;

   --  Keeps line Result.Line of the file at Path as Result's text; the
   --  text stays empty when the file no longer reads.
   procedure Fetch_Line (Path : String; Result : in out Load_Result) is
      R    : Reader;
      Line : Line_Buffer;
   begin
      Stream_IO.Open (R.File, Stream_IO.In_File, Path);
      for Number in First_Line .. Result.Line loop
         Read_Line (R, Line);
         exit when Line.Kind = Past_End;
         if Number = Result.Line then
            Keep_Text (Result, Line);
         end if;
      end loop;
      Stream_IO.Close (R.File);
   exception
      when
        Ada.IO_Exceptions.Name_Error
        | Ada.IO_Exceptions.Use_Error
        | Ada.IO_Exceptions.Device_Error
        | Ada.IO_Exceptions.End_Error
      =>
         Close_If_Open (R);
   end Fetch_Line;

   --  Finish, then, on a refusal, the refused line's text.  A refusal
   --  already standing before Finish runs came from Feed; one that
   --  appears only after it came from Finish itself, at end of input
   --  with no next line to quote a token from.
   procedure Finish_Parse (Path : String; Result : in out Load_Result) is
      Failed_Before_Finish : constant Boolean := Parse.Failed (Parser);
   begin
      Parse.Finish (Parser, Doc);
      if Parse.Failed (Parser) then
         Result.Status := Refused;
         Result.Refusal := Parse.Error (Parser);
         Result.At_End := not Failed_Before_Finish;
         Result.Line := Result.Refusal.Line;
         Fetch_Line (Path, Result);
      else
         Result.Status := Loaded;
      end if;
   end Finish_Parse;

   --  The verdict once every line is read: a file with no line is Empty.
   procedure Conclude
     (Path : String; Line_Count : Natural; Result : in out Load_Result) is
   begin
      if Line_Count = 0 then
         Result.Status := Empty;
      else
         Finish_Parse (Path, Result);
      end if;
   end Conclude;

   procedure Load (Path : String; Result : out Load_Result) is
      R          : Reader;
      Line_Count : Natural;
   begin
      Result := (others => <>);
      Parse.Start (Parser, Doc);
      Stream_IO.Open (R.File, Stream_IO.In_File, Path);
      Feed_Lines (R, Result, Line_Count);
      Stream_IO.Close (R.File);
      if Result.Status /= Too_Long then
         Conclude (Path, Line_Count, Result);
      end if;
   exception
      when
        Ada.IO_Exceptions.Name_Error
        | Ada.IO_Exceptions.Use_Error
        | Ada.IO_Exceptions.Device_Error
        | Ada.IO_Exceptions.Data_Error
        | Ada.IO_Exceptions.End_Error
      =>
         Close_If_Open (R);
         Result := (others => <>);
   end Load;

   function Document return Args.Document_Access
   is (Doc'Access);

end Fabula.Shell.Files;
