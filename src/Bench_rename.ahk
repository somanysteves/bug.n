/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  Bench_rename.ahk -- end-to-end functional test for view-rename
  inside a real bugn-bench.exe process. Drives Manager_applyViewRename
  + persistence with real Win32 IO (Config_saveSession / restoreLayout
  through a temp file) — but does NOT touch the bar GUI.

  The other bench scenarios (urgent / dispatch / titlestorm) only
  call Manager functions, never Bar_init. Following that pattern is
  load-bearing: re-running Bar_init from the bench's scenario code
  registers extra appbars (SHAppBarMessage ABM_NEW at Bar.ahk:159),
  and on Win11 those churn the workspace slot the user's bug.n bar
  has reserved — observed on real hardware to drop the user's bar's
  workspace reservation, leaving the bar visible but apps tiling
  over it until reload.

  Bar reflow is therefore not exercised here directly; we instead
  verify the underlying width calculation (Bar_getTextWidth) returns
  a larger value for the renamed name. The Bar_init loop itself is
  well-trodden code (used by every monitor connect / resolution
  change in Manager_resetMonitorConfiguration), and Yunit covers
  the rename helper that feeds it (test_Manager_applyViewRename).

  Custom Gui in Manager_renameView is wet-tested by the user.

  Exits 0 on pass, 1 on fail. Invoked via
  `bugn-bench.exe --scenario rename`.
*/

Bench_runRename() {
  Global Manager_aMonitor, Manager_layoutDirty

  aMonitor      := Manager_aMonitor
  aView         := Monitor_#%aMonitor%_aView_#1
  originalName  := Config_viewNames_#%aView%
  renameTarget  := "bench-rename-" . A_TickCount

  failures := 0

  ;; --- state mutation ---
  If Not Manager_applyViewRename(aView, renameTarget) {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: Manager_applyViewRename returned False for fresh name '" . renameTarget . "'", 0)
    ExitApp, 1
  }

  If (Config_viewNames_#%aView% != renameTarget) {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: Config_viewNames_#" . aView . " expected '" . renameTarget . "', got '" . Config_viewNames_#%aView% . "'", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runRename: ✓ Config_viewNames_#" . aView . " mutated to '" . renameTarget . "'", 0)
  }

  If Not Manager_layoutDirty {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: Manager_layoutDirty was not set after rename", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runRename: ✓ Manager_layoutDirty set", 0)
  }

  ;; --- width math: Bar_init reflows based on Bar_getTextWidth, so
  ;; assert the underlying width calc grows with the longer name ---
  oldDisplayedWidth := Bar_getTextWidth(" " . originalName . " ")
  newDisplayedWidth := Bar_getTextWidth(" " . renameTarget . " ")
  If (newDisplayedWidth <= oldDisplayedWidth) {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: renamed name doesn't compute a larger width (old=" . oldDisplayedWidth . " new=" . newDisplayedWidth . ")", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runRename: ✓ Bar_getTextWidth grew (" . oldDisplayedWidth . " -> " . newDisplayedWidth . ")", 0)
  }

  ;; --- persistence round-trip through a temp file ---
  tempFile := A_Temp . "\bugn_bench_rename.ini"
  If FileExist(tempFile)
    FileDelete, %tempFile%
  If FileExist(tempFile . ".tmp")
    FileDelete, %tempFile%.tmp

  Config_saveSession("", tempFile)
  FileRead, content, %tempFile%
  expectedLine := "Config_viewNames_#" . aView . "=" . renameTarget
  If (InStr(content, expectedLine) = 0) {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: saved file did not contain '" . expectedLine . "'; got:`n" . content, 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runRename: ✓ saved file contains '" . expectedLine . "'", 0)
  }

  Config_viewNames_#%aView% := "stale"
  Config_restoreLayout(tempFile, aMonitor)
  If (Config_viewNames_#%aView% != renameTarget) {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: restoreLayout did not load name back; expected '" . renameTarget . "', got '" . Config_viewNames_#%aView% . "'", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runRename: ✓ restoreLayout round-tripped name from disk", 0)
  }

  If FileExist(tempFile)
    FileDelete, %tempFile%
  If FileExist(tempFile . ".tmp")
    FileDelete, %tempFile%.tmp

  ;; Restore the in-memory state name so Bench_cleanup leaves it
  ;; consistent with what the user's session expects on next read.
  ;; (No Bar_init call — see header comment.)
  Config_viewNames_#%aView% := originalName

  If failures {
    Debug_logMessage("DEBUG[0] Bench_runRename: " . failures . " assertion(s) failed", 0)
    ExitApp, 1
  }
  Debug_logMessage("DEBUG[0] Bench_runRename: PASS", 0)
  ExitApp, 0
}
