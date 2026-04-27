/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  Perf.ahk -- lightweight benchmarking + timing instrumentation.

  Two pieces:
  (1) Perf_start / Perf_end wrap hot functions. When Perf_enabled is False
      (the default) they're cheap no-ops, so production runs are unaffected.
  (2) Perf_runBench drives a fixed scenario (spawn N cmd windows, switch
      views, move windows, arrange) and writes a CSV row per (scenario,
      phase) with min/median/p95/max latencies. Triggered by `bugn.exe --bench`.
*/

Perf_init(enabled, csvPath, commit) {
  Global Perf_enabled, Perf_csvPath, Perf_commit, Perf_starts, Perf_samples

  Perf_enabled := enabled
  Perf_csvPath := csvPath
  Perf_commit  := commit
  Perf_starts  := {}
  Perf_samples := {}
}

Perf_start(label) {
  Global Perf_enabled, Perf_starts

  If Not Perf_enabled
    Return
  Perf_starts[label] := A_TickCount
}

Perf_end(label) {
  Global Perf_enabled, Perf_starts, Perf_samples

  If Not Perf_enabled
    Return
  If Not Perf_starts.HasKey(label)
    Return
  delta := A_TickCount - Perf_starts[label]
  If Not Perf_samples.HasKey(label)
    Perf_samples[label] := []
  Perf_samples[label].Push(delta)
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

;; Spawn N independent windows. We use `cmd.exe /k title bug.n_bench` so
;; each invocation creates its own window — Windows 11 Notepad is
;; single-instance with tabs, so it fails the per-window assumption.
;; cmd.exe doesn't hand off (unlike some Win11 launchers), so its PID is
;; reliable; we capture it as belt-and-suspenders alongside the HWND diff
;; in Manager_managedWndIds.
Perf_spawnWindows(n, ByRef pidList) {
  pidList := ""
  Loop, % n {
    Run, %ComSpec% /k title bug.n_bench, , , spawnedPid
    If spawnedPid
      pidList .= spawnedPid . ";"
    Sleep, 250    ;; let shell hook process each spawn before the next
  }
}

;; Return the `;`-separated set of HWNDs in `current` that aren't in `baseline`.
Perf_diffWndIds(baseline, current) {
  StringTrimRight, currentTrimmed, current, 1
  newIds := ""
  Loop, PARSE, currentTrimmed, `;
  {
    If A_LoopField And Not InStr(baseline, A_LoopField . ";")
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
  Global Manager_aMonitor, Manager_managedWndIds, Config_viewCount, Perf_csvPath

  aMonitor := Manager_aMonitor
  originalView := Monitor_#%aMonitor%_aView_#1

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
    Perf_cleanup(spawnedWndIds, spawnedPids, originalView)
    ExitApp, 2
  }
  spawnedWndIds := Perf_diffWndIds(baselineWndIds, Manager_managedWndIds)
  finalCount := Perf_countManaged()
  Debug_logMessage("DEBUG[0] Perf_runBench: " . windowCount . " windows registered, total managed = " . finalCount, 0)
  Sleep, 800    ;; let any pending shell-hook work + initial arrange settle

  Perf_writeHeader()
  Perf_writeRow("window_spawn", finalCount, "Manager_onShellMessage,Manager_sync,View_arrange")

  ;; Scenario 1: view switch (benchView <-> switchTarget). Both empty of
  ;; user windows, so this exercises Monitor_activateView + View_arrange
  ;; without touching the user's layout.
  Perf_resetSamples()
  Loop, % iterations {
    Monitor_activateView(switchTarget)
    Monitor_activateView(benchView)
  }
  Perf_writeRow("view_switch", finalCount, "Monitor_activateView,View_arrange")
  Sleep, 300

  ;; Scenario 2: forced re-tile of the active view
  Perf_resetSamples()
  Loop, % iterations {
    View_arrange(aMonitor, benchView, True)
  }
  Perf_writeRow("view_arrange", finalCount, "View_arrange,Tiler_stackTiles")
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
  Sleep, 300

  ;; Scenario 4: orphan_storm — kill half the spawned cmds out-of-band
  ;; via Process,Close (simulating a missed WINDOWDESTROYED event) and
  ;; verify Manager_sync's orphan-cleanup pass prunes them. The first
  ;; call should detect and prune the orphans (longer); subsequent calls
  ;; find nothing to prune (shorter), so min/median/p95/max spread
  ;; reflects the cleanup cost.
  preOrphanCount := Perf_countManaged()
  killedPids := Perf_killHalfPids(spawnedPids)
  Sleep, 200    ;; let any in-flight shell events from the kills settle
  StringReplace, dummy, killedPids, `;, `;, UseErrorLevel All
  killedCount := ErrorLevel
  Debug_logMessage("DEBUG[0] Perf_runBench: orphan_storm killed " . killedCount . " PIDs: " . killedPids . " (pre-cleanup managed = " . preOrphanCount . ")", 0)
  Perf_resetSamples()
  Loop, % iterations {
    Manager_sync()
  }
  Perf_writeRow("orphan_storm", finalCount, "Manager_sync")
  postOrphanCount := Perf_countManaged()
  expectedCount := preOrphanCount - killedCount
  If (postOrphanCount = expectedCount)
    Debug_logMessage("DEBUG[0] Perf_runBench: orphan_storm cleanup OK — managed dropped " . preOrphanCount . " -> " . postOrphanCount, 0)
  Else
    Debug_logMessage("DEBUG[0] Perf_runBench: orphan_storm REGRESSION — managed went " . preOrphanCount . " -> " . postOrphanCount . ", expected " . expectedCount . " (killed " . killedCount . "). Orphan cleanup may have regressed.", 0)
  Sleep, 300

  Debug_logMessage("DEBUG[0] Perf_runBench: complete, wrote " Perf_csvPath, 0)
  Perf_cleanup(spawnedWndIds, spawnedPids, originalView)
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
  Perf_killByTitle("bug.n_bench")
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
