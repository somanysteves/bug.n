/*
  Tests for Manager_validateAlive (src/Manager.ahk).

  Pins the third call site of #59: validateAlive walks
  Manager_managedWndIds looking for HWNDs that no longer exist
  (WinExist == 0) and unmanages them. Pre-fix it returned a bool
  and the timer always re-arranged Manager_aMonitor; now it
  returns the set of affected monitors as a ";m1;m2;" string so
  Manager_validateAliveTimer can arrange each.

  Fake HWNDs (1001, 1002, ...) naturally fail WinExist under the
  Yunit harness, so every managed entry classifies as dead and
  gets unmanaged. Tests use that to drive the function without
  needing a real OS window.
*/

class TestManagerValidateAlive
{
  Begin()
  {
    Global Config_viewCount, Bar_initialized
    Global Manager_aMonitor, Manager_managedWndIds, Manager_allWndIds
    Global Bar_hideTitleWndIds
    Global Monitor_#1_aView_#1, Monitor_#2_aView_#1
    Global View_#1_#1_wndIds, View_#1_#3_wndIds, View_#2_#1_wndIds, View_#2_#3_wndIds
    Global View_#1_#1_aWndIds, View_#1_#3_aWndIds, View_#2_#1_aWndIds, View_#2_#3_aWndIds
    Global Window_#1001_monitor, Window_#1001_tags
    Global Window_#1001_isDecorated, Window_#1001_isFloating, Window_#1001_isUrgent, Window_#1001_area
    Global Window_#1002_monitor, Window_#1002_tags
    Global Window_#1002_isDecorated, Window_#1002_isFloating, Window_#1002_isUrgent, Window_#1002_area

    Bar_initialized      := False
    Config_viewCount     := 9
    Manager_aMonitor     := 1
    Monitor_#1_aView_#1  := 3
    Monitor_#2_aView_#1  := 1

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
    Window_#1001_tags        := 4
    Window_#1001_isDecorated := True
    Window_#1001_isFloating  := False
    Window_#1001_isUrgent    := False
    Window_#1001_area        := ""

    Window_#1002_monitor     := 2
    Window_#1002_tags        := 1
    Window_#1002_isDecorated := True
    Window_#1002_isFloating  := False
    Window_#1002_isUrgent    := False
    Window_#1002_area        := ""
  }

  EmptyManagedList_ReturnsEmptyAffectedSet()
  {
    Global Manager_managedWndIds
    Manager_managedWndIds := ""
    result := Manager_validateAlive()
    Yunit.Assert(result = "", "no managed wndIds -> empty affected set, got '" . result . "'")
  }

  DeadWindowsOnMultipleMonitors_ReturnsUnionOfMonitors()
  {
    result := Manager_validateAlive()
    Yunit.Assert(InStr(result, ";1;"), "affected set must include m1, got '" . result . "'")
    Yunit.Assert(InStr(result, ";2;"), "affected set must include m2, got '" . result . "'")
  }

  DeadWindowsSameMonitor_MonitorListedOnce()
  {
    ;; Move 1002 to m1 so both dead windows share a monitor.
    Global Window_#1002_monitor, View_#2_#1_wndIds, View_#1_#1_wndIds
    Window_#1002_monitor := 1
    Window_#1002_tags    := 1
    View_#2_#1_wndIds    := ""
    View_#1_#1_wndIds    := "1002;"
    result := Manager_validateAlive()
    Yunit.Assert(result = ";1;", "single-monitor affected set must be ';1;', got '" . result . "'")
  }

  PrunesEntriesFromManagedList()
  {
    Global Manager_managedWndIds
    Manager_validateAlive()
    Yunit.Assert(Manager_managedWndIds = "", "all dead entries must be removed from managed list, got '" . Manager_managedWndIds . "'")
  }
}
