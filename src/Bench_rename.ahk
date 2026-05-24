/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  Bench_rename.ahk -- end-to-end functional test for the view-rename
  hotkey (Win+/). Unlike Yunit, which covers the pure
  Manager_applyViewRename helper and the Config_saveSession /
  Config_restoreLayout filters in isolation, this scenario drives the
  full UI path inside a real bugn-bench.exe process:

    - Manager_renameView pops the InputBox.
    - A timer in the bench fills the edit control and clicks OK
      via ControlSetText / ControlClick (WM_-message based, no OS
      input queue — so the user's running bug.n hotkeys are safe).
    - Bar_init rebuilds each monitor's bar; we sample the renamed
      view element's width before and after to confirm it reflowed.
    - Config_saveSession round-trips through a temp file so we
      verify persistence end-to-end without touching the real
      _Layout.ini (Bench_cleanup never calls Manager_saveState).

  Exits with 0 on pass, 1 on fail (each failure is logged via
  Debug_logMessage at level 0). Invoked via `bugn-bench.exe
  --scenario rename`.
*/

Bench_runRename() {
  Global Manager_aMonitor, Manager_monitorCount, Manager_layoutDirty, Bench_rename_newName

  aMonitor      := Manager_aMonitor
  aView         := Monitor_#%aMonitor%_aView_#1
  originalName  := Config_viewNames_#%aView%
  renameTarget  := "bench-rename-" . A_TickCount

  ;; Sample bar element width before rename.
  GuiN := (aMonitor - 1) + 1
  Gui, %GuiN%: Default
  ;; GuiControlGet 'Pos' creates beforeX/Y/W/H from the base name.
  GuiControlGet, before, Pos, Bar_#%aMonitor%_view_#%aView%

  failures := 0

  ;; --- end-to-end rename through the dialog ---
  Bench_rename_newName := renameTarget
  SetTimer, Bench_rename_fillBox, -300
  Manager_renameView()
  SetTimer, Bench_rename_fillBox, Off  ;; safety in case the dialog never appeared

  Sleep, 200   ;; let bar rebuild settle

  If (Config_viewNames_#%aView% != renameTarget) {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: Config_viewNames_#" . aView . " expected '" . renameTarget . "', got '" . Config_viewNames_#%aView% . "'", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runRename: ✓ Config_viewNames_#" . aView . " mutated to '" . renameTarget . "'", 0)
  }

  GuiControlGet, after, Pos, Bar_#%aMonitor%_view_#%aView%
  If (afterW <= beforeW) {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: bar element width did not grow after rename (before=" . beforeW . " after=" . afterW . ") — Bar_init rebuild did not reflow", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runRename: ✓ bar element reflowed (width " . beforeW . " -> " . afterW . ")", 0)
  }

  If Not Manager_layoutDirty {
    Debug_logMessage("DEBUG[0] Bench_runRename FAIL: Manager_layoutDirty was not set after rename", 0)
    failures += 1
  }

  ;; --- persistence round-trip through a temp file (NOT Main_autoLayout) ---
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

  ;; Pretend a restart wiped the global, then restore from disk.
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

  ;; --- restore original name + rebuild bar so the bench leaves no trace ---
  Config_viewNames_#%aView% := originalName
  Loop, % Manager_monitorCount
    Bar_init(A_Index)
  Loop, % Manager_monitorCount
    Bar_updateView(A_Index, Monitor_#%A_Index%_aView_#1)

  If failures {
    Debug_logMessage("DEBUG[0] Bench_runRename: " . failures . " assertion(s) failed", 0)
    ExitApp, 1
  }
  Debug_logMessage("DEBUG[0] Bench_runRename: PASS — Win+/ dialog → Bar_init reflow → Config_saveSession/restoreLayout round-trip verified", 0)
  ExitApp, 0
}

;; Asynchronous filler. Manager_renameView's InputBox blocks the
;; auto-execute thread; this timer fires in its own AHK pseudo-thread
;; while the dialog is modal, locates it by title, and submits via
;; control messages (no OS input queue — so the user's running bug.n
;; never sees these keypresses).
Bench_rename_fillBox:
  ;; Per-thread match-mode override: standard Win32 dialog class is the
  ;; most reliable identifier for an AHK InputBox; the title-based match
  ;; (which Bench_main sets to mode 3 / exact) is fragile.
  SetTitleMatchMode, 2
  Debug_logMessage("DEBUG[0] Bench_runRename: fillBox timer fired, waiting for dialog", 0)
  WinWait, ahk_class #32770, , 3
  If ErrorLevel {
    Debug_logMessage("DEBUG[0] Bench_runRename: no #32770 dialog appeared within 3s", 0)
    Return
  }
  WinGetTitle, dlgTitle, ahk_class #32770
  Debug_logMessage("DEBUG[0] Bench_runRename: dialog found, title='" . dlgTitle . "', filling Edit1 with '" . Bench_rename_newName . "'", 0)
  ControlSetText, Edit1, %Bench_rename_newName%, ahk_class #32770
  If ErrorLevel
    Debug_logMessage("DEBUG[0] Bench_runRename: ControlSetText Edit1 failed (ErrorLevel=" . ErrorLevel . ")", 0)
  ControlClick, Button1, ahk_class #32770
  If ErrorLevel
    Debug_logMessage("DEBUG[0] Bench_runRename: ControlClick Button1 failed (ErrorLevel=" . ErrorLevel . ")", 0)
  Debug_logMessage("DEBUG[0] Bench_runRename: submitted, dialog should be closing", 0)
Return
