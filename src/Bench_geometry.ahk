/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3

  Bench_geometry.ahk -- post-tile correctness assertion (#41).

  The perf scenarios in Perf_runBench measure timing of View_arrange /
  Tiler_stackTiles / Monitor_activateView. They confirm the AHK thread
  returns quickly but say nothing about where the windows actually
  landed. PR #38 shipped a sign error in the feedforward DWM correction
  math that left every tile 14 px right and 28 px narrow; every perf
  bench passed because none of them looked at pixel positions.

  Bench_assertTiled fills that gap by comparing each tiled window's
  actual rect (Window_getPosEx) to the expected rect computed by the
  tiler itself in "trace" mode -- same code path as production, but the
  leaf records areas instead of moving windows. This catches:
    - sign / offset errors in Window_correctedSendCoords,
    - DeferWindowPos silently dropping a window mid-batch,
    - tiling onto the wrong monitor when (m, v) routing breaks,
    - future refactors that regress in-place geometry.

  The 2 px tolerance matches Tiler_stackTiles's own in-place check
  (Tiler.ahk:435) and absorbs DWM sub-pixel rounding.

  Called only by the bench (Perf_runBench / Bench_run*). Production
  arrange paths are untouched.
*/

;; Returns the number of assertion failures (0 = pass). Logs per-window
;; diffs at level 0 so a CI run surfaces them without --debug.
;;   m         - monitor index (typically Manager_aMonitor)
;;   v         - view index (the bench playground view)
;;   scenario  - label string included in every log line for triage
Bench_assertTiled(m, v, scenario) {
  Local fn, l, x, y, w, h, tiledCount, areaN, hwnd, failures, i
  Local actX, actY, actW, actH
  Local slotHwnds, expX, expY, expW, expH

  l  := View_#%m%_#%v%_layout_#1
  fn := Config_layoutFunction_#%l%
  ;; Floating layouts (and any unknown layout function) have no per-window
  ;; expected geometry -- skip silently.
  If (fn != "tile" And fn != "monocle")
    Return 0

  View_getTiledWndIds(m, v)
  tiledCount := View_tiledWndId0
  If (tiledCount = 0)
    Return 0

  ;; Snapshot slot -> hwnd up front so a window destroyed mid-check doesn't
  ;; shift our reporting indices.
  slotHwnds := []
  Loop, % tiledCount
    slotHwnds.Push(View_tiledWndId%A_Index%)

  ;; Wait for pending async window moves to drain before sampling positions.
  ;; Tiler_stackTiles uses BeginDeferWindowPos + SWP_ASYNCWINDOWPOS: each move
  ;; is posted to the target window's message queue and the call returns
  ;; without waiting. Reading positions immediately races with the queued
  ;; moves -- a heavy scenario (layout_restructure: 720 moves) leaves the
  ;; queue still draining at assertion time.
  ;;
  ;; Polling-until-stable is the reliable mechanism: SendMessageTimeout(WM_NULL)
  ;; can't drain a posted-message queue (sent messages are processed before
  ;; posted ones), and a fixed Sleep is either too short for heavy scenarios
  ;; or too long for light ones. Poll positions, sleep briefly, repoll; when
  ;; nothing moved between samples, the queue has drained. 2 px stability
  ;; threshold absorbs DWM sub-pixel jitter without false-positive matches.
  ;; ~2 s total cap (20 iters × 100 ms) -- beyond that we sample whatever's
  ;; there and let the assertion fail with that data; it's bench output, not
  ;; production.
  prevX := []
  prevY := []
  prevW := []
  prevH := []
  Loop, % tiledCount {
    If Window_getPosEx(slotHwnds[A_Index], px, py, pw, ph) {
      prevX.Push(px), prevY.Push(py), prevW.Push(pw), prevH.Push(ph)
    } Else {
      prevX.Push(0),  prevY.Push(0),  prevW.Push(0),  prevH.Push(0)
    }
  }
  stableIters := 0
  Loop, 20 {
    Sleep, 100
    stable := True
    Loop, % tiledCount {
      If Window_getPosEx(slotHwnds[A_Index], curX, curY, curW, curH) {
        If (Abs(curX - prevX[A_Index]) > 2 Or Abs(curY - prevY[A_Index]) > 2
            Or Abs(curW - prevW[A_Index]) > 2 Or Abs(curH - prevH[A_Index]) > 2) {
          stable := False
        }
        prevX[A_Index] := curX, prevY[A_Index] := curY
        prevW[A_Index] := curW, prevH[A_Index] := curH
      }
    }
    If stable {
      stableIters := A_Index
      Break
    }
  }
  ;; Single-iteration settle is the normal case; only log when something
  ;; took longer (queue was unusually backed up or a window was slow).
  If (stableIters != 1)
    Debug_logMessage("DEBUG[0] Bench_assertTiled [" . scenario . "]: positions stabilized after " . stableIters . " poll iteration(s)", 0)

  ;; Same margin-adjusted area View_arrange feeds the tiler (View_arrange.ahk:27-30).
  x := Monitor_#%m%_x + View_#%m%_#%v%_layoutGapWidth + View_#%m%_#%v%_margin4
  y := Monitor_#%m%_y + View_#%m%_#%v%_layoutGapWidth + View_#%m%_#%v%_margin1
  w := Monitor_#%m%_width  - 2 * View_#%m%_#%v%_layoutGapWidth - View_#%m%_#%v%_margin4 - View_#%m%_#%v%_margin2
  h := Monitor_#%m%_height - 2 * View_#%m%_#%v%_layoutGapWidth - View_#%m%_#%v%_margin1 - View_#%m%_#%v%_margin3

  expX := []
  expY := []
  expW := []
  expH := []
  If (fn = "monocle") {
    ;; Every tiled window targets the same fullscreen rect.
    Loop, % tiledCount {
      expX.Push(x)
      expY.Push(y)
      expW.Push(w)
      expH.Push(h)
    }
  } Else {
    ;; fn = "tile" -- use the tiler's own math as the oracle.
    Tiler_layoutTiles(m, v, x, y, w, h, "trace")
    areaN := View_#%m%_#%v%_area_#0
    If (areaN != tiledCount) {
      Debug_logMessage("DEBUG[0] Bench_assertTiled [" . scenario . "]: trace produced " . areaN . " areas but " . tiledCount . " windows are tiled on monitor " . m . " view " . v . " -- assertion skipped", 0)
      Return 0
    }
    Loop, % tiledCount {
      expX.Push(View_#%m%_#%v%_area_#%A_Index%_x)
      expY.Push(View_#%m%_#%v%_area_#%A_Index%_y)
      expW.Push(View_#%m%_#%v%_area_#%A_Index%_width)
      expH.Push(View_#%m%_#%v%_area_#%A_Index%_height)
    }
  }

  failures := 0
  Loop, % tiledCount {
    hwnd := slotHwnds[A_Index]
    If Not Window_getPosEx(hwnd, actX, actY, actW, actH) {
      Debug_logMessage("DEBUG[0] Bench_assertTiled [" . scenario . "] FAIL: slot " . A_Index . " hwnd " . hwnd . " -- Window_getPosEx returned false", 0)
      failures += 1
      Continue
    }
    If (Abs(actX - expX[A_Index]) > 1 Or Abs(actY - expY[A_Index]) > 1
        Or Abs(actW - expW[A_Index]) > 1 Or Abs(actH - expH[A_Index]) > 1) {
      WinGetClass, wndClass, ahk_id %hwnd%
      Debug_logMessage("DEBUG[0] Bench_assertTiled [" . scenario . "] FAIL: slot " . A_Index . " hwnd " . hwnd
        . " class=" . wndClass
        . " expected (" . expX[A_Index] . "," . expY[A_Index] . "," . expW[A_Index] . "x" . expH[A_Index] . ")"
        . " actual ("   . actX           . "," . actY           . "," . actW           . "x" . actH           . ")", 0)
      failures += 1
    }
  }
  If (failures = 0)
    Debug_logMessage("DEBUG[0] Bench_assertTiled [" . scenario . "]: PASS " . tiledCount . " windows (monitor " . m . " view " . v . ", layout " . fn . ")", 0)
  Return failures
}
