/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  Bench_urgent.ahk -- end-to-end behavior test for the urgent-view
  feature. Unlike the Yunit harness (which calls Manager_onShellMessage
  with synthetic wParam/lParam against mocked Manager_managedWndIds),
  this scenario runs inside a real bugn-bench.exe process so the test
  exercises:

    - the real shell-hook registration (Manager_registerShellHook),
    - real Manager_manage / Manager__setWinProperties populating
      Manager_managedWndIds with whatever HWND format the OS is using,
    - real FlashWindowEx → HSHELL_FLASH delivery through the OS shell
      broadcast and into Manager_onShellMessage,
    - and the real Manager_markUrgent / Manager_activateUrgentView
      writing to the real per-monitor/per-view globals.

  Catches the failure mode the Yunit tests can't: a discrepancy between
  the HWND format bug.n uses internally and the format the OS hands to
  the shell hook for FlashWindowEx events. (Yunit tests pass synthetic
  decimal HWNDs; only the real shell hook reveals e.g. the SetFormat-
  hex/Manager-decimal mismatch that originally swallowed every flash in
  production.)

  Reuses Perf.ahk's spawn / wait-for-managed / cleanup helpers — the
  perf bench already proved cmd.exe is a reliable bug.n-managed test
  fixture. Refuses to run if the playground views (last two) hold live
  user windows. Restores the original view on exit.

  Exits with 0 on pass, 1 on fail (each failure is logged via
  Debug_logMessage at level 0). Invoked via `bugn-bench.exe --scenario
  urgent`.
*/

Bench_runUrgent() {
  Global Manager_aMonitor, Manager_managedWndIds, Config_viewCount

  aMonitor      := Manager_aMonitor
  originalView  := Monitor_#%aMonitor%_aView_#1
  testView      := Config_viewCount         ;; the urgent-target view
  awayView      := Config_viewCount - 1     ;; we sit here while flashing

  If Perf_viewHasLiveWindows(View_#%aMonitor%_#%testView%_wndIds)
    Or Perf_viewHasLiveWindows(View_#%aMonitor%_#%awayView%_wndIds) {
    Debug_logMessage("DEBUG[0] Bench_runUrgent: playground views " . awayView . "/" . testView . " on monitor " . aMonitor . " hold live user windows. Aborting to preserve them.", 0)
    ExitApp, 3
  }
  View_#%aMonitor%_#%testView%_wndIds := ""
  View_#%aMonitor%_#%awayView%_wndIds := ""

  ;; Land the spawned cmd on testView.
  Monitor_activateView(testView)
  Sleep, 200

  baselineWndIds := Manager_managedWndIds
  Run, %ComSpec% /k title bug.n_itest, , , spawnedPid
  If Not Perf_waitForManagedDelta(baselineWndIds, 1, 8000) {
    Debug_logMessage("DEBUG[0] Bench_runUrgent FAIL: cmd never registered as managed within 8s", 0)
    Bench_urgent_cleanup("", spawnedPid, originalView)
    ExitApp, 1
  }
  spawnedDiff := Perf_diffWndIds(baselineWndIds, Manager_managedWndIds)
  StringTrimRight, cmdHwnd, spawnedDiff, 1   ;; trim trailing ;
  Debug_logMessage("DEBUG[0] Bench_runUrgent: spawned cmd HWND=" . cmdHwnd . " on view " . testView, 0)
  Sleep, 500   ;; let arrange settle

  ;; Switch to awayView so testView (and the cmd on it) is hidden. This
  ;; is the point of the regression: bug.n SW_HIDEs every window on a
  ;; non-active view, and the dispatch must still surface those flashes.
  Monitor_activateView(awayView)
  Sleep, 300

  failures := 0

  If View_#%aMonitor%_#%testView%_isUrgent {
    Debug_logMessage("DEBUG[0] Bench_runUrgent FAIL: testView already urgent before flash (state leak)", 0)
    failures += 1
  }

  ;; FlashWindowEx with FLASHW_ALL (caption + taskbar). Each flash
  ;; produces one HSHELL_FLASH for every shell-hook listener.
  Bench_flashWindow(cmdHwnd, 5, 200)

  ;; Give the shell broadcast + Manager_onShellMessage time to dispatch.
  ;; HSHELL_FLASH events are synchronous to the message pump but we
  ;; sleep generously so this isn't tied to scheduler quirks.
  Sleep, 800

  If Not View_#%aMonitor%_#%testView%_isUrgent {
    Debug_logMessage("DEBUG[0] Bench_runUrgent FAIL: View_#" . aMonitor . "_#" . testView . "_isUrgent stayed False after FlashWindowEx — HSHELL_FLASH dispatch did not reach Manager_markUrgent for HWND " . cmdHwnd, 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runUrgent: ✓ testView marked urgent after flash", 0)
  }
  If Not Window_#%cmdHwnd%_isUrgent {
    Debug_logMessage("DEBUG[0] Bench_runUrgent FAIL: Window_#" . cmdHwnd . "_isUrgent stayed False — Manager_markUrgent loop did not flag the window", 0)
    failures += 1
  }

  ;; Now exercise Win+U.
  Manager_activateUrgentView()
  Sleep, 300

  If (Monitor_#%aMonitor%_aView_#1 != testView) {
    Debug_logMessage("DEBUG[0] Bench_runUrgent FAIL: Manager_activateUrgentView did not jump to view " . testView . ", landed on " . Monitor_#%aMonitor%_aView_#1, 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runUrgent: ✓ Win+U jumped to urgent view " . testView, 0)
  }
  If View_#%aMonitor%_#%testView%_isUrgent {
    Debug_logMessage("DEBUG[0] Bench_runUrgent FAIL: urgency on testView not cleared after activation", 0)
    failures += 1
  }

  Bench_urgent_cleanup(cmdHwnd ";", spawnedPid, originalView)

  If failures {
    Debug_logMessage("DEBUG[0] Bench_runUrgent: " . failures . " assertion(s) failed", 0)
    ExitApp, 1
  }
  Debug_logMessage("DEBUG[0] Bench_runUrgent: PASS — real-OS HSHELL_FLASH → Manager_markUrgent → Manager_activateUrgentView round-trip verified", 0)
  ExitApp, 0
}

;; FlashWindowEx wrapper. Builds the FLASHWINFO struct and DllCalls.
;;   hwnd     - target window handle
;;   count    - number of flashes
;;   timeoutMs - rate (ms) per flash
Bench_flashWindow(hwnd, count, timeoutMs) {
  Local fwi
  ;; FLASHWINFO layout: cbSize(4) + pad(4) + hwnd(8) + dwFlags(4) + uCount(4) + dwTimeout(4) = 32 bytes on x64.
  ;; On x64 the struct is naturally aligned: cbSize starts at 0, hwnd at 8.
  VarSetCapacity(fwi, 32, 0)
  NumPut(32,        fwi,  0, "UInt")     ;; cbSize
  NumPut(hwnd + 0,  fwi,  8, "Ptr")      ;; hwnd (force numeric so SetFormat hex doesn't break NumPut)
  NumPut(3,         fwi, 16, "UInt")     ;; dwFlags = FLASHW_ALL (caption | taskbar)
  NumPut(count,     fwi, 20, "UInt")     ;; uCount
  NumPut(timeoutMs, fwi, 24, "UInt")     ;; dwTimeout
  DllCall("user32.dll\FlashWindowEx", "Ptr", &fwi)
}

Bench_urgent_cleanup(cmdHwnd, spawnedPid, originalView) {
  Global Manager_aMonitor

  If cmdHwnd
    Perf_closeWndIds(cmdHwnd)
  Perf_killByTitle("bug.n_itest")
  Sleep, 200
  If spawnedPid
    Process, Close, %spawnedPid%
  Sleep, 300
  If (originalView And originalView != Monitor_#%Manager_aMonitor%_aView_#1)
    Monitor_activateView(originalView)
}
