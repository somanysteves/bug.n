/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>

  Manager_setCursor lives in its own file so unit tests can swap it for
  a no-op stub (tests/stubs_io.ahk) without actually moving the OS
  cursor via DllCall("SetCursorPos"). See tests/README.md for the
  stub-swap pattern.
*/

Manager_setCursor(wndId) {
  Local wndHeight, wndWidth, wndX, wndY

  If Config_mouseFollowsFocus {
    If wndId {
      WinGetPos, wndX, wndY, wndWidth, wndHeight, ahk_id %wndId%
      DllCall("SetCursorPos", "Int", Round(wndX + wndWidth / 2), "Int", Round(wndY + wndHeight / 2))
    } Else
      DllCall("SetCursorPos", "Int", Round(Monitor_#%Manager_aMonitor%_x + Monitor_#%Manager_aMonitor%_width / 2), "Int", Round(Monitor_#%Manager_aMonitor%_y + Monitor_#%Manager_aMonitor%_height / 2))
  }
}
