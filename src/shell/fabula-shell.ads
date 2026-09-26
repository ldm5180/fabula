--  The shell: the one layer that meets the outside world -- feature
--  files, the console, the report file and the user's own code.  Its
--  bodies stay outside the proof.  Every result it hands a caller is
--  typed, and an exception from the user's code stops here.

package Fabula.Shell
  with Pure, SPARK_Mode
is
end Fabula.Shell;
