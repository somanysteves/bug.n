/*
  Test-only stubs for symbols referenced at load time by src/ files but
  not exercised by the functions under test. AHK v1 resolves function
  references eagerly, so including a source file requires every callee
  to be defined somewhere — these no-ops satisfy that requirement.

  If a test ever needs the real behaviour of one of these, either include
  the real source file ahead of this stub, or delete the stub and pull in
  the real dependency.
*/

Debug_logMessage(msg, level := 0) {
  ; no-op
}

Window_move(wndId, x, y, w, h) {
  ; no-op
}

Manager_loop(index, increment, lowerBound, upperBound) {
  ; stub — real implementation at src/Manager.ahk:296. Tiler_setAxis
  ; references it, but no current test exercises that path. When a suite
  ; covers Manager_loop (or Tiler_setAxis) directly, drop this stub and
  ; include the real source.
  Return, 0
}
