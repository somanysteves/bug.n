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
    ;; A real (hidden) Gui HWND stands in for a window that blipped out on
    ;; the previous pass and is back now: seeded in the miss set, it must
    ;; take the existsNow path -- stay managed, mark cleared -- while the
    ;; fake 1002 alongside it is pruned on its second miss.
    Global Manager_managedWndIds, Manager_validateAliveMissed
    Gui, VAReappear:New, +HwndrealHwnd
    Gui, VAReappear:Show, Hide w10 h10
    Manager_managedWndIds       := realHwnd . ";1002;"
    Manager_validateAliveMissed := realHwnd . ";1002;"
    result := Manager_validateAlive()
    Gui, VAReappear:Destroy
    Yunit.Assert(Manager_managedWndIds = realHwnd . ";"
      , "reappeared hwnd must stay managed and 1002 be pruned, got '" . Manager_managedWndIds . "'")
    Yunit.Assert(Manager_validateAliveMissed = ""
      , "reappeared hwnd's miss mark must be cleared, got '" . Manager_validateAliveMissed . "'")
    Yunit.Assert(result = ";2;", "only 1002's monitor is affected, got '" . result . "'")
  }

  TimerPass_WithDeferredMiss_RearmsOnce_SettledPass_DoesNot()
  {
    ;; Manager_validateAliveTimer must re-arm itself while a miss is
    ;; deferred, or a dead window with no further shell churn is never
    ;; confirmed and pruned. Counted via Manager_armDebouncedTimer's
    ;; per-label arm counter; the real timer is cancelled after each pass.
    Global Bench_armCount_Manager_validateAliveTimer, Config_dynamicTiling
    Global Manager_validateInProgress, Manager_managedWndIds
    Config_dynamicTiling       := False
    Manager_validateInProgress := False
    ;; Seed: in AHK v1 "" + 0 is "", so an unset counter never increments.
    Bench_armCount_Manager_validateAliveTimer := 0
    before := 0
    Gosub, Manager_validateAliveTimer          ;; both fake hwnds defer
    SetTimer, Manager_validateAliveTimer, Off
    afterDefer := Bench_armCount_Manager_validateAliveTimer
    Gosub, Manager_validateAliveTimer          ;; confirming pass prunes both
    SetTimer, Manager_validateAliveTimer, Off
    afterPrune := Bench_armCount_Manager_validateAliveTimer
    Yunit.Assert(afterDefer - before = 1, "deferred miss must re-arm exactly once, got " . (afterDefer - before))
    Yunit.Assert(Manager_managedWndIds = "", "confirming pass must prune, got '" . Manager_managedWndIds . "'")
    Yunit.Assert(afterPrune = afterDefer, "settled pass must not re-arm, got " . (afterPrune - afterDefer))
  }

  Reconnect_ArmsPostGraceValidatePass()
  {
    ;; Suppressed passes forget their misses, so the reconnect itself must
    ;; schedule a pass for after the grace or a window that died while
    ;; disconnected is never pruned.
    Global Bench_armCount_Manager_validateAliveTimer, Config_dynamicTiling
    Global Manager_sessionActive
    Config_dynamicTiling  := False
    Manager_sessionActive := False
    Bench_armCount_Manager_validateAliveTimer := 0
    Manager_applySessionChange(0x8)            ;; WTS_SESSION_UNLOCK: no live lock query
    SetTimer, Manager_validateAliveTimer, Off
    Yunit.Assert(Bench_armCount_Manager_validateAliveTimer = 1
      , "reconnect must arm one validate pass, got " . Bench_armCount_Manager_validateAliveTimer)
  }

  TimerPass_SuppressedInGrace_RearmsForRemainingGrace()
  {
    ;; A shell event inside the grace can replace the post-grace arm with a
    ;; 200 ms one; that pass is suppressed, so it must re-arm itself.
    Global Bench_armCount_Manager_validateAliveTimer, Config_dynamicTiling
    Global Manager_validateInProgress, Manager_lastReconnectTick, Manager_managedWndIds
    Config_dynamicTiling       := False
    Manager_validateInProgress := False
    Manager_lastReconnectTick  := A_TickCount  ;; just reconnected, in grace
    Bench_armCount_Manager_validateAliveTimer := 0
    Gosub, Manager_validateAliveTimer
    SetTimer, Manager_validateAliveTimer, Off
    Yunit.Assert(Bench_armCount_Manager_validateAliveTimer = 1
      , "suppressed in-grace pass must re-arm once, got " . Bench_armCount_Manager_validateAliveTimer)
    Yunit.Assert(Manager_managedWndIds = "1001;1002;", "in-grace pass must not prune, got '" . Manager_managedWndIds . "'")
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
