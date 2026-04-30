/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>

  Window_getHidden lives in its own file so unit tests can swap it for
  a controllable stub (tests/stubs_io.ahk). The real implementation
  reaches out to the OS twice per call (WinGetClass / WinGetTitle, with
  a DetectHiddenWindows toggle in between) and returns truthy for any
  SW_HIDDEN top-level window — which is every window that bug.n itself
  has hidden because it lives on a non-active view. The HSHELL_FLASH
  dispatch in Manager_onShellMessage runs *before* this function's
  early-return so flashes from those windows still mark their view
  urgent; the stub lets tests verify that ordering invariant.

  See tests/README.md for the stub-swap pattern.
*/

Window_getHidden(wndId, ByRef wndClass, ByRef wndTitle) {
  WinGetClass, wndClass, ahk_id %wndId%
  WinGetTitle, wndTitle, ahk_id %wndId%
  If Not wndClass And Not wndTitle {
    detectHiddenWnds := A_DetectHiddenWindows
    DetectHiddenWindows, On
    WinGetClass, wndClass, ahk_id %wndId%
    WinGetTitle, wndTitle, ahk_id %wndId%
    DetectHiddenWindows, %detectHiddenWnds%
    ;; If now wndClass Or wndTitle, but Not wndClass And Not wndTitle before, wnd is hidden.
    Return, (wndClass Or wndTitle)
  } Else
    Return, False
}
