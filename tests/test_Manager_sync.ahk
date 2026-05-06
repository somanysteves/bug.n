/*
  Tests for Manager_syncShouldReportActive in src/Manager.ahk.

  Pins the gate that decides whether Manager_sync's "already managed
  but reactivated" branch reports a window via its ByRef wndIds out
  param. The gate fires only when the window is the currently active
  window AND not hung — matches the loop's intent ("brought into
  focus by something") rather than firing for every already-managed
  window on every sync.

  Manager_sync itself calls WinGet which can't be stubbed under the
  Yunit harness; the helper exists so this gate has direct coverage.
*/

class TestManagerSync
{
  ActiveAndNotHung_Reports()
  {
    Yunit.Assert(Manager_syncShouldReportActive(123, 123, False)
      , "active + not hung should be reported")
  }

  ActiveButHung_DoesNotReport()
  {
    Yunit.Assert(Not Manager_syncShouldReportActive(123, 123, True)
      , "active but hung should NOT be reported (existing isHung guard)")
  }

  NotActiveAndNotHung_DoesNotReport()
  {
    Yunit.Assert(Not Manager_syncShouldReportActive(123, 999, False)
      , "non-active should NOT be reported, even when not hung")
  }

  NotActiveAndHung_DoesNotReport()
  {
    Yunit.Assert(Not Manager_syncShouldReportActive(123, 999, True)
      , "non-active and hung should NOT be reported")
  }
}
