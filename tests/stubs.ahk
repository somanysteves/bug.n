/*
  Test-only stubs for symbols that live in src/Main.ahk and therefore
  can't be included in the test runner (Main.ahk has an auto-execute
  section that would actually start bug.n). Every other src/ file is
  loaded for real by tests/run.ahk.
*/

Main_evalCommand(command) {
  ; no-op — command-dispatch function defined in src/Main.ahk:70.
  ; Tests don't exercise callers that would invoke it.
}
