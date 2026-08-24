/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  Bench_spawnPin.ahk -- end-to-end behavior test for the spawn-pin
  feature (Manager_consumeSpawnPin). The Yunit suite already covers the
  pin-file parsing, FIFO ordering, staleness, and monitor/tags copy in
  isolation with synthetic globals. This scenario runs inside a real
  bugn-bench.exe process to exercise what Yunit can't:

    - the real Manager_manage path taking a *real* new window through the
      tags = 0 default, WinGet ProcessName filter, and consumeSpawnPin,
    - the real OS HWND format flowing through Manager_isManaged (the same
      hex/decimal mismatch class of bug the urgent bench guards against),
    - a genuine Alacritty (alacritty.exe) window, so the process-name
      filter is validated against the actual shipped terminal.

  Shape: land a reference window (mspaint) on the reference view, drop a
  fresh pin for its HWND (the producer's job in production), drift the
  active view away, then spawn Alacritty and assert it lands on the
  reference view -- NOT the active view -- and that the pin line is gone.

  Reuses Perf.ahk spawn/wait/cleanup helpers. Refuses to run if the two
  playground views hold live user windows; restores the original view on
  exit. Exit 0 pass, 1 fail, 3 skip (playground occupied / Alacritty
  absent). Invoked via `bugn-bench.exe --scenario spawnpin`.
*/

Bench_runSpawnPin() {
  Global Manager_aMonitor, Manager_managedWndIds, Config_viewCount, Main_dataDir

  aMonitor     := Manager_aMonitor
  originalView := Monitor_#%aMonitor%_aView_#1
  refView      := Config_viewCount         ;; the reference window's view
  activeView   := Config_viewCount - 1     ;; we sit here when the pin fires
  pinFile      := Main_dataDir . "\spawn-pins.txt"

  If Perf_viewHasLiveWindows(View_#%aMonitor%_#%refView%_wndIds)
    Or Perf_viewHasLiveWindows(View_#%aMonitor%_#%activeView%_wndIds) {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin: playground views " . activeView . "/" . refView . " on monitor " . aMonitor . " hold live user windows. Aborting to preserve them.", 0)
    ExitApp, 3
  }
  View_#%aMonitor%_#%refView%_wndIds    := ""
  View_#%aMonitor%_#%activeView%_wndIds := ""

  ;; 1. Land a reference window on refView (its monitor + tags is what a
  ;;    matching spawn should inherit).
  Monitor_activateView(refView)
  Sleep, 200
  baseline := Manager_managedWndIds
  Run, mspaint.exe, , , refPid
  If Not Perf_waitForManagedDelta(baseline, 1, 8000) {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin FAIL: reference mspaint never registered as managed within 8s", 0)
    Bench_spawnPin_cleanup("", refPid, "", "", originalView, pinFile)
    ExitApp, 1
  }
  refDiff := Perf_diffWndIds(baseline, Manager_managedWndIds)
  StringTrimRight, refHwnd, refDiff, 1
  refMon  := Window_#%refHwnd%_monitor
  refTags := Window_#%refHwnd%_tags
  Debug_logMessage("DEBUG[0] Bench_runSpawnPin: reference mspaint HWND=" . refHwnd . " monitor=" . refMon . " tags=" . refTags . " on view " . refView, 0)
  Sleep, 300

  ;; 2. Producer stand-in: append one fresh pin for the reference HWND.
  ;;    Decimal, per the contract; A_NowUTC -> unix epoch for the timestamp.
  refDec := refHwnd + 0
  now := A_NowUTC
  now -= 19700101000000, Seconds
  If FileExist(pinFile)
    FileDelete, %pinFile%
  FileAppend, % refDec . " " . now . "`n", %pinFile%

  ;; 3. Drift the active view away -- without the pin the spawn would land
  ;;    here (activeView), not on refView.
  Monitor_activateView(activeView)
  Sleep, 300

  ;; 4. Spawn the pinned terminal.
  baseline2 := Manager_managedWndIds
  Run, alacritty.exe, , UseErrorLevel, alacrittyPid
  If ErrorLevel {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin: alacritty.exe could not be launched (not installed?). Skipping.", 0)
    Bench_spawnPin_cleanup(refHwnd . ";", refPid, "", "", originalView, pinFile)
    ExitApp, 3
  }
  If Not Perf_waitForManagedDelta(baseline2, 1, 12000) {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin FAIL: Alacritty never registered as managed within 12s", 0)
    Bench_spawnPin_cleanup(refHwnd . ";", refPid, "", alacrittyPid, originalView, pinFile)
    ExitApp, 1
  }
  alacDiff := Perf_diffWndIds(baseline2, Manager_managedWndIds)
  StringTrimRight, alacHwnd, alacDiff, 1
  alacMon  := Window_#%alacHwnd%_monitor
  alacTags := Window_#%alacHwnd%_tags
  Debug_logMessage("DEBUG[0] Bench_runSpawnPin: Alacritty HWND=" . alacHwnd . " monitor=" . alacMon . " tags=" . alacTags, 0)

  failures := 0

  If (alacTags != refTags) {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin FAIL: pinned window tags=" . alacTags . " expected " . refTags . " (refView " . refView "); active view was " . activeView, 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin: ✓ pinned window inherited the reference view (tags=" . alacTags . "), not the active view", 0)
  }
  If (alacMon != refMon) {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin FAIL: pinned window monitor=" . alacMon . " expected " . refMon, 0)
    failures += 1
  }
  If Not InStr(View_#%aMonitor%_#%refView%_wndIds, alacHwnd) {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin FAIL: pinned window not placed in refView " . refView . " wndIds list", 0)
    failures += 1
  }

  ;; 5. The consumed pin line must be gone.
  pinLeft := ""
  If FileExist(pinFile)
    FileRead, pinLeft, %pinFile%
  If InStr(pinLeft, refDec) {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin FAIL: pin line for " . refDec . " not consumed; file still holds it", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin: ✓ pin line consumed", 0)
  }

  Bench_spawnPin_cleanup(refHwnd . ";", refPid, alacHwnd . ";", alacrittyPid, originalView, pinFile)

  If failures {
    Debug_logMessage("DEBUG[0] Bench_runSpawnPin: " . failures . " assertion(s) failed", 0)
    ExitApp, 1
  }
  Debug_logMessage("DEBUG[0] Bench_runSpawnPin: PASS — real Alacritty spawn inherited the pinned monitor+view via Manager_manage/consumeSpawnPin", 0)
  ExitApp, 0
}

Bench_spawnPin_cleanup(refHwnd, refPid, alacHwnd, alacPid, originalView, pinFile) {
  Global Manager_aMonitor

  If alacHwnd
    Perf_closeWndIds(alacHwnd)
  If refHwnd
    Perf_closeWndIds(refHwnd)
  Sleep, 200
  If alacPid
    Process, Close, %alacPid%
  If refPid
    Process, Close, %refPid%
  If (pinFile And FileExist(pinFile))
    FileDelete, %pinFile%
  Sleep, 300
  If (originalView And originalView != Monitor_#%Manager_aMonitor%_aView_#1)
    Monitor_activateView(originalView)
}
