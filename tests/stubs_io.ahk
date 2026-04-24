/*
  Test-only stub replacements for IO-heavy src/ symbols that would
  otherwise reach out to the OS (moving real windows, moving the mouse
  cursor, etc.). Loaded by tests/run.ahk *instead of* the real
  src/View_arrange.ahk and src/Manager_setCursor.ahk — the real files
  must not be #Included by the test runner or AHK will error on
  duplicate definitions.

  Tests that want to assert "did the code path attempt to arrange?"
  can inspect the Test_* counters below.
*/

Test_viewArrangeCallCount      := 0
Test_viewArrangeLastMonitor    := 0
Test_viewArrangeLastView       := 0
Test_viewArrangeLastSetLayout  := False

Test_managerSetCursorCallCount := 0
Test_managerSetCursorLastWndId := 0

View_arrange(m, v, setLayout = False) {
  Global Test_viewArrangeCallCount, Test_viewArrangeLastMonitor
  Global Test_viewArrangeLastView, Test_viewArrangeLastSetLayout
  Test_viewArrangeCallCount     += 1
  Test_viewArrangeLastMonitor   := m
  Test_viewArrangeLastView      := v
  Test_viewArrangeLastSetLayout := setLayout
}

Manager_setCursor(wndId) {
  Global Test_managerSetCursorCallCount, Test_managerSetCursorLastWndId
  Test_managerSetCursorCallCount += 1
  Test_managerSetCursorLastWndId := wndId
}

;; Test-only replacement for View_getTiledWndIds. The production
;; version (src/View_getTiledWndIds.ahk) filters the view's wndIds
;; list with WinExist + Window_isHung, which rejects fake test window
;; IDs. This stub trusts the list wholesale — tests are responsible
;; for populating View_#%m%_#%v%_wndIds with only the IDs they want
;; treated as tiled, and for setting Window_#%id%_isFloating if that
;; matters to the scenario (default: not floating).
View_getTiledWndIds(m, v)
{
  Local n, tiledWndIds, wndIds

  n := 0
  tiledWndIds := ""
  StringTrimRight, wndIds, View_#%m%_#%v%_wndIds, 1
  Loop, PARSE, wndIds, `;
  {
    If A_LoopField And Not Window_#%A_LoopField%_isFloating
    {
      n += 1
      tiledWndIds .= A_LoopField ";"
    }
  }
  View_tiledWndIds := tiledWndIds
  StringTrimRight, tiledWndIds, tiledWndIds, 1
  StringSplit, View_tiledWndId, tiledWndIds, `;

  Return, n
}
