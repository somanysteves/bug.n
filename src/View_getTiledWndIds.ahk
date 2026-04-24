/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>

  View_getTiledWndIds lives in its own file so unit tests can swap it
  for a stub (tests/stubs_io.ahk) that derives the tiled list directly
  from View_#%m%_#%v%_wndIds without calling WinExist / Window_isHung
  — which would otherwise reject fake test window IDs. See
  tests/README.md for the stub-swap pattern.
*/

View_getTiledWndIds(m, v)
{
  Local n, tiledWndIds, wndIds

  n := 0
  tiledWndIds := ""
  StringTrimRight, wndIds, View_#%m%_#%v%_wndIds, 1
  Loop, PARSE, wndIds, `;
  {
    If A_LoopField And Not Window_#%A_LoopField%_isFloating And WinExist("ahk_id " A_LoopField) and Not Window_isHung(A_LoopField)
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
