/*
  Tests for Manager_barTitleDispatch (src/Manager.ahk) -- the side-effect
  half of the Manager_barTitleAction / Manager_barTitleDispatch split.

  Covers the three failure modes Copilot flagged on PR #38:
    1. immediate branch must cancel a pending deferred timer (otherwise a
       redundant Bar_updateTitle would fire ~50 ms later).
    2. defer branch must arm the timer (otherwise the bar stops updating
       during streaming-window workloads).
    3. skip branch must NOT call Bar_updateTitle (the whole point of the
       perf win on background-window redraws).

  Bar_updateTitle is stubbed in tests/stubs_io.ahk with a call counter;
  the Manager_barTitleDeferred label calls that same stub, so the defer
  branch's eventual fire is observable here too.
*/

class TestManagerBarTitleDispatch {
  Begin() {
    Global Test_Bar_updateTitle_callCount
    Test_Bar_updateTitle_callCount := 0
    ;; Ensure no leftover timer from a prior test fires during this one.
    SetTimer, Manager_barTitleDeferred, Off
  }

  End() {
    SetTimer, Manager_barTitleDeferred, Off
  }

  Skip_NoCall_NoDeferredFire() {
    Global Test_Bar_updateTitle_callCount

    Manager_barTitleDispatch("skip")
    Yunit.Assert(Test_Bar_updateTitle_callCount = 0
      , "skip must not call Bar_updateTitle synchronously; got "
      . Test_Bar_updateTitle_callCount)

    Sleep, 100
    Yunit.Assert(Test_Bar_updateTitle_callCount = 0
      , "skip must not arm the deferred timer either; got "
      . Test_Bar_updateTitle_callCount . " after 100 ms")
  }

  Defer_DeferredFireOnly() {
    Global Test_Bar_updateTitle_callCount

    Manager_barTitleDispatch("defer")
    Yunit.Assert(Test_Bar_updateTitle_callCount = 0
      , "defer must not call Bar_updateTitle synchronously; got "
      . Test_Bar_updateTitle_callCount)

    Sleep, 100
    Yunit.Assert(Test_Bar_updateTitle_callCount = 1
      , "deferred timer (50 ms) should have fired exactly once; got "
      . Test_Bar_updateTitle_callCount . " after 100 ms")
  }

  Immediate_CallsNow_CancelsPendingDefer() {
    Global Test_Bar_updateTitle_callCount

    ;; Arm a defer first.
    Manager_barTitleDispatch("defer")
    Yunit.Assert(Test_Bar_updateTitle_callCount = 0
      , "precondition: defer is not synchronous")

    ;; Immediate must call now AND cancel the pending defer.
    Manager_barTitleDispatch("immediate")
    Yunit.Assert(Test_Bar_updateTitle_callCount = 1
      , "immediate should call Bar_updateTitle synchronously; got "
      . Test_Bar_updateTitle_callCount)

    Sleep, 100
    Yunit.Assert(Test_Bar_updateTitle_callCount = 1
      , "pending defer must have been cancelled (counter still 1 after "
      . "100 ms); got " . Test_Bar_updateTitle_callCount)
  }

  Immediate_StandaloneCall() {
    Global Test_Bar_updateTitle_callCount

    Manager_barTitleDispatch("immediate")
    Yunit.Assert(Test_Bar_updateTitle_callCount = 1
      , "immediate with no pending defer still calls Bar_updateTitle; got "
      . Test_Bar_updateTitle_callCount)

    Sleep, 100
    Yunit.Assert(Test_Bar_updateTitle_callCount = 1
      , "no stray defer fired after immediate; got "
      . Test_Bar_updateTitle_callCount . " after 100 ms")
  }
}
