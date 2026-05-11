/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3

  Bench_dispatch.ahk -- microbench for the per-keypress hotkey
  dispatch path (Config_redirectHotkey). Refactor B routed the
  static `#k::Func()` directives through Config_setHotkey() so the
  popup can enumerate them, which moved each keypress from a
  direct AHK function call to a label-dispatched lookup over
  Config_hotkey_#N_*. The window-management bench scenarios don't
  exercise this path -- they call Manager_*/View_*/Tiler_*
  functions directly. This scenario measures dispatch in
  isolation by calling Config_redirectHotkey N times against a
  representative key (mid-list index = average lookup depth) and
  reports per-call cost via QueryPerformanceCounter.

  Bench's Main_evalCommand is a no-op stub, so this measures the
  lookup loop + parameter-name parsing in Main_evalCommand without
  the cost of the destination function. That's the right thing to
  isolate -- the destination function's cost is unchanged by the
  refactor; only the dispatch wrapper is new.
*/

Bench_runDispatch(iterations) {
  Global Config_hotkeyCount

  If (iterations < 1)
    iterations := 100000

  If (Config_hotkeyCount = 0) {
    Debug_logMessage("DEBUG[0] Bench_runDispatch FAIL: no hotkeys registered (Config_hotkeyCount = 0). Refactor-B build expected ~110 defaults from Config_initDefaultHotkeys().", 0)
    ExitApp, 1
  }

  ;; Mid-list key gives average-case lookup depth (the loop in
  ;; Config_redirectHotkey scans linearly until match). First or last
  ;; would skew best/worst case.
  midIdx := Round(Config_hotkeyCount / 2)
  key    := Config_hotkey_#%midIdx%_key

  If (key = "") {
    Debug_logMessage("DEBUG[0] Bench_runDispatch FAIL: key at mid-index " . midIdx . " is empty (tombstone or count drift)", 0)
    ExitApp, 1
  }

  Debug_logMessage("DEBUG[0] Bench_runDispatch: timing " . iterations . " calls of Config_redirectHotkey(""" . key . """) against " . Config_hotkeyCount . " registered hotkeys", 0)

  DllCall("QueryPerformanceFrequency", "Int64*", freq)
  DllCall("QueryPerformanceCounter",   "Int64*", t0)
  Loop, %iterations% {
    Config_redirectHotkey(key)
  }
  DllCall("QueryPerformanceCounter",   "Int64*", t1)

  elapsedMs := (t1 - t0) * 1000.0 / freq
  perCallUs := elapsedMs * 1000.0 / iterations

  Debug_logMessage("DEBUG[0] Bench_runDispatch: " . iterations . " calls in " . Round(elapsedMs, 3) . "ms = " . Round(perCallUs, 3) . "us/call (key=" . key . ", hotkeyCount=" . Config_hotkeyCount . ")", 0)
  ExitApp, 0
}
