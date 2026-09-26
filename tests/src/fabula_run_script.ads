--  A scripted shell for the runner: it drains requests and notices,
--  answers each request from the test's own outcome functions, and
--  writes one trace line per request and per notice.  No user code,
--  no IO.
with Ada.Containers.Indefinite_Vectors;

with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Results;
with Fabula.Run;

with Fabula_Fixtures;

package Fabula_Run_Script is

   package Traces is new Ada.Containers.Indefinite_Vectors (Positive, String);
   subtype Trace is Traces.Vector;

   --  Fails the test, naming the first line where Got and Want part.
   procedure Assert_Trace (Got : Trace; Want : Fabula_Fixtures.Lines);

   --  Fails the test with both sets of counters spelled out.
   procedure Assert_Counts (Got, Want : Fabula.Results.Counts);

   generic
      with package Run is new Fabula.Run (<>);

      with
        function Hook_Outcome
          (Kind : Run.Reg.Hook_Kind; Frame : Fabula.Frames.Frame)
           return Fabula.Check.Outcome;

      with
        function Step_Outcome
          (Kind : Run.Reg.Step_Kind) return Fabula.Check.Outcome;

      --  Extra trace text for a step request, read from its arguments.
      with
        function Step_Note
          (Kind : Run.Reg.Step_Kind;
           A    : Fabula.Args.List;
           F    : Fabula.Frames.Frame) return String;
   package Shell is

      --  Answers requests and resumes notices until the runner idles.
      procedure Drain (R : in out Run.Runner; Log : in out Trace);

      --  A whole run over one parsed document: start, the feature,
      --  finish, each drained.  The document is Fabula_Run_Script.Doc.
      procedure Run_One
        (Source    : Fabula_Fixtures.Lines;
         Opts      : Run.Options;
         Selection : Run.Line_Selection;
         Log       : out Trace;
         R         : out Run.Runner);

   end Shell;

   --  One library-level document the shells run against.
   procedure Load (Source : Fabula_Fixtures.Lines);

   function Doc_Ref return Fabula.Args.Document_Access;

end Fabula_Run_Script;
