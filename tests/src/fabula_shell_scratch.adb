with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;

package body Fabula_Shell_Scratch is

   use Ada.Streams.Stream_IO;

   function Fresh_Dir (Name : String) return String is
      Path : constant String := Root & "/" & Name;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_Tree (Path);
      end if;
      Ada.Directories.Create_Path (Path);
      return Path;
   end Fresh_Dir;

   procedure Write_File (Path : String; Content : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      String'Write (Stream (F), Content);
      Close (F);
   end Write_File;

   function Read_File (Path : String) return String is
      F : File_Type;
   begin
      Open (F, In_File, Path);
      declare
         Content : String (1 .. Natural (Size (F)));
      begin
         String'Read (Stream (F), Content);
         Close (F);
         return Content;
      end;
   end Read_File;

   --  The capture file opens for APPEND: closing a Text_IO file that
   --  Text_IO itself never wrote to otherwise adds a line feed.  Its
   --  UTF-8 encoding makes a Text_IO.Put re-encode upper-half bytes, as
   --  a main built with -gnatW8 does, so only raw writes pass through.
   function Capture (Action : not null access procedure) return String is
      Path : constant String := Root & "/capture.txt";
      F    : Ada.Text_IO.File_Type;
   begin
      Ada.Directories.Create_Path (Root);
      Write_File (Path, "");
      Ada.Text_IO.Open (F, Ada.Text_IO.Append_File, Path, Form => "WCEM=8");
      Ada.Text_IO.Set_Output (F);
      begin
         Action.all;
      exception
         when others =>
            Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);
            Ada.Text_IO.Close (F);
            raise;
      end;
      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);
      Ada.Text_IO.Close (F);
      return Read_File (Path);
   end Capture;

end Fabula_Shell_Scratch;
