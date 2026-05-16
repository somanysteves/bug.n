/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  Bench_titleStorm.ahk -- HSHELL_REDRAW storm benchmark.

  Reproduces the workload that triggered the intermittent hotkey lag:
  rapid title changes on a managed window fire one HSHELL_REDRAW per
  change, each of which lands in Manager_onShellMessage. The default
  WinGetTitle path inside that handler uses SendMessageTimeout with a
  five-second default; on a slow window every call can block sub-second
  durations, starving hotkeys. This bench drives N WinSetTitle calls
  back-to-back and measures how long bug.n takes to handle the resulting
  redraw event burst.

  cmd.exe responds to WM_GETTEXT quickly, so this scenario does not
  reproduce the worst-case multi-second blocks. It measures the baseline
  per-event cost in Manager_onShellMessage; a change that removes
  WinGetTitle calls from the hot path will show up as a lower median /
  p95 even on responsive windows.

  Invoked via `bugn-bench.exe --scenario titlestorm [--iterations N]`.
  Refuses to run if the playground view (Config_viewCount) holds live
  user windows. Restores the original view on exit. Exits with 0 on
  pass, 1 on failure (fewer than half the expected Manager_onShell-
  Message samples arrived -- either the shell hook isn't wired or the
  events are coalescing more than expected).
*/

Bench_runTitleStorm() {
  Global Manager_aMonitor, Manager_managedWndIds, Config_viewCount
  Global Bench_iterations, Perf_samples

  aMonitor      := Manager_aMonitor
  originalView  := Monitor_#%aMonitor%_aView_#1
  testView      := Config_viewCount

  If Perf_viewHasLiveWindows(View_#%aMonitor%_#%testView%_wndIds) {
    Debug_logMessage("DEBUG[0] Bench_runTitleStorm: playground view " . testView . " on monitor " . aMonitor . " holds live user windows. Aborting to preserve them.", 0)
    ExitApp, 3
  }
  View_#%aMonitor%_#%testView%_wndIds := ""

  Monitor_activateView(testView)
  Sleep, 200

  baselineWndIds := Manager_managedWndIds
  Run, %ComSpec% /k title bug.n_titlestorm, , , spawnedPid
  If Not Perf_waitForManagedDelta(baselineWndIds, 1, 8000) {
    Debug_logMessage("DEBUG[0] Bench_runTitleStorm FAIL: cmd never registered as managed within 8s", 0)
    Bench_titleStorm_cleanup("", spawnedPid, originalView)
    ExitApp, 1
  }
  spawnedDiff := Perf_diffWndIds(baselineWndIds, Manager_managedWndIds)
  StringTrimRight, cmdHwnd, spawnedDiff, 1
  Debug_logMessage("DEBUG[0] Bench_runTitleStorm: spawned cmd HWND=" . cmdHwnd . " on view " . testView, 0)
  Sleep, 800   ;; let arrange + any pending shell events settle

  ;; Discard setup-phase samples so we measure only the storm.
  Perf_resetSamples()
  Sleep, 100

  ;; Fire N WinSetTitle calls back-to-back. Each invocation calls
  ;; SetWindowText synchronously on cmd, after which the shell
  ;; broadcasts HSHELL_REDRAW to every listener (including us).
  ;; Events queue at the message pump until we yield -- the drain
  ;; loop below is what actually times the handler.
  t0 := A_TickCount
  Loop, % Bench_iterations {
    newTitle := "bug.n_titlestorm_" . A_Index
    WinSetTitle, ahk_id %cmdHwnd%, , %newTitle%
  }
  loopMs := A_TickCount - t0

  ;; Drain: wait for the shell-hook event queue to settle. We poll the
  ;; Perf_samples count for "Manager_onShellMessage" -- when it stops
  ;; growing for two consecutive 100 ms windows, the storm is done.
  drainStart := A_TickCount
  prevCount  := -1
  stableTicks := 0
  Loop {
    Sleep, 100
    n := 0
    If Perf_samples.HasKey("Manager_onShellMessage")
      n := Perf_samples["Manager_onShellMessage"].MaxIndex()
    If (n = prevCount And n > 0) {
      stableTicks += 1
      If (stableTicks >= 2)
        Break
    } Else {
      stableTicks := 0
    }
    prevCount := n
    If (A_TickCount - drainStart > 15000) {
      Debug_logMessage("DEBUG[0] Bench_runTitleStorm WARN: drain timed out at 15s with " . n . " samples", 0)
      Break
    }
  }
  totalMs := A_TickCount - t0

  eventCount := 0
  If Perf_samples.HasKey("Manager_onShellMessage")
    eventCount := Perf_samples["Manager_onShellMessage"].MaxIndex()

  Debug_logMessage("DEBUG[0] Bench_runTitleStorm: " . Bench_iterations . " WinSetTitle calls in " . loopMs . " ms; " . eventCount . " Manager_onShellMessage samples; total " . totalMs . " ms", 0)

  ;; Floor at half iterations (min 1): empirically the mapping is ~1:1, but
  ;; allow some coalescing loss while still catching wrong-cmdHwnd / hook-
  ;; unregistered failures from passing on a single stray sample.
  failures := 0
  minEvents := Max(Bench_iterations // 2, 1)
  If (eventCount < minEvents) {
    Debug_logMessage("DEBUG[0] Bench_runTitleStorm FAIL: only " . eventCount . " Manager_onShellMessage samples out of " . Bench_iterations . " WinSetTitle calls (expected at least " . minEvents . ")", 0)
    failures += 1
  }

  ;; Write the per-event distribution row(s) -- existing Perf_writeRow
  ;; turns Perf_samples into min/median/p95/max columns per label.
  ;; Manager_onShellMessage_full wraps the whole handler (covers every
  ;; title-fetch site we're optimizing); Manager_onShellMessage is the
  ;; inner dispatch phase. Both should be populated -- Perf_writeRow
  ;; warns if either is missing.
  Perf_writeHeader()
  Perf_writeRow("titlestorm", 1, "Manager_onShellMessage_full,Manager_onShellMessage")

  Bench_titleStorm_cleanup(cmdHwnd . ";", spawnedPid, originalView)

  If failures {
    Debug_logMessage("DEBUG[0] Bench_runTitleStorm: " . failures . " assertion(s) failed", 0)
    ExitApp, 1
  }
  Debug_logMessage("DEBUG[0] Bench_runTitleStorm: PASS -- HSHELL_REDRAW storm processed, see CSV for per-event distribution", 0)
  ExitApp, 0
}

Bench_titleStorm_cleanup(cmdHwnd, spawnedPid, originalView) {
  Global Manager_aMonitor

  If cmdHwnd
    Perf_closeWndIds(cmdHwnd)
  Perf_killByTitle("bug.n_titlestorm")
  Sleep, 200
  If spawnedPid
    Process, Close, %spawnedPid%
  Sleep, 300
  If (originalView And originalView != Monitor_#%Manager_aMonitor%_aView_#1)
    Monitor_activateView(originalView)
}
