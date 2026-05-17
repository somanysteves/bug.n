/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>

  View_activateWindow_now lives in its own file so tests can swap it
  for a stub (tests/stubs_io.ahk) without invoking the real WinGet /
  Window_set / Manager_winActivate chain. View_cycleDrainRearm shares
  the file so tests can observe re-arm decisions without actually
  arming an AHK timer that the test process won't wait for. See
  tests/README.md for the stub-swap pattern.
*/

;; Synchronous worker for the cycle path. Called either directly from
;; the d=0 absolute-index branch of View_activateWindow, or from the
;; View_cycleDrain label once per burst.
View_activateWindow_now(i, d) {
  Local aWndId, direction, failure, j, v, wndId, wndId0, wndIds

  Perf_start("View_activateWindow")
  WinGet, aWndId, ID, A
  Debug_logMessage("DEBUG[2] Active Windows ID: " . aWndId, 2, False)
  v := Monitor_#%Manager_aMonitor%_aView_#1
  Debug_logMessage("DEBUG[2] View (" . v . ") wndIds: " . View_#%Manager_aMonitor%_#%v%_wndIds, 2, False)
  StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%v%_wndIds, 1
  StringSplit, wndId, wndIds, `;
  Debug_logMessage("DEBUG[2] wndId count: " . wndId0, 2, False)
  If (i > 0) And (i <= wndId0) And (d = 0) {
    wndId := wndId%i%
    Window_set(wndId, "AlwaysOnTop", "On")
    Window_set(wndId, "AlwaysOnTop", "Off")
    Window_#%wndId%_isMinimized := False
    Manager_winActivate(wndId)
  } Else If (wndId0 > 1) {
    If Not InStr(Manager_managedWndIds, aWndId . ";") Or Window_#%aWndId%_isFloating
      Window_set(aWndId, "Bottom", "")
    Loop, % wndId0 {
      If (wndId%A_Index% = aWndId) {
        j := A_Index
        Break
      }
    }
    Debug_logMessage("DEBUG[2] Current wndId index: " . j, 2, False)

    If (d > 0)
      direction = 1
    Else
      direction = -1
    i := Manager_loop(j, d, 1, wndId0)
    Loop, % wndId0 {
      Debug_logMessage("DEBUG[2] Next wndId index: " . i, 2, False)
      wndId := wndId%i%
      If Not Window_#%wndId%_isMinimized {
        ;; If there are hung windows on the screen, we still want to be able to cycle through them.
        failure := Manager_winActivate(wndId)
        If Not failure
          Break
      }
      i := Manager_loop(i, direction, 1, wndId0)
    }
  }
  Perf_end("View_activateWindow")
}

;; Re-arm helper for the View_cycleDrain label, factored out so tests
;; can stub it (the test process exits before any 30ms timer would
;; fire, so production-real SetTimer would be unobservable in unit
;; tests).
View_cycleDrainRearm() {
  SetTimer, View_cycleDrain, -30
}
