/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>

  View_arrange lives in its own file so unit tests can swap it for a
  no-op stub (tests/stubs_io.ahk) without pulling in WinMove/WinActivate
  side effects. See tests/README.md for the stub-swap pattern.
*/

View_arrange(m, v, setLayout = False) {
  Local fn, h, l, w, x, y

  Perf_start("View_arrange")
  Debug_logMessage("DEBUG[1] View_arrange(" . m . ", " . v . ")", 1)

  l := View_#%m%_#%v%_layout_#1
  fn := Config_layoutFunction_#%l%
  If fn {
    x := Monitor_#%m%_x + View_#%m%_#%v%_layoutGapWidth + View_#%m%_#%v%_margin4
    y := Monitor_#%m%_y + View_#%m%_#%v%_layoutGapWidth + View_#%m%_#%v%_margin1
    w := Monitor_#%m%_width - 2 * View_#%m%_#%v%_layoutGapWidth - View_#%m%_#%v%_margin4 - View_#%m%_#%v%_margin2
    h := Monitor_#%m%_height - 2 * View_#%m%_#%v%_layoutGapWidth - View_#%m%_#%v%_margin1 - View_#%m%_#%v%_margin3

    ;; All window actions are performed on independent windows. A delay won't help.
    SetWinDelay, 0
    If Config_dynamicTiling Or setLayout {
      View_getTiledWndIds(m, v)
      If (fn = "monocle") {
        ;; 'View_getLayoutSymbol_monocle'
        View_#%m%_#%v%_layoutSymbol := "[" View_tiledWndId0 "]"
        ;; 'View_arrange_monocle'
        Tiler_stackTiles(0, 0, 1, View_tiledWndId0, +1, 3, x, y, w, h, 0)
      } Else    ;; (fn = "tile")
        Tiler_layoutTiles(m, v, x, y, w, h)
    } Else If (fn = "tile") {
      Tiler_layoutTiles(m, v, x, y, w, h, "blank")
      If Config_continuouslyTraceAreas
        View_traceAreas(True)
    }
    SetWinDelay, 10
  }
  Else    ;; floating layout (no 'View_arrange_', following is 'View_getLayoutSymbol_')'
    View_#%m%_#%v%_layoutSymbol := Config_layoutSymbol_#%l%

  Bar_updateLayout(m)
  Perf_end("View_arrange")
}
