/*
  Tests for Manager_classifyHideEvent (src/Manager.ahk).

  Decides what to do when EVENT_OBJECT_HIDE arrives:
    "expected" — bug.n hid the window itself (view switch); consume flag.
    "ignore"   — third-party window we never tracked; do nothing.
    "queue"    — owning app hid one of our managed windows; deferred
                 handler will unmanage it. Triggered by e.g. PowerToys
                 Command Palette dismissal (regression caught Q2 2026:
                 invisible ghost in view 3's master tile slot).
*/

class TestManagerClassifyHideEvent
{
  Begin()
  {
    Global Manager_managedWndIds, Manager_pendingHideWndIds
    Global Window_#0xa00c6_expectedHide, Window_#0x10362_expectedHide
    Manager_managedWndIds      := "0xa00c6;0x6012a;"
    Manager_pendingHideWndIds  := ""
    Window_#0xa00c6_expectedHide := False
    Window_#0x10362_expectedHide := False
  }

  ExpectedFlag_ReturnsExpected_ClearsFlag_NoQueueChange()
  {
    Global Manager_pendingHideWndIds, Window_#0xa00c6_expectedHide
    Window_#0xa00c6_expectedHide := True
    result := Manager_classifyHideEvent("0xa00c6")
    Yunit.Assert(result = "expected", "expected 'expected', got '" . result . "'")
    Yunit.Assert(Window_#0xa00c6_expectedHide = False, "flag should be cleared")
    Yunit.Assert(Manager_pendingHideWndIds = "", "queue should be untouched, got '" . Manager_pendingHideWndIds . "'")
  }

  UnmanagedHwnd_ReturnsIgnore_NoQueueChange()
  {
    Global Manager_pendingHideWndIds
    result := Manager_classifyHideEvent("0x10362")
    Yunit.Assert(result = "ignore", "expected 'ignore', got '" . result . "'")
    Yunit.Assert(Manager_pendingHideWndIds = "", "queue should be untouched, got '" . Manager_pendingHideWndIds . "'")
  }

  ManagedHwndNoFlag_ReturnsQueue_AppendsToQueue()
  {
    Global Manager_pendingHideWndIds
    result := Manager_classifyHideEvent("0xa00c6")
    Yunit.Assert(result = "queue", "expected 'queue', got '" . result . "'")
    Yunit.Assert(Manager_pendingHideWndIds = "0xa00c6;", "queue should contain 0xa00c6;, got '" . Manager_pendingHideWndIds . "'")
  }

  ManagedHwndNoFlag_Twice_AppendsBoth()
  {
    Global Manager_pendingHideWndIds
    Manager_classifyHideEvent("0xa00c6")
    Manager_classifyHideEvent("0x6012a")
    Yunit.Assert(Manager_pendingHideWndIds = "0xa00c6;0x6012a;", "queue should contain both, got '" . Manager_pendingHideWndIds . "'")
  }

  ;; The regression in PR #57: PowerToys Command Palette has WinUI class,
  ;; gets briefly shown (SHOW event -> Manager_manage), then PT hides it
  ;; with no bug.n involvement -> HIDE event arrives with no expectedHide
  ;; flag set -> we must queue an unmanage, else the ghost stays tagged
  ;; for the active view and Tiler_layoutTiles allocates it a tile slot.
  PrefixCollision_AvoidsFalseMatch()
  {
    ;; Manager_managedWndIds = "0xa00c6;..." — 0xa00c shares a prefix.
    ;; InStr must look for "0xa00c;" (with trailing ';') not just "0xa00c"
    ;; to avoid mis-classifying an unmanaged hwnd as managed.
    Global Manager_pendingHideWndIds
    result := Manager_classifyHideEvent("0xa00c")
    Yunit.Assert(result = "ignore", "0xa00c (prefix of 0xa00c6) must classify as ignore, got '" . result . "'")
    Yunit.Assert(Manager_pendingHideWndIds = "", "queue should be untouched, got '" . Manager_pendingHideWndIds . "'")
  }
}
