/*
  Test helpers for seeding the window-management globals that src/View.ahk
  and src/Manager.ahk read from. Lets tests exercise View_shuffleWindow,
  View_activateWindow, etc. without real OS windows.

  Pair with tests/stubs_io.ahk, which stubs View_arrange,
  Manager_setCursor, and View_getTiledWndIds so OS side effects and
  filters don't fire.
*/

;; Set up a single-monitor, single-view tiled scenario.
;;   m            - monitor index (e.g. 1)
;;   v            - view index (e.g. 1)
;;   wndIds       - 1-indexed AHK array of fake window IDs in tiled order
ViewState_setupTiled(m, v, wndIds) {
  Local id, idList

  Manager_aMonitor         := m
  Monitor_#%m%_aView_#1    := v
  View_#%m%_#%v%_layout_#1 := 1
  Config_layoutFunction_#1 := "tile"

  idList := ""
  For _, id in wndIds {
    idList .= id . ";"
    Window_#%id%_isFloating := 0
  }
  View_#%m%_#%v%_wndIds := idList
}

;; Clear globals between tests.
ViewState_teardown(m, v, wndIds) {
  Local id

  View_#%m%_#%v%_wndIds := ""
  For _, id in wndIds
    Window_#%id%_isFloating := ""
  Test_viewArrangeCallCount      := 0
  Test_managerSetCursorCallCount := 0
}

;; Returns the current tiled order as a 1-indexed array of IDs.
ViewState_getOrderedWndIds(m, v) {
  Local s

  s := View_#%m%_#%v%_wndIds
  StringTrimRight, s, s, 1
  Return StrSplit(s, ";")
}

;; Parse a `<keyCombo>::View_shuffleWindow(i, d)` binding from
;; src/Config.ahk. Populates i and d ByRef. If the binding isn't found,
;; i and d are left empty — the caller's Yunit.Assert will catch it.
;;
;; Rationale: the J-wrap bug lives at the Config binding layer, not
;; inside View_shuffleWindow. Parsing the binding makes these tests
;; red-then-green with respect to the Config fix instead of
;; characterization-only.
ViewState_parseShuffleBinding(keyCombo, ByRef i, ByRef d) {
  Local configPath, contents, escapedKey, pattern, m

  configPath := A_ScriptDir . "\..\src\Config.ahk"
  FileRead, contents, %configPath%
  ;; Escape AHK hotkey modifiers (+, !, ^) for regex. `#` isn't special.
  escapedKey := RegExReplace(keyCombo, "([\+\!\^])", "\$1")
  pattern := "Om)^" . escapedKey . "::View_shuffleWindow\(\s*(.+?)\s*,\s*(.+?)\s*\)"
  If Not RegExMatch(contents, pattern, m) {
    i := ""
    d := ""
    Return
  }
  i := m.1 + 0
  d := m.2 + 0
}
