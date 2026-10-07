/*
  Tests for Manager_validateAlive (src/Manager.ahk).

  validateAlive walks Manager_managedWndIds looking for HWNDs that no
  longer exist (WinExist == 0) and unmanages them, returning the set of
  affected monitors as a ";m1;m2;" string so Manager_validateAliveTimer
  can arrange each (#59).

  Two reconnect-orphan guards layer on top of that walk:

    * Session gate -- while the WTS session is inactive (disconnected /
      locked) or within the post-reconnect grace, the prune is skipped
      entirely (Manager_shouldSuppressHideUnmanage). A teardown blip must
      not drop a live window.

    * Two-pass debounce -- a managed HWND must fail WinExist on two
      *consecutive* passes before it is pruned (Manager_classifyAliveCheck
      + the Manager_validateAliveMissed tracker). The first miss only
      defers; the confirming pass prunes.

  Fake HWNDs (1001, 1002, ...) naturally fail WinExist under the Yunit
  harness, so every managed entry classifies as missing. Begin() puts the
  session gate in its non-suppressing state (active, never reconnected ->
  past grace) and clears the miss tracker, so tests drive the debounce by
  calling validateAlive once (defer) or twice (prune).
*/

class TestManagerValidateAlive
{
  Begin()
  {
    Global Config_viewCount, Bar_initialized
    Global Manager_aMonitor, Manager_managedWndIds, Manager_allWndIds
    Global Bar_hideTitleWndIds
    Global Manager_sessionActive, Manager_lastReconnectTick, Config_sessionReconnectGraceMs
    Global Manager_validateAliveMissed
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

    ;; Session gate in its steady-state "do not suppress" position: active,
    ;; and lastReconnectTick 0 means msSinceReconnect is a huge A_TickCount
    ;; -> well past grace. Miss tracker cleared so each test starts fresh.
    Manager_sessionActive       := True
    Manager_lastReconnectTick   := 0
    Config_sessionReconnectGraceMs := 2000
    Manager_validateAliveMissed := ""

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

  FirstPass_Defers_NoPruneNoAffected()
  {
    ;; A window missing for the first time must not be pruned -- this is the
    ;; teardown blip the debounce rides out.
    Global Manager_managedWndIds
    result := Manager_validateAlive()
    Yunit.Assert(result = "", "first miss must defer (empty affected set), got '" . result . "'")
    Yunit.Assert(Manager_managedWndIds = "1001;1002;"
      , "first miss must leave the managed list intact, got '" . Manager_managedWndIds . "'")
  }

  DeadWindowsOnMultipleMonitors_ReturnsUnionOfMonitors_OnSecondPass()
  {
    first := Manager_validateAlive()
    Yunit.Assert(first = "", "first pass defers -> empty, got '" . first . "'")
    result := Manager_validateAlive()
    Yunit.Assert(InStr(result, ";1;"), "second pass affected set must include m1, got '" . result . "'")
    Yunit.Assert(InStr(result, ";2;"), "second pass affected set must include m2, got '" . result . "'")
  }

  DeadWindowsSameMonitor_MonitorListedOnce_OnSecondPass()
  {
    ;; Move 1002 to m1 so both dead windows share a monitor.
    Global Window_#1002_monitor, Window_#1002_tags, View_#2_#1_wndIds, View_#1_#1_wndIds
    Window_#1002_monitor := 1
    Window_#1002_tags    := 1
    View_#2_#1_wndIds    := ""
    View_#1_#1_wndIds    := "1002;"
    Manager_validateAlive()
    result := Manager_validateAlive()
    Yunit.Assert(result = ";1;", "single-monitor affected set must be ';1;', got '" . result . "'")
  }

  PrunesEntriesFromManagedList_OnSecondPass()
  {
    Global Manager_managedWndIds
    Manager_validateAlive()
    Yunit.Assert(Manager_managedWndIds = "1001;1002;"
      , "managed list must be intact after one pass, got '" . Manager_managedWndIds . "'")
    Manager_validateAlive()
    Yunit.Assert(Manager_managedWndIds = ""
      , "all twice-missed entries must be removed after the confirming pass, got '" . Manager_managedWndIds . "'")
  }

  ReappearedWindow_ClearsMark_IsNotPruned()
  {
    ;; 1001 blips out this pass (fake hwnd always fails WinExist), then is
    ;; "revived" by removing it from the managed list before the second
    ;; pass so the only remaining entry (1002) is the one that stays gone.
    ;; What this pins is that a mark set on the first pass is per-hwnd: 1002
    ;; still prunes on the confirming pass, independent of 1001. The pure
    ;; reappear-clears-mark path (existsNow True) is covered directly in
    ;; TestManagerValidateAliveDebounce.
    Global Manager_managedWndIds
    Manager_validateAlive()                 ;; both deferred
    Manager_managedWndIds := "1002;"        ;; 1001 no longer tracked
    result := Manager_validateAlive()       ;; 1002 second miss -> prune
    Yunit.Assert(InStr(result, ";2;"), "1002 must prune on its second miss, got '" . result . "'")
    Yunit.Assert(Manager_managedWndIds = "", "1002 removed from managed list, got '" . Manager_managedWndIds . "'")
  }

  SessionInactive_SuppressesPrune_AcrossBothPasses()
  {
    ;; While the session is inactive (disconnected/locked) the whole prune
    ;; is skipped -- the windows are transiently unfindable, not gone.
    Global Manager_sessionActive, Manager_managedWndIds
    Manager_sessionActive := False
    first := Manager_validateAlive()
    second := Manager_validateAlive()
    Yunit.Assert(first = "" And second = "", "inactive session must never prune, got '" . first . "' / '" . second . "'")
    Yunit.Assert(Manager_managedWndIds = "1001;1002;"
      , "inactive session must leave the managed list intact, got '" . Manager_managedWndIds . "'")
  }
}
