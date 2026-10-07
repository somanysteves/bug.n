/*
  Tests for the two-pass debounce decision in Manager_validateAlive
  (src/Manager.ahk).

  Manager_validateAlive prunes managed HWNDs that fail WinExist. On an
  RDP/Citrix disconnect/reconnect the session desktop is torn down and
  rebuilt, and managed top-level windows transiently fail WinExist for a
  moment even though their HWNDs survive. A single-pass prune reads that
  blip as "window is dead" and silently orphans a live window
  (HANDOFF 2026-09-29 -- the primary, previously-unlogged reconnect-orphan
  path).

  The fix requires a managed HWND to fail WinExist on two *consecutive*
  validateAlive passes before it is pruned. The per-pass decision is
  factored into a pure function so it is Yunit-testable without a live
  WinEvent hook or a real disconnect:

    Manager_classifyAliveCheck(existsNow, missedBefore)
      "alive" -- WinExist succeeded this pass; clear any miss mark.
      "defer" -- first miss (not seen missing last pass); mark and wait.
      "prune" -- second consecutive miss; the window is really gone.
*/

class TestManagerValidateAliveDebounce
{
  Exists_NotMissedBefore_IsAlive()
  {
    Yunit.Assert(Manager_classifyAliveCheck(True, False) = "alive"
      , "existing window, never missed -> alive")
  }

  Exists_MissedBefore_IsAlive()
  {
    ;; A window that blipped out last pass but is back now must clear its
    ;; mark, not be pruned -- this is exactly the transient teardown blip
    ;; the debounce exists to ride out.
    Yunit.Assert(Manager_classifyAliveCheck(True, True) = "alive"
      , "window reappeared after one miss -> alive (mark cleared)")
  }

  Missing_FirstTime_Defers()
  {
    Yunit.Assert(Manager_classifyAliveCheck(False, False) = "defer"
      , "first WinExist miss must defer, not prune")
  }

  Missing_SecondConsecutive_Prunes()
  {
    Yunit.Assert(Manager_classifyAliveCheck(False, True) = "prune"
      , "second consecutive WinExist miss must prune")
  }
}
