/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  Perf.ahk -- lightweight benchmarking + timing instrumentation.

  Two pieces:
  (1) Perf_start / Perf_end wrap hot functions. When Perf_enabled is False
      (the default) they're cheap no-ops, so production runs are unaffected.
  (2) Perf_runBench drives a fixed scenario (spawn N cmd windows, switch
      views, move windows, arrange) and writes a CSV row per (scenario,
      phase) with min/median/p95/max latencies. Triggered by `bugn-bench.exe`.
*/

Perf_init(enabled, csvPath, commit) {
  Global Perf_enabled, Perf_csvPath, Perf_commit, Perf_starts, Perf_samples, Perf_qpcFrequency

  Perf_enabled := enabled
  Perf_csvPath := csvPath
  Perf_commit  := commit
  Perf_starts  := {}
  Perf_samples := {}

  ;; QueryPerformanceCounter for sub-millisecond timing. A_TickCount has
  ;; ~15.6 ms resolution on Windows (one system clock tick), which is far
  ;; too coarse for the sub-tick operations we measure (e.g. a
  ;; Manager_onShellMessage call on a responsive window takes ~1-2 ms).
  ;; Frequency is "counts per second" and is constant for the life of the
  ;; process, so we cache it once here. CSV column names (min_ms etc.)
  ;; keep their ms denomination but now carry fractional precision.
  ;;
  ;; No error check on the DllCall: per MSDN, QueryPerformanceFrequency
  ;; on Windows XP+ "will always succeed and will thus never return zero"
  ;; (https://learn.microsoft.com/en-us/windows/win32/api/profileapi/nf-profileapi-queryperformancefrequency).
  freq := 0
  DllCall("QueryPerformanceFrequency", "Int64*", freq)
  Perf_qpcFrequency := freq
}

Perf_start(label) {
  Global Perf_enabled, Perf_starts

  If Not Perf_enabled
    Return
  now := 0
  DllCall("QueryPerformanceCounter", "Int64*", now)
  Perf_starts[label] := now
}

Perf_end(label) {
  Global Perf_enabled, Perf_starts, Perf_samples, Perf_qpcFrequency

  If Not Perf_enabled
    Return
  If Not Perf_starts.HasKey(label)
    Return
  now := 0
  DllCall("QueryPerformanceCounter", "Int64*", now)
  ;; counts → ms (float). Multiply before divide so we don't truncate
  ;; sub-millisecond intervals to zero.
  deltaMs := (now - Perf_starts[label]) * 1000.0 / Perf_qpcFrequency
  If Not Perf_samples.HasKey(label)
    Perf_samples[label] := []
  Perf_samples[label].Push(deltaMs)
}

Perf_resetSamples() {
  Global Perf_samples
  Perf_samples := {}
}

;; Sort an AHK array of numbers ascending. Returns a `n-delimited string
;; that callers can `StringSplit` to access by 1-based index.
Perf_sortAscending(samples) {
  str := ""
  For idx, val in samples
    str .= val . "`n"
  StringTrimRight, str, str, 1
  Sort, str, N
  Return str
}

Perf_writeHeader() {
  Global Perf_csvPath

  If Not FileExist(Perf_csvPath)
    FileAppend, commit`,scenario`,window_count`,phase`,iterations`,min_ms`,median_ms`,p95_ms`,max_ms`r`n, %Perf_csvPath%
}

Perf_writeRow(scenario, windowCount, expectedLabels = "") {
  Global Perf_csvPath, Perf_commit, Perf_samples

  totalSamples := 0
  For label, samples in Perf_samples {
    n := samples.MaxIndex()
    If Not n
      Continue
    totalSamples += n
    sortedStr := Perf_sortAscending(samples)
    StringSplit, sorted, sortedStr, `n
    minV := sorted1
    maxV := sorted%n%
    medianIdx := (n + 1) // 2
    If (medianIdx < 1)
      medianIdx := 1
    medianV := sorted%medianIdx%
    p95Idx := Ceil(n * 0.95)
    If (p95Idx < 1)
      p95Idx := 1
    If (p95Idx > n)
      p95Idx := n
    p95V := sorted%p95Idx%

    line := Perf_commit . "," . scenario . "," . windowCount . "," . label . "," . n . "," . minV . "," . medianV . "," . p95V . "," . maxV . "`r`n"
    FileAppend, %line%, %Perf_csvPath%
  }
  If (totalSamples = 0)
    Debug_logMessage("DEBUG[0] Perf_runBench: scenario '" . scenario . "' produced zero samples — wrappers never fired (likely an early-return in the function under test)", 0)
  Else If expectedLabels
  {
    Loop, PARSE, expectedLabels, `,
    {
      If Not Perf_samples.HasKey(A_LoopField)
        Debug_logMessage("DEBUG[0] Perf_runBench: scenario '" . scenario . "' missing samples for expected label '" . A_LoopField . "'", 0)
    }
  }
}

;; Spawn N independent windows. We use mspaint.exe (Paint) — multi-instance
;; on Win11, standard top-level window proc, no conhost quirks. Cmd was the
;; earlier choice because it spawns reliably, but conhost clamps height to
;; a character-cell multiple and intermittently refuses position changes,
;; which surfaced as false-positive geometry-assertion failures in #41.
;; Paint accepts SetWindowPos coordinates exactly, so it's an honest oracle
;; for the assertion. Windows 11 Notepad is single-instance with tabs and
;; was ruled out for that reason.
;;
;; Paint takes 1-3 s to fully initialize on cold launch. WinWait per spawn
;; blocks until the actual MSPaintApp window exists for the spawned PID;
;; a fixed Sleep would either be too short (race with mspaint's internal
;; init resize, surfacing as bench-side false-positive geometry failures)
;; or pessimistically long. Brief settle after WinWait absorbs the first
;; internal resize before bug.n's tiler races ahead.
Perf_spawnWindows(n, ByRef pidList) {
  Local spawnedPid, prevDetect
  pidList := ""
  prevDetect := A_DetectHiddenWindows
  DetectHiddenWindows, On    ;; mspaint may still be hidden when WinWait first probes
  Loop, % n {
    Run, mspaint.exe, , , spawnedPid
    If spawnedPid {
      pidList .= spawnedPid . ";"
      ;; Block until mspaint actually creates its top-level window. 8 s
      ;; cap matches Perf_waitForManagedDelta's per-window expectation
      ;; (#19 baseline); cold launches under load can take several seconds.
      WinWait, ahk_class MSPaintApp ahk_pid %spawnedPid%, , 8
      If ErrorLevel
        Debug_logMessage("DEBUG[0] Perf_spawnWindows: timed out waiting for mspaint PID " . spawnedPid . " window to appear", 0)
    }
    Sleep, 400    ;; settle: mspaint runs an internal resize shortly after
                  ;; window creation; tile too soon and the resize overrides
                  ;; bug.n's SetWindowPos
  }
  DetectHiddenWindows, %prevDetect%
}

;; Return the `;`-separated set of HWNDs in `current` that aren't in `baseline`.
Perf_diffWndIds(baseline, current) {
  StringTrimRight, currentTrimmed, current, 1
  newIds := ""
  Loop, PARSE, currentTrimmed, `;
  {
    If A_LoopField And Not InStr(";" . baseline, ";" . A_LoopField . ";")
      newIds .= A_LoopField . ";"
  }
  Return newIds
}

;; Wait until at least `delta` HWNDs not in `baselineWndIds` have shown up
;; in Manager_managedWndIds, or until timeoutMs elapses. Counts the diff
;; rather than `current - baselineCount` because Manager_sync's
;; validate-on-sync pass can legitimately prune stale baseline entries
;; during spawn, making a count-delta go negative even when all spawned
;; windows registered correctly.
Perf_waitForManagedDelta(baselineWndIds, delta, timeoutMs) {
  Global Manager_managedWndIds

  deadline := A_TickCount + timeoutMs
  Loop {
    Sleep, 50
    diff := Perf_diffWndIds(baselineWndIds, Manager_managedWndIds)
    StringReplace, dummy, diff, `;, `;, UseErrorLevel All
    If (ErrorLevel >= delta)
      Return True
    If (A_TickCount > deadline)
      Return False
  }
}

Perf_countManaged() {
  Global Manager_managedWndIds
  StringReplace, dummy, Manager_managedWndIds, `;, `;, UseErrorLevel All
  Return ErrorLevel
}

;; True if any HWND in a `;`-separated wndIds string still corresponds to
;; an existing top-level window. Used to distinguish stale saved-state
;; entries from real user windows the bench would disturb.
Perf_viewHasLiveWindows(wndIds) {
  StringTrimRight, trimmed, wndIds, 1
  Loop, PARSE, trimmed, `;
  {
    If A_LoopField And WinExist("ahk_id " . A_LoopField)
      Return True
  }
  Return False
}

Perf_closeWndIds(wndIds) {
  StringTrimRight, trimmed, wndIds, 1
  Loop, PARSE, trimmed, `;
  {
    If A_LoopField
      WinKill, ahk_id %A_LoopField%    ;; WM_CLOSE then terminate if no response
  }
}

;; Force-terminate every PID in a `;`-separated list. Used as the final
;; cleanup pass so a cmd window that escaped the HWND diff and the title
;; sweep (e.g. spawned but not yet visible) is still killed.
Perf_closePids(pidList) {
  StringTrimRight, trimmed, pidList, 1
  Loop, PARSE, trimmed, `;
  {
    If A_LoopField
      Process, Close, %A_LoopField%
  }
}

;; Kill the first half of a `;`-separated PID list via Process,Close.
;; Used by the orphan_storm scenario to simulate "WINDOWDESTROYED was
;; never received" -- Process,Close terminates the process out-of-band,
;; and on a busy system bug.n's shell hook may miss the destroy event
;; (especially while Manager_hideShow=True). Returns the killed PIDs as
;; their own `;`-separated string so callers can verify cleanup.
Perf_killHalfPids(pidList) {
  StringTrimRight, trimmed, pidList, 1
  StringSplit, pids, trimmed, `;
  killed := ""
  half := pids0 // 2
  Loop, % half {
    pid := pids%A_Index%
    If pid {
      Process, Close, %pid%
      killed .= pid . ";"
    }
  }
  Return killed
}

;; Bench harness. Called once after Manager_init has finished and the
;; message pump is running (so shell-hook events for spawned windows are
;; processed).
;;
;; The bench operates on real bug.n state (real Manager, real shell hook,
;; real Win32) so its measurements reflect production behavior. To avoid
;; shuffling the user's actual windows, it runs on a *playground* pair of
;; views (the last two views, typically 8 and 9). If those views aren't
;; empty the bench refuses to run rather than disturb the user's layout.
;; The original view is restored on exit; saved session state is left
;; alone (Main_cleanup skips Manager_saveState in bench mode).
Perf_runBench(windowCount, iterations) {
  Global Manager_aMonitor, Manager_managedWndIds, Config_viewCount, Perf_csvPath, Config_dynamicTiling

  aMonitor := Manager_aMonitor
  originalView := Monitor_#%aMonitor%_aView_#1
  geometryFailures := 0    ;; #41: Bench_assertTiled accumulator across scenarios

  ;; Use the last two views as the bench playground. View_switch flips
  ;; between them, so both must be empty of user windows. Saved state can
  ;; leave stale HWNDs in View_wndIds (the Manager_init forget pass logs
  ;; "doesn't match expected" but doesn't strip those entries from the
  ;; per-view list), so check for *live* windows rather than empty strings.
  benchView    := Config_viewCount
  switchTarget := Config_viewCount - 1
  If Perf_viewHasLiveWindows(View_#%aMonitor%_#%benchView%_wndIds)
    Or Perf_viewHasLiveWindows(View_#%aMonitor%_#%switchTarget%_wndIds) {
    Debug_logMessage("DEBUG[0] Perf_runBench: bench playground views " . switchTarget . " and " . benchView . " on monitor " . aMonitor . " hold live user windows. Aborting to preserve them.", 0)
    ExitApp, 3
  }
  ;; Clear stale (dead-HWND) entries so the bench starts on a clean slate.
  View_#%aMonitor%_#%benchView%_wndIds := ""
  View_#%aMonitor%_#%switchTarget%_wndIds := ""

  ;; Switch to the playground view before spawning so all bench-spawned
  ;; cmds get assigned to it.
  Monitor_activateView(benchView)
  Sleep, 200

  baselineWndIds := Manager_managedWndIds
  baselineCount  := Perf_countManaged()
  Debug_logMessage("DEBUG[0] Perf_runBench: baseline managed count = " baselineCount . " (playground view " . benchView . ")", 0)

  ;; Scenario 0: window_spawn -- capture Manager_onShellMessage / Manager_sync /
  ;; View_arrange samples that fire while the OS notifies bug.n about each
  ;; spawned cmd. This is the only scenario that exercises the shell-hook
  ;; entry point (the others call Monitor_activateView / View_arrange /
  ;; View_shuffleWindow directly), so it's the only one whose numbers move
  ;; when Config_shellMsgDelay changes.
  Perf_resetSamples()

  spawnedPids := ""
  Perf_spawnWindows(windowCount, spawnedPids)
  If Not Perf_waitForManagedDelta(baselineWndIds, windowCount, 10000) {
    Global Manager_allWndIds
    StringReplace, dummy, Manager_allWndIds, `;, `;, UseErrorLevel All
    allCount := ErrorLevel
    spawnedWndIds := Perf_diffWndIds(baselineWndIds, Manager_managedWndIds)
    StringReplace, dummy, spawnedWndIds, `;, `;, UseErrorLevel All
    spawnedDiffCount := ErrorLevel
    Debug_logMessage("DEBUG[0] Perf_runBench: timed out waiting for " . windowCount . " windows to register (spawned-diff = " . spawnedDiffCount . ", all-seen count = " . allCount . ")", 0)
    Debug_logMessage("DEBUG[0] Perf_runBench: spawnedPids=" . spawnedPids, 0)
    Debug_logMessage("DEBUG[0] Perf_runBench: spawnedWndIds (managed) =" . spawnedWndIds, 0)
    Debug_logMessage("DEBUG[0] Perf_runBench: Manager_allWndIds=" . Manager_allWndIds, 0)
    StringTrimRight, pidsTrim, spawnedPids, 1
    Loop, PARSE, pidsTrim, `;
    {
      If A_LoopField {
        WinGet, hwndForPid, ID, ahk_pid %A_LoopField%
        ;; Numeric compare — Manager_managedWndIds / Manager_allWndIds may
        ;; hold HWNDs in hex or decimal depending on SetFormat state at
        ;; insert time (see Manager_isManaged comment). InStr would
        ;; falsely report 'no' on a format mismatch.
        inManaged := Manager_isManaged(hwndForPid) ? "yes" : "no"
        inAll := "no"
        StringTrimRight, allTrimmed, Manager_allWndIds, 1
        target := hwndForPid + 0
        Loop, PARSE, allTrimmed, `;
        {
          If A_LoopField And ((A_LoopField + 0) = target) {
            inAll := "yes"
            Break
          }
        }
        Debug_logMessage("DEBUG[0] Perf_runBench: PID=" . A_LoopField . " HWND=" . hwndForPid . " managed=" . inManaged . " seen=" . inAll, 0)
      }
    }
    Perf_cleanup(spawnedWndIds, spawnedPids, originalView)
    ExitApp, 2
  }
  spawnedWndIds := Perf_diffWndIds(baselineWndIds, Manager_managedWndIds)
  finalCount := Perf_countManaged()
  Debug_logMessage("DEBUG[0] Perf_runBench: " . windowCount . " windows registered, total managed = " . finalCount, 0)
  Sleep, 800    ;; let any pending shell-hook work + initial arrange settle

  Perf_writeHeader()
  Perf_writeRow("window_spawn", finalCount, "Manager_onShellMessage,Manager_sync,View_arrange")
  geometryFailures += Bench_assertTiled(aMonitor, benchView, "window_spawn")

  ;; Scenario 1: view switch (benchView <-> switchTarget). Both empty of
  ;; user windows, so this exercises Monitor_activateView + View_arrange
  ;; without touching the user's layout.
  Perf_resetSamples()
  Loop, % iterations {
    Monitor_activateView(switchTarget)
    Monitor_activateView(benchView)
  }
  Perf_writeRow("view_switch", finalCount, "Monitor_activateView,Monitor_activateView_saveCtx,Monitor_activateView_aotOn,Monitor_activateView_aotOff,Monitor_activateView_finalShow,View_arrange,Bar_updateViewPair")
  Sleep, 300

  ;; Scenario 2: forced re-tile of the active view
  Perf_resetSamples()
  Loop, % iterations {
    View_arrange(aMonitor, benchView, True)
  }
  Perf_writeRow("view_arrange", finalCount, "View_arrange,Tiler_stackTiles")
  geometryFailures += Bench_assertTiled(aMonitor, benchView, "view_arrange")
  Sleep, 300

  ;; Scenario 3: shuffle focused window through tile slots. View_shuffleWindow
  ;; (not View_moveWindow — that one just SetWindowPos's a single window and
  ;; never calls View_arrange) swaps positions in the tiled list and re-arranges
  ;; the view, exercising both View_arrange and Tiler_stackTiles. Needs the
  ;; active window to be a managed, tiled window — without explicit activation
  ;; the focus could be on something unmanaged (taskbar, our own bench process)
  ;; and the function would early-return.
  Perf_focusFirstSpawned(spawnedWndIds)
  Perf_resetSamples()
  Loop, % iterations {
    View_shuffleWindow(0, +1)
  }
  Perf_writeRow("window_shuffle", finalCount, "View_arrange,Tiler_stackTiles")
  geometryFailures += Bench_assertTiled(aMonitor, benchView, "window_shuffle")
  Sleep, 300

  ;; Scenario 3b: window_cycle — measures the per-cycle WORK cost of
  ;; advancing the active window within the current view. Win+J / Win+K
  ;; in production routes through View_activateWindow's coalescer (#46),
  ;; which returns immediately and arms a one-shot timer; a tight loop
  ;; over that wrapper would measure only scheduling overhead. The bench
  ;; calls View_activateWindow_now directly so we keep measuring the
  ;; underlying activation cost -- regression detection on the work
  ;; itself, not on the coalescer. focusFirstSpawned re-anchors the
  ;; active window since the prior shuffle scenario rotated the wndIds
  ;; list.
  Perf_focusFirstSpawned(spawnedWndIds)
  Perf_resetSamples()
  Loop, % iterations {
    View_activateWindow_now(0, +1)
  }
  Perf_writeRow("window_cycle", finalCount, "View_activateWindow,Manager_winActivate,Manager_setCursor,Window_activate,Window_activate_winActivate,Window_activate_winGetA")
  Sleep, 300

  ;; Scenario 3c: monocle_cycle — regression coverage for #94. In monocle
  ;; every tiled window shares fullscreen coords, so a bare WinActivate can
  ;; fail to repaint Z-order against a same-position peer; the fix
  ;; (View_activateWithRaise) flips AlwaysOnTop on/off to force the raise.
  ;; Switch to monocle, cycle, and assert the OS-active window actually
  ;; advances. A regression → ExitApp 3 so a missing/broken flip is caught
  ;; at bench time, not by a user pressing Win+J in monocle.
  Perf_focusFirstSpawned(spawnedWndIds)
  prevLayout := View_#%aMonitor%_#%benchView%_layout_#1
  View_setLayout(2)
  Sleep, 200
  Perf_resetSamples()
  monocleCycleRegressions := 0
  Loop, % iterations {
    WinGet, preActive, ID, A
    View_activateWindow_now(0, +1)
    WinGet, postActive, ID, A
    If (preActive = postActive)
      monocleCycleRegressions += 1
  }
  Perf_writeRow("monocle_cycle", finalCount, "View_activateWindow,Manager_winActivate,Window_activate,Window_activate_winActivate,Window_activate_winGetA")
  geometryFailures += Bench_assertTiled(aMonitor, benchView, "monocle_cycle")
  View_setLayout(prevLayout)
  Sleep, 200
  If (monocleCycleRegressions > 0) {
    Debug_logMessage("DEBUG[0] Perf_runBench: monocle_cycle REGRESSION — " . monocleCycleRegressions . " of " . iterations . " cycles failed to swap the active window (issue #94)", 0)
    Perf_cleanup(spawnedWndIds, spawnedPids, originalView)
    ExitApp, 3
  }
  Sleep, 300

  ;; Scenario 4: populated view_switch — spawn another batch of windows on
  ;; switchTarget so flipping between the two views exercises the real
  ;; hide/show + arrange paths with N windows on each side. The empty-views
  ;; view_switch above measures fixed overhead; this one measures the
  ;; per-window cost the user feels switching virtual desktops.
  preSecondManaged := Manager_managedWndIds
  secondPids := ""
  Monitor_activateView(switchTarget)
  Sleep, 300
  Perf_spawnWindows(windowCount, secondPids)
  If Not Perf_waitForManagedDelta(preSecondManaged, windowCount, 10000) {
    Global Manager_allWndIds
    StringReplace, dummy, Manager_allWndIds, `;, `;, UseErrorLevel All
    allCount := ErrorLevel
    secondWndIds := Perf_diffWndIds(preSecondManaged, Manager_managedWndIds)
    StringReplace, dummy, secondWndIds, `;, `;, UseErrorLevel All
    secondDiffCount := ErrorLevel
    Debug_logMessage("DEBUG[0] Perf_runBench: timed out waiting for second-batch spawn to register on view " . switchTarget . " (second-diff = " . secondDiffCount . ", all-seen count = " . allCount . ")", 0)
    Debug_logMessage("DEBUG[0] Perf_runBench: secondPids=" . secondPids, 0)
    Debug_logMessage("DEBUG[0] Perf_runBench: secondWndIds (managed) =" . secondWndIds, 0)
    Debug_logMessage("DEBUG[0] Perf_runBench: Manager_allWndIds=" . Manager_allWndIds, 0)
    StringTrimRight, pidsTrim, secondPids, 1
    Loop, PARSE, pidsTrim, `;
    {
      If A_LoopField {
        WinGet, hwndForPid, ID, ahk_pid %A_LoopField%
        inManaged := Manager_isManaged(hwndForPid) ? "yes" : "no"
        inAll := "no"
        StringTrimRight, allTrimmed, Manager_allWndIds, 1
        target := hwndForPid + 0
        Loop, PARSE, allTrimmed, `;
        {
          If A_LoopField And ((A_LoopField + 0) = target) {
            inAll := "yes"
            Break
          }
        }
        Debug_logMessage("DEBUG[0] Perf_runBench: PID=" . A_LoopField . " HWND=" . hwndForPid . " managed=" . inManaged . " seen=" . inAll, 0)
      }
    }
    Perf_cleanup(spawnedWndIds . secondWndIds, spawnedPids . secondPids, originalView)
    ExitApp, 2
  }
  secondWndIds := Perf_diffWndIds(preSecondManaged, Manager_managedWndIds)
  populatedCount := Perf_countManaged()
  Sleep, 800

  Perf_resetSamples()
  Loop, % iterations {
    Monitor_activateView(benchView)
    Monitor_activateView(switchTarget)
  }
  Perf_writeRow("view_switch_populated", populatedCount, "Monitor_activateView,Monitor_activateView_saveCtx,Monitor_activateView_hide,Monitor_activateView_aotOn,Monitor_activateView_aotOff,Monitor_activateView_show,Monitor_activateView_finalShow,View_arrange,Tiler_stackTiles,Bar_updateViewPair,Manager_winActivate")
  geometryFailures += Bench_assertTiled(aMonitor, switchTarget, "view_switch_populated")
  Sleep, 300

  ;; Scenario 5: layout_restructure — Win+H/; (MFactor), Shift+Win+H/;
  ;; (MY), and Ctrl+Win+H/; (StackMX) all flow through View_setLayoutProperty
  ;; and trigger an arrange. Active view here is switchTarget (last
  ;; activated by view_switch_populated) with windowCount cmds. Each
  ;; pair oscillates +/- so values stay in range — MFactor within
  ;; (0,1), MY/StackMX within Tiler_setMY/Tiler_setStackMX's 1..9. The
  ;; six labels blend into a single View_setLayoutProperty row; the
  ;; three Tiler_set* helpers are sub-ms so the cost is dominated by
  ;; the shared View_arrange + Tiler_stackTiles path.
  Perf_resetSamples()
  Loop, % iterations {
    View_setLayoutProperty("MFactor", 0, +0.05)
    View_setLayoutProperty("MFactor", 0, -0.05)
    View_setLayoutProperty("MY", 0, +1)
    View_setLayoutProperty("MY", 0, -1)
    View_setLayoutProperty("StackMX", 0, +1)
    View_setLayoutProperty("StackMX", 0, -1)
  }
  Perf_writeRow("layout_restructure", populatedCount, "View_setLayoutProperty,View_arrange,Tiler_stackTiles")
  geometryFailures += Bench_assertTiled(aMonitor, switchTarget, "layout_restructure")
  Sleep, 300

  ;; Scenario 5b: window_move_area — Alt+1..0 / Alt+J / Alt+K
  ;; (View_moveWindow) moves the focused window between tile areas without
  ;; re-arranging the view. Exercises the Window_moveAsync wrapper on a
  ;; single window (one SetWindowPos call, no Tiler batch).
  ;;
  ;; View_moveWindow's inner block only fires when View_#m_#v_area_#0 > 0,
  ;; and area_#0 is only populated by Tiler_layoutTiles's "blank" path —
  ;; which itself only runs when Config_dynamicTiling is False (static tile
  ;; mode). The default (and the user's) Config_dynamicTiling = True path
  ;; never populates areas, leaving View_moveWindow effectively a no-op
  ;; (see the @TODO in View.ahk:195). Toggle Config_dynamicTiling False
  ;; around the scenario, prime area_#0 via View_arrange, then restore.
  prevDynamicTiling := Config_dynamicTiling
  Config_dynamicTiling := False
  View_arrange(Manager_aMonitor, switchTarget)
  Sleep, 100
  Perf_focusFirstSpawned(secondWndIds)
  Perf_resetSamples()
  Loop, % iterations {
    View_moveWindow(0, +1)
  }
  Perf_writeRow("window_move_area", populatedCount, "View_moveWindow,Window_moveAsync,Manager_setCursor")
  Config_dynamicTiling := prevDynamicTiling
  View_arrange(Manager_aMonitor, switchTarget)
  ;; Non-blank Tiler_layoutTiles doesn't reset area_#0; do it manually.
  View_#%Manager_aMonitor%_#%switchTarget%_area_#0 := 0
  Sleep, 300

  ;; Scenario 5c: window_maximize — Win+Shift+M / Alt+Shift+M
  ;; (Manager_maximizeWindow) floats the active window and sizes it to the
  ;; full monitor. First iteration also calls View_toggleFloatingWindow
  ;; (cold cost in max/p95); after that the body is Window_set + the async
  ;; SetWindowPos each iteration. Window stays floating after this scenario
  ;; — taskbar_toggle below ignores floaters in its re-arrange so it's
  ;; safe to run before it.
  Perf_focusFirstSpawned(secondWndIds)
  Perf_resetSamples()
  Loop, % iterations {
    Manager_maximizeWindow()
  }
  Perf_writeRow("window_maximize", populatedCount, "Manager_maximizeWindow,Window_moveAsync")
  Sleep, 300

  ;; Scenario 6: taskbar_toggle — Win+B (Monitor_toggleTaskBar) hides/shows
  ;; the real Windows taskbar, recomputes work area, repositions the bug.n
  ;; bar, and re-arranges the active view. Different cost shape than the
  ;; other arranges: the work area itself changes, so this measures
  ;; WinHide/WinShow on a system-managed window plus the reflow path. Paired
  ;; toggles per iteration so the OS taskbar ends in the state it started.
  ;;
  ;; Setup: bug.n's default Config_showTaskBar=False means production bug.n
  ;; typically has the taskbar hidden by the time the bench starts. Bench's
  ;; Monitor_getWorkArea uses default DetectHiddenWindows Off so its probe
  ;; misses a hidden Shell_TrayWnd, leaving Monitor_taskBarClass empty and
  ;; making Monitor_toggleTaskBar a no-op. Probe via DllCall FindWindow
  ;; rather than WinExist: on Win11, AHK's window enumeration can fail to
  ;; surface a hidden Shell_TrayWnd by class even with DetectHiddenWindows
  ;; On (apparent Win11+AHK quirk specific to that system window), while
  ;; user32!FindWindow finds it reliably. Verify the tray's center lies
  ;; within aMonitor's bounds before claiming the class — matches
  ;; Monitor_getWorkArea's pattern (Monitor.ahk:184–193) and avoids
  ;; mis-binding to a tray on a different display when "show taskbar on
  ;; all displays" is on. Skipped when no candidate falls on aMonitor.
  If Not Monitor_#%aMonitor%_taskBarClass {
    SysGet, monBounds, Monitor, %aMonitor%
    prevDetect := A_DetectHiddenWindows
    DetectHiddenWindows, On
    candidates := "Shell_TrayWnd,Shell_SecondaryTrayWnd"
    Loop, PARSE, candidates, `,
    {
      candClass := A_LoopField
      trayHwnd  := DllCall("FindWindow", "Str", candClass, "Ptr", 0, "Ptr")
      If trayHwnd {
        WinGetPos, tbX, tbY, tbW, tbH, ahk_id %trayHwnd%
        cx := tbX + tbW / 2
        cy := tbY + tbH / 2
        If (cx >= monBoundsLeft And cx <= monBoundsRight
            And cy >= monBoundsTop And cy <= monBoundsBottom) {
          Monitor_#%aMonitor%_taskBarClass := candClass
          Break
        }
      }
    }
    DetectHiddenWindows, %prevDetect%
  }
  If Not Monitor_#%aMonitor%_taskBarClass {
    Debug_logMessage("DEBUG[0] Perf_runBench: taskbar_toggle skipped — no Shell_TrayWnd or Shell_SecondaryTrayWnd on monitor " . aMonitor . " (FindWindow result, if any, fell outside its bounds)", 0)
  } Else {
    Perf_resetSamples()
    Loop, % iterations {
      Monitor_toggleTaskBar()
      Monitor_toggleTaskBar()
    }
    Perf_writeRow("taskbar_toggle", populatedCount, "Monitor_toggleTaskBar,Monitor_getWorkArea,Bar_move,View_arrange,Tiler_stackTiles")
    Sleep, 300
  }

  ;; Scenario 7: orphan_storm — kill half the spawned cmds out-of-band
  ;; via Process,Close (simulating a missed WINDOWDESTROYED event) and
  ;; verify Manager_validateAlive prunes them. The first call detects
  ;; and prunes the orphans (longer); subsequent calls find nothing to
  ;; prune (shorter), so min/median/p95/max spread reflects the cleanup
  ;; cost. Calls Manager_validateAlive directly rather than waiting for
  ;; the deferred Manager_validateAliveTimer fire — measuring the
  ;; function's cost, not the timer plumbing.
  preOrphanCount := Perf_countManaged()
  killedPids := Perf_killHalfPids(spawnedPids)
  Sleep, 200    ;; let any in-flight shell events from the kills settle
  StringReplace, dummy, killedPids, `;, `;, UseErrorLevel All
  killedCount := ErrorLevel
  Debug_logMessage("DEBUG[0] Perf_runBench: orphan_storm killed " . killedCount . " PIDs: " . killedPids . " (pre-cleanup managed = " . preOrphanCount . ")", 0)
  Perf_resetSamples()
  Loop, % iterations {
    Manager_validateAlive()
  }
  Perf_writeRow("orphan_storm", populatedCount, "Manager_validateAlive")
  postOrphanCount := Perf_countManaged()
  expectedCount := preOrphanCount - killedCount
  If (postOrphanCount = expectedCount)
    Debug_logMessage("DEBUG[0] Perf_runBench: orphan_storm cleanup OK — managed dropped " . preOrphanCount . " -> " . postOrphanCount, 0)
  Else
    Debug_logMessage("DEBUG[0] Perf_runBench: orphan_storm REGRESSION — managed went " . preOrphanCount . " -> " . postOrphanCount . ", expected " . expectedCount . " (killed " . killedCount . "). Orphan cleanup may have regressed.", 0)
  Sleep, 300

  Debug_logMessage("DEBUG[0] Perf_runBench: complete, wrote " Perf_csvPath, 0)
  If (geometryFailures > 0) {
    Debug_logMessage("DEBUG[0] Perf_runBench: " . geometryFailures . " geometry assertion failure(s) across scenarios -- see Bench_assertTiled lines above (issue #41)", 0)
    Perf_cleanup(spawnedWndIds . secondWndIds, spawnedPids . secondPids, originalView)
    ExitApp, 3
  }
  Perf_cleanup(spawnedWndIds . secondWndIds, spawnedPids . secondPids, originalView)
  ExitApp
}

;; Three-pass cleanup: WinKill the HWNDs we tracked via the managed-list
;; diff, then sweep by window title for any cmd that didn't get classified,
;; then force-close by PID for any cmd that escaped both (e.g. spawned but
;; not yet visible). Finally, switch the user's monitor back to the view
;; they were on before the bench started.
Perf_cleanup(spawnedWndIds, spawnedPids, originalView) {
  Global Manager_aMonitor

  Perf_closeWndIds(spawnedWndIds)
  ;; No title sweep -- Paint shares "Untitled - Paint" with any of the
  ;; user's own Paint instances, so killing by title would clobber them.
  ;; spawnedPids is authoritative; Perf_closePids handles everything we
  ;; opened, classified or not.
  Sleep, 200
  Perf_closePids(spawnedPids)
  Sleep, 300
  ;; Restore the user's view. Manager_cleanup will un-hide all managed
  ;; windows on ExitApp regardless, but flipping back keeps things tidy
  ;; if the bench is ever invoked without immediately exiting.
  If (originalView And originalView != Monitor_#%Manager_aMonitor%_aView_#1)
    Monitor_activateView(originalView)
}

;; Kill any visible windows whose title contains the given substring.
;; Used as a belt-and-suspenders cleanup for cmd windows we spawned but
;; that didn't end up in Manager_managedWndIds (e.g. classification race).
Perf_killByTitle(title) {
  prev := A_TitleMatchMode
  SetTitleMatchMode, 2
  WinGet, found, List, %title%
  Loop, % found {
    id := found%A_Index%
    WinKill, ahk_id %id%
  }
  SetTitleMatchMode, %prev%
}

Perf_focusFirstSpawned(spawnedWndIds) {
  StringTrimRight, trimmed, spawnedWndIds, 1
  Loop, PARSE, trimmed, `;
  {
    If A_LoopField {
      WinActivate, ahk_id %A_LoopField%
      Sleep, 150    ;; let activation propagate so subsequent WinGet,A returns it
      WinGet, activeId, ID, A
      If (activeId != A_LoopField)
        Debug_logMessage("DEBUG[0] Perf_focusFirstSpawned: activation didn't take (wanted " . A_LoopField . ", got " . activeId . ") — likely UIPI/foreground-lock; window_move scenario may produce no samples", 0)
      Return
    }
  }
}
