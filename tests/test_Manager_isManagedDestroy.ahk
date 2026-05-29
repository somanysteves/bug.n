/*
  Tests for Manager_isManagedDestroy (src/Manager.ahk).

  Pure decision for the EVENT_OBJECT_DESTROY branch of the WinEvent
  callback Manager_onWindowCreateOrShow. Returns truthy iff a window
  bug.n is managing was just destroyed, in which case the caller arms
  Manager_validateAliveTimer to prune it and re-tile.

  Regression (fixed on branch fix/destroy-backstop-ancestor-gate): the
  callback ran a GetAncestor(hwnd, GA_ROOT) == self "top-level" gate
  BEFORE the destroy branch. EVENT_OBJECT_DESTROY is delivered
  out-of-context, so by the time the callback runs the window is gone,
  GetAncestor returns 0, and the gate rejected every real destroy. With
  the legacy shell hook intermittently dropping HSHELL_WINDOWDESTROYED
  (#19), nothing re-tiled after closing a window. Managed-list
  membership is the authoritative guard for a gone window, so this
  predicate never consults GetAncestor.
*/

class TestManagerIsManagedDestroy
{
  Begin()
  {
    Global Manager_managedWndIds
    Manager_managedWndIds := "0xa00c6;0x6012a;"
  }

  ManagedWindowLevelDestroy_ReturnsTrue()
  {
    ;; The core fix: a managed, window-level (idObject=idChild=0) destroy
    ;; must be recognized even though top-level-ness can't be confirmed
    ;; via GetAncestor on a window that no longer exists.
    Yunit.Assert(Manager_isManagedDestroy(0x8001, 0, 0, "0xa00c6") = True
      , "managed window-level destroy must be recognized")
  }

  UnmanagedDestroy_ReturnsFalse()
  {
    Yunit.Assert(Manager_isManagedDestroy(0x8001, 0, 0, "0x99999") = False
      , "destroy of an unmanaged hwnd must not arm validateAlive")
  }

  ChildObjectDestroy_ReturnsFalse()
  {
    ;; idObject != 0 or idChild != 0 → a control/child destroy, not the
    ;; top-level window itself.
    Yunit.Assert(Manager_isManagedDestroy(0x8001, 1, 0, "0xa00c6") = False
      , "child-object destroy (idObject!=0) must be ignored")
    Yunit.Assert(Manager_isManagedDestroy(0x8001, 0, 1, "0xa00c6") = False
      , "child destroy (idChild!=0) must be ignored")
  }

  NonDestroyEvent_ReturnsFalse()
  {
    ;; CREATE / SHOW / HIDE on a managed hwnd must not be a destroy.
    Yunit.Assert(Manager_isManagedDestroy(0x8000, 0, 0, "0xa00c6") = False
      , "CREATE (0x8000) must not be a destroy")
    Yunit.Assert(Manager_isManagedDestroy(0x8002, 0, 0, "0xa00c6") = False
      , "SHOW (0x8002) must not be a destroy")
    Yunit.Assert(Manager_isManagedDestroy(0x8003, 0, 0, "0xa00c6") = False
      , "HIDE (0x8003) must not be a destroy")
  }

  FormatCanonicalization_MatchesAcrossHexAndDecimal()
  {
    ;; The hook delivers hwnd as a raw integer; the managed list may be
    ;; stored hex or decimal (see Manager_isManaged). Numeric comparison
    ;; must match regardless of format. 0xa00c6 == 655558.
    Global Manager_managedWndIds
    Manager_managedWndIds := "655558;"
    Yunit.Assert(Manager_isManagedDestroy(0x8001, 0, 0, "0xa00c6") = True
      , "decimal-stored + hex input must match")
    Yunit.Assert(Manager_isManagedDestroy(0x8001, 0, 0, 655558) = True
      , "decimal-stored + decimal input must match")
  }
}
