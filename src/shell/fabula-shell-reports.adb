with Ada.IO_Exceptions;

with Fabula.Shell.Console;

package body Fabula.Shell.Reports
  with SPARK_Mode => Off
is

   use Ada.Streams.Stream_IO;

   procedure Open (R : in out Report; Path : String; Result : out Status) is
   begin
      if Is_Open (R) then
         Result := Already_Open;
         return;
      elsif Path = "" then
         Result := Open_Failed;
         return;
      end if;
      Create (R.File, Out_File, Path);
      R.Where := To_File;
      Result := Ok;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Result := Open_Failed;
   end Open;

   procedure Open_Console (R : in out Report; Result : out Status) is
   begin
      if Is_Open (R) then
         Result := Already_Open;
      else
         R.Where := To_Console;
         Result := Ok;
      end if;
   end Open_Console;

   --  The console reports its own failures by a flag that stays set, so
   --  a write fails when the flag rises during it.
   procedure Write_To_Console (Chunk : String; Result : out Status) is
      Before : constant Boolean := Console.Write_Failed;
   begin
      Console.Put (Chunk);
      Result :=
        (if Console.Write_Failed and then not Before
         then Write_Failed
         else Ok);
   end Write_To_Console;

   procedure Write (R : in out Report; Chunk : String; Result : out Status) is
   begin
      case R.Where is
         when Nowhere    =>
            Result := Not_Open;

         when To_Console =>
            Write_To_Console (Chunk, Result);

         when To_File    =>
            String'Write (Stream (R.File), Chunk);
            Result := Ok;
      end case;
   exception
      when Ada.IO_Exceptions.Device_Error | Ada.IO_Exceptions.Use_Error =>
         Result := Write_Failed;
   end Write;

   procedure Close (R : in out Report; Result : out Status) is
      Was : constant Target := R.Where;
   begin
      R.Where := Nowhere;
      Result := (if Was = Nowhere then Not_Open else Ok);
      if Was = To_File then
         Close (R.File);
      end if;
   exception
      when Ada.IO_Exceptions.Device_Error | Ada.IO_Exceptions.Use_Error =>
         Result := Write_Failed;
   end Close;

end Fabula.Shell.Reports;
