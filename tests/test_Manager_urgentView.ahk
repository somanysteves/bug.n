/*
  Tests for the urgent-view feature in src/Manager.ahk.

  Covers Manager_markUrgent (called from the HSHELL_FLASH branch of
  Manager_onShellMessage), Manager_activateUrgentView (Win+U), and the
  urgency-clearing block inserted at the top of Monitor_activateView.

  The bar GUI is NOT initialized in the test runner — Bar_init never
  runs, so Bar_initialized is empty, which makes Bar_updateView and
  Bar_updateTitle early-return. That keeps these tests pure logic
  exercises against the global state Manager_*/View_*/Window_*.

  AHK v1 scoping note: every method (including Begin/End) uses bare
  `Global` so that dynamic variable names like `View_#1_#2_isUrgent`
  resolve to the actual globals rather than creating silent local
  shadows. Without this, dynamic writes inside a method create locals
  that vanish on return — and assertions against the "real" globals
  see the unchanged initial values.
*/

class TestManagerUrgentView
{
  Begin()
  {
    Global

    Manager_aMonitor      := 1
    Manager_managedWndIds := "1001;1002;"
    Manager_hideShow      := False
    Monitor_#1_aView_#1   := 1
    Monitor_#1_aView_#2   := 1
    Manager_monitorCount  := 1
    Config_viewCount      := 3
    Config_syncMonitorViews := 0

    View_#1_#1_isUrgent := False
    View_#1_#2_isUrgent := False
    View_#1_#3_isUrgent := False
    View_#1_#1_wndIds   := ""
    View_#1_#2_wndIds   := ""
    View_#1_#3_wndIds   := ""
    View_#1_#1_aWndIds  := "0;"
    View_#1_#2_aWndIds  := "0;"
    View_#1_#3_aWndIds  := "0;"
    View_#1_#1_showBar  := True
    View_#1_#2_showBar  := True
    View_#1_#3_showBar  := True

    Monitor_#1_showBar  := True

    Window_#1001_isUrgent   := False
    Window_#1001_isFloating := False
    Window_#1001_isMinimized := False
    Window_#1001_monitor    := 1
    Window_#1001_tags       := 0
    Window_#1002_isUrgent   := False
    Window_#1002_isFloating := False
    Window_#1002_isMinimized := False
    Window_#1002_monitor    := 1
    Window_#1002_tags       := 0
  }

  End()
  {
    Global

    Manager_aMonitor      := ""
    Manager_managedWndIds := ""
    Manager_hideShow      := ""
    Monitor_#1_aView_#1   := ""
    Monitor_#1_aView_#2   := ""
    Manager_monitorCount  := ""
    Config_viewCount      := ""
    Config_syncMonitorViews := ""

    View_#1_#1_isUrgent := ""
    View_#1_#2_isUrgent := ""
    View_#1_#3_isUrgent := ""
    View_#1_#1_wndIds   := ""
    View_#1_#2_wndIds   := ""
    View_#1_#3_wndIds   := ""
    View_#1_#1_aWndIds  := ""
    View_#1_#2_aWndIds  := ""
    View_#1_#3_aWndIds  := ""
    View_#1_#1_showBar  := ""
    View_#1_#2_showBar  := ""
    View_#1_#3_showBar  := ""

    Monitor_#1_showBar  := ""

    Window_#1001_isUrgent    := ""
    Window_#1001_isFloating  := ""
    Window_#1001_isMinimized := ""
    Window_#1001_monitor     := ""
    Window_#1001_tags        := ""
    Window_#1002_isUrgent    := ""
    Window_#1002_isFloating  := ""
    Window_#1002_isMinimized := ""
    Window_#1002_monitor     := ""
    Window_#1002_tags        := ""

    ;; Monitor #2 state used by sync-mode tests; harmless to clear when unset.
    Monitor_#2_aView_#1 := ""
    Monitor_#2_aView_#2 := ""
    Monitor_#2_showBar  := ""
    View_#2_#1_isUrgent := ""
    View_#2_#2_isUrgent := ""
    View_#2_#3_isUrgent := ""
    View_#2_#1_wndIds   := ""
    View_#2_#2_wndIds   := ""
    View_#2_#3_wndIds   := ""
    View_#2_#1_aWndIds  := ""
    View_#2_#2_aWndIds  := ""
    View_#2_#3_aWndIds  := ""
    View_#2_#1_showBar  := ""
    View_#2_#2_showBar  := ""
    View_#2_#3_showBar  := ""
  }

  ;; --- Manager_markUrgent ---

  MarkUrgent_SetsWindowAndViewFlag()
  {
    Global

    ;; Window 1001 lives on views 1 and 2; active view is 1.
    Window_#1001_tags := (1 << 0) | (1 << 1)
    View_#1_#1_wndIds := "1001;"
    View_#1_#2_wndIds := "1001;"

    Manager_markUrgent(1001)

    Yunit.Assert(Window_#1001_isUrgent = True
      , "markUrgent should set Window_#1001_isUrgent; got '" . Window_#1001_isUrgent . "'")
    Yunit.Assert(View_#1_#2_isUrgent = True
      , "markUrgent should set View_#1_#2_isUrgent; got '" . View_#1_#2_isUrgent . "'")
  }

  MarkUrgent_DoesNotMarkActiveView()
  {
    Global

    ;; Window 1001 only on the active view (view 1).
    Window_#1001_tags := 1 << 0
    View_#1_#1_wndIds := "1001;"

    Manager_markUrgent(1001)

    Yunit.Assert(View_#1_#1_isUrgent = False
      , "markUrgent must not mark the active view; View_#1_#1_isUrgent = '" . View_#1_#1_isUrgent . "'")
    Yunit.Assert(Window_#1001_isUrgent = False
      , "markUrgent must not set window flag when only on active view; got '" . Window_#1001_isUrgent . "'")
  }

  MarkUrgent_MultipleViewsLitSimultaneously()
  {
    Global

    ;; Window 1001 on view 2; window 1002 on view 3. Active is view 1.
    Window_#1001_tags := 1 << 1
    Window_#1002_tags := 1 << 2
    View_#1_#2_wndIds := "1001;"
    View_#1_#3_wndIds := "1002;"

    Manager_markUrgent(1001)
    Manager_markUrgent(1002)

    Yunit.Assert(View_#1_#2_isUrgent = True
      , "View 2 should be urgent after first mark; got '" . View_#1_#2_isUrgent . "'")
    Yunit.Assert(View_#1_#3_isUrgent = True
      , "View 3 should be urgent simultaneously with view 2; got '" . View_#1_#3_isUrgent . "'")
  }

  ;; --- Monitor_activateView clears urgency on destination ---

  ActivateView_ClearsUrgencyOnDestination()
  {
    Global

    ;; Window 1001 is urgent on view 2, active view is 1.
    Window_#1001_tags     := 1 << 1
    View_#1_#2_wndIds     := "1001;"
    View_#1_#2_isUrgent   := True
    Window_#1001_isUrgent := True

    Monitor_activateView(2)

    Yunit.Assert(View_#1_#2_isUrgent = False
      , "Activating view 2 should clear its urgency flag; got '" . View_#1_#2_isUrgent . "'")
    Yunit.Assert(Window_#1001_isUrgent = False
      , "Activating view 2 should clear urgent window flag; got '" . Window_#1001_isUrgent . "'")
  }

  ActivateView_LeavesOtherUrgentViewsIntact()
  {
    Global

    ;; Two urgent views; activate one, the other must stay urgent.
    Window_#1001_tags := 1 << 1
    Window_#1002_tags := 1 << 2
    View_#1_#2_wndIds := "1001;"
    View_#1_#3_wndIds := "1002;"
    View_#1_#2_isUrgent := True
    View_#1_#3_isUrgent := True
    Window_#1001_isUrgent := True
    Window_#1002_isUrgent := True

    Monitor_activateView(2)

    Yunit.Assert(View_#1_#2_isUrgent = False
      , "View 2 urgency should clear after activation; got '" . View_#1_#2_isUrgent . "'")
    Yunit.Assert(View_#1_#3_isUrgent = True
      , "View 3 urgency should be preserved when activating view 2; got '" . View_#1_#3_isUrgent . "'")
  }

  ActivateView_SyncMonitorViews_ClearsUrgencyOnAllSyncedMonitors()
  {
    Global

    ;; Two monitors switching in lockstep. Both have view 2 flagged urgent.
    ;; When the user activates view 2 from monitor 1, the sync loop pulls
    ;; monitor 2 onto view 2 as well — its urgency must clear or the now-
    ;; active view will render with the urgent palette.
    Manager_monitorCount    := 2
    Config_syncMonitorViews := 1

    Monitor_#2_aView_#1 := 1
    Monitor_#2_aView_#2 := 1
    Monitor_#2_showBar  := True
    View_#2_#1_isUrgent := False
    View_#2_#2_isUrgent := False
    View_#2_#3_isUrgent := False
    View_#2_#1_wndIds   := ""
    View_#2_#2_wndIds   := ""
    View_#2_#3_wndIds   := ""
    View_#2_#1_aWndIds  := "0;"
    View_#2_#2_aWndIds  := "0;"
    View_#2_#3_aWndIds  := "0;"
    View_#2_#1_showBar  := True
    View_#2_#2_showBar  := True
    View_#2_#3_showBar  := True

    Window_#1001_tags     := 1 << 1
    Window_#1001_monitor  := 1
    Window_#1001_isUrgent := True
    View_#1_#2_wndIds     := "1001;"
    View_#1_#2_isUrgent   := True

    Window_#1002_tags     := 1 << 1
    Window_#1002_monitor  := 2
    Window_#1002_isUrgent := True
    View_#2_#2_wndIds     := "1002;"
    View_#2_#2_isUrgent   := True

    Monitor_activateView(2)

    Yunit.Assert(View_#1_#2_isUrgent = False
      , "Monitor 1's view 2 urgency should clear; got '" . View_#1_#2_isUrgent . "'")
    Yunit.Assert(Window_#1001_isUrgent = False
      , "Monitor 1's window 1001 urgency should clear; got '" . Window_#1001_isUrgent . "'")

    Yunit.Assert(View_#2_#2_isUrgent = False
      , "Monitor 2's view 2 urgency should also clear under syncMonitorViews; got '" . View_#2_#2_isUrgent . "'")
    Yunit.Assert(Window_#1002_isUrgent = False
      , "Monitor 2's window 1002 urgency should also clear; got '" . Window_#1002_isUrgent . "'")
  }

  ;; --- integration: Manager_onShellMessage → Manager_markUrgent ---
  ;;
  ;; Locks in the dispatch path. Regression guard: Manager_onShellMessage
  ;; has an early-return for windows that Window_getHidden flags as
  ;; SW_HIDDEN, and bug.n hides every window that is on a non-active
  ;; view — i.e. exactly the windows whose flashes we want to surface.
  ;; If the HSHELL_FLASH check ever moves below that early-return again,
  ;; this test goes red.

  ShellHook_HSHELL_FLASH_DispatchesToMarkUrgentForManagedWindow()
  {
    Global

    Window_#1001_tags := 1 << 1
    View_#1_#2_wndIds := "1001;"

    ;; HSHELL_FLASH = 32774, defined locally inside Manager_onShellMessage.
    Manager_onShellMessage(32774, 1001)

    Yunit.Assert(View_#1_#2_isUrgent = True
      , "HSHELL_FLASH on a managed window should mark its non-active view urgent; got '" . View_#1_#2_isUrgent . "'")
    Yunit.Assert(Window_#1001_isUrgent = True
      , "HSHELL_FLASH on a managed window should set the window's urgent flag; got '" . Window_#1001_isUrgent . "'")
  }

  ShellHook_HSHELL_FLASH_IgnoresUnmanagedWindow()
  {
    Global

    ;; Window 9999 is NOT in Manager_managedWndIds (Begin sets "1001;1002;").
    Window_#9999_tags    := 1 << 1
    Window_#9999_monitor := 1
    View_#1_#2_wndIds    := "9999;"

    Manager_onShellMessage(32774, 9999)

    Yunit.Assert(View_#1_#2_isUrgent = False
      , "HSHELL_FLASH on an unmanaged window must not mark any view; got '" . View_#1_#2_isUrgent . "'")
  }

  ;; Regression guard for the SW_HIDDEN early-return: bug.n SW_HIDEs
  ;; every window on a non-active view, and Window_getHidden returns
  ;; True for those — they are exactly the windows whose flashes we
  ;; want to surface as red bar entries. If the HSHELL_FLASH dispatch
  ;; ever moves below the Window_getHidden early-return again, hidden
  ;; windows' flashes are silently dropped.
  ;;
  ;; The test stubs Window_getHidden to True (via stubs_io.ahk) so the
  ;; early-return *would* fire if the dispatch were ordered after it.
  ;; A passing assertion here means the dispatch ran first.
  ShellHook_HSHELL_FLASH_FiresEvenForHiddenWindow()
  {
    Global

    Window_#1001_tags := 1 << 1
    View_#1_#2_wndIds := "1001;"
    Test_Window_getHidden_returns := True

    Manager_onShellMessage(32774, 1001)

    Test_Window_getHidden_returns := ""

    Yunit.Assert(View_#1_#2_isUrgent = True
      , "HSHELL_FLASH on a hidden managed window must still mark its view urgent — "
      . "if this fails, the dispatch has likely been moved below the Window_getHidden "
      . "early-return; got View_#1_#2_isUrgent = '" . View_#1_#2_isUrgent . "'")
  }


  ;; --- Manager_activateUrgentView (Win+U) ---

  ActivateUrgentView_JumpsToFirstUrgentView()
  {
    Global

    ;; Active view is 1; view 2 is urgent.
    Window_#1001_tags := 1 << 1
    View_#1_#2_wndIds := "1001;"
    View_#1_#2_isUrgent := True

    Manager_activateUrgentView()

    Yunit.Assert(Monitor_#1_aView_#1 = 2
      , "Should jump to view 2; aView = " . Monitor_#1_aView_#1)
  }

  ActivateUrgentView_NoUrgentViewIsNoop()
  {
    Global

    Manager_activateUrgentView()

    Yunit.Assert(Monitor_#1_aView_#1 = 1
      , "No urgent views: aView should stay 1; got " . Monitor_#1_aView_#1)
  }

  ActivateUrgentView_CyclesOnRepeatedPress()
  {
    Global

    ;; Two urgent views (2 and 3), active is 1. Press 1 → 2; press 2 → 3.
    Window_#1001_tags := 1 << 1
    Window_#1002_tags := 1 << 2
    View_#1_#2_wndIds := "1001;"
    View_#1_#3_wndIds := "1002;"
    View_#1_#2_isUrgent := True
    View_#1_#3_isUrgent := True
    Window_#1001_isUrgent := True
    Window_#1002_isUrgent := True

    Manager_activateUrgentView()
    Yunit.Assert(Monitor_#1_aView_#1 = 2
      , "First press should jump to view 2; got " . Monitor_#1_aView_#1)

    Manager_activateUrgentView()
    Yunit.Assert(Monitor_#1_aView_#1 = 3
      , "Second press should cycle to view 3; got " . Monitor_#1_aView_#1)
  }

  ;; Regression guard: when the urgent window is NOT the most-recently-active
  ;; window in its view, Win+U used to land on the view but focus the wrong
  ;; window — the head of aWndIds, not the flashing one. Monitor_activateView
  ;; ends with `Manager_winActivate(View_getActiveWindow(m, i))`, and
  ;; View_getActiveWindow walks aWndIds head-first. So for Win+U to focus the
  ;; urgent window, Manager_activateUrgentView must promote it to the head of
  ;; the destination view's aWndIds before delegating to Monitor_activateView.
  ActivateUrgentView_FocusesUrgentWindowNotMostRecentlyActive()
  {
    Global

    ;; View 2 holds two windows. 1001 was last active there; 1002 is the one
    ;; that flashed. With 1001 at the head of aWndIds, Monitor_activateView's
    ;; final winActivate resolves to 1001 — the wrong window — unless Win+U
    ;; promotes the urgent window first.
    Window_#1001_tags     := 1 << 1
    Window_#1002_tags     := 1 << 1
    View_#1_#2_wndIds     := "1001;1002;"
    View_#1_#2_aWndIds    := "1001;1002;0;"
    View_#1_#2_isUrgent   := True
    Window_#1002_isUrgent := True

    Manager_activateUrgentView()

    Yunit.Assert(Monitor_#1_aView_#1 = 2
      , "Win+U should still jump to view 2; got " . Monitor_#1_aView_#1)
    Yunit.Assert(SubStr(View_#1_#2_aWndIds, 1, 5) = "1002;"
      , "Win+U must promote the urgent window (1002) to the head of "
      . "View_#1_#2_aWndIds so Manager_winActivate focuses it, not the "
      . "previously-active 1001; got View_#1_#2_aWndIds = '"
      . View_#1_#2_aWndIds . "'")
  }
}
