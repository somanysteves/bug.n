/*
  Tests for Manager_shouldReintegrateOnRestore (src/Manager.ahk).

  Decides whether an EVENT_OBJECT_SHOW arrival for a managed HWND
  should trigger the reverse-minimize reintegration sequence
  (un-float, prepend to _aWndIds, re-arrange) introduced for #96.

  Pure decision factored out of the SHOW branch so it has direct
  coverage without needing the WinEvent hook, a real window, or
  Window_isMinimized's WinGet call to fire.

  Three input axes:
    isManaged        — HWND is in Manager_managedWndIds.
    isUserMinimized  — Window_#X_isUserMinimized was set by
                       Manager_minimizeWindow (distinguishes our
                       float-as-minimize from a user-explicit
                       float toggle).
    isMinimized      — OS minimized state right now. We only want
                       to reintegrate after the OS has actually
                       restored the window (state went False).

  Truth table — only the "managed + we minimized it + now visible"
  cell returns True. Every other combination is left alone:
   - Unmanaged windows are never our problem.
   - !isUserMinimized covers user-floated and never-minimized cases —
     reintegrating either would surprise the user.
   - Still-minimized covers spurious SHOW events that arrive before
     the OS actually un-minimizes; the next SHOW after restore will
     match cleanly.
*/

class TestManagerShouldReintegrateOnRestore
{
  ManagedUserMinimizedRestored_True()
  {
    Yunit.Assert(Manager_shouldReintegrateOnRestore(True, True, False)
      , "managed + isUserMinimized + restored should reintegrate")
  }

  ManagedUserMinimizedStillMinimized_False()
  {
    Yunit.Assert(Not Manager_shouldReintegrateOnRestore(True, True, True)
      , "SHOW before OS actually restores should NOT reintegrate")
  }

  ManagedNotUserMinimizedRestored_False()
  {
    ;; The user explicitly floated this window; SHOW fires when they
    ;; refocus it. We must not auto-untile a window the user told us
    ;; to float.
    Yunit.Assert(Not Manager_shouldReintegrateOnRestore(True, False, False)
      , "managed but not isUserMinimized (e.g. user-floated) should NOT reintegrate")
  }

  ManagedNotUserMinimizedStillMinimized_False()
  {
    Yunit.Assert(Not Manager_shouldReintegrateOnRestore(True, False, True)
      , "managed, no flag, still minimized — nothing to do")
  }

  UnmanagedUserMinimizedRestored_False()
  {
    ;; Defensive: if Manager_unmanage cleared the HWND from
    ;; Manager_managedWndIds between minimize and restore, don't try
    ;; to re-add it. The next genuine adopt will pick it up.
    Yunit.Assert(Not Manager_shouldReintegrateOnRestore(False, True, False)
      , "unmanaged HWND must NOT be reintegrated even with stale flag")
  }

  UnmanagedNotUserMinimizedRestored_False()
  {
    Yunit.Assert(Not Manager_shouldReintegrateOnRestore(False, False, False)
      , "unmanaged + no flag — third-party SHOW; do nothing")
  }
}
