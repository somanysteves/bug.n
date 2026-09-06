/*
  Tests for the WTS session-teardown gate that stops bug.n from
  unmanaging managed windows during an RDP/Citrix disconnect/reconnect
  (or lock/unlock) burst of EVENT_OBJECT_HIDE events.

  Two pure decision functions carry the logic so the WM_WTSSESSION_CHANGE
  message path and the WinEvent HIDE path -- neither directly exercisable
  under Yunit -- don't need a live session to test:

    Manager_sessionStatusIsActive(status)
      Maps a WTS_* session-change code to True (session became active:
      unlock / remote-connect / console-connect), False (session became
      inactive: lock / remote-disconnect / console-disconnect), or ""
      (logon/logoff/unknown -- no state change).

    Manager_shouldSuppressHideUnmanage(sessionActive, msSinceReconnect, graceMs)
      True when a queued app-side HIDE should be treated as teardown churn
      and NOT unmanaged: session currently inactive, OR within graceMs of
      the last reconnect (the OS keeps firing HIDE up to several seconds
      past the reconnect -- see the 2026-09-03 log capture, unmanage burst
      trailed the display change by ~7s).
*/

class TestManagerSessionGate
{
  ;; ---- Manager_sessionStatusIsActive ----

  Status_Unlock_IsActive()
  {
    Yunit.Assert(Manager_sessionStatusIsActive(0x8) = True, "WTS_SESSION_UNLOCK must be active")
  }

  Status_RemoteConnect_IsActive()
  {
    Yunit.Assert(Manager_sessionStatusIsActive(0x3) = True, "WTS_REMOTE_CONNECT must be active")
  }

  Status_ConsoleConnect_IsActive()
  {
    Yunit.Assert(Manager_sessionStatusIsActive(0x1) = True, "WTS_CONSOLE_CONNECT must be active")
  }

  Status_Lock_IsInactive()
  {
    Yunit.Assert(Manager_sessionStatusIsActive(0x7) = False, "WTS_SESSION_LOCK must be inactive")
  }

  Status_RemoteDisconnect_IsInactive()
  {
    Yunit.Assert(Manager_sessionStatusIsActive(0x4) = False, "WTS_REMOTE_DISCONNECT must be inactive")
  }

  Status_ConsoleDisconnect_IsInactive()
  {
    Yunit.Assert(Manager_sessionStatusIsActive(0x2) = False, "WTS_CONSOLE_DISCONNECT must be inactive")
  }

  Status_Logon_NoChange()
  {
    ;; WTS_SESSION_LOGON (0x5) / LOGOFF (0x6): not a connect/lock transition,
    ;; so the gate leaves Manager_sessionActive untouched.
    Yunit.Assert(Manager_sessionStatusIsActive(0x5) = "", "WTS_SESSION_LOGON must be no-change")
    Yunit.Assert(Manager_sessionStatusIsActive(0x6) = "", "WTS_SESSION_LOGOFF must be no-change")
  }

  ;; ---- Manager_shouldSuppressHideUnmanage ----

  Inactive_Suppresses_RegardlessOfGrace()
  {
    ;; While locked/disconnected the reconnect clock is irrelevant.
    Yunit.Assert(Manager_shouldSuppressHideUnmanage(False, 999999, 2000) = True
      , "inactive session must suppress unmanage")
  }

  Active_WithinGrace_Suppresses()
  {
    Yunit.Assert(Manager_shouldSuppressHideUnmanage(True, 500, 2000) = True
      , "active but 500ms post-reconnect (< 2000 grace) must suppress")
  }

  Active_AtGraceBoundary_DoesNotSuppress()
  {
    ;; Boundary is exclusive: exactly graceMs elapsed -> grace over.
    Yunit.Assert(Manager_shouldSuppressHideUnmanage(True, 2000, 2000) = False
      , "at exactly graceMs the grace window is over, must not suppress")
  }

  Active_PastGrace_DoesNotSuppress()
  {
    ;; The normal steady-state case: a genuine palette dismissal must still
    ;; be unmanaged.
    Yunit.Assert(Manager_shouldSuppressHideUnmanage(True, 5000, 2000) = False
      , "active and well past grace must not suppress (genuine dismissal)")
  }

  Active_NeverReconnected_DoesNotSuppress()
  {
    ;; Manager_lastReconnectTick starts at 0, so msSinceReconnect is a huge
    ;; positive A_TickCount -- must read as "grace long over", not suppress.
    Yunit.Assert(Manager_shouldSuppressHideUnmanage(True, 123456789, 2000) = False
      , "never-reconnected (huge delta) must not suppress")
  }

  Active_NegativeDelta_DoesNotSuppress()
  {
    ;; A_TickCount 32-bit wraparound inside the grace window yields a
    ;; negative delta. Safe default: don't suppress (mirror
    ;; Manager_shouldResetDebouncedTimer's negative-delta handling).
    Yunit.Assert(Manager_shouldSuppressHideUnmanage(True, -50, 2000) = False
      , "negative (wrapped) delta must not suppress")
  }
}
