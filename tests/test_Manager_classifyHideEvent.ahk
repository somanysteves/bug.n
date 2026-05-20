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
    ;; Manager_isManaged uses numeric comparison so prefix collision
    ;; can't false-match even if the formats differ.
    Global Manager_pendingHideWndIds
    result := Manager_classifyHideEvent("0xa00c")
    Yunit.Assert(result = "ignore", "0xa00c (prefix of 0xa00c6) must classify as ignore, got '" . result . "'")
    Yunit.Assert(Manager_pendingHideWndIds = "", "queue should be untouched, got '" . Manager_pendingHideWndIds . "'")
  }

  ;; bug.n stores HWNDs in Manager_managedWndIds in whatever format
  ;; SetFormat, Integer was set to at insert time — hex on most code
  ;; paths, decimal on others (see Manager_isManaged comment block at
  ;; Manager.ahk:880-889). The HIDE-event callback receives hwnd as a
  ;; raw integer from the WinEventHook bridge. If the classifier does
  ;; a string InStr against Manager_managedWndIds without normalizing,
  ;; a decimal-stored entry will silently miss a hex-formatted input
  ;; (or vice-versa) — every HIDE event for that window would be
  ;; misclassified as 'ignore' and the ghost would persist.
  ;;
  ;; The next three tests use 0xa00c6 == 655558 (same numeric value,
  ;; different string formats) to lock both sides of the format
  ;; boundary down. Caught by Copilot review on PR #58.

  DecimalStored_HexInput_ClassifiesQueue()
  {
    Global Manager_managedWndIds, Manager_pendingHideWndIds, Window_#655558_expectedHide
    Manager_managedWndIds       := "655558;"
    Manager_pendingHideWndIds   := ""
    Window_#655558_expectedHide := False
    result := Manager_classifyHideEvent("0xa00c6")
    Yunit.Assert(result = "queue", "decimal-stored + hex input must classify as queue, got '" . result . "'")
    Yunit.Assert(Manager_pendingHideWndIds = "655558;", "queue must hold the canonical (decimal) stored key, got '" . Manager_pendingHideWndIds . "'")
  }

  HexStored_DecimalInput_ClassifiesQueue()
  {
    Global Manager_managedWndIds, Manager_pendingHideWndIds, Window_#0xa00c6_expectedHide
    Manager_managedWndIds        := "0xa00c6;"
    Manager_pendingHideWndIds    := ""
    Window_#0xa00c6_expectedHide := False
    result := Manager_classifyHideEvent(655558)
    Yunit.Assert(result = "queue", "hex-stored + decimal input must classify as queue, got '" . result . "'")
    Yunit.Assert(Manager_pendingHideWndIds = "0xa00c6;", "queue must hold the canonical (hex) stored key, got '" . Manager_pendingHideWndIds . "'")
  }

  HexStored_DecimalInput_ConsumesExpectedFlag()
  {
    ;; The expectedHide flag was set via Window_hideAsync's
    ;; Window_#%wndId%_expectedHide := True under the caller's format.
    ;; If the callback reads under a different format string, the flag
    ;; sticks around forever and the next genuine app-side hide gets
    ;; misclassified as 'expected' — letting a real ghost slip through.
    Global Manager_managedWndIds, Manager_pendingHideWndIds, Window_#0xa00c6_expectedHide
    Manager_managedWndIds        := "0xa00c6;"
    Manager_pendingHideWndIds    := ""
    Window_#0xa00c6_expectedHide := True
    result := Manager_classifyHideEvent(655558)
    Yunit.Assert(result = "expected", "expectedHide on hex-stored key must be consumed when input is decimal, got '" . result . "'")
    Yunit.Assert(Window_#0xa00c6_expectedHide = False, "flag on canonical hex key must be cleared")
    Yunit.Assert(Manager_pendingHideWndIds = "", "queue must be untouched on 'expected', got '" . Manager_pendingHideWndIds . "'")
  }
}
