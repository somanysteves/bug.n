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

;; Returns the currently-active OS window's ID. Thin wrapper around
;; `WinGet, <var>, ID, A` so callers can accept an injected active
;; window ID (useful for unit tests that don't have a real OS focus).
Window_getActiveId() {
  Local aWndId
  WinGet, aWndId, ID, A
  Return, aWndId
}

Window_activate(wndId) {
  Perf_start("Window_activate")
  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_activate: Potentially hung window " . wndId, 2)
    Perf_end("Window_activate")
    Return, 1
  } Else {
    Perf_start("Window_activate_winActivate")
    WinActivate, ahk_id %wndId%
    Perf_end("Window_activate_winActivate")
    Perf_start("Window_activate_winGetA")
    WinGet, aWndId, ID, A
    Perf_end("Window_activate_winGetA")
    Perf_end("Window_activate")
    If (wndId != aWndId)
      Return, 1
    Else
      Return, 0
  }
}

Window_close(wndId) {
  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_close: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    WinClose, ahk_id %wndId%
    Return, 0
  }
}

;; Given a ghost window, try to find its body. This is only known to work on Windows 7
Window_findHung(ghostWndId) {
  Global Config_ghostWndSubString

  WinGetTitle, ghostWndTitle, ahk_id %ghostWndId%
  StringReplace, ghostWndTitle, ghostWndTitle, %Config_ghostWndSubString%,
  WinGetPos, ghostWndX, ghostWndY, ghostWndW, ghostWndH, ahk_id %ghostWndId%

  SetTitleMatchMode, 2
  WinGet, wndId, List, %ghostWndTitle%
  Loop, % wndId {
    If (wndId%A_Index% = ghostWndId)
      Continue
    WinGetPos, wndX, wndY, wndW, wndH, % "ahk_id" wndId%A_Index%
    If (wndX = ghostWndX) And (wndY = ghostWndY) And (wndW = ghostWndW) And (wndH = ghostWndH)
      Return, wndId%A_Index%
  }
  Return, 0
}

;; Window_getHidden lives in src/Window_getHidden.ahk so tests can stub it out.
;; See tests/README.md for the stub-swap pattern.

;; Returns the window's DWM extended frame bounds (visible rect) in
;; X/Y/Width/Height, plus per-side invisible-border offsets.
;;
;; Win10/11 windows in non-maximized state have asymmetric invisible
;; borders: top = 0 (resize handle lives inside the title bar) while
;; left/right/bottom ≈ 8 px (drop shadow / resize handle outside the
;; visible frame). When maximized, top also gains the ~8 px offset.
;; A single symmetric "average" offset can't compensate for top != bottom
;; correctly -- it lands a stack tile (top_off + bottom_off) / 2 px off
;; in Y. See test_Window_correctedSendCoords for the math.
;;
;; Per-side offsets (Top_Offset, Right_Offset, Bottom_Offset, Left_Offset)
;; are defined so that:
;;   gwr_left   = dwm_left   - Left_Offset
;;   gwr_top    = dwm_top    - Top_Offset
;;   gwr_right  = dwm_right  + Right_Offset
;;   gwr_bottom = dwm_bottom + Bottom_Offset
;; i.e. each side's offset is the (non-negative for shadowed windows)
;; thickness of the invisible border on that side, measured outward from
;; the visible DWM rect.
;;
;; Offset_X / Offset_Y retain their original (Width - GWR_Width) // 2 /
;; (Height - GWR_Height) // 2 definitions. They're no longer consumed
;; inside bug.n -- the tiler's in-place skip check now compares the
;; visible rect (X/Y/Width/Height) directly to the target, and the
;; correction math (Window_correctedSendCoords, Window_moveAsync) uses
;; the per-side offsets exclusively. The symmetric values stay in the
;; signature only because Window_getPosEx is a vendored utility whose
;; ByRef contract is exported.
Window_getPosEx(hWindow, ByRef X = "", ByRef Y = "", ByRef Width = "", ByRef Height = ""
    , ByRef Offset_X = "", ByRef Offset_Y = ""
    , ByRef Top_Offset = "", ByRef Right_Offset = "", ByRef Bottom_Offset = "", ByRef Left_Offset = "") {
  Static Dummy5693, RECTPlus, S_OK := 0x0, DWMWA_EXTENDED_FRAME_BOUNDS := 9

  ;-- Workaround for AutoHotkey Basic
  PtrType := (A_PtrSize=8) ? "Ptr" : "UInt"

  ;-- Get the window's dimensions
  ;   Note: Only the first 16 bytes of the RECTPlus structure are used by the
  ;   DwmGetWindowAttribute and GetWindowRect functions.
  VarSetCapacity(RECTPlus, 24,0)
  DWMRC := DllCall("dwmapi\DwmGetWindowAttribute"
      ,PtrType,hWindow                                ;-- hwnd
      ,"UInt",DWMWA_EXTENDED_FRAME_BOUNDS             ;-- dwAttribute
      ,PtrType,&RECTPlus                              ;-- pvAttribute
      ,"UInt",16)                                     ;-- cbAttribute

  If (DWMRC <> S_OK) {
    If ErrorLevel in -3, -4   ;-- Dll or function not found (older than Vista)
    {
      ;-- Do nothing else (for now)
    } Else
      outputdebug,
        (LTrim Join`s
         Function: %A_ThisFunc% -
         Unknown error calling "dwmapi\DwmGetWindowAttribute".
         RC = %DWMRC%,
         ErrorLevel = %ErrorLevel%,
         A_LastError = %A_LastError%.
         "GetWindowRect" used instead.
        )

    ;-- Collect the position and size from "GetWindowRect"
    DllCall("GetWindowRect", PtrType, hWindow, PtrType, &RECTPlus)
  }

  ;-- Populate the output variables
  X := Left :=NumGet(RECTPlus, 0, "Int")
  Y := Top  :=NumGet(RECTPlus, 4, "Int")
  Right     :=NumGet(RECTPlus, 8, "Int")
  Bottom    :=NumGet(RECTPlus, 12, "Int")
  Width     :=Right-Left
  Height    :=Bottom-Top
  Offset_X       := 0
  Offset_Y       := 0
  Top_Offset     := 0
  Right_Offset   := 0
  Bottom_Offset  := 0
  Left_Offset    := 0

  ;-- If DWM is not used (older than Vista or DWM not enabled), we're done
  If (DWMRC <> S_OK)
    Return &RECTPlus

  ;-- Collect dimensions via GetWindowRect
  VarSetCapacity(RECT, 16, 0)
  DllCall("GetWindowRect", PtrType, hWindow, PtrType, &RECT)
  GWR_Left   := NumGet(RECT, 0, "Int")
  GWR_Top    := NumGet(RECT, 4, "Int")
  GWR_Right  := NumGet(RECT, 8, "Int")
  GWR_Bottom := NumGet(RECT, 12, "Int")
  GWR_Width  := GWR_Right  - GWR_Left
  GWR_Height := GWR_Bottom - GWR_Top

  ;-- Per-side offsets (each is the invisible-border thickness on that
  ;-- side, measured outward from the DWM visible rect). Non-negative for
  ;-- typical shadowed windows.
  Left_Offset   := Left   - GWR_Left
  Top_Offset    := Top    - GWR_Top
  Right_Offset  := GWR_Right  - Right
  Bottom_Offset := GWR_Bottom - Bottom

  ;-- Symmetric averages, retained for legacy callers (in-place skip check).
  NumPut(Offset_X := (Width  - GWR_Width)  // 2, RECTPlus, 16, "Int")
  NumPut(Offset_Y := (Height - GWR_Height) // 2, RECTPlus, 20, "Int")
  Return &RECTPlus
}
;; unknown: WinGetPosEx (https://autohotkey.com/boards/viewtopic.php?t=3392; 2016-01-18: retrieved "Error 404 - File not found")

;; Set Window_#%wndId%_expectedHide=True so the EVENT_OBJECT_HIDE callback
;; (Manager_onWindowCreateOrShow) can tell our hide apart from an app-side
;; one. Only set when the window was actually visible — a no-op hide on an
;; already-hidden window (e.g. PowerToys Command Palette while dismissed)
;; produces no HIDE event, and leaving the flag stale would cause the next
;; genuine app-side hide to be misattributed to us.
;;
;; Early-return on already-hidden windows: SW_HIDE / WinHide on an
;; invisible window is a no-op, so we skip the cross-process round-trip.
;; The view-switch hide loop iterates every wndId in the leaving view;
;; with a dozen managed windows + app-side-hidden ghosts (Cmd Palette,
;; etc.) the saved syscalls add up.
Window_hide(wndId) {
  Global
  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_hide: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    If Not DllCall("IsWindowVisible", "Ptr", wndId)
      Return, 0
    Window_#%wndId%_expectedHide := True
    WinHide, ahk_id %wndId%
    Return, 0
  }
}

;; Fire-and-forget hide via ShowWindowAsync. Unlike Window_hide (WinHide
;; → SendMessage(WM_SHOWWINDOW), blocking on the window proc), this
;; posts the message and returns immediately. Used by
;; Monitor_activateView's hide loop where per-window blocking
;; accumulates into the user-visible "blank desktop" gap. Safe on hung
;; windows — ShowWindowAsync queues the message rather than waiting on
;; the proc, so we skip the Window_isHung check.
;;
;; expectedHide tracking and early-return — see Window_hide.
Window_hideAsync(wndId) {
  Global
  If Not DllCall("IsWindowVisible", "Ptr", wndId)
    Return 0
  Window_#%wndId%_expectedHide := True
  Return DllCall("ShowWindowAsync", "Ptr", wndId, "Int", 0) ? 0 : 1    ;; SW_HIDE = 0
}

Window_isChild(wndId) {
  WS_CHILD = 0x40000000
  WinGet, wndStyle, Style, ahk_id %wndId%

  Return, wndStyle & WS_CHILD
}

Window_isElevated(wndId) {
  WinGetTitle, wndTitle, ahk_id %wndId%
  WinSetTitle, ahk_id %wndId%, , % wndTitle " "
  WinGetTitle, newWndTitle, ahk_id %wndId%
  WinSetTitle, ahk_id %wndId%, , % wndTitle
  Return, (newWndTitle = wndTitle)
}

Window_isGhost(wndId) {
  Local wndClass, wndProc

  WinGet, wndProc, ProcessName, ahk_id %wndId%
  WinGetClass, wndClass, ahk_id %wndId%
  If (wndProc = "dwm.exe") And (wndClass = "Ghost")
    Return, 1
  Else
    Return, 0
}

;; 0 - Not hung
;; 1 - Hung
Window_isHung(wndId) {
  ;; IsHungAppWindow queries the OS kernel flag directly — no message sent,
  ;; never blocks. Returns true only for windows that have been unresponsive
  ;; for >5 seconds (the Windows ghost threshold), so it never produces the
  ;; false positives that a short SendMessage timeout does for windows that
  ;; are merely slow (e.g. resuming from sleep or mid-ShowWindowAsync).
  If Not wndId
    Return 0
  Return DllCall("IsHungAppWindow", "Ptr", wndId, "Int")
}

;; Non-blocking title fetch: SendMessageTimeout with SMTO_ABORTIFHUNG and a
;; 200 ms cap. AHK's WinGetTitle (GetWindowText -> SendMessage, no timeout)
;; can stall the AHK thread for seconds when the target window's proc is
;; slow to service WM_GETTEXT -- the pathology behind keyboard hangs when
;; clicking into Edge/Slack under load. Returns "" on timeout, hung window,
;; or null HWND. 4096-WCHAR buffer (8192 bytes) gives ample headroom for
;; long titles. Not used in Manager_applyRules: rule result is sticky per-HWND,
;; so timeout-as-empty would permanently mismatch title rules (#45).
Window_getTitleNonBlocking(wndId) {
  Local title, result
  If Not wndId
    Return ""
  VarSetCapacity(title, 8192)
  result := DllCall("SendMessageTimeout", "Ptr", wndId, "UInt", 0x000D
      , "UPtr", 4095, "Ptr", &title, "UInt", 0x0002, "UInt", 200, "UPtr*", 0)
  If Not result
    Return ""
  VarSetCapacity(title, -1)
  Return title
}

Window_isNotVisible(wndId) {
  WS_VISIBLE = 0x10000000
  WinGet, wndStyle, Style, ahk_id %wndId%
  If (wndStyle & WS_VISIBLE) {
    WinGetPos, wndX, wndY, wndW, wndH, ahk_id %wndId%
    hasDimensions := wndW And wndH
    isOnMonitor := Monitor_get(wndX + 5, wndY + 5) Or Monitor_get(wndX + wndW - 5, wndY + 5) Or Monitor_get(wndX + wndW, wndY + wndH - 5) Or Monitor_get(wndX + 5, wndY + wndH - 5)
    Return, (Not hasDimensions Or Not isOnMonitor)
  } Else
    Return, True
}

Window_isPopup(wndId) {
  WS_POPUP = 0x80000000
  WinGet, wndStyle, Style, ahk_id %wndId%

  Return, wndStyle & WS_POPUP
}

Window_isProg(wndId) {
  Local wndClass, wndTitle
  WinGetClass, wndClass, ahk_id %wndId%
  If (wndClass = "Progman") Or (wndClass = "WorkerW") Or (wndClass = "DesktopBackgroundClass")
    Return, 0
  If (wndClass = "AutoHotkeyGui") {
    wndTitle := Window_getTitleNonBlocking(wndId)
    If (SubStr(wndTitle, 1, 10) = "bug.n_BAR_")
      Return, 0
  }
  Return, wndId
}

Window_maximize(wndId) {
  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_maximize: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    WinMaximize, ahk_id %wndId%
    Return, 0
  }
}

Window_minimize(wndId) {
  Global

  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_minimize: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    WinMinimize, ahk_id %wndId%
    Window_#%wndId%_isMinimized := True
    Return, 0
  }
}

Window_move(wndId, x, y, width, height) {
  Local wndClass, wndMinMax, WM_ENTERSIZEMOVE, WM_EXITSIZEMOVE
  Local wndH, wndW, wndX, wndY
  
  ;; Check, if the window has already the given position and size and no action is required.
  If Not wndId Or Window_getPosEx(wndId, wndX, wndY, wndW, wndH) And (Abs(wndX - x) < 2 And Abs(wndY - y) < 2 And Abs(wndW - width) < 2 And Abs(wndH - height) < 2)
    Return, 0

  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_move: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    WinGet, wndMinMax, MinMax, ahk_id %wndId%
    If (wndMinMax = -1 And Not Window_#%wndId%_isMinimized)
      WinRestore, ahk_id %wndId%
  }

  WM_ENTERSIZEMOVE = 0x0231
  WM_EXITSIZEMOVE  = 0x0232
  If ErrorLevel {
    Debug_logMessage("DEBUG[2] Window_move: Potentially hung window " . wndId, 1)
    Return, 1
  } Else {
    SendMessage, WM_ENTERSIZEMOVE, , , , ahk_id %wndId%
    WinMove, ahk_id %wndId%, , %x%, %y%, %width%, %height%
    
    WinGetClass, wndClass, ahk_id %wndId%
    If (wndClass == "mintty") {
      Sleep, % Config_shellMsgDelay
    }
    ;If Not (wndMinMax = 1) Or Not Window_#%wndId%_isDecorated Or Manager_windowNotMaximized(width, height) {
    If (mmngr2 == "") {
      If Window_getPosEx(wndId, wndX, wndY, wndW, wndH) And (Abs(wndX - x) > 1 Or Abs(wndY - y) > 1 Or Abs(wndW - width) > 1 Or Abs(wndH - height) > 1) {
        x -= wndX - x
        y -= wndY - y
        width  += width - wndW - 1
        height += height - wndH - 1
        WinMove, ahk_id %wndId%, , %x%, %y%, %width%, %height%
      }
    }
    
    SendMessage, WM_EXITSIZEMOVE, , , , ahk_id %wndId%
    Return, 0
  }
}

;; Feedforward DWM-frame correction. Per-side offsets from Window_getPosEx
;; are the invisible-border thickness on each side, measured outward from
;; the visible DWM rect (non-negative for typical Win10/11 shadowed
;; windows). To land the visible rect at (tileX, tileY, tileW, tileH),
;; SetWindowPos receives a GWR shifted out by each side's offset and
;; grown by (left + right) horizontally and (top + bottom) vertically.
;;
;; Per-side rather than a single symmetric offset: Win10/11 non-maximized
;; windows have top = 0 and left/right/bottom ≈ 8 px, so a symmetric
;; average ((0 + 8)/2 = 4) shifts every stack tile 4 px above its target.
;; #41 caught this; see test_Window_correctedSendCoords for the math.
Window_correctedSendCoords(tileX, tileY, tileW, tileH
    , topOffset, rightOffset, bottomOffset, leftOffset
    , ByRef sendX, ByRef sendY, ByRef sendW, ByRef sendH) {
  sendX := tileX - leftOffset
  sendY := tileY - topOffset
  sendW := tileW + leftOffset + rightOffset
  sendH := tileH + topOffset  + bottomOffset
}

;; Async move with feedforward DWM-frame correction. Doesn't block.
Window_moveAsync(wndId, x, y, width, height) {
  Local wndX, wndY, wndW, wndH, offsetX, offsetY
  Local topOff, rightOff, bottomOff, leftOff
  Local sendX, sendY, sendW, sendH, SWP_FLAGS, result
  If Not wndId
    Return 1
  Perf_start("Window_moveAsync")
  Window_getPosEx(wndId, wndX, wndY, wndW, wndH, offsetX, offsetY, topOff, rightOff, bottomOff, leftOff)
  Window_correctedSendCoords(x, y, width, height, topOff, rightOff, bottomOff, leftOff, sendX, sendY, sendW, sendH)
  SWP_FLAGS := 0x4000 | 0x0004 | 0x0010 | 0x0200    ;; ASYNCWINDOWPOS | NOZORDER | NOACTIVATE | NOOWNERZORDER
  result := DllCall("SetWindowPos", "Ptr", wndId, "Ptr", 0
      , "Int", sendX, "Int", sendY, "Int", sendW, "Int", sendH
      , "UInt", SWP_FLAGS) ? 0 : 1
  Perf_end("Window_moveAsync")
  Return result
}

Window_restore(wndId = 0) {
  If (wndId = 0)
    WinGet, wndId, ID, A

  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_restore: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    WinRestore, ahk_id %wndId%
    Return, 0
  }
}

Window_set(wndId, type, value) {
  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_set: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    WinSet, %type%, %value%, ahk_id %wndId%
    Return, 0
  }
}

Window_show(wndId) {
  If Window_isHung(wndId) {
    Debug_logMessage("DEBUG[2] Window_show: Potentially hung window " . wndId, 2)
    Return, 1
  } Else {
    WinShow, ahk_id %wndId%
    Return, 0
  }
}

;; Fire-and-forget show counterpart. SW_SHOWNA matches WinShow's
;; ShowWindow(SW_SHOWNOACTIVATE) — no per-window focus grab as the
;; loop iterates; Manager_winActivate sets focus once after.
Window_showAsync(wndId) {
  Return DllCall("ShowWindowAsync", "Ptr", wndId, "Int", 8) ? 0 : 1    ;; SW_SHOWNA = 8
}

Window_toggleDecor(wndId = 0) {
  Global

  If (wndId = 0)
    WinGet, wndId, ID, A

  Window_#%wndId%_isDecorated := Not Window_#%wndId%_isDecorated
  If Window_#%wndId%_isDecorated
    Window_set(wndId, "Style", "+0xC00000")
  Else
    Window_set(wndId, "Style", "-0xC00000")
}
