/*
  Tests for Manager__processHideQueue (extracted from the
  Manager_winHideDeferred label in src/Manager.ahk).

  Pins the second half of #59: when the deferred unmanage timer
  drains a queue spanning multiple monitors, View_arrange and
  Bar_updateView must run *per affected monitor*, not just
  Manager_aMonitor. Pre-fix, an EVENT_OBJECT_HIDE on a non-active
  monitor would be unmanaged correctly (after the unmanage fix)
  but the sibling monitor's bar/tile layout would not refresh
  until a user-driven view switch on that monitor.
*/

class TestManagerProcessHideQueue
{
  Begin()
  {
    Global Config_viewCount, Config_dynamicTiling, Bar_initialized
    Global Manager_aMonitor, Manager_managedWndIds, Manager_allWndIds
    Global Bar_hideTitleWndIds
    Global Monitor_#1_aView_#1, Monitor_#2_aView_#1
    Global View_#1_#1_wndIds, View_#1_#3_wndIds, View_#2_#1_wndIds, View_#2_#3_wndIds
    Global View_#1_#1_aWndIds, View_#1_#3_aWndIds, View_#2_#1_aWndIds, View_#2_#3_aWndIds
    Global Window_#1001_monitor, Window_#1001_tags
    Global Window_#1001_isDecorated, Window_#1001_isFloating, Window_#1001_isUrgent, Window_#1001_area
    Global Window_#1002_monitor, Window_#1002_tags
    Global Window_#1002_isDecorated, Window_#1002_isFloating, Window_#1002_isUrgent, Window_#1002_area
    Global Test_viewArrangeCallCount, Test_viewArrangeHistory
    Global Manager_sessionActive, Manager_lastReconnectTick, Config_sessionReconnectGraceMs

    Bar_initialized      := False
    Config_viewCount     := 9
    Config_dynamicTiling := True
    Manager_aMonitor     := 1

    ;; Session gate defaults: active, never reconnected (grace long over) so
    ;; the unmanage path runs normally. The SessionInactive_* cases below flip
    ;; Manager_sessionActive to assert suppression.
    Manager_sessionActive         := True
    Manager_lastReconnectTick     := 0
    Config_sessionReconnectGraceMs := 2000
    Monitor_#1_aView_#1  := 3
    Monitor_#2_aView_#1  := 1

    ;; 1001 lives on m1/view3; 1002 lives on m2/view1
    Manager_managedWndIds := "1001;1002;"
    Manager_allWndIds     := "1001;1002;"
    Bar_hideTitleWndIds   := ""

    View_#1_#1_wndIds  := ""
    View_#1_#3_wndIds  := "1001;"
    View_#2_#1_wndIds  := "1002;"
    View_#2_#3_wndIds  := ""
    View_#1_#1_aWndIds := ""
    View_#1_#3_aWndIds := "1001;"
    View_#2_#1_aWndIds := "1002;"
    View_#2_#3_aWndIds := ""

    Window_#1001_monitor     := 1
    Window_#1001_tags        := 4   ;; view 3
    Window_#1001_isDecorated := True
    Window_#1001_isFloating  := False
    Window_#1001_isUrgent    := False
    Window_#1001_area        := ""

    Window_#1002_monitor     := 2
    Window_#1002_tags        := 1   ;; view 1
    Window_#1002_isDecorated := True
    Window_#1002_isFloating  := False
    Window_#1002_isUrgent    := False
    Window_#1002_area        := ""

    Test_viewArrangeCallCount := 0
    Test_viewArrangeHistory   := ""
  }

  EmptyQueue_NoArrangeCalls()
  {
    Global Test_viewArrangeCallCount
    result := Manager__processHideQueue("")
    Yunit.Assert(result = "", "empty queue must yield empty affected-monitor set, got '" . result . "'")
    Yunit.Assert(Test_viewArrangeCallCount = 0, "no View_arrange calls expected, got " . Test_viewArrangeCallCount)
  }

  SingleWindow_OnNonActiveMonitor_ArrangesThatMonitor()
  {
    ;; The regression in #59: window on m2, m1 is active.
    ;; Pre-fix, View_arrange targeted m1; m2 was left stale.
    Global Test_viewArrangeCallCount, Test_viewArrangeHistory
    result := Manager__processHideQueue("1002")
    Yunit.Assert(result = ";2;", "affected set must be ';2;', got '" . result . "'")
    Yunit.Assert(Test_viewArrangeCallCount = 1, "exactly one View_arrange, got " . Test_viewArrangeCallCount)
    Yunit.Assert(InStr(Test_viewArrangeHistory, ";2,1;"), "View_arrange must target m2/v1, history: '" . Test_viewArrangeHistory . "'")
  }

  MultipleWindows_DifferentMonitors_ArrangesEach()
  {
    Global Test_viewArrangeCallCount, Test_viewArrangeHistory
    result := Manager__processHideQueue("1001;1002")
    Yunit.Assert(InStr(result, ";1;"), "affected set must include m1, got '" . result . "'")
    Yunit.Assert(InStr(result, ";2;"), "affected set must include m2, got '" . result . "'")
    Yunit.Assert(Test_viewArrangeCallCount = 2, "exactly two View_arrange calls, got " . Test_viewArrangeCallCount)
    Yunit.Assert(InStr(Test_viewArrangeHistory, ";1,3;"), "View_arrange must target m1/v3, history: '" . Test_viewArrangeHistory . "'")
    Yunit.Assert(InStr(Test_viewArrangeHistory, ";2,1;"), "View_arrange must target m2/v1, history: '" . Test_viewArrangeHistory . "'")
  }

  MultipleWindows_SameMonitor_ArrangesOnce()
  {
    ;; Two queued hides on the same monitor must coalesce into a
    ;; single View_arrange/Bar_updateView, not one per window.
    Global Window_#1002_monitor, Window_#1002_tags, View_#1_#1_wndIds, Test_viewArrangeCallCount
    Window_#1002_monitor := 1
    Window_#1002_tags    := 1   ;; view 1
    View_#1_#1_wndIds    := "1002;"
    result := Manager__processHideQueue("1001;1002")
    Yunit.Assert(result = ";1;", "affected set must be ';1;' only, got '" . result . "'")
    Yunit.Assert(Test_viewArrangeCallCount = 1, "exactly one View_arrange (coalesced), got " . Test_viewArrangeCallCount)
  }

  UnmanagedHwndInQueue_Skipped()
  {
    ;; A queued hwnd that got concurrently unmanaged (no longer in
    ;; Manager_managedWndIds) must be skipped without affecting the
    ;; arrange set.
    Global Test_viewArrangeCallCount
    result := Manager__processHideQueue("9999;1002")
    Yunit.Assert(result = ";2;", "unmanaged 9999 must be skipped, affected = ';2;', got '" . result . "'")
    Yunit.Assert(Test_viewArrangeCallCount = 1, "one arrange (for m2 only), got " . Test_viewArrangeCallCount)
  }

  DynamicTilingOff_SkipsViewArrangeButStillUpdatesBar()
  {
    ;; Config_dynamicTiling=False suppresses View_arrange but the
    ;; bar still refreshes (matches pre-extraction semantics for the
    ;; active-monitor path).
    Global Config_dynamicTiling, Test_viewArrangeCallCount
    Config_dynamicTiling := False
    result := Manager__processHideQueue("1002")
    Yunit.Assert(result = ";2;", "affected set still tracked, got '" . result . "'")
    Yunit.Assert(Test_viewArrangeCallCount = 0, "no View_arrange when dynamicTiling off, got " . Test_viewArrangeCallCount)
  }

  SessionInactive_SuppressesUnmanage_WindowStaysManaged()
  {
    ;; The fix: during a disconnect/lock (session inactive) the app-side
    ;; HIDE burst must NOT unmanage. The window stays in Manager_managedWndIds
    ;; and on its view; no monitor is arranged (nothing was dropped).
    Global Manager_sessionActive, Manager_managedWndIds, View_#2_#1_wndIds, Test_viewArrangeCallCount
    Manager_sessionActive := False
    result := Manager__processHideQueue("1002")
    Yunit.Assert(result = "", "no monitor affected when suppressed, got '" . result . "'")
    Yunit.Assert(Test_viewArrangeCallCount = 0, "no View_arrange when suppressed, got " . Test_viewArrangeCallCount)
    Yunit.Assert(InStr(Manager_managedWndIds, "1002;"), "1002 must stay managed, got '" . Manager_managedWndIds . "'")
    Yunit.Assert(View_#2_#1_wndIds = "1002;", "1002 must stay on its view, got '" . View_#2_#1_wndIds . "'")
  }

  SessionActiveWithinReconnectGrace_SuppressesUnmanage()
  {
    ;; Reconnect just happened (lastReconnectTick = now): the trailing HIDE
    ;; burst is still teardown churn and must be suppressed even though the
    ;; session flag already flipped back to active.
    Global Manager_sessionActive, Manager_lastReconnectTick, Manager_managedWndIds
    Manager_sessionActive     := True
    Manager_lastReconnectTick := A_TickCount   ;; 0ms elapsed, well within 2000 grace
    result := Manager__processHideQueue("1002")
    Yunit.Assert(result = "", "within grace: no monitor affected, got '" . result . "'")
    Yunit.Assert(InStr(Manager_managedWndIds, "1002;"), "1002 must stay managed within grace, got '" . Manager_managedWndIds . "'")
  }
}
