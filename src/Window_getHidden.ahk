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
  a controllable stub (tests/stubs_io.ahk). Returns truthy for any
  SW_HIDDEN top-level window — which is every window that bug.n itself
  has hidden because it lives on a non-active view. The HSHELL_FLASH
  dispatch in Manager_onShellMessage runs *before* this function's
  early-return so flashes from those windows still mark their view
  urgent; the stub lets tests verify that ordering invariant.

  Class-first short-circuit: WinGetClass without DetectHiddenWindows
  returns a non-empty class for any visible top-level window, so a
  populated class alone proves visibility -- no title fetch needed on
  the fast path. The slow path (class empty without DHW) re-queries
  with DHW and uses Window_getTitleNonBlocking, preserving the hang
  protection that motivated this function in the first place.

  ByRef wndTitle is empty when the function short-circuits on a
  visible window. Callers that need the title for visible windows
  must fetch it themselves (see Manager_getWindowInfo).

  See tests/README.md for the stub-swap pattern.
*/

Window_getHidden(wndId, ByRef wndClass, ByRef wndTitle) {
  wndTitle := ""
  WinGetClass, wndClass, ahk_id %wndId%
  If wndClass
    Return, False
  detectHiddenWnds := A_DetectHiddenWindows
  DetectHiddenWindows, On
  WinGetClass, wndClass, ahk_id %wndId%
  DetectHiddenWindows, %detectHiddenWnds%
  ;; Title: raw SendMessageTimeout works on hidden windows without DetectHiddenWindows.
  wndTitle := Window_getTitleNonBlocking(wndId)
  ;; If wndClass Or wndTitle now (but wndClass was empty before DHW), wnd is hidden.
  Return, (wndClass Or wndTitle)
}
