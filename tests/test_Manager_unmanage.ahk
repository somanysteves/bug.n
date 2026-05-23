/*
  Tests for Manager_unmanage (src/Manager.ahk).

  Pins #59: the per-view strip loop and Bar_updateView call must
  target the window's own monitor (Window_#%wndId%_monitor),
  not Manager_aMonitor. The EVENT_OBJECT_HIDE hook and
  Manager_validateAlive can both call unmanage for windows on
  monitors other than the currently-active one. Pre-fix, the
  loop stripped from View_#%Manager_aMonitor%_#... and left the
  real monitor's view holding a ghost wndId.

  Also asserts the new return contract: Manager_unmanage returns
  the affected monitor (or 0 if Window_#%wndId%_monitor was
  unset). Callers (winHideDeferred queue, validateAlive timer)
  use this to arrange the right monitor's view post-unmanage.
*/

class TestManagerUnmanage
{
  Begin()
  {
    Global Config_viewCount, Manager_aMonitor, Bar_initialized
    Global Manager_allWndIds, Manager_managedWndIds, Bar_hideTitleWndIds
    Global Monitor_#1_aView_#1, Monitor_#2_aView_#1
    Global View_#1_#1_wndIds, View_#1_#3_wndIds, View_#2_#1_wndIds, View_#2_#3_wndIds
    Global View_#1_#1_aWndIds, View_#1_#3_aWndIds, View_#2_#1_aWndIds, View_#2_#3_aWndIds
    Global Window_#0xa00c6_monitor, Window_#0xa00c6_tags, Window_#0xa00c6_isDecorated
    Global Window_#0xa00c6_isFloating, Window_#0xa00c6_isUrgent, Window_#0xa00c6_area

    Bar_initialized      := False  ;; Bar_updateView early-returns
    Config_viewCount     := 9
    Manager_aMonitor     := 1      ;; active monitor != window's monitor
    Monitor_#1_aView_#1  := 3
    Monitor_#2_aView_#1  := 3

    Manager_managedWndIds := "0xa00c6;"
    Manager_allWndIds     := "0xa00c6;"
    Bar_hideTitleWndIds   := ""

    View_#1_#1_wndIds := ""
    View_#1_#3_wndIds := ""
    View_#2_#1_wndIds := ""
    View_#2_#3_wndIds := "0xa00c6;"
    View_#1_#1_aWndIds := ""
    View_#1_#3_aWndIds := ""
    View_#2_#1_aWndIds := ""
    View_#2_#3_aWndIds := "0xa00c6;"

    Window_#0xa00c6_monitor     := 2
    Window_#0xa00c6_tags        := 4   ;; 1 << (3-1) -> view 3 only
    Window_#0xa00c6_isDecorated := True
    Window_#0xa00c6_isFloating  := False
    Window_#0xa00c6_isUrgent    := False
    Window_#0xa00c6_area        := ""
  }

  StripsFromWindowsOwnMonitor_NotActiveMonitor()
  {
    Global View_#1_#3_wndIds, View_#2_#3_wndIds
    Manager_unmanage("0xa00c6")
    Yunit.Assert(View_#2_#3_wndIds = "", "monitor 2's view 3 must be stripped, got '" . View_#2_#3_wndIds . "'")
    Yunit.Assert(View_#1_#3_wndIds = "", "monitor 1's view 3 must be untouched, got '" . View_#1_#3_wndIds . "'")
  }

  StripsFromWindowsOwnMonitor_aWndIds()
  {
    Global View_#1_#3_aWndIds, View_#2_#3_aWndIds
    Manager_unmanage("0xa00c6")
    Yunit.Assert(View_#2_#3_aWndIds = "", "monitor 2's view 3 aWndIds must be stripped, got '" . View_#2_#3_aWndIds . "'")
    Yunit.Assert(View_#1_#3_aWndIds = "", "monitor 1's view 3 aWndIds must be untouched, got '" . View_#1_#3_aWndIds . "'")
  }

  ReturnsAffectedMonitor()
  {
    result := Manager_unmanage("0xa00c6")
    Yunit.Assert(result = 2, "unmanage must return the window's monitor (2), got '" . result . "'")
  }

  ClearsManagedAndAllWndIds()
  {
    Global Manager_managedWndIds, Manager_allWndIds
    Manager_unmanage("0xa00c6")
    Yunit.Assert(Manager_managedWndIds = "", "managed list must be cleared, got '" . Manager_managedWndIds . "'")
    Yunit.Assert(Manager_allWndIds = "", "all list must be cleared, got '" . Manager_allWndIds . "'")
  }

  MultipleViewsTagged_StripsAllOnWindowsMonitor()
  {
    Global View_#1_#1_wndIds, View_#1_#3_wndIds, View_#2_#1_wndIds, View_#2_#3_wndIds
    Global Window_#0xa00c6_tags
    Window_#0xa00c6_tags := 5  ;; views 1 and 3 (1 | 4)
    View_#2_#1_wndIds := "0xa00c6;"
    Manager_unmanage("0xa00c6")
    Yunit.Assert(View_#2_#1_wndIds = "", "monitor 2's view 1 must be stripped, got '" . View_#2_#1_wndIds . "'")
    Yunit.Assert(View_#2_#3_wndIds = "", "monitor 2's view 3 must be stripped, got '" . View_#2_#3_wndIds . "'")
    Yunit.Assert(View_#1_#1_wndIds = "", "monitor 1's view 1 must be untouched, got '" . View_#1_#1_wndIds . "'")
    Yunit.Assert(View_#1_#3_wndIds = "", "monitor 1's view 3 must be untouched, got '" . View_#1_#3_wndIds . "'")
  }

  ClearsPerWindowGlobals()
  {
    Global Window_#0xa00c6_monitor, Window_#0xa00c6_tags
    Global Window_#0xa00c6_isDecorated, Window_#0xa00c6_isFloating
    Global Window_#0xa00c6_isUrgent, Window_#0xa00c6_area
    Manager_unmanage("0xa00c6")
    Yunit.Assert(Window_#0xa00c6_monitor = "", "_monitor must be cleared")
    Yunit.Assert(Window_#0xa00c6_tags = "", "_tags must be cleared")
    Yunit.Assert(Window_#0xa00c6_isDecorated = "", "_isDecorated must be cleared")
    Yunit.Assert(Window_#0xa00c6_isFloating = "", "_isFloating must be cleared")
    Yunit.Assert(Window_#0xa00c6_isUrgent = "", "_isUrgent must be cleared")
    Yunit.Assert(Window_#0xa00c6_area = "", "_area must be cleared")
  }
}
