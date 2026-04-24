/*
  Yunit output module for CI runs. Prints PASS/FAIL lines to stdout (same
  format as vendor/Yunit/Stdout.ahk) and increments TEST_FAIL_COUNT on
  failure so the runner can exit with a non-zero status.

  The counter globals are initialized in run.ahk's auto-execute block;
  this file only defines the module class.
*/

class CIReporter
{
  Update(Category, Test, Result)
  {
    global TEST_FAIL_COUNT, TEST_PASS_COUNT
    if IsObject(Result)
    {
      Details := " at line " . Result.Line . " " . Result.Message . " (" . Result.File . ")"
      Status := "FAIL"
      TEST_FAIL_COUNT += 1
    }
    else
    {
      Details := ""
      Status := "PASS"
      TEST_PASS_COUNT += 1
    }
    FileAppend, %Status%: %Category%.%Test%%Details%`n, *
  }
}
