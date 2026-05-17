/*
  Covers the View_cycleDrain label's contract under the coalescer (#46):

  1. Drain snapshots the delta, zeroes it, calls the worker once.
  2. An empty delta is a no-op (no worker call, no rearm).
  3. If presses arrive during the worker (delta accumulates), drain
     must re-arm the timer so the next drain picks up the accumulation.
     Catches the failure mode Copilot flagged on PR #48: AHK's one-shot
     timer fire can be swallowed when the same label is already running,
     leaving View_cycleDelta non-zero with no pending timer and the
     mid-drain presses stuck forever.

  Worker (View_activateWindow_now) and re-arm (View_cycleDrainRearm)
  are stubbed via tests/stubs_io.ahk -- the real bodies live in
  src/View_activateWindow_now.ahk and reach out to the OS / arm an AHK
  timer that the test process won't outlive.
*/

class TestViewCycleDrain {
  Begin() {
    Global View_cycleDelta, View_cycleDelta_pending
    Global Test_View_activateWindow_now_calls, Test_View_activateWindow_now_inject
    Global Test_View_cycleDrainRearm_callCount
    View_cycleDelta                       := 0
    View_cycleDelta_pending               := 0
    Test_View_activateWindow_now_calls    := ""
    Test_View_activateWindow_now_inject   := 0
    Test_View_cycleDrainRearm_callCount   := 0
  }

  ZeroDelta_NoWorkerCall_NoRearm() {
    Global View_cycleDelta
    Global Test_View_activateWindow_now_calls, Test_View_cycleDrainRearm_callCount
    View_cycleDelta := 0

    Gosub, View_cycleDrain

    Yunit.Assert(View_cycleDelta = 0, "delta should remain 0; got " . View_cycleDelta)
    Yunit.Assert(Test_View_activateWindow_now_calls = "", "no worker call expected; got " . Test_View_activateWindow_now_calls)
    Yunit.Assert(Test_View_cycleDrainRearm_callCount = 0, "no rearm expected; got " . Test_View_cycleDrainRearm_callCount)
  }

  PositiveDelta_WorkerCalledWithDelta_DeltaZeroed_NoRearm() {
    Global View_cycleDelta
    Global Test_View_activateWindow_now_calls, Test_View_cycleDrainRearm_callCount
    View_cycleDelta := 3

    Gosub, View_cycleDrain

    Yunit.Assert(Test_View_activateWindow_now_calls = "0,3;"
      , "expected worker called once with (0, 3); got '" . Test_View_activateWindow_now_calls . "'")
    Yunit.Assert(View_cycleDelta = 0, "delta should be zeroed; got " . View_cycleDelta)
    Yunit.Assert(Test_View_cycleDrainRearm_callCount = 0
      , "no rearm expected (nothing accumulated during work); got " . Test_View_cycleDrainRearm_callCount)
  }

  NegativeDelta_WorkerCalledWithNegativeDelta() {
    Global View_cycleDelta, Test_View_activateWindow_now_calls
    View_cycleDelta := -2

    Gosub, View_cycleDrain

    Yunit.Assert(Test_View_activateWindow_now_calls = "0,-2;"
      , "expected worker called once with (0, -2); got '" . Test_View_activateWindow_now_calls . "'")
  }

  DeltaAccumulatedDuringWork_RearmsTimer() {
    ;; The bug Copilot flagged: when a press lands while drain is in the
    ;; middle of View_activateWindow_now, View_cycleDelta becomes non-zero
    ;; but the SetTimer re-arm fired by the hotkey thread can be swallowed
    ;; (AHK may drop a fire while the same label is busy). Without an
    ;; explicit post-work re-arm, that press is stuck forever.
    Global View_cycleDelta
    Global Test_View_activateWindow_now_calls, Test_View_activateWindow_now_inject
    Global Test_View_cycleDrainRearm_callCount
    View_cycleDelta := 1
    ;; Stub injects +2 into cycleDelta during its call, simulating two
    ;; hotkey presses arriving while drain is mid-WinActivate.
    Test_View_activateWindow_now_inject := 2

    Gosub, View_cycleDrain

    Yunit.Assert(Test_View_activateWindow_now_calls = "0,1;"
      , "expected worker called once with the snapshotted delta (1); got '" . Test_View_activateWindow_now_calls . "'")
    Yunit.Assert(View_cycleDelta = 2
      , "expected the injected presses to leave delta=2 for the next drain; got " . View_cycleDelta)
    Yunit.Assert(Test_View_cycleDrainRearm_callCount = 1
      , "expected drain to re-arm the timer because delta accumulated during work; got " . Test_View_cycleDrainRearm_callCount)
  }
}
