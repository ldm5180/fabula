with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;

with Fabula.Ast;

package body Fabula.Shell.Files
  with SPARK_Mode => Off
is

   use Ada.Streams;
   use type Ada.Directories.File_Kind;

   ---------------------------------------------------------------------
   --  Split.
   ---------------------------------------------------------------------

   function All_Digits (S : String) return Boolean
   is (for all C of S => C in '0' .. '9');

   --  The line a group of digits names; 0 for an empty group, a zero,
   --  or a number past Positive'Last.
   function Line_Of (Group : String) return Natural is
      Value : Long_Long_Integer := 0;
   begin
      for C of Group loop
         Value :=
           Value
           * 10
           + Long_Long_Integer (Character'Pos (C) - Character'Pos ('0'));
         if Value > Long_Long_Integer (Positive'Last) then
            return 0;
         end if;
      end loop;
      return Natural (Value);
   end Line_Of;

   --  Adds Line unless it is there already.
   procedure Add
     (L : in out Line_Numbers; Line : Positive; Status : out Search_Status) is
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

   function Split (Argument : String) return Target is
      Result : Target;
      Last   : Natural := Argument'Last;
      Colon  : Natural;
   begin
      loop
         Colon :=
           Ada.Strings.Fixed.Index
             (Argument (Argument'First .. Last), ":", Ada.Strings.Backward);
         exit when
           Colon = 0 or else not All_Digits (Argument (Colon + 1 .. Last));
         if Line_Of (Argument (Colon + 1 .. Last)) = 0 then
            Result.Status := Bad_Line_Number;
            return Result;
         end if;
         Add
           (Result.Lines,
            Line_Of (Argument (Colon + 1 .. Last)),
            Result.Status);
         exit when Result.Status /= Found;
         Last := Colon - 1;
      end loop;
      if Result.Status = Found then
         if Last - Argument'First + 1 > Limits.Max_Path_Length then
            Result.Status := Path_Too_Long;
         else
            Frames.Set (Result.Path, Argument (Argument'First .. Last));
         end if;
      end if;
      return Result;
   end Split;

   ---------------------------------------------------------------------
   --  Discover.
   ---------------------------------------------------------------------

   package Name_Lists is new
     Ada.Containers.Indefinite_Vectors (Positive, String);
   package Name_Sorting is new Name_Lists.Generic_Sorting;

   Suffix : constant String := ".feature";

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
            if Name /= "." and then Name /= ".." then
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
         Frames.Set (List.Files (List.Count).Path, Path);
         List.Files (List.Count).Lines := Lines;
         Status := Found;
      end if;
   end Append;

   --  Every feature file beneath Dir, which sits Depth levels down from
   --  the argument (the argument itself is level 1).
   procedure Walk
     (Dir    : String;
      Depth  : Positive;
      List   : in out File_List;
      Status : out Search_Status) is
   begin
      Status := Found;
      if Depth > Limits.Max_Search_Depth then
         Status := Too_Deep;
         return;
      end if;
      for Name of Entries (Dir) loop
         declare
            Path : constant String := Ada.Directories.Compose (Dir, Name);
         begin
            if Is_Directory (Path) then
               Walk (Path, Depth + 1, List, Status);
            elsif Is_Feature_Name (Name) then
               Append (List, Path, (others => <>), Status);
            end if;
         end;
         exit when Status /= Found;
      end loop;
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
         Walk (Path, 1, List, Status);
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
      end if;
      if Status /= Found then
         List.Count := Kept;
      end if;
   end Discover;

   ---------------------------------------------------------------------
   --  Load.
   ---------------------------------------------------------------------

   Doc    : aliased Ast.Document;
   Parser : Parse.Parser;

   Chunk_Bytes : constant := 4_096;

   --  A file read line by line; its bytes arrive a chunk at a time.
   type Reader is limited record
      File  : Stream_IO.File_Type;
      Chunk : Stream_Element_Array (1 .. Chunk_Bytes);
      Next  : Stream_Element_Offset := 1;
      Last  : Stream_Element_Offset := 0;
   end record;

   type Line_Kind is (Whole, Overlong, Past_End);

   subtype Buffer_Length is Natural range 0 .. Limits.Max_Line_Length + 1;

   --  One line, Text (1 .. Len), without its LF or the CR that ends it.
   --  An Overlong line keeps its first characters; Past_End has none.
   type Line_Buffer is record
      Kind : Line_Kind := Past_End;
      Text : String (1 .. Limits.Max_Line_Length + 1);
      Len  : Buffer_Length := 0;
   end record;

   --  The next byte as a character; Got is False at the end of the file.
   procedure Next_Byte
     (R : in out Reader; C : out Character; Got : out Boolean) is
   begin
      if R.Next > R.Last then
         Stream_IO.Read (R.File, R.Chunk, R.Last);
         R.Next := R.Chunk'First;
      end if;
      Got := R.Next <= R.Last;
      C := (if Got then Character'Val (R.Chunk (R.Next)) else ASCII.NUL);
      if Got then
         R.Next := R.Next + 1;
      end if;
   end Next_Byte;

   procedure Read_Line (R : in out Reader; Line : out Line_Buffer) is
      C       : Character;
      Got     : Boolean;
      Started : Boolean := False;
   begin
      Line.Kind := Whole;
      Line.Len := 0;
      loop
         Next_Byte (R, C, Got);
         exit when not Got or else C = ASCII.LF;
         Started := True;
         if Line.Len = Line.Text'Last then
            Line.Kind := Overlong;
            return;
         end if;
         Line.Len := Line.Len + 1;
         Line.Text (Line.Len) := C;
      end loop;
      if not Got and then not Started then
         Line.Kind := Past_End;
      elsif Line.Len > 0 and then Line.Text (Line.Len) = ASCII.CR then
         Line.Len := Line.Len - 1;
      end if;
      if Line.Len > Limits.Max_Line_Length then
         Line.Kind := Overlong;
      end if;
   end Read_Line;

   procedure Keep_Text (Result : in out Load_Result; Line : Line_Buffer) is
      Len : constant Natural := Natural'Min (Line.Len, Limits.Max_Line_Length);
   begin
      Result.Text (1 .. Len) := Line.Text (1 .. Len);
      Result.Len := Len;
   end Keep_Text;

   --  Feeds R's lines to the parser until the end of the file, a
   --  refusal, or a line too long to feed; Lines counts the lines read.
   procedure Feed_Lines
     (R : in out Reader; Result : in out Load_Result; Lines : out Natural)
   is
      Line : Line_Buffer;
   begin
      Lines := 0;
      loop
         Read_Line (R, Line);
         exit when Line.Kind = Past_End;
         if Lines = Positive'Last then
            raise Ada.IO_Exceptions.Data_Error
              with "more lines than it counts";
         end if;
         Lines := Lines + 1;
         if Line.Kind = Overlong then
            Result.Status := Too_Long;
            Result.Line := Lines;
            Keep_Text (Result, Line);
            return;
         end if;
         Parse.Feed (Parser, Doc, Line.Text (1 .. Line.Len), Lines);
         exit when Parse.Failed (Parser);
      end loop;
   end Feed_Lines;

   --  Keeps line Result.Line of the file at Path as Result's text; the
   --  text stays empty when the file no longer reads.
   procedure Fetch_Line (Path : String; Result : in out Load_Result) is
      R    : Reader;
      Line : Line_Buffer;
   begin
      Stream_IO.Open (R.File, Stream_IO.In_File, Path);
      for Number in 1 .. Result.Line loop
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
         if Stream_IO.Is_Open (R.File) then
            Stream_IO.Close (R.File);
         end if;
   end Fetch_Line;

   --  The verdict once every line is read: Finish, then keep the refused
   --  line's text.
   procedure Conclude
     (Path : String; Lines : Natural; Result : in out Load_Result) is
   begin
      if Lines = 0 then
         Result.Status := Empty;
         return;
      end if;
      Parse.Finish (Parser, Doc);
      if Parse.Failed (Parser) then
         Result.Status := Refused;
         Result.Refusal := Parse.Error (Parser);
         Result.Line := Result.Refusal.Line;
         Fetch_Line (Path, Result);
      else
         Result.Status := Loaded;
      end if;
   end Conclude;

   procedure Load (Path : String; Result : out Load_Result) is
      R     : Reader;
      Lines : Natural;
   begin
      Result := (others => <>);
      Parse.Start (Parser, Doc);
      Stream_IO.Open (R.File, Stream_IO.In_File, Path);
      Feed_Lines (R, Result, Lines);
      Stream_IO.Close (R.File);
      if Result.Status /= Too_Long then
         Conclude (Path, Lines, Result);
      end if;
   exception
      when
        Ada.IO_Exceptions.Name_Error
        | Ada.IO_Exceptions.Use_Error
        | Ada.IO_Exceptions.Device_Error
        | Ada.IO_Exceptions.Data_Error
        | Ada.IO_Exceptions.End_Error
      =>
         if Stream_IO.Is_Open (R.File) then
            Stream_IO.Close (R.File);
         end if;
         Result := (others => <>);
   end Load;

   function Document return Args.Document_Access
   is (Doc'Access);

end Fabula.Shell.Files;
