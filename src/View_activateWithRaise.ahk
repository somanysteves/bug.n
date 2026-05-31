/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>
*/

;; Force-raise wndId to the top of Z-order, then activate.
;; The AlwaysOnTop on/off flip is the workaround for Windows' focus-
;; stealing prevention: a bare WinActivate gives keyboard focus but
;; the OS may not repaint the Z-order against a same-position peer.
;; In monocle layout every tiled window sits at identical fullscreen
;; coords, so without the flip Win+J/K appears to "do nothing" (issue
;; #94). Returns Manager_winActivate's failure flag for callers that
;; want to advance to the next window when activation fails (hung
;; window detection in the cycle loop).
View_activateWithRaise(wndId) {
  Window_set(wndId, "AlwaysOnTop", "On")
  Window_set(wndId, "AlwaysOnTop", "Off")
  Return Manager_winActivate(wndId)
}
