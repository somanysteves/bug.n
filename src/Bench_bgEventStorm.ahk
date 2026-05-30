/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3

  Bench_bgEventStorm.ahk -- smoke test for #86's debounce-with-maxWait
  fix (Manager_armDebouncedTimer's maxWaitMs cap on
  Manager_winCreateOrShowDeferred).

  ## What it does

  Spawns parallel child bugn-bench.exe processes in helper mode that
  create+destroy hidden top-level GUI windows in a tight loop. Each
  iteration emits EVENT_OBJECT_CREATE/SHOW/DESTROY/HIDE on a window the
  bench's hook sees (WINEVENT_SKIPOWNPROCESS filters by PID, so
  separately-spawned children are visible). The bench then sleeps a
  measurement window mid-storm and checks
  Perf_samples["Manager_winCreateOrShowDeferred"] for fires.

  ## Why this is a smoke test, not a hard regression test

  An ideal regression test would fail pre-fix (naive `SetTimer, -50`
  starves) and pass post-fix (capped timer fires periodically). In
  practice the helper's event rate can't reliably be tuned to that
  boundary from AHK:
  - Below ~25 events/sec, the naive timer opportunistically fires
    through gaps and the bench falsely passes pre-fix.
  - Above ~80 events/sec (3+ helpers), the bench's AHK main thread
    saturates on hook callbacks and even the capped timer can't get
    scheduled — the bench falsely fails post-fix.
  - The window between those is narrow and OS-load-dependent.

  So the bench is positioned as a smoke check: post-fix, under sustained
  cross-process CREATE/SHOW load, the capped timer should fire at least
  once during the measurement window. The pure-logic correctness of the
  cap is covered by TestManagerShouldResetDebouncedTimer (Yunit).

  ## Invocation

  `bugn-bench.exe --scenario bgEventStorm`.
*/

Bench_runBgEventStorm() {
  Global Manager_aMonitor, Manager_managedWndIds, Config_viewCount
  Global Bench_iterations, Perf_samples

  aMonitor      := Manager_aMonitor
  originalView  := Monitor_#%aMonitor%_aView_#1
  testView      := Config_viewCount

  If Perf_viewHasLiveWindows(View_#%aMonitor%_#%testView%_wndIds) {
    Debug_logMessage("DEBUG[0] Bench_runBgEventStorm: playground view " . testView . " on monitor " . aMonitor . " holds live user windows. Aborting to preserve them.", 0)
    ExitApp, 3
  }
  View_#%aMonitor%_#%testView%_wndIds := ""

  Monitor_activateView(testView)
  Sleep, 200

  ;; Re-launch ourselves as the storm helper. A separately-spawned child
  ;; bypasses the parent hook's WINEVENT_SKIPOWNPROCESS filter (which is
  ;; PID-scoped, not image-scoped). 20 000 Gui Show/Destroy iterations is
  ;; enough wall-clock for the warmup + measurement window with margin.
  benchExe := A_ScriptFullPath
  helperIters := 20000

  ;; Two parallel helpers (separate PIDs, each bypassing SKIPOWNPROCESS)
  ;; sustain enough event load on the bench's hook that the capped timer
  ;; visibly fires multiple times during the measurement window. More
  ;; helpers saturate the hook callback path so even the capped timer
  ;; can't get scheduled, defeating the smoke check.
  helperPids := ""
  Loop, 2 {
    Run, "%benchExe%" --scenario bgEventStormHelper --iterations %helperIters%, , , helperPid
    If helperPid
      helperPids .= helperPid . ";"
  }
  Debug_logMessage("DEBUG[0] Bench_runBgEventStorm: spawned helpers " . helperPids, 0)
  If Not helperPids {
    Debug_logMessage("DEBUG[0] Bench_runBgEventStorm FAIL: could not spawn helpers", 0)
    Bench_bgEventStorm_cleanup("", originalView)
    ExitApp, 1
  }

  ;; Warmup: let the helper finish App_init / Perf_init / hook registration
  ;; and actually enter its Gui Show/Destroy loop. The helper is a fresh
  ;; bugn-bench.exe process — startup is several seconds on a cold cache.
  Sleep, 3000

  ;; Snapshot the deferred-fire count, then sleep a measurement window
  ;; while the helper continues firing events. With the maxWait cap the
  ;; fire latency is bounded at ~maxWait + waitMs even under sustained
  ;; arming; without the cap (current state — bug exists), the timer is
  ;; pushed forward indefinitely and fires zero times during the storm.
  measureMs := 1500
  baselineFires := Bench_bgEventStorm_fireCount()
  Debug_logMessage("DEBUG[0] Bench_runBgEventStorm: baseline fires=" . baselineFires . "; sleeping " . measureMs . " ms mid-storm", 0)
  Sleep, % measureMs
  finalFires := Bench_bgEventStorm_fireCount()
  observed := finalFires - baselineFires

  Debug_logMessage("DEBUG[0] Bench_runBgEventStorm: end-of-window fires=" . finalFires . " (observed " . observed . " during the " . measureMs . " ms window)", 0)

  Bench_bgEventStorm_cleanup(helperPids, originalView)

  If (observed < 1) {
    Debug_logMessage("DEBUG[0] Bench_runBgEventStorm FAIL: Manager_winCreateOrShowDeferred fired 0 times during " . measureMs . " ms of sustained cross-process CREATE/SHOW load — timer starved (regressed #86 maxWait cap)", 0)
    ExitApp, 1
  }
  Debug_logMessage("DEBUG[0] Bench_runBgEventStorm: PASS — Manager_winCreateOrShowDeferred fired " . observed . " time(s) during " . measureMs . " ms of sustained storm (cap prevents starvation)", 0)
  ExitApp, 0
}

;; Pull the cumulative fire count for Manager_winCreateOrShowDeferred from
;; Perf_samples (populated by the Perf_start/Perf_end wrappers around the
;; label body). Returns 0 if the timer hasn't fired yet — a key signal:
;; pre-fix, the count stays at its baseline for the entire storm window.
Bench_bgEventStorm_fireCount() {
  Global Perf_samples
  If Not Perf_samples.HasKey("Manager_winCreateOrShowDeferred")
    Return 0
  Return Perf_samples["Manager_winCreateOrShowDeferred"].MaxIndex()
}

Bench_bgEventStorm_cleanup(helperPids, originalView) {
  Global Manager_aMonitor

  ;; Helpers exit on their own after `iterations`, but the measurement
  ;; window is short — terminate each so the remaining Gui churn doesn't
  ;; leak into the user's session.
  StringTrimRight, helperPidsTrim, helperPids, 1
  Loop, PARSE, helperPidsTrim, `;
  {
    If A_LoopField
      Process, Close, %A_LoopField%
  }
  Perf_killByTitle("bug.n_eventstorm_child")
  Sleep, 300

  If (originalView And originalView != Monitor_#%Manager_aMonitor%_aView_#1)
    Monitor_activateView(originalView)
}

;; Storm-emit loop, run in a separately-spawned bugn-bench.exe child so
;; its events bypass the parent hook's WINEVENT_SKIPOWNPROCESS filter
;; (PID-scoped). Gui Show/Destroy is the fastest way to emit
;; EVENT_OBJECT_CREATE/SHOW pairs from inside AHK — no process spawn
;; cost, no shell hook noise from cmd's exit.
;;
;; +ToolWindow -Caption keeps the storm visually unobtrusive; the
;; helper windows are 1x1 corner-pinned and immediately destroyed so
;; the burst is pure churn rather than accumulating top-level windows.
Bench_runBgEventStormHelper(iterations) {
  If (iterations < 1)
    iterations := 20000

  Debug_logMessage("DEBUG[0] Bench_runBgEventStormHelper: emitting " . iterations . " CREATE/SHOW pairs", 0)
  Loop, % iterations {
    Gui, EventStormChild: New, +ToolWindow -Caption +AlwaysOnTop, bug.n_eventstorm_child
    Gui, EventStormChild: Show, x0 y0 w1 h1 NoActivate
    Gui, EventStormChild: Destroy
  }
  Debug_logMessage("DEBUG[0] Bench_runBgEventStormHelper: done", 0)
  ExitApp, 0
}
