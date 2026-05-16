/*
  Tests for Manager_barTitleAction (src/Manager.ahk).

  This is the pure function that classifies a shell event into one of
  three end-of-handler bar-title actions: "immediate", "defer", "skip".
  The actual side-effect dispatch (calling Bar_updateTitle, arming a
  one-shot SetTimer, or doing nothing) is wired in
  Manager_onShellMessage; pulling the decision into a pure function
  keeps the logic Yunit-coverable without having to stub SetTimer.

  Covers every wParam reachable at the dispatch point:
    1     HSHELL_WINDOWCREATED
    2     HSHELL_WINDOWDESTROYED
    4     HSHELL_WINDOWACTIVATED
    6     HSHELL_REDRAW                 (the gated case)
    32772 HSHELL_RUDEAPPACTIVATED
*/

class TestManagerBarTitleAction
{
  WindowCreatedReturnsImmediate()
  {
    Yunit.Assert(Manager_barTitleAction(1, 0x1234, 0x5678) = "immediate"
      , "HSHELL_WINDOWCREATED should always be immediate; got '"
      . Manager_barTitleAction(1, 0x1234, 0x5678) . "'")
  }

  WindowDestroyedReturnsImmediate()
  {
    Yunit.Assert(Manager_barTitleAction(2, 0x1234, 0x5678) = "immediate"
      , "HSHELL_WINDOWDESTROYED should always be immediate; got '"
      . Manager_barTitleAction(2, 0x1234, 0x5678) . "'")
  }

  WindowActivatedReturnsImmediate()
  {
    Yunit.Assert(Manager_barTitleAction(4, 0x1234, 0x5678) = "immediate"
      , "HSHELL_WINDOWACTIVATED should always be immediate; got '"
      . Manager_barTitleAction(4, 0x1234, 0x5678) . "'")
  }

  RudeAppActivatedReturnsImmediate()
  {
    Yunit.Assert(Manager_barTitleAction(32772, 0x1234, 0x5678) = "immediate"
      , "HSHELL_RUDEAPPACTIVATED should always be immediate; got '"
      . Manager_barTitleAction(32772, 0x1234, 0x5678) . "'")
  }

  ;; The two cases that matter for the perf win:

  RedrawOnActiveWindowReturnsDefer()
  {
    ;; lParam == activeWndId: the active window's own title changed.
    ;; Defer so a burst (streaming response) collapses into one update.
    Yunit.Assert(Manager_barTitleAction(6, 0x1234, 0x1234) = "defer"
      , "HSHELL_REDRAW on the active window should defer; got '"
      . Manager_barTitleAction(6, 0x1234, 0x1234) . "'")
  }

  RedrawOnBackgroundWindowReturnsSkip()
  {
    ;; lParam != activeWndId: some other window's title changed, the
    ;; bar's content is unaffected. Skip entirely.
    Yunit.Assert(Manager_barTitleAction(6, 0x1234, 0x5678) = "skip"
      , "HSHELL_REDRAW on a background window should skip; got '"
      . Manager_barTitleAction(6, 0x1234, 0x5678) . "'")
  }
}
