/*
  Tests for src/View.ahk's View_shuffleWindow, exercised through the
  actual `#+j` / `#+k` bindings in src/Config.ahk via
  ViewState_parseShuffleBinding. If the Config binding is changed to
  pass different arguments, these tests automatically test the new
  binding — which is how the Win+Shift+J wrap-around regression is
  red-then-green tested against a Config.ahk typo rather than being
  a characterization of internal function behavior.
*/

class TestViewShuffleWindow
{
  ShuffleDown_FromTop_MovesToSecondPosition()
  {
    ;; 5 tiled windows, active = top. Win+Shift+J should step down one.
    Local wndIds, i, d, ordered
    wndIds := [1001, 1002, 1003, 1004, 1005]
    ViewState_setupTiled(1, 1, wndIds)
    ViewState_parseShuffleBinding("#+j", i, d)

    View_shuffleWindow(i, d, 1001)

    ordered := ViewState_getOrderedWndIds(1, 1)
    Yunit.Assert(ordered[2] = 1001
      , "Win+Shift+J from top should move active window to position 2; got "
      . ordered[1] . "," . ordered[2] . "," . ordered[3] . "," . ordered[4] . "," . ordered[5])

    ViewState_teardown(1, 1, wndIds)
  }

  ShuffleDown_FromBottom_WrapsToTop()
  {
    ;; 5 tiled windows, active = bottom. Win+Shift+J should wrap to position 1.
    Local wndIds, i, d, ordered
    wndIds := [1001, 1002, 1003, 1004, 1005]
    ViewState_setupTiled(1, 1, wndIds)
    ViewState_parseShuffleBinding("#+j", i, d)

    View_shuffleWindow(i, d, 1005)

    ordered := ViewState_getOrderedWndIds(1, 1)
    Yunit.Assert(ordered[1] = 1005
      , "Win+Shift+J from bottom should wrap active window to position 1; got "
      . ordered[1] . "," . ordered[2] . "," . ordered[3] . "," . ordered[4] . "," . ordered[5])

    ViewState_teardown(1, 1, wndIds)
  }

  ShuffleUp_FromTop_WrapsToBottom()
  {
    ;; 5 tiled windows, active = top. Win+Shift+K should wrap to position 5.
    ;; (Green before and after the J fix — sanity check that the harness works
    ;; for a case the existing code already handles correctly.)
    Local wndIds, i, d, ordered
    wndIds := [1001, 1002, 1003, 1004, 1005]
    ViewState_setupTiled(1, 1, wndIds)
    ViewState_parseShuffleBinding("#+k", i, d)

    View_shuffleWindow(i, d, 1001)

    ordered := ViewState_getOrderedWndIds(1, 1)
    Yunit.Assert(ordered[5] = 1001
      , "Win+Shift+K from top should wrap active window to position 5; got "
      . ordered[1] . "," . ordered[2] . "," . ordered[3] . "," . ordered[4] . "," . ordered[5])

    ViewState_teardown(1, 1, wndIds)
  }
}
