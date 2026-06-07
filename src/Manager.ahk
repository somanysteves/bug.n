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

Manager_init()
{
  Local doRestore

  Manager_setWindowBorders()
  Bar_getHeight()
  ; axes, dimensions, percentage, flipped, gapWidth
  Manager_layoutDirty := 0
  ; New/closed windows, active changed,
  Manager_windowsDirty := 0
  Manager_aMonitor := 1
  View_tiledWndId0 := 0

  doRestore := 0
  If (Config_autoSaveSession = "ask")
  {
    MsgBox, % (0x4 | 0x1000), , Would you like to restore an auto-saved session?
    IfMsgBox Yes
      doRestore := 1
  }
  Else If (Config_autoSaveSession = "auto")
  {
    doRestore := 1
  }

  mmngr1 := New MonitorManager()
  mmngr2 := ""
  SysGet, Manager_monitorCount, MonitorCount
  Debug_logMessage("DEBUG[0] Manager_init: Found " . Manager_monitorCount . " monitor" . (Manager_monitorCount != 1 ? "s" . "") . ".", 0)
  Loop, % Manager_monitorCount
  {
    Sleep, % Config_shellMsgDelay
    Monitor_init(A_Index, doRestore)
    Debug_logMessage("DEBUG[6] MonitorW: " . Monitor_#%A_Index%_width . ", MMW1: " . mmngr1.monitors[A_Index].width . ", MM1dpiX: " . mmngr1.monitors[A_Index].dpiX . ", MM1scaleX: " . mmngr1.monitors[A_Index].scaleX, 6)
  }
  Bar_initCmdGui()

  Manager_hideShow         := False
  Manager_validateInProgress := False
  Manager_taskBarDirty     := 0
  Manager_pausedForBench   := False
  Manager_pausedForBenchSkipped := 0
  ;; Default for production; bench overrides to True in Bench_main.ahk
  ;; auto-execute (which runs before App_init -> Manager_init).
  If (Manager_isBench = "")
    Manager_isBench := False
  Bar_hideTitleWndIds      := ""
  Manager_allWndIds        := ""
  Manager_managedWndIds    := ""
  Manager_pendingHideWndIds := ""
  Manager_urgentWndIds     := ""
  Manager_initial_sync(doRestore)

  Bar_updateStatus()
  Bar_updateTitle()
  Loop, % Manager_monitorCount
  {
    View_arrange(A_Index, Monitor_#%A_Index%_aView_#1)
    Bar_updateView(A_Index, Monitor_#%A_Index%_aView_#1)
  }

  Manager_registerShellHook()
  Manager_registerWindowCreateOrShowHook()
  Manager_registerTaskBarHook()
  SetTimer, Manager_doMaintenance, %Config_maintenanceInterval%
  SetTimer, Bar_loop, %Config_readinInterval%
}

Manager_activateMonitor(i, d = 0) {
  Local aView, aWndHeight, aWndId, aWndWidth, aWndX, aWndY, v, wndId

  If (Manager_monitorCount > 1) {
    aView := Monitor_#%Manager_aMonitor%_aView_#1
    WinGet, aWndId, ID, A
    If WinExist("ahk_id" aWndId) And InStr(View_#%Manager_aMonitor%_#%aView%_wndIds, aWndId ";") And Window_isProg(aWndId) {
      WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
      If (Monitor_get(aWndX + aWndWidth / 2, aWndY + aWndHeight / 2) = Manager_aMonitor)
        View_setActiveWindow(Manager_aMonitor, aView, aWndId)
    }

    ;; Manually set the active monitor.
    If (i = 0)
      i := Manager_aMonitor
    Manager_aMonitor := Manager_loop(i, d, 1, Manager_monitorCount)
    v := Monitor_#%Manager_aMonitor%_aView_#1
    wndId := View_getActiveWindow(Manager_aMonitor, v)
    Debug_logMessage("DEBUG[1] Manager_activateMonitor: Manager_aMonitor: " Manager_aMonitor ", i: " i ", d: " d ", wndId: " wndId, 1)
    Manager_winActivate(wndId)
  }
}

Manager_applyRules(wndId, ByRef isManaged, ByRef m, ByRef tags, ByRef isFloating, ByRef isDecorated, ByRef hideTitle, ByRef action) {
  Local i, wndClass, wndTitle
  Local rule0, rule1, rule2, rule3, rule4, rule5, rule6, rule7, rule8, rule9, rule10

  isManaged   := True
  m           := 0
  tags        := 0
  isFloating  := False
  isDecorated := False
  hideTitle   := False
  action      := ""

  WinGetClass, wndClass, ahk_id %wndId%
  ;; Sync WinGetTitle: rule result is sticky per-HWND, so a timed-out title would
  ;; permanently downgrade the window to the catch-all rule (#45).
  WinGetTitle, wndTitle, ahk_id %wndId%
  If (wndClass Or wndTitle) {
    Loop, % Config_ruleCount {
      ;; The rules are traversed in reverse order.
      i := Config_ruleCount - A_Index + 1
      StringSplit, rule, Config_rule_#%i%, `;
      If RegExMatch(wndClass . ";" . wndTitle, rule1 . ";" . rule2) And (rule3 = "" Or %rule3%(wndId)) {
        isManaged   := rule4
        m           := rule5
        tags        := rule6
        isFloating  := rule7
        isDecorated := rule8
        hideTitle   := rule9
        action      := rule10
        ;; The first matching rule is returned, i. e. the last in the original rder of Config_rule.
        Break
      }
    }
    Debug_logMessage("DEBUG[1] Manager_applyRules: class: " wndClass ", title: " wndTitle ", wndId: " wndId ", rule #: " i, 1)
  } Else {
    isManaged := False
    If wndTitle
      hideTitle := True
  }
}

Manager_cleanup()
{
  Local aWndId, m, ncmSize, ncm, wndIds

  ;; Unhook before WinShow'ing the taskbar below — otherwise our hook would
  ;; observe its own teardown and schedule a deferred sync mid-cleanup.
  If Manager_taskBarHook {
    DllCall("UnhookWinEvent", "Ptr", Manager_taskBarHook)
    Manager_taskBarHook := 0
  }
  If Manager_winCreateOrShowHook {
    DllCall("UnhookWinEvent", "Ptr", Manager_winCreateOrShowHook)
    Manager_winCreateOrShowHook := 0
  }
  SetTimer, Manager_winCreateOrShowDeferred, Off
  SetTimer, Manager_winHideDeferred, Off

  ;; Cancel any deferred sync the hook had armed before we unhooked. Without
  ;; this, an in-flight one-shot timer would fire mid-teardown and
  ;; Monitor_syncTaskBarState could reflow windows while cleanup is restoring
  ;; per-monitor state.
  SetTimer, Manager_taskBarSyncDeferred, Off
  Manager_taskBarDirty := 0

  WinGet, aWndId, ID, A

  Manager_restoreWindowBorders()

  ;; Show borders and title bars.
  StringTrimRight, wndIds, Manager_managedWndIds, 1
  Manager_hideShow := True
  Loop, PARSE, wndIds, `;
  {
    Window_showAsync(A_LoopField)
    If Not Config_showBorder
      Window_set(A_LoopField, "Style", "+0x40000")
    Window_set(A_LoopField, "Style", "+0xC00000")
  }

  ;; Show the task bar.
  WinShow, Start ahk_class Button
  WinShow, ahk_class Shell_TrayWnd
  Manager_hideShow := False

  ;; Restore window positions and sizes.
  Loop, % Manager_monitorCount
  {
    m := A_Index
    Monitor_#%m%_showBar := False
    Monitor_#%m%_showTaskBar := True
    Monitor_getWorkArea(m)
    Loop, % Config_viewCount
    {
      View_arrange(m, A_Index, True)
    }
  }
  Window_set(aWndId, "AlwaysOnTop", "On")
  Window_set(aWndId, "AlwaysOnTop", "Off")

  DllCall("Shell32.dll\SHAppBarMessage", "UInt", (ABM_REMOVE := 0x1), "UInt", &Bar_appBarData)
  ;; SKAN: Crazy Scripting : Quick Launcher for Portable Apps (http://www.autohotkey.com/forum/topic22398.html)
}

;; Parse the AHK modifier prefix characters from a hotkey string and build
;; a SendInput-compatible key-up sequence for those modifiers. Used by
;; Manager_closeWindow to drain WM_KEYUP messages that would otherwise
;; have been routed to (and swallowed by) the closed window, leaving
;; phantom modifiers held that silently break subsequent hotkeys.
;;
;; Prefixes processed: # ! ^ + (Win, Alt, Ctrl, Shift).
;; Prefixes skipped:   < > * ~ $ (variant / non-modifier-key prefixes).
;; First unrecognized character ends the prefix scan (it's the key name).
;; Pure: only reads its argument, returns a string.
Manager_modifiersFromHotkey(hotkeyStr) {
  Local result, c
  result := ""
  Loop, Parse, hotkeyStr
  {
    c := A_LoopField
    If (c = "#")
      result .= "{LWin up}{RWin up}"
    Else If (c = "+")
      result .= "{LShift up}{RShift up}"
    Else If (c = "^")
      result .= "{LCtrl up}{RCtrl up}"
    Else If (c = "!")
      result .= "{LAlt up}{RAlt up}"
    Else If (c = "<" Or c = ">" Or c = "*" Or c = "~" Or c = "$")
      Continue
    Else
      Break
  }
  Return result
}

Manager_closeWindow() {
  Local aWndId, mods

  mods := Manager_modifiersFromHotkey(A_ThisHotkey)
  WinGet, aWndId, ID, A
  If Window_isProg(aWndId)
    Window_close(aWndId)
  ;; Release any modifier keys that were held for this hotkey. Windows routes
  ;; WM_KEYUP for modifiers to the focused window; if that window just closed
  ;; (or was never closeable), the up events are swallowed and the OS treats
  ;; the modifiers as still held -- subsequent keypresses land as Win+key or
  ;; Shift+key instead of plain keys until each modifier is physically tapped.
  ;; SendInput {key up} is a no-op for keys already up, so this is safe even
  ;; when Window_isProg returned 0 (desktop, bar, etc.) and no close occurred.
  If mods
    SendInput %mods%
}

; Asynchronous management of various WM properties.
; We want to make sure that we can recover the layout and windows in the event of
; unexpected problems.
; Periodically check for changes to these things and save them somewhere (not over
; user-defined files).
Manager_doMaintenance:
  Critical

  ;; @TODO: Manager_sync?
  If Not (Config_autoSaveSession = "off") And Not (Config_autoSaveSession = "False")
    Manager_saveState()
Return

;; Single-runner deferred orphan validator. Manager_onShellMessage
;; schedules this with `SetTimer, ..., -200` after each shell event;
;; AHK's SetTimer naturally debounces a burst of N events within 200 ms
;; into a single fire 200 ms after the last one. The
;; Manager_validateInProgress flag prevents a long-running validate from
;; being re-entered if the timer fires again before it completes.
;;
;; If validate prunes any orphans and dynamic tiling is on, re-arranges
;; the active view so the reclaimed slot collapses immediately.
;;
;; Deliberately NOT Critical (unlike Manager_doMaintenance which saves
;; session state and must complete uninterrupted). Validate is a cleanup
;; pass that's safe to interleave with other threads, and the user
;; asked for a non-blocking design — Critical would block Bar_loop,
;; hotkeys, and shell events for the duration of validate (~10-50 ms
;; typical). The Manager_validateInProgress flag, not Critical, is the
;; mechanism that ensures only one validate runs at a time.
Manager_validateAliveTimer:
  Critical Off    ;; explicit: keep other timers/hotkeys/shell events responsive
  If Manager_validateInProgress
    Return
  Manager_validateInProgress := True
  validateAliveAffected := Manager_validateAlive()
  Loop, PARSE, validateAliveAffected, `;
  {
    If Not A_LoopField
      Continue
    If Config_dynamicTiling
      View_arrange(A_LoopField, Monitor_#%A_LoopField%_aView_#1)
  }
  Manager_validateInProgress := False
Return

;; Debounce target for Bar_updateTitle. See Manager_barTitleAction.
Manager_barTitleDeferred:
  Critical Off
  Bar_updateTitle()
Return

;; Deferred handler for Manager_onObjectShowOrHide. The hook callback runs on
;; the AHK message thread, so we keep it fast and bounce the actual sync work
;; here. Negative timer = one-shot, naturally debouncing bursts of events
;; (e.g., explorer batching show/hide on a single state change).
;;
;; Manager_taskBarDirty is a bitmask of monitors needing sync — populated by
;; the hook callback after mapping each event's hwnd to its monitor. Read
;; and clear up-front so any event that fires during the loop re-arms a
;; fresh timer cycle rather than getting eaten by the clear.
Manager_taskBarSyncDeferred:
  Critical Off
  dirty := Manager_taskBarDirty
  Manager_taskBarDirty := 0
  Loop, % Manager_monitorCount {
    m := A_Index
    If (dirty & (1 << (m - 1)))
      Monitor_syncTaskBarState(m)
  }
Return

;; Deferred handler for Manager_onWindowCreateOrShow (#19). Per-burst Manager_sync
;; instead of per-event Manager_manage — sync's enumeration is idempotent
;; on Manager_managedWndIds so duplicate adopts are no-ops.
Manager_winCreateOrShowDeferred:
  Critical Off
  ;; Burst is ending — next event after this fire starts fresh. Cleared
  ;; before Manager_sync so a CREATE/SHOW arriving mid-sync is treated as
  ;; a new burst (it will re-arm a fresh 50 ms timer) and won't be missed.
  Manager_clearDebouncedTimerArm("Manager_winCreateOrShowDeferred")
  ;; Perf wrappers are no-ops unless Perf_enabled (bench mode). bgEventStorm
  ;; reads the sample count to assert the timer actually fired during a
  ;; sustained cross-process CREATE/SHOW storm (#86 regression test).
  Perf_start("Manager_winCreateOrShowDeferred")
  winCreateSyncDummy := ""
  winCreateIsChanged := Manager_sync(winCreateSyncDummy)
  If winCreateIsChanged
  {
    If Config_dynamicTiling
      View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
    Bar_updateView(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
  }
  ;; #96: symmetric restore for windows minimized via Win+N (default). The
  ;; existing Manager_onShellMessage path at ~line 1138 handles this when
  ;; HSHELL_WINDOWACTIVATED fires, but Win11 Alt+Tab restore doesn't
  ;; reliably emit that — EVENT_OBJECT_SHOW does. Walk only the cached-
  ;; minimized subset (Window_#X_isMinimized is set true by Window_minimize,
  ;; whose sole caller is Manager_minimizeWindow). Cost is one property
  ;; read per managed HWND plus a WinGet only for the typically-empty
  ;; user-minimized set.
  StringTrimRight, winRestoreManagedIds, Manager_managedWndIds, 1
  Loop, PARSE, winRestoreManagedIds, `;
  {
    winRestoreHwnd := A_LoopField
    If Not winRestoreHwnd
      Continue
    winRestoreCachedMinimized := Window_#%winRestoreHwnd%_isMinimized
    If Not winRestoreCachedMinimized
      Continue
    If Not WinExist("ahk_id " . winRestoreHwnd)
      Continue
    WinGet, winRestoreMinMax, MinMax, ahk_id %winRestoreHwnd%
    ;; isManaged hard-coded True: loop body only runs for HWNDs we just
    ;; parsed out of Manager_managedWndIds. Cached flag passed live so a
    ;; future refactor that moves the Continue guards still gets a
    ;; correct decision from the helper.
    If Not Manager_shouldReintegrateOnRestore(True, winRestoreCachedMinimized, winRestoreMinMax = -1)
      Continue
    winRestoreM := Window_#%winRestoreHwnd%_monitor
    winRestoreV := Monitor_#%winRestoreM%_aView_#1
    Window_#%winRestoreHwnd%_isFloating  := False
    Window_#%winRestoreHwnd%_isMinimized := False
    View_setActiveWindow(winRestoreM, winRestoreV, winRestoreHwnd)
    View_arrange(winRestoreM, winRestoreV)
    Bar_updateView(winRestoreM, winRestoreV)
  }
  Perf_end("Manager_winCreateOrShowDeferred")
Return

;; Decision matrix for an EVENT_OBJECT_HIDE arrival, factored out of
;; Manager_onWindowCreateOrShow so it's testable without a real WinEvent
;; hook firing.
;;
;;   not in Manager_managedWndIds -> "ignore"    (third-party window we
;;                                                never tracked)
;;   expectedHide=True            -> "expected"  (consume the flag; bug.n
;;                                                hid it for a view switch)
;;   managed, no flag             -> "queue"     (owning app hid it; the
;;                                                deferred handler will
;;                                                unmanage on next tick)
;;
;; Side effects: on "expected" the flag is cleared. On "queue" the
;; canonical stored key is appended to Manager_pendingHideWndIds. Caller
;; is responsible for arming Manager_winHideDeferred when "queue" is
;; returned.
;;
;; Manager_isManaged canonicalizes the input (any numeric form: hex
;; string, decimal string, or integer) to whatever format
;; Manager_managedWndIds stored at manage time — hex on most code paths,
;; decimal on others (see Manager_isManaged comment block,
;; Manager.ahk:880-889). Skipping this normalization means a HIDE event
;; carrying a hex string would silently miss a decimal-stored entry (or
;; vice-versa) and the ghost would persist. Caught by Copilot review on
;; PR #58 and locked in by test_Manager_classifyHideEvent.ahk.
;; #96: pure decision for whether an EVENT_OBJECT_SHOW arrival for a
;; previously-managed HWND should trigger the reverse-minimize
;; reintegration sequence. Factored for direct Yunit coverage; the
;; SHOW callback path can't be exercised without a real WinEvent hook.
;;
;;   isManaged       — HWND is in Manager_managedWndIds.
;;   isUserMinimized — cached Window_#X_isMinimized. Only set True
;;                     by Window_minimize, which is only called from
;;                     Manager_minimizeWindow (Win+N default). It
;;                     distinguishes "we minimized this" from a
;;                     user-explicit float toggle, which we must NOT
;;                     auto-untile.
;;   isMinimized     — current OS state (WinGet MinMax = -1). False
;;                     means the OS already restored the window.
;;
;; Returns True iff all three identify a window we minimized that
;; has now been restored externally. Reintegration body (clear
;; isFloating, clear cached _isMinimized, View_arrange) mirrors
;; Manager_onShellMessage's HSHELL_WINDOWACTIVATED branch at line
;; ~1138 — Win11 doesn't reliably fire HSHELL_WINDOWACTIVATED for
;; Alt+Tab restore, so the WinEvent SHOW path needs the same logic.
Manager_shouldReintegrateOnRestore(isManaged, isUserMinimized, isMinimized) {
  Return isManaged And isUserMinimized And Not isMinimized
}

Manager_classifyHideEvent(hwnd) {
  Global
  Local key
  key := Manager_isManaged(hwnd)
  If Not key
    Return "ignore"
  If Window_#%key%_expectedHide {
    Window_#%key%_expectedHide := False
    Return "expected"
  }
  Manager_pendingHideWndIds .= key ";"
  Return "queue"
}

;; Drain managed windows whose owning app hid them (PowerToys Command
;; Palette dismissal, etc.). Manager_onWindowCreateOrShow queues them
;; when EVENT_OBJECT_HIDE fires without a matching expectedHide flag.
;; If we don't untag, View_getTiledWndIds keeps counting the now-invisible
;; window and Tiler_layoutTiles allocates it a tile slot that renders empty.
Manager_winHideDeferred:
  Critical Off
  winHideQueue := Manager_pendingHideWndIds
  Manager_pendingHideWndIds := ""
  StringTrimRight, winHideQueue, winHideQueue, 1
  Manager__processHideQueue(winHideQueue)
Return

;; Extracted body of Manager_winHideDeferred so the multi-monitor
;; arrange logic is Yunit-testable. Unmanages every still-hidden
;; managed non-hung window in the supplied queue, then arranges +
;; refreshes the bar for each *affected monitor's* visible view --
;; not just Manager_aMonitor (#59 pre-fix targeted only the active
;; monitor, leaving sibling monitors with ghost tile slots until a
;; user-driven view switch on that monitor).
;;
;; Returns the affected-monitor set as a ";m1;m2;" string (or "").
;; The label ignores the return; tests assert on it directly.
Manager__processHideQueue(queue) {
  Global
  Local affected, m

  affected := ""
  Loop, PARSE, queue, `;
  {
    If Not A_LoopField
      Continue
    ;; Re-verify: still hidden (didn't bounce back), still managed
    ;; (no concurrent unmanage), and not hung (don't unmanage a hung
    ;; window — IsWindowVisible can flicker on resume).
    ;; Manager_isManaged does numeric comparison so prefix/suffix
    ;; collisions between the queued hwnd and other managed entries
    ;; (e.g., 12 inside 112) can't false-match — matches the pattern
    ;; locked in for classifyHideEvent by PR #58.
    If DllCall("IsWindowVisible", "Ptr", A_LoopField)
      Continue
    If Not Manager_isManaged(A_LoopField)
      Continue
    If Window_isHung(A_LoopField)
      Continue
    Debug_logMessage("DEBUG[1] Manager__processHideQueue: unmanage " A_LoopField " (app-side hide)", 1)
    m := Manager_unmanage(A_LoopField)
    If m And Not InStr(affected, ";" m ";")
      affected .= ";" m ";"
  }
  Loop, PARSE, affected, `;
  {
    If Not A_LoopField
      Continue
    If Config_dynamicTiling
      View_arrange(A_LoopField, Monitor_#%A_LoopField%_aView_#1)
    Bar_updateView(A_LoopField, Monitor_#%A_LoopField%_aView_#1)
  }
  Return affected
}

Manager_getWindowInfo() {
  Local aWndClass, aWndHeight, aWndId, aWndPId, aWndPName, aWndStyle, aWndTitle, aWndWidth, aWndX, aWndY, detectHiddenWnds, isHidden, text, v

  detectHiddenWnds := A_DetectHiddenWindows
  DetectHiddenWindows, On
  WinGet, aWndId, ID, A
  DetectHiddenWindows, %detectHiddenWnds%
  isHidden := Window_getHidden(aWndId, aWndClass, aWndTitle)
  ;; Window_getHidden leaves wndTitle empty for visible windows; debug helper
  ;; needs it for display, so fetch it directly (blocking is fine — manual
  ;; hotkey, not a shell-event hot path).
  If Not aWndTitle
    WinGetTitle, aWndTitle, ahk_id %aWndId%
  WinGet, aWndPName, ProcessName, ahk_id %aWndId%
  WinGet, aWndPId, PID, ahk_id %aWndId%
  WinGet, aWndStyle, Style, ahk_id %aWndId%
  WinGet, aWndMinMax, MinMax, ahk_id %aWndId%
  WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
  text := "ID: " aWndId (isHidden ? " [hidden]" : "") "`nclass:`t" aWndClass "`ntitle:`t" aWndTitle
  If InStr(Bar_hideTitleWndIds, aWndId ";")
    text .= " [hidden]"
  text .= "`nprocess:`t" aWndPName " [" aWndPId "]`nstyle:`t" aWndStyle "`nmetrics:`tx: " aWndX ", y: " aWndY ", width: " aWndWidth ", height: " aWndHeight
  If InStr(Manager_managedWndIds, aWndId ";") {
    text .= "`ntags:`t" Window_#%aWndId%_tags
    If Window_#%aWndId%_isFloating
      text .= " [floating]"
  } Else
    text .= "`ntags:`t--"
  text .= "`n`nConfig_rule=" aWndClass ";" aWndTitle ";;" Manager_getWindowRule(aWndId)
  MsgBox, % (260 | 0x1000), bug.n: Window Information, % text "`n`nCopy text to clipboard?"
  IfMsgBox Yes
    Clipboard := text
}

Manager_getWindowList()
{
  Local text, v, aWndId, aWndTitle, wndIds, wndTitle

  v := Monitor_#%Manager_aMonitor%_aView_#1
  aWndId := View_getActiveWindow(Manager_aMonitor, v)
  WinGetTitle, aWndTitle, ahk_id %aWndId%
  text := "Active Window`n" aWndId ":`t" aWndTitle

  StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%v%_wndIds, 1
  text .= "`n`nWindow List"
  Loop, PARSE, wndIds, `;
  {
    WinGetTitle, wndTitle, ahk_id %A_LoopField%
    text .= "`n" A_LoopField ":`t" wndTitle
  }

  MsgBox, % (260 | 0x1000), bug.n: Window List, % text "`n`nCopy text to clipboard?"
  IfMsgBox Yes
    Clipboard := text
}

Manager_getWindowRule(wndId) {
  Local rule, wndMinMax
  
  rule := ""
  WinGet, wndMinMax, MinMax, ahk_id %wndId%
  If InStr(Manager_managedWndIds, wndId ";") {
    rule .= "1;"
    If (Window_#%wndId%_monitor = "")
      rule .= "0;"
    Else
      rule .= Window_#%wndId%_monitor ";"
    If (Window_#%wndId%_tags = "")
      rule .= "0;"
    Else
      rule .= Window_#%wndId%_tags ";"
    If Window_#%wndId%_isFloating
      rule .= "1;"
    Else
      rule .= "0;"
    If Window_#%wndId%_isDecorated
      rule .= "1;"
    Else
      rule .= "0;"
  } Else
    rule .= "0;;;;;"
  If InStr(Bar_hideTitleWndIds, wndId ";")
    rule .= "1;"
  Else
    rule .= "0;"
  If (wndMinMax = 1)
    rule .= "maximize"
  
  Return, rule
}

Manager_lockWorkStation()
{
  Global Config_shellMsgDelay

  RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Policies\System, DisableLockWorkstation, 0
  Sleep, % Config_shellMsgDelay
  DllCall("LockWorkStation")
  Sleep, % 4 * Config_shellMsgDelay
  RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Policies\System, DisableLockWorkstation, 1
}
;; Unambiguous: Re-use WIN+L as a hotkey in bug.n (http://www.autohotkey.com/community/viewtopic.php?p=500903&sid=eb3c7a119259b4015ff045ef80b94a81#p500903)

Manager_loop(index, increment, lowerBound, upperBound) {
  If (upperBound <= 0) Or (upperBound < lowerBound) Or (upperBound = 0)
    Return, 0

  numberOfIndexes := upperBound - lowerBound + 1
  lowerBoundBasedIndex := index - lowerBound
  lowerBoundBasedIndex := Mod(lowerBoundBasedIndex + increment, numberOfIndexes)
  If (lowerBoundBasedIndex < 0)
    lowerBoundBasedIndex += numberOfIndexes

  Return, lowerBound + lowerBoundBasedIndex
}

Manager__setWinProperties(wndId, isManaged, m, tags, isDecorated, isFloating, hideTitle, action = "") {
  Local a := False

  If Not InStr(Manager_allWndIds, wndId ";")
    Manager_allWndIds .= wndId ";"

  If (isManaged) {
    If (action = "close" Or action = "maximize" Or action = "restore")
      Window_%action%(wndId)

    If Not InStr(Manager_managedWndIds, wndId ";")
      Manager_managedWndIds .= wndId ";"
    Window_#%wndId%_monitor     := m
    Window_#%wndId%_tags        := tags
    Window_#%wndId%_isDecorated := isDecorated
    Window_#%wndId%_isFloating  := isFloating
    Window_#%wndId%_isMinimized := False
    Window_#%wndId%_isUrgent    := False
    Window_#%wndId%_area        := 0

    If Not Config_showBorder
      Window_set(wndId, "Style", "-0x40000")
    If Not Window_#%wndId%_isDecorated
      Window_set(wndId, "Style", "-0xC00000")

    a := Window_#%wndId%_tags & (1 << (Monitor_#%m%_aView_#1 - 1))
    If a {
      ;; A newly created window defines the active monitor, if it is visible.
      Manager_aMonitor := m
      Manager_winActivate(wndId)
    } Else {
      Manager_hideShow := True
      Window_hide(wndId)
      Manager_hideShow := False
    }
  }
  If hideTitle And Not InStr(Bar_hideTitleWndIds, wndId ";")
    Bar_hideTitleWndIds .= wndId . ";"

  Return, a
}

;; Accept a window to be added to the system for management.
;; Provide a monitor and view preference, but don't override the config.
Manager_manage(preferredMonitor, preferredView, wndId, rule = "") {
  Local a, action, c0, hideTitle, i, isDecorated, isFloating, isManaged, l, m, n, replace, search, tags, body
  Local rule0, rule1, rule2, rule3, rule4, rule5, rule6, rule7
  Local wndControlList0, wndId0, wndIds, wndX, wndY, wndWidth, wndHeight

  ;; Manage any window only once.
  If InStr(Manager_allWndIds, wndId ";") And (rule = "")
    Return

  body := 0
  If Window_isGhost(wndId) {
    Debug_logMessage("DEBUG[2] A window has given up the ghost (Ghost wndId: " . wndId . ")", 2)
    body := Window_findHung(wndId)
    If body {
      isManaged := InStr(Manager_managedWndIds, body ";")
      m := Window_#%body%_monitor
      tags := Window_#%body%_tags
      isDecorated := Window_#%body%_isDecorated
      isFloating := Window_#%body%_isFloating
      hideTitle := InStr(Bar_hideTitleWndIds, body ";")
      action := ""
    } Else
      Debug_logMessage("DEBUG[1] No body could be found for ghost wndId: " . wndId, 1)
  }

  ;; Apply rules if the window is either a normal window or a ghost without a body.
  If (body = 0) {
    Manager_applyRules(wndId, isManaged, m, tags, isFloating, isDecorated, hideTitle, action)
    If Not (rule = "") {
      StringSplit, rule, rule, `;
      isManaged   := rule1
      m           := rule2
      tags        := rule3
      isFloating  := rule4
      isDecorated := rule5
      hideTitle   := rule6
      action      := rule7
    }
    If (m = 0)
      m := preferredMonitor
    If (m < 0)
      m := 1
    If (m > Manager_monitorCount)    ;; If the specified monitor is out of scope, set it to the max. monitor.
      m := Manager_monitorCount
    If (tags = 0)
      tags := 1 << (preferredView - 1)
  }

  a := Manager__setWinProperties(wndId, isManaged, m, tags, isDecorated, isFloating, hideTitle, action)

  ; Do view placement.
  If isManaged {
    Loop, % Config_viewCount
      If (Window_#%wndId%_tags & (1 << (A_Index - 1))) {
        If (body) {
          ; Try to position near the body.
          View_ghostWindow(m, A_Index, body, wndId)
        }
        Else
          View_addWindow(m, A_Index, wndId)
      }
  }

  Return, a
}

Manager_maximizeWindow() {
  Local aWndId

  Perf_start("Manager_maximizeWindow")
  WinGet, aWndId, ID, A
  If InStr(Manager_managedWndIds, aWndId ";") And Not Window_#%aWndId%_isFloating
    View_toggleFloatingWindow(aWndId)
  Window_set(aWndId, "Top", "")

  Window_moveAsync(aWndId, Monitor_#%Manager_aMonitor%_x, Monitor_#%Manager_aMonitor%_y, Monitor_#%Manager_aMonitor%_width, Monitor_#%Manager_aMonitor%_height)
  Perf_end("Manager_maximizeWindow")
}

Manager_minimizeWindow() {
  Local aView, aWndId

  WinGet, aWndId, ID, A
  aView := Monitor_#%Manager_aMonitor%_aView_#1
  StringReplace, View_#%Manager_aMonitor%_#%aView%_aWndIds, View_#%Manager_aMonitor%_#%aView%_aWndIds, % aWndId ";",, All
  If InStr(Manager_managedWndIds, aWndId ";") And Not Window_#%aWndId%_isFloating
    View_toggleFloatingWindow(aWndId)
  Window_set(aWndId, "Bottom", "")

  Window_minimize(aWndId)
}

Manager_moveWindow() {
  Local aWndId, SC_MOVE, WM_SYSCOMMAND

  WinGet, aWndId, ID, A
  If InStr(Manager_managedWndIds, aWndId . ";") And Not Window_#%aWndId%_isFloating
    View_toggleFloatingWindow(aWndId)
  Window_set(aWndId, "Top", "")

  WM_SYSCOMMAND = 0x112
  SC_MOVE       = 0xF010
  SendMessage, WM_SYSCOMMAND, SC_MOVE, , , ahk_id %aWndId%
}

Manager_onDisplayChange(a, wParam, uMsg, lParam) {
  Debug_logMessage("DEBUG[1] Manager_onDisplayChange( a: " . a . ", uMsg: " . uMsg . ", wParam: " . wParam . ", lParam: " . lParam . " )", 1)
  Manager_armDebouncedTimer("Manager_displayChangeFire", 2000)
}

;; Debounced handler — fires 2 s after the last WM_DISPLAYCHANGE. Multiple
;; rapid events (e.g. virtual display cycling on session resume) collapse
;; into one call after the display settles. Decision/prompt/apply all run
;; inside the timer so the synchronous prompt dialog can't stack during a
;; storm.
Manager_displayChangeFire:
  Manager_displayChangeProcess()
Return

Manager_displayChangeProcess() {
  Global Config_monitorDisplayChangeMessages, Manager_displayChangeSessionChoice
  Global Manager_displayChangeInProgress, Manager_displayChangePending

  ;; Re-entrancy guard: Manager_displayChangePrompt spins on Sleep, so a
  ;; new WM_DISPLAYCHANGE during the prompt can re-arm the debounce timer
  ;; and re-fire this function before the original returns. Set a pending
  ;; flag and let the active run pick it up after its current cycle.
  If Manager_displayChangeInProgress {
    Manager_displayChangePending := True
    Return
  }
  Manager_displayChangeInProgress := True

  Loop {
    Manager_displayChangePending := False
    decision := Manager_displayChangeDecide(Config_monitorDisplayChangeMessages, Manager_displayChangeSessionChoice)
    If (decision = "prompt") {
      Manager_displayChangePrompt(choice, remember)
      Manager_displayChangeRecordSessionChoice(choice, remember)
      decision := Manager_displayChangeDecide(Config_monitorDisplayChangeMessages, choice)
    }
    Manager_displayChangeApply(decision)
  } Until !Manager_displayChangePending

  Manager_displayChangeInProgress := False
}

;; Returns the action to take for a WM_DISPLAYCHANGE event, given the
;; persistent config setting and any session-only override the user picked
;; via the "remember this decision for this session" checkbox.
;;   "reset"     -> Manager_resetMonitorConfiguration (re-detect monitors)
;;   "rearrange" -> redraw active views without re-detecting monitors
;;   "ignore"    -> no-op
;;   "prompt"    -> caller should show the dialog
Manager_displayChangeDecide(configValue, sessionChoice) {
  If (sessionChoice = "yes")
    Return "reset"
  If (sessionChoice = "no")
    Return "rearrange"
  If (sessionChoice = "cancel")
    Return "ignore"
  If (configValue = "on")
    Return "reset"
  If (configValue = "off" || configValue = 0)
    Return "ignore"
  Return "prompt"
}

Manager_displayChangeApply(decision) {
  Global Manager_monitorCount

  Debug_logMessage("DEBUG[6] displayChangeApply: decision=" . decision, 6)
  If (decision = "reset") {
    Manager_resetMonitorConfiguration()
  } Else If (decision = "rearrange") {
    Loop, % Manager_monitorCount {
      i := A_Index
      View_arrange(i, Monitor_#%i%_aView_#1)
      Bar_updateView(i, Monitor_#%i%_aView_#1)
    }
    Bar_updateStatus()
    Bar_updateTitle()
  }
}

Manager_displayChangeRecordSessionChoice(choice, remember) {
  Global Manager_displayChangeSessionChoice
  If (remember)
    Manager_displayChangeSessionChoice := choice
}

Manager_displayChangePrompt(ByRef choice, ByRef remember) {
  Global MgrDispChange_choice, MgrDispChange_remember, MgrDispChange_done

  MgrDispChange_choice   := "cancel"
  MgrDispChange_remember := False
  MgrDispChange_done     := False

  Gui, MgrDispChange:New, +OwnDialogs +AlwaysOnTop +ToolWindow, bug.n
  Gui, MgrDispChange:Add, Text, , Would you like to reset the monitor configuration?`n'No' will only rearrange all active views.`n'Cancel' will result in no change.
  Gui, MgrDispChange:Add, Checkbox, vMgrDispChange_remember, Remember this decision for this session
  Gui, MgrDispChange:Add, Button, gMgrDispChange_btnYes Default w80, &Yes
  Gui, MgrDispChange:Add, Button, gMgrDispChange_btnNo x+10 w80, &No
  Gui, MgrDispChange:Add, Button, gMgrDispChange_btnCancel x+10 w80, &Cancel
  Gui, MgrDispChange:Show

  While (!MgrDispChange_done)
    Sleep, 50

  choice   := MgrDispChange_choice
  remember := MgrDispChange_remember
}

;; --- Manager_displayChangePrompt button handlers (script-scope labels) ---
MgrDispChange_btnYes:
  Gui, MgrDispChange:Submit, NoHide
  MgrDispChange_choice := "yes"
  MgrDispChange_done   := True
  Gui, MgrDispChange:Destroy
Return

MgrDispChange_btnNo:
  Gui, MgrDispChange:Submit, NoHide
  MgrDispChange_choice := "no"
  MgrDispChange_done   := True
  Gui, MgrDispChange:Destroy
Return

MgrDispChange_btnCancel:
MgrDispChangeGuiClose:
MgrDispChangeGuiEscape:
  Gui, MgrDispChange:Submit, NoHide
  MgrDispChange_choice := "cancel"
  MgrDispChange_done   := True
  Gui, MgrDispChange:Destroy
Return

/*
  Possible indications for a ...
    new window: 1 (started by Windows Explorer) or 6 (started by cmd, shell or Win+E).
      There doesn't seem to be a reliable way to get all application starts.
    closed window: 2 (always?) or 13 (ghost)
    focus change: 4 or 32772
    title change: 6 or 32774
*/

;; Decides what Manager_onShellMessage should do with Bar_updateTitle at
;; end-of-handler for a given shell event. Pure so it's Yunit-testable;
;; the actual side-effect dispatch (immediate call vs. SetTimer vs. no-
;; op) lives in Manager_onShellMessage.
;;
;; Returns:
;;   "immediate" - call Bar_updateTitle() now. Default for non-REDRAW
;;                 events where the active window may have changed
;;                 (create / destroy / activate / rude-app-activate).
;;   "defer"     - arm a short one-shot timer. HSHELL_REDRAW on the
;;                 currently active window means its title changed;
;;                 deferring debounces a burst (e.g. browser streaming
;;                 a response) into a single bar update after the burst
;;                 settles, instead of redrawing per chunk.
;;   "skip"      - do nothing. HSHELL_REDRAW on a background window
;;                 doesn't change the bar's content (the bar shows the
;;                 *active* window's title), so the update would be
;;                 pure waste. This is the largest single win on the
;;                 streaming-background-window workload.
Manager_barTitleAction(wParam, lParam, activeWndId) {
  ;; HSHELL_REDRAW = 6.
  If (wParam != 6)
    Return "immediate"
  If (lParam = activeWndId)
    Return "defer"
  Return "skip"
}

;; Side-effect dispatch for Manager_barTitleAction's classification.
;; Split out so the three branches are Yunit-coverable without invoking
;; the full Manager_onShellMessage path.
Manager_barTitleDispatch(action) {
  If (action = "immediate") {
    SetTimer, Manager_barTitleDeferred, Off
    Bar_updateTitle()
  } Else If (action = "defer")
    Manager_armDebouncedTimer("Manager_barTitleDeferred", 50)
}

Manager_onShellMessage(wParam, lParam) {
  Local a, action, isChanged, aWndClass, aWndHeight, aWndId, aWndWidth, aWndX, aWndY, benchHandle, i, m, managedKey, t, wndClass, wndId, wndId0, wndIds, wndIsHidden, wndTitle, x, y
  ;; HSHELL_* become global.

  ;; MESSAGE NAME AND         ... NUMBER    COMMENTS, POSSIBLE EVENTS
  HSHELL_WINDOWCREATED        :=  1         ;; window shown
  HSHELL_WINDOWDESTROYED      :=  2         ;; window hidden, destroyed or deactivated
  HSHELL_ACTIVATESHELLWINDOW  :=  3
  HSHELL_WINDOWACTIVATED      :=  4         ;; window title changed, window activated (by mouse, Alt+Tab or hotkey); alternative message: 32772
  HSHELL_GETMINRECT           :=  5
  HSHELL_REDRAW               :=  6         ;; window title changed
  HSHELL_TASKMAN              :=  7
  HSHELL_LANGUAGE             :=  8
  HSHELL_SYSMENU              :=  9
  HSHELL_ENDTASK              := 10
  HSHELL_ACCESSIBILITYSTATE   := 11
  HSHELL_APPCOMMAND           := 12
  ;; The following two are seen when a hung window recovers.
  HSHELL_WINDOWREPLACED       := 13         ;; hung window recovered and replaced the ghost window (lParam indicates the ghost window.)
  HSHELL_WINDOWREPLACING      := 14         ;; hung window recovered (lParam indicates the previously hung and now recovered window.)
  HSHELL_HIGHBIT              := 32768      ;; 0x8000
  HSHELL_FLASH                := 32774      ;; (HSHELL_REDRAW|HSHELL_HIGHBIT); window signalling an application update (The window is flashing due to some event, one message for each flash.)
  HSHELL_RUDEAPPACTIVATED     := 32772      ;; (HSHELL_WINDOWACTIVATED|HSHELL_HIGHBIT); full-screen app or root-privileged window activated? alternative message: 4
  ;; Any message may be missed, if bug.n is hung or they come in too quickly.

  SetFormat, Integer, hex
  lParam := lParam + 0
  SetFormat, Integer, d

  Debug_logMessage("DEBUG[2] Manager_onShellMessage( wParam: " . wParam . ", lParam: " . lParam . " )", 2)

  ;; Full-handler timing. The existing "Manager_onShellMessage" label starts
  ;; later (after the early-returns) and measures only the dispatch phase;
  ;; "_full" wraps the entire function so Perf samples reflect every code
  ;; path, including HSHELL_FLASH urgent dispatch and the hidden-window
  ;; early-return. If a new early-return is added below, it must be
  ;; preceded by Perf_end("Manager_onShellMessage_full") to avoid leaking
  ;; an unclosed sample.
  Perf_start("Manager_onShellMessage_full")

  ;; Urgent-view dispatch must run before the hidden-window early-return:
  ;; bug.n SW_HIDEs every window that is on a non-active view, and those
  ;; are exactly the windows whose flashes we want to surface as red bar
  ;; entries. Window_getHidden returns True for any SW_HIDDEN window, so
  ;; the existing early-return swallows every meaningful HSHELL_FLASH if
  ;; this dispatch is placed below it.
  ;;
  ;; Note: Manager_isManaged is called rather than InStr-ing
  ;; Manager_managedWndIds inline. This function declares Local … which
  ;; puts it in assume-local mode; an inline reference to
  ;; Manager_managedWndIds would shadow as an empty local. The helper
  ;; declares the variable Global explicitly so the read is always
  ;; against the real global.
  ;;
  ;; Use the stored-key form from Manager_managedWndIds so the
  ;; Window_#%wndId%_* dynamic-variable lookups inside Manager_markUrgent
  ;; match the format Manager__setWinProperties used at manage time
  ;; (typically hex in production, decimal in Yunit tests).
  If (wParam = HSHELL_FLASH) And lParam {
    managedKey := Manager_isManaged(lParam)
    If managedKey {
      Manager_markUrgent(managedKey)
      Perf_end("Manager_onShellMessage_full")
      Return
    }
  }

  t0 := A_TickCount
  wndIsHidden := Window_getHidden(lParam, wndClass, wndTitle)
  Debug_logMessage("DEBUG[3] Manager_onShellMessage: getHidden=" . wndIsHidden . " ms=" . (A_TickCount - t0), 3)
  If wndIsHidden {
    ;; If there is no window class or title, it is assumed that the window is not identifiable.
    ;;   The problem was, that i. a. claws-mail triggers Manager_sync, but the application window
    ;;   would not be ready for being managed, i. e. class and title were not available. Therefore more
    ;;   attempts were needed.
    Perf_end("Manager_onShellMessage_full")
    Return
  }

  If (wParam = 4 Or wParam = 32772) {
    If (lParam = 0) {
      ;; Desktop activated (Citrix reconnect, clicking the shell, etc.).
      ;; The active-window class/title lookup that used to live here would
      ;; block the AHK thread when post-reconnect windows were slow to
      ;; service WM_GETTEXT -- mouse position alone is enough to identify
      ;; the active monitor. (Bar_updateTitle below still queries the
      ;; active window, but its title fetch is non-blocking-capped.)
      MouseGetPos, x, y
      m := Monitor_get(x, y)
      If m
        Manager_aMonitor := m
      Bar_updateTitle()
    } Else {
      ;; Query lParam directly (the window that just got focus) instead
      ;; of WinGet ID, A on the OS-reported active window -- saves a
      ;; round-trip in this block. WorkerW always has an empty title so
      ;; class alone identifies the desktop-click case.
      WinGetClass, aWndClass, ahk_id %lParam%
      If (aWndClass = "WorkerW") {
        MouseGetPos, x, y
        m := Monitor_get(x, y)
        If m
          Manager_aMonitor := m
        Bar_updateTitle()
      }
    }
  }

  ;; This was previously inactive due to `HSHELL_WINDOWREPLACED` not being defined in this function.
  ;; Afterwards it caused problems managing new windows, when messages come in too quickly.
;  If (wParam = HSHELL_WINDOWREPLACED)
;  {    ;; This shouldn't need a redraw because the window was supposedly replaced.
;    Manager_unmanage(lParam)
;  }

; If (wParam = 14)
; {    ;; Window recovered from being hung. Maybe force a redraw.
; }

  ;; @todo: There are two problems with the use of Manager_hideShow:
  ;;   1) If Manager_hideShow is set when we hit this block, we won't take some actions that should eventually be taken.
  ;;      This _may_ explain why some windows never get picked up when spamming Win+E
  ;;   2) There is a race condition between the time that Manager_hideShow is checked and any other action which we are
  ;;      trying to protect against. If another process (hotkey) enters a hideShow block after Manager_hideShow has
  ;;      been checked here, bad things could happen. I've personally observed that windows may be permanently hidden.
  ;;   Look into the use of AHK synchronization primitives.
  If (wParam = 1 Or wParam = 2 Or wParam = 4 Or wParam = 6 Or wParam = 32772) And lParam And Not Manager_hideShow
  {
    Perf_start("Manager_onShellMessage")
    ;; Skip while bugn-bench.exe is running (#19). Don't self-pause if we ARE the bench.
    If (Not Manager_isBench) {
      benchHandle := DllCall("OpenMutex", "UInt", 0x00100000, "Int", 0, "Str", "Local\bug.n-bench-active", "Ptr")
      If benchHandle {
        DllCall("CloseHandle", "Ptr", benchHandle)
        If Not Manager_pausedForBench {
          Debug_logMessage("DEBUG[0] Manager: pausing for bench (#19)", 0)
          Manager_pausedForBench := True
          Manager_pausedForBenchSkipped := 0
        }
        Manager_pausedForBenchSkipped += 1
        Perf_end("Manager_onShellMessage")
        Perf_end("Manager_onShellMessage_full")
        Return
      }
      If Manager_pausedForBench {
        Debug_logMessage("DEBUG[0] Manager: resuming after bench (skipped " . Manager_pausedForBenchSkipped . " events)", 0)
        Manager_pausedForBench := False
      }
    }
    ;; Process shell events immediately. The previous Sleep,
    ;; %Config_shellMsgDelay% here was a workaround for transient popups
    ;; (issue #83 — Total Commander's TDLG2FILEACTIONMIN flashes during
    ;; file rename, etc.) — bug.n would tile the popup before it died,
    ;; leaving a gap. Two-phase commit handles this correctly: tile on
    ;; create, untile on destroy. Brief flicker for genuine phantoms is
    ;; preferable to a 350 ms latency penalty on every real window event.
    wndIds := ""
    t1 := A_TickCount
    a := isChanged := Manager_sync(wndIds)
    Debug_logMessage("DEBUG[3] Manager_onShellMessage: sync ms=" . (A_TickCount - t1) . " isChanged=" . isChanged . " wndIds=" . wndIds, 3)

    If isChanged
    {
      If Config_dynamicTiling
        View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
      Bar_updateView(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
    }

    If (Manager_monitorCount > 1 And a > -1)
    {
      WinGet, aWndId, ID, A
      WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
      m := Monitor_get(aWndX + aWndWidth / 2, aWndY + aWndHeight / 2)
      Debug_logMessage("DEBUG[1] Manager_onShellMessage: Manager_monitorCount: " Manager_monitorCount ", Manager_aMonitor: " Manager_aMonitor ", m: " m ", aWndId: " aWndId, 1)
      ;; The currently active window defines the active monitor.
      If m
        Manager_aMonitor := m
    }

    If wndIds
    {    ;; If there are new (unrecognized) windows, which are hidden ...
      If (Config_onActiveHiddenWnds = "view")
      {  ;; ... change the view to show the first hidden window
        wndId := SubStr(wndIds, 1, InStr(wndIds, ";") - 1)
        currentView := Monitor_#%Manager_aMonitor%_aView_#1
        prevView    := Monitor_#%Manager_aMonitor%_aView_#2
        Loop, % Config_viewCount
        {
          If (Window_#%wndId%_tags & 1 << A_Index - 1)
          {
            If Manager_isStaleViewBounce(A_Index, prevView, View_#%Manager_aMonitor%_#%currentView%_wndIds, wndId, lParam)
            {
              Debug_logMessage("DEBUG[3] Skipping stale bounce to view " . A_Index . ": " . lParam . " already on current view " . currentView, 3)
              Break
            }
            Debug_logMessage("DEBUG[3] Switching views because " . wndId . " is considered hidden and active", 3)
            ;; A newly created window defines the active monitor, if it is visible.
            Manager_aMonitor := Window_#%wndId%_monitor
            Monitor_activateView(A_Index)
            Break
          }
        }
      }
      Else
      {  ;; ... re-hide them
        StringTrimRight, wndIds, wndIds, 1
        StringSplit, wndId, wndIds, `;
        If (Config_onActiveHiddenWnds = "hide")
        {
          Loop, % wndId0
          {
            Window_hide(wndId%A_Index%)
          }
        }
        Else If (Config_onActiveHiddenWnds = "tag")
        {
          ;; ... or tag all of them for the current view.
          t := Monitor_#%Manager_aMonitor%_aView_#1
          Loop, % wndId0
          {
            wndId := wndId%A_Index%
            View_#%Manager_aMonitor%_#%t%_wndIds := wndId ";" View_#%Manager_aMonitor%_#%t%_wndIds
            View_setActiveWindow(Manager_aMonitor, t, wndId)
            Window_#%wndId%_tags += 1 << t - 1
          }
          Bar_updateView(Manager_aMonitor, t)
          If Config_dynamicTiling
            View_arrange(Manager_aMonitor, t)
        }
      }
    }

    If InStr(Manager_managedWndIds, lParam ";") {
      WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %lParam%
      If (Monitor_get(aWndX + aWndWidth / 2, aWndY + aWndHeight / 2) = Manager_aMonitor)
        View_setActiveWindow(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1, lParam)
      Else
        Manager_winActivate(View_getActiveWindow(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1))
      If Window_#%lParam%_isMinimized {
        Window_#%lParam%_isFloating := False
        Window_#%lParam%_isMinimized := False
        View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
      }
    }

    ;; This is a workaround for a redrawing problem of the bug.n bar, which
    ;; seems to get lost, when windows are created or destroyed under the
    ;; following conditions.
    If (Manager_monitorCount > 1) And (Config_verticalBarPos = "tray") {
      Loop, % (Manager_monitorCount - 1) {
        i := A_Index + 1
        Bar_updateLayout(i)
        Bar_updateStatic(i)
        Loop, % Config_viewCount
          Bar_updateView(i, A_Index)
      }
      Bar_updateStatus()
    }
    If (wParam = HSHELL_REDRAW) {
      WinGet, aWndId, ID, A
      action := Manager_barTitleAction(wParam, lParam, aWndId)
    } Else {
      action := "immediate"
    }
    Manager_barTitleDispatch(action)
    Perf_end("Manager_onShellMessage")

    ;; Defer orphan validation off the shell-event hot path. Using a
    ;; negative SetTimer interval makes this a one-shot; rapid bursts of
    ;; shell events naturally debounce because each call re-arms the same
    ;; label rather than queueing additional fires. Validate runs ~200 ms
    ;; after the last event and cleans up HWNDs whose WINDOWDESTROYED
    ;; was missed (event dropped during Manager_hideShow, force-killed
    ;; process, etc.). The timer label has a single-runner guard.
    Manager_armDebouncedTimer("Manager_validateAliveTimer", 200)
  }
  Perf_end("Manager_onShellMessage_full")
}

Manager_override(rule = "") {
  Local aWndId, aWndMinMax
  
  WinGet, aWndId, ID, A
  If (rule = "") {
    rule := Manager_getWindowRule(aWndId)
    InputBox, rule, bug.n: Override, % "Which rule should be applied?`n`n<is managed>;<m>;<tags>;<is floating>;<is decorated>;<hide title>;<action>",, 483, 152,,,,, % rule
    If Not (ErrorLevel = 0)
      Return
  }
  Manager_manage(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1, aWndId, rule)
  If Config_dynamicTiling
    View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
  Bar_updateView(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
}

;; Hooks Windows' EVENT_OBJECT_SHOW / EVENT_OBJECT_HIDE so we learn the moment
;; Shell_TrayWnd's visibility changes — whether bug.n drove the change (Win+B)
;; or something else did (explorer restart, session/display events, third-party
;; apps calling SHAppBarMessage). The cached Monitor_#%m%_showTaskBar flag is
;; reconciled in Manager_onObjectShowOrHide so the work area always reflects
;; what's actually on screen.
;;
;; Filtered to explorer.exe's PID at the kernel level so unrelated system show/
;; hide events (every popup, menu, tooltip on the box) never reach the AHK
;; message thread — a global hook is heavy enough to delay HSHELL_WINDOWCREATED
;; processing during window-spawn bursts (caught the bench failing on it). On
;; explorer restart the PID changes and the hook stops firing; TaskbarCreated
;; (broadcast to all top-level windows when explorer (re)starts) lets us
;; rebuild the hook in Manager_onTaskbarCreated.
Manager_registerTaskBarHook() {
  Global Manager_taskBarHook, Manager_taskBarHookCb, Manager_taskBarCreatedMsg

  If Not Manager_taskBarHookCb
    Manager_taskBarHookCb := RegisterCallback("Manager_onObjectShowOrHide", "F")

  If Not Manager_taskBarCreatedMsg {
    Manager_taskBarCreatedMsg := DllCall("RegisterWindowMessage", "Str", "TaskbarCreated")
    OnMessage(Manager_taskBarCreatedMsg, "Manager_onTaskbarCreated")
  }

  Process, Exist, explorer.exe
  explorerPid := ErrorLevel
  If Not explorerPid {
    Debug_logMessage("DEBUG[1] Manager_registerTaskBarHook: explorer.exe not running; will hook on TaskbarCreated", 1)
    Manager_taskBarHook := 0
    Return
  }

  Manager_taskBarHook := DllCall("SetWinEventHook"
    , "UInt", 0x8002          ;; EVENT_OBJECT_SHOW
    , "UInt", 0x8003          ;; EVENT_OBJECT_HIDE
    , "Ptr",  0               ;; hmodWinEventProc (NULL = out-of-context)
    , "Ptr",  Manager_taskBarHookCb
    , "UInt", explorerPid     ;; OS-level filter: only events from explorer.exe
    , "UInt", 0               ;; idThread (0 = all threads of explorerPid)
    , "UInt", 0)              ;; WINEVENT_OUTOFCONTEXT
  Debug_logMessage("DEBUG[1] Manager_registerTaskBarHook: hook=" . Manager_taskBarHook . " explorerPid=" . explorerPid, 1)
}

;; TaskbarCreated handler: explorer (re)started, so the PID our hook was bound
;; to is gone (or never existed). Tear down any stale hook and rebuild against
;; the new explorer process.
Manager_onTaskbarCreated(wParam, lParam, msg, hwnd) {
  Global Manager_taskBarHook

  If Manager_taskBarHook {
    DllCall("UnhookWinEvent", "Ptr", Manager_taskBarHook)
    Manager_taskBarHook := 0
  }
  Manager_registerTaskBarHook()
}

;; WinEventHook callback. With explorer-PID filtering at the kernel level,
;; the only events reaching us are explorer's own — but explorer owns plenty
;; beyond the taskbar (Start menu surface, jump lists, file-explorer windows)
;; so the class check is still required. Real work bounces to
;; Manager_taskBarSyncDeferred via a one-shot timer.
;;
;; Maps each taskbar event to a single monitor via the hwnd's center point so
;; the deferred sync only touches the affected monitor (matters for users with
;; "show taskbar on all displays" — a hide/show on one tray shouldn't reflow
;; the other).
Manager_onObjectShowOrHide(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) {
  Local wndClass, prevDetect, x, y, w, h, m

  ;; Window-level events only — skip controls, menus, accessibility children.
  If (idObject != 0)
    Return

  ;; HIDE fires after the window is hidden, so we may need to introspect a
  ;; hidden window to read its class and position.
  prevDetect := A_DetectHiddenWindows
  DetectHiddenWindows, On
  WinGetClass, wndClass, ahk_id %hwnd%
  If (wndClass != "Shell_TrayWnd" And wndClass != "Shell_SecondaryTrayWnd") {
    DetectHiddenWindows, %prevDetect%
    Return
  }
  WinGetPos, x, y, w, h, ahk_id %hwnd%
  DetectHiddenWindows, %prevDetect%

  m := Monitor_get(x + w / 2, y + h / 2)
  If (m <= 0)
    Return

  Manager_taskBarDirty |= (1 << (m - 1))
  Manager_armDebouncedTimer("Manager_taskBarSyncDeferred", 50)
}

Manager_registerShellHook() {
  Global Config_monitorDisplayChangeMessages

  WM_DISPLAYCHANGE := 126   ;; This message is sent when the display resolution has changed.
  Gui, +LastFound
  hWnd := WinExist()
  WinGetClass, wndClass, ahk_id %hWnd%
  WinGetTitle, wndTitle, ahk_id %hWnd%
  DllCall("RegisterShellHookWindow", "UInt", hWnd)    ;; Minimum operating systems: Windows 2000 (http://msdn.microsoft.com/en-us/library/ms644989(VS.85).aspx)
  Debug_logMessage("DEBUG[1] Manager_registerShellHook; hWnd: " . hWnd . ", wndClass: " . wndClass . ", wndTitle: " . wndTitle, 1)
  msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
  OnMessage(msgNum, "Manager_onShellMessage")
  If !(Config_monitorDisplayChangeMessages = "off" || Config_monitorDisplayChangeMessages = 0)
    OnMessage(WM_DISPLAYCHANGE, "Manager_onDisplayChange")
}
;; SKAN: How to Hook on to Shell to receive its messages? (http://www.autohotkey.com/forum/viewtopic.php?p=123323#123323)

;; EVENT_OBJECT_CREATE and EVENT_OBJECT_SHOW backstop for HSHELL_WINDOWCREATED
;; that the legacy RegisterShellHookWindow drops under load (#19). Some apps
;; (e.g. Teams) create their main window hidden and show it later; CREATE fires
;; while the window is invisible so WinGet-List misses it, but SHOW fires when
;; it becomes visible and gives us a second chance. Global hook (no PID filter)
;; — see Manager_registerTaskBarHook for the load-on-message-thread caveat.
;; WINEVENT_SKIPOWNPROCESS ensures bug.n's own hide/show (view switching) does
;; not feed back into the deferred sync. The bench is the gate: if pass rate
;; worsens with this hook installed, the volume is too high.
Manager_registerWindowCreateOrShowHook() {
  Global Manager_winCreateOrShowHook, Manager_winCreateOrShowHookCb

  If Not Manager_winCreateOrShowHookCb
    Manager_winCreateOrShowHookCb := RegisterCallback("Manager_onWindowCreateOrShow", "F")

  Manager_winCreateOrShowHook := DllCall("SetWinEventHook"
    , "UInt", 0x8000          ;; eventMin: EVENT_OBJECT_CREATE
    , "UInt", 0x8003          ;; eventMax: EVENT_OBJECT_HIDE (all four events handled in callback)
    , "Ptr",  0               ;; hmodWinEventProc (NULL = out-of-context)
    , "Ptr",  Manager_winCreateOrShowHookCb
    , "UInt", 0               ;; idProcess (0 = all processes)
    , "UInt", 0               ;; idThread (0 = all threads)
    , "UInt", 2)              ;; WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
  Debug_logMessage("DEBUG[1] Manager_registerWindowCreateOrShowHook: hook=" . Manager_winCreateOrShowHook, 1)
}

;; Pure decision for the EVENT_OBJECT_DESTROY branch below. True iff a
;; window bug.n is managing was just destroyed (window-level, not a
;; control/child object). Reads only Manager_managedWndIds (via
;; Manager_isManaged), so it is unit-testable without a live hook.
;;
;; Deliberately never consults GetAncestor: EVENT_OBJECT_DESTROY arrives
;; out-of-context, so by the time we run the window is gone and
;; GetAncestor returns 0. The old callback ran a GA_ROOT==self top-level
;; gate ahead of the destroy branch, which therefore rejected every real
;; destroy — with the legacy shell hook dropping HSHELL_WINDOWDESTROYED
;; under load (#19), nothing re-tiled after a close. Managed-list
;; membership is the authoritative signal: a hwnd only enters the list
;; after Manager_manage accepted it as a top-level managed window.
Manager_isManagedDestroy(event, idObject, idChild, hwnd) {
  If (event != 0x8001)              ;; EVENT_OBJECT_DESTROY
    Return False
  If (idObject != 0 Or idChild != 0)
    Return False
  Return (Manager_isManaged(hwnd) != "")
}

;; Pure decision for the "debounce with maxWait" pattern (canonical
;; reference: lodash's `_.debounce(fn, wait, { maxWait })`). Returns True
;; iff the caller should (re)arm the underlying SetTimer, False iff a
;; previously-armed timer should be left alone so it fires on schedule.
;;
;; Without the cap, AHK's `SetTimer, <label>, -N` debounce coalesces a
;; burst into a single fire — desirable for the common case — but each
;; event resets the one-shot to "fire N ms from now". Under sustained
;; arming activity the timer is pushed forward indefinitely and never
;; fires (#86 — alacritty unmanaged for 46 s on a busy machine until an
;; unrelated bug.n hotkey unblocked the timer).
;;
;; firstArmedTick is A_TickCount at the start of the current burst (0
;; when no timer is pending). maxDelayMs bounds worst-case fire latency
;; while preserving the in-burst coalesce benefit. maxDelayMs = 0 disables
;; the cap (naive debounce — default mode used by every other deferred
;; timer in Manager.ahk; opt in at a site by passing a positive value
;; when starvation becomes observable).
;;
;; Wraparound: A_TickCount is 32-bit and rolls over every ~49.7 days. A
;; negative delta indicates the wrap landed inside an active burst; treat
;; it the same as "cap exceeded" so the pending timer fires and the next
;; event starts a fresh burst in the new tick range.
Manager_shouldResetDebouncedTimer(firstArmedTick, now, maxDelayMs) {
  Local delta
  ;; `Not firstArmedTick` is the AHK idiom for "0 or uninitialized". In
  ;; expression mode `"" = 0` evaluates False (empty string isn't pure-
  ;; numeric — comparison falls back alphabetic), so a literal `= 0`
  ;; check would treat an uninitialized dynamic global as a stale tick
  ;; and refuse to ever re-arm. `Not` and `If` treat "" and 0 alike.
  If Not firstArmedTick
    Return True
  If Not maxDelayMs
    Return True
  delta := now - firstArmedTick
  If (delta < 0)
    Return False
  Return (delta < maxDelayMs)
}

;; Re-arm a debounced one-shot SetTimer, label-keyed, implementing the
;; lodash-style "debounce with maxWait" pattern via
;; Manager_shouldResetDebouncedTimer above. waitMs is the quiet period
;; after the last arm; maxWaitMs > 0 bounds worst-case fire latency at
;; roughly maxWaitMs regardless of further arms (use maxWaitMs = 0, the
;; default, for the naive form used by every other deferred timer in
;; Manager.ahk).
;;
;; Per-label state lives in dynamic globals named
;; Manager_debounceTick_<label> so callers can adopt this helper without
;; coordinating a global per timer. The matching label MUST call
;; Manager_clearDebouncedTimerArm(label) at entry so the next event after
;; the fire starts a fresh burst.
Manager_armDebouncedTimer(label, waitMs, maxWaitMs := 0) {
  Global
  Local tickKey, armCountKey, now
  ;; Side-channel arm counter for benches to verify the hook is actually
  ;; firing under load (see Bench_bgEventStorm). Unconditional because
  ;; AHK's RegisterCallback bridge doesn't reliably expose super-globals
  ;; to nested function calls, so a Manager_isBench gate here reads as
  ;; False from the hook path and the counter never updates. One global
  ;; increment per arm is negligible.
  armCountKey := "Bench_armCount_" . label
  %armCountKey% := (%armCountKey% + 0) + 1
  If (maxWaitMs > 0) {
    tickKey := "Manager_debounceTick_" . label
    now := A_TickCount
    If Not Manager_shouldResetDebouncedTimer(%tickKey%, now, maxWaitMs)
      Return
    ;; Same `Not` idiom as in shouldReset: uninitialized dynamic globals
    ;; read as "", which `= 0` does not match in expression mode.
    If Not %tickKey%
      %tickKey% := now
  }
  SetTimer, % label, % -waitMs
}

;; Clear the burst marker for a debounced timer armed via
;; Manager_armDebouncedTimer. Call from the timer's label at entry so the
;; next event after the fire starts a fresh burst. Only required when the
;; timer is armed with maxWaitMs > 0; naive-mode arms (maxWaitMs = 0)
;; record no tick, so flipping a label to a cap later just starts fresh
;; without inheriting stale state.
Manager_clearDebouncedTimerArm(label) {
  Global
  Local tickKey
  tickKey := "Manager_debounceTick_" . label
  %tickKey% := 0
}

;; WinEventHook callback. Filter cheaply, defer real work via SetTimer to
;; avoid Manager_manage on the message-thread hot path. Mirrors the mutex
;; gate in Manager_onShellMessage so production doesn't manage bench
;; windows during a coexistence-mutex window.
Manager_onWindowCreateOrShow(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) {
  Global Manager_isBench, Manager_pendingHideWndIds
  ;; CREATE (0x8000), DESTROY (0x8001), SHOW (0x8002), HIDE (0x8003).
  If (event != 0x8000 And event != 0x8001 And event != 0x8002 And event != 0x8003)
    Return
  ;; Window-level events only — skip controls, menus, accessibility children.
  If (idObject != 0 Or idChild != 0)
    Return
  ;; Coexistence with bugn-bench.exe (#19), same gate as Manager_onShellMessage.
  ;; Without `Global Manager_isBench` above, AHK's RegisterCallback bridge
  ;; doesn't expose super-globals — empty read would short-circuit the bench
  ;; on its own mutex. Confirmed empirically before adding the declaration.
  If (Not Manager_isBench) {
    benchHandle := DllCall("OpenMutex", "UInt", 0x00100000, "Int", 0, "Str", "Local\bug.n-bench-active", "Ptr")
    If benchHandle {
      DllCall("CloseHandle", "Ptr", benchHandle)
      Return
    }
  }
  ;; EVENT_OBJECT_DESTROY backstop for HSHELL_WINDOWDESTROYED drops under
  ;; load (#19). Decided before the GetAncestor gate below — a destroyed
  ;; window is already gone, so that gate would reject every real destroy
  ;; (see Manager_isManagedDestroy for the full rationale).
  If (event = 0x8001) {
    If Manager_isManagedDestroy(event, idObject, idChild, hwnd) {
      Debug_logMessage("DEBUG[1] Manager_onWindowCreateOrShow: DESTROY managed hwnd=" . hwnd . " -- arming validateAlive", 1)
      Manager_armDebouncedTimer("Manager_validateAliveTimer", 200)
    }
    Return
  }
  ;; Skip non-top-level windows for the remaining live-window events
  ;; (CREATE/SHOW/HIDE still exist, so GetAncestor is reliable). GA_ROOT == 2.
  If (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)
    Return
  If (event = 0x8003) {
    ;; EVENT_OBJECT_HIDE: distinguish our hide (view-switching) from an
    ;; app hiding itself. See Manager_classifyHideEvent for the decision
    ;; matrix; this branch is just dispatch. Raw hwnd flows through —
    ;; Manager_isManaged inside the classifier canonicalizes against the
    ;; stored format (hex or decimal).
    If (Manager_classifyHideEvent(hwnd) = "queue")
      Manager_armDebouncedTimer("Manager_winHideDeferred", 50)
    Return
  }
  ;; CREATE or SHOW. Defer via Manager_armDebouncedTimer with a 250 ms
  ;; maxWait cap so sustained cross-process CREATE/SHOW activity can't
  ;; starve the sync (#86). The cap is the only site in the file that
  ;; opts in to maxWait — every other arm uses the naive default of 0.
  Manager_armDebouncedTimer("Manager_winCreateOrShowDeferred", 50, 250)
}

Manager_resetMonitorConfiguration() {
  Local GuiN, hWnd, i, j, m, mPrimary, wndClass, wndIds, wndTitle

  Debug_logMessage("DEBUG[6] resetMonitorConfig: entry, monitorCount=" . Manager_monitorCount, 6)
  m := Manager_monitorCount
  SysGet, Manager_monitorCount, MonitorCount
  Debug_logMessage("DEBUG[6] resetMonitorConfig: old=" . m . " new=" . Manager_monitorCount, 6)
  If (Manager_monitorCount < m) {
    ;; A monitor has been disconnected. Which one?
    Debug_logMessage("DEBUG[6] resetMonitorConfig: branch=disconnect", 6)
    i := Monitor_find(-1, m)
    If (i > 0) {
      SysGet, mPrimary, MonitorPrimary
      GuiN := (m - 1) + 1
      Gui, %GuiN%: Destroy
      Loop, % Config_viewCount {
        If View_#%i%_#%A_Index%_wndIds {
          View_#%mPrimary%_#%A_Index%_wndIds .= View_#%i%_#%A_Index%_wndIds
          StringTrimRight, wndIds, View_#%i%_#%A_Index%_wndIds, 1
          Loop, PARSE, wndIds, `;
          {
            Window_#%A_LoopField%_monitor := mPrimary
          }
          If (Manager_aMonitor = i)
            Manager_aMonitor := mPrimary
        }
      }
      Loop, % m - i {
        j := i + A_Index
        Monitor_moveToIndex(j, j - 1)
        Debug_logMessage("DEBUG[6] resetMonitorConfig: disconnect Bar_init(" . (j-1) . ") start", 6)
        Monitor_getWorkArea(j - 1)
        Bar_init(j - 1)
        Debug_logMessage("DEBUG[6] resetMonitorConfig: disconnect Bar_init(" . (j-1) . ") done", 6)
      }
    }
  } Else If (Manager_monitorCount > m) {
    ;; A monitor has been connected. Where has it been put?
    Debug_logMessage("DEBUG[6] resetMonitorConfig: branch=connect", 6)
    i := Monitor_find(+1, Manager_monitorCount)
    If (i > 0) {
      Loop, % Manager_monitorCount - i {
        j := Manager_monitorCount - A_Index
        Monitor_moveToIndex(j, j + 1)
        Debug_logMessage("DEBUG[6] resetMonitorConfig: connect Bar_init(" . (j+1) . ") start", 6)
        Monitor_getWorkArea(j + 1)
        Bar_init(j + 1)
        Debug_logMessage("DEBUG[6] resetMonitorConfig: connect Bar_init(" . (j+1) . ") done", 6)
      }
      Debug_logMessage("DEBUG[6] resetMonitorConfig: connect Monitor_init(" . i . ") start", 6)
      Monitor_init(i, True)
      Debug_logMessage("DEBUG[6] resetMonitorConfig: connect Monitor_init(" . i . ") done", 6)
    }
  } Else {
    ;; Has the resolution of a monitor been changed?
    mmngr2 := New MonitorManager()
    Loop, % Manager_monitorCount {
      Monitor_getWorkArea(A_Index)
      Debug_logMessage("DEBUG[6] MonitorW: " . Monitor_#%A_Index%_width . ", MMW1: " . mmngr1.monitors[A_Index].width . ", MM1dpiX: " . mmngr1.monitors[A_Index].dpiX . ", MM1scaleX: " . mmngr1.monitors[A_Index].scaleX . ", MMW2: " . mmngr2.monitors[A_Index].width . ", MM2dpiX: " . mmngr2.monitors[A_Index].dpiX . ", MM2scaleX: " . mmngr2.monitors[A_Index].scaleX, 6)
      Debug_logMessage("DEBUG[6] resetMonitorConfig: else Bar_init(" . A_Index . ") start", 6)
      Bar_init(A_Index)
      Debug_logMessage("DEBUG[6] resetMonitorConfig: else Bar_init(" . A_Index . ") done", 6)
    }
    mmngr2 := ""
  }
  Debug_logMessage("DEBUG[6] resetMonitorConfig: saveState start", 6)
  Manager_saveState()
  Debug_logMessage("DEBUG[6] resetMonitorConfig: saveState done", 6)
  Loop, % Manager_monitorCount {
    Debug_logMessage("DEBUG[6] resetMonitorConfig: View_arrange(" . A_Index . ") start", 6)
    View_arrange(A_Index, Monitor_#%A_Index%_aView_#1)
    Debug_logMessage("DEBUG[6] resetMonitorConfig: View_arrange(" . A_Index . ") done", 6)
    Debug_logMessage("DEBUG[6] resetMonitorConfig: Bar_updateView(" . A_Index . ") start", 6)
    Bar_updateView(A_Index, Monitor_#%A_Index%_aView_#1)
    Debug_logMessage("DEBUG[6] resetMonitorConfig: Bar_updateView(" . A_Index . ") done", 6)
  }
  Debug_logMessage("DEBUG[6] resetMonitorConfig: restoreWindowState start", 6)
  Manager__restoreWindowState(Main_autoWindowState)
  Debug_logMessage("DEBUG[6] resetMonitorConfig: restoreWindowState done", 6)
  Bar_updateStatus()
  Bar_updateTitle()

  Gui, +LastFound
  hWnd := WinExist()
  WinGetClass, wndClass, ahk_id %hWnd%
  WinGetTitle, wndTitle, ahk_id %hWnd%
  DllCall("RegisterShellHookWindow", "UInt", hWnd)    ;; Minimum operating systems: Windows 2000 (http://msdn.microsoft.com/en-us/library/ms644989(VS.85).aspx)
  Debug_logMessage("DEBUG[1] Manager_registerShellHook; hWnd: " . hWnd . ", wndClass: " . wndClass . ", wndTitle: " . wndTitle, 1)
}

Manager_restoreWindowBorders()
{
  Local ncm, ncmSize

  If Config_selBorderColor
    DllCall("SetSysColors", "Int", 1, "Int*", 10, "UInt*", Manager_normBorderColor)
  If (Config_borderWidth > 0) Or (Config_borderPadding >= 0 And A_OSVersion = "WIN_VISTA")
  {
    ncmSize := VarSetCapacity(ncm, 4 * (A_OSVersion = "WIN_VISTA" ? 11 : 10) + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), 0)
    NumPut(ncmSize, ncm, 0, "UInt")
    DllCall("SystemParametersInfo", "UInt", 0x0029, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
    If (Config_borderWidth > 0)
      NumPut(Manager_borderWidth, ncm, 4, "Int")
    If (Config_borderPadding >= 0 And A_OSVersion = "WIN_VISTA")
      NumPut(Manager_borderPadding, ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
    DllCall("SystemParametersInfo", "UInt", 0x002a, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
  }
}

;; Parses one persisted "Window ..." line from _WindowState.ini into its
;; columns. Returns True if the line has >= 8 fields, False otherwise.
;; Accepts both the current 8-column format and the legacy 9-column format
;; (which carried a trailing title field that restore never read back).
Manager__parseSavedWindowLine(line, ByRef wndId, ByRef processName, ByRef monitor, ByRef tags, ByRef isFloating, ByRef isDecorated, ByRef hideTitle, ByRef isManaged) {
  Local items0, items1, items2, items3, items4, items5, items6, items7, items8
  StringSplit, items, line, `;
  If (items0 < 8)
    Return False
  wndId       := items1
  processName := items2
  monitor     := items3
  tags        := items4
  isFloating  := items5
  isDecorated := items6
  hideTitle   := items7
  isManaged   := items8
  Return True
}

;; Restore previously saved window state.
;; If the state is completely different, this function won't do much. However, if restoring from a crash
;; or simply restarting bug.n, it should completely recover the window state.
Manager__restoreWindowState(filename) {
  Local vidx, widx, i, j, m, v, candidate_set, detectHidden, view_set, excluded_view_set, view_m0, view_v0, view_list0, wnds0, items0, wndId, expectedPName, wndPName, view_var, isManaged, isFloating, isDecorated, hideTitle, ruleIsManaged, ruleM, ruleTags, ruleIsFloating, ruleIsDecorated, ruleHideTitle, ruleAction

  If Not FileExist(filename)
    Return

  widx := 1
  vidx := 1

  view_set := ""
  excluded_view_set := ""

  ;; Read all interesting things from the file.
  Loop, READ, %filename%
  {
    If (SubStr(A_LoopReadLine, 1, 5) = "View_") {
      i := InStr(A_LoopReadLine, "#")
      j := InStr(A_LoopReadLine, "_", false, i)
      m := SubStr(A_LoopReadLine, i + 1, j - i - 1)
      i := InStr(A_LoopReadLine, "#", false, j)
      j := InStr(A_LoopReadLine, "_", false, i)
      v := SubStr(A_LoopReadLine, i + 1, j - i - 1)

      i := InStr(A_LoopReadLine, "=", j + 1)


      If (m <= Manager_monitorCount) And ( v <= Config_viewCount ) {
        view_list%vidx% := SubStr(A_LoopReadLine, i + 1)
        view_m%vidx% := m
        view_v%vidx% := v
        view_set := view_set . view_list%vidx%
        vidx := vidx + 1
      } Else {
        excluded_view_set := excluded_view_set . view_list%vidx%
        Debug_logMessage("View (" . m . ", " . v . ") is no longer available (" . vidx . ")", 0)
      }
    } Else If (SubStr(A_LoopReadLine, 1, 7) = "Window ") {
      wnds%widx% := SubStr(A_LoopReadLine, 8)
      widx := widx + 1
    }
  }

  ;Debug_logMessage("view_set: " . view_set, 1)
  ;Debug_logMessage("excluded_view_set: " . excluded_view_set, 1)

  candidate_set := ""

  ; Scan through all defined windows. Create a candidate set of windows based on whether the properties of existing windows match.
  Loop, % (widx - 1) {
    If Not Manager__parseSavedWindowLine(wnds%A_Index%, wndId, expectedPName, m, v, isFloating, isDecorated, hideTitle, isManaged) {
      Debug_logMessage("Window '" . wnds%A_Index% . "' could not be processed due to parse error", 0)
      Continue
    }

    detectHidden := A_DetectHiddenWindows
    DetectHiddenWindows, On
    WinGet, wndPName, ProcessName, ahk_id %wndId%
    DetectHiddenWindows, %detectHidden%
    If Not ( expectedPName = wndPName ) {
      Debug_logMessage("Window ahk_id " . wndId . " process '" . wndPName . "' doesn't match expected '" . expectedPName . "', forgetting this window", 0)
      Continue
    }

    ;; Re-apply current rules — a rule added since this state was saved may now exclude this window.
    ;; DetectHiddenWindows must be On so WinGetClass/WinGetTitle inside Manager_applyRules
    ;; can read the class and title of windows that bug.n has hidden on inactive views.
    DetectHiddenWindows, On
    Manager_applyRules(wndId, ruleIsManaged, ruleM, ruleTags, ruleIsFloating, ruleIsDecorated, ruleHideTitle, ruleAction)
    DetectHiddenWindows, %detectHidden%
    If Not ruleIsManaged {
      Debug_logMessage("Window ahk_id " . wndId . " excluded by current rules during state restore, skipping.", 0)
      Continue
    }

    ; If Managed
    If ( isManaged ) {
      If ( InStr(view_set, wndId) = 0) {
        If ( InStr(excluded_view_set, wndId) )
          Debug_logMessage("Window ahk_id " . wndId . " is being ignored because it no longer belongs to an active view", 0)
        Else
          Debug_logMessage("Window ahk_id " . wndId . " is being ignored because it doesn't exist in any views", 0)
        Continue
      }
    }

    ; Set up the window.
    Manager__setWinProperties(wndId, isManaged, m, v, isDecorated, isFloating, hideTitle )
    ;Window_hide(wndId)

    candidate_set := candidate_set . wndId . ";"
  }

  ;Debug_logMessage("candidate_set: " . candidate_set, 1)

  ; Set up all views. Must filter the window list by those from the candidate set.
  Loop, % (vidx - 1) {
    StringSplit, items, view_list%A_Index%, `;
    view_set := ""
    Loop, % (items0 - 1) {
      If ( items%A_Index% And InStr(candidate_set, items%A_Index% ) > 0 )
        view_set := view_set . items%A_Index% . ";"
    }
    view_var := "View_#" . view_m%A_Index% . "_#" . view_v%A_Index% . "_wndIds"
    %view_var% := view_set
  }
}

Manager_saveState() {
  Critical
  Global Config_filePath, Config_viewCount, Main_autoLayout, Main_autoWindowState, Manager_isBench, Manager_layoutDirty, Manager_monitorCount, Manager_windowsDirty

  ;; Bench mode must never persist session state: the maintenance timer fires during runs and would overwrite the user's real _Layout.ini / _WindowState.ini.
  If Manager_isBench
    Return

  Debug_logMessage("DEBUG[2] Manager_saveState", 2)

  ;; @TODO: Check for changes to the layout.
  ;If Manager_layoutDirty {
    Debug_logMessage("DEBUG[2] Manager_saveState: " Main_autoLayout, 2)
    Config_saveSession(Config_filePath, Main_autoLayout)
    Manager_layoutDirty := 0
  ;}

  ;; @TODO: Check for changes to windows.
  ;If Manager_windowsDirty {
    Debug_logMessage("DEBUG[2] Manager_saveState: " Main_autoWindowState, 2)
    Manager_saveWindowState(Main_autoWindowState, Manager_monitorCount, Config_viewCount)
    Manager_windowsDirty := 0
  ;}
}

Manager_saveWindowState(filename, nm, nv) {
  Local allWndId0, allWndIds, detectHidden, wndPName, text, monitor, wndId, view, isManaged, isTitleHidden

  text := "; bug.n - tiling window management`n; @version " VERSION "`n`n"

  tmpfname := filename . ".tmp"
  FileDelete, %tmpfname%

  ; Dump window ID and process name. If these two don't match an existing process, we won't try
  ;   to recover that window.
  StringTrimRight, allWndIds, Manager_allWndIds, 1
  StringSplit, allWndId, allWndIds, `;
  detectHidden := A_DetectHiddenWindows
  DetectHiddenWindows, On
  Debug_logMessage("DEBUG[3] Manager_saveWindowState: loop start wndCount=" . allWndId0, 3)
  Loop, % allWndId0 {
    wndId := allWndId%A_Index%

    ;; Prune ghost handles (abnormal kills never fire WINDOWDESTROYED) so _WindowState.ini self-heals.
    If Not WinExist("ahk_id " . wndId) {
      StringReplace, Manager_allWndIds, Manager_allWndIds, %wndId%`;,
      Continue
    }

    WinGet, wndPName, ProcessName, ahk_id %wndId%

    ; wndId;processName;Monitor;Tags;Floating;Decorated;HideTitle;Managed

    isManaged := InStr(Manager_managedWndIds, wndId . ";")
    isTitleHidden := InStr(Bar_hideTitleWndIds, wndId . ";")

    text .= "Window " . wndId . ";" . wndPName . ";"
    If isManaged
      text .= Window_#%wndId%_monitor . ";" . Window_#%wndId%_tags . ";" . Window_#%wndId%_isFloating . ";" . Window_#%wndId%_isDecorated . ";"
    Else
      text .= ";;;;"
    text .= isTitleHidden . ";" . isManaged . "`n"
  }
  DetectHiddenWindows, %detectHidden%

  text .= "`n"

  ;; Dump window arrangements on every view. If some views or monitors have disappeared, leave their
  ;;   corresponding windows alone.

  Loop, % nm {
    monitor := A_Index
    Loop, % nv {
      view := A_Index
      ;; Dump all view window lists
      text .= "View_#" . monitor . "_#" . view . "_wndIds=" . View_#%monitor%_#%view%_wndIds . "`n"
    }
  }

  FileAppend, %text%, %tmpfname%
  If ErrorLevel {
    If FileExist(tmpfname)
      FileDelete, %tmpfname%
  } Else
    FileMove, %tmpfname%, %filename%, 1
}

;; Manager_setCursor lives in src/Manager_setCursor.ahk so tests can
;; stub it out. See tests/README.md for the stub-swap pattern.

;; Pops a +AlwaysOnTop custom Gui (matching the Help_show pattern at
;; Help.ahk:38) for the user to type a new name for the active view.
;; AHK's InputBox is unreliable in this code path: it inherits the
;; calling thread's (non-foreground) process state, hits Win11's
;; foreground-lock, can pop behind other AlwaysOnTop windows, and
;; carries a generic #32770 class that bug.n's window-event hook
;; would otherwise try to manage. A named Gui ("RenameView") with
;; a unique window title (bug.n_RENAME) sidesteps all of that.
;;
;; Asynchronous by design: this function shows the dialog and
;; returns. The actual mutation + bar rebuild happens in the
;; Manager_renameViewSubmit label when the user hits Enter / clicks OK.
Manager_renameView() {
  Global
  Local m, mX, mY, mW, mH, popupH, popupW, x, y, current

  Manager_renameView_aView := Monitor_#%Manager_aMonitor%_aView_#1
  current := Config_viewNames_#%Manager_renameView_aView%

  Gui, RenameView: Default
  Gui, +LabelManager_renameViewGui
  Gui, Destroy
  Gui, +LastFound -Caption +ToolWindow +AlwaysOnTop +Border +OwnDialogs +HwndManager_renameView_hwnd
  Gui, Color, %Config_backColor_#1_#3%
  Gui, Margin, 16, 16
  Gui, Font, c%Config_fontColor_#1_#3% s%Config_fontSize%, %Config_fontName%
  Gui, Add, Text, , % "Rename view " . Manager_renameView_aView . ":"
  Gui, Add, Edit, w300 vManager_renameView_input, %current%
  Gui, Add, Button, Default w80 gManager_renameViewSubmit, OK
  Gui, Add, Button, x+10 w80 gManager_renameViewCancel, Cancel

  m := Manager_aMonitor
  mX := Monitor_#%m%_x
  mY := Monitor_#%m%_y
  mW := Monitor_#%m%_width
  mH := Monitor_#%m%_height
  popupW := 332
  popupH := 110
  x := mX + (mW - popupW) / 2
  y := mY + (mH - popupH) / 2

  Gui, Show, x%x% y%y% w%popupW% h%popupH%, bug.n_RENAME
  GuiControl, Focus, Manager_renameView_input

  ;; GuiEscape doesn't fire reliably on Win11 for a -Caption +ToolWindow
  ;; Gui hosting an editable Edit (the Edit captures Esc before it
  ;; bubbles to the Gui's WM_COMMAND IDCANCEL handler). Bind Esc
  ;; explicitly while the dialog is the active window.
  Manager_setScopedHotkey(Manager_renameView_hwnd, "Esc", "Manager_renameViewCancel")
}

;; Common dismissal: tear down the Gui and release the per-dialog
;; Esc hotkey so it doesn't fire stray Cancels in other contexts.
Manager_renameView_dismiss() {
  Global Manager_renameView_hwnd
  Gui, RenameView: Default
  Gui, Destroy
  Manager_clearScopedHotkey(Manager_renameView_hwnd, "Esc")
}

;; Bind <key> to <handler> while the window <hwnd> is active.
;; Pairs the Hotkey IfWinActive directive with a reset so subsequent
;; Hotkey commands anywhere in the process aren't accidentally scoped
;; to <hwnd>. Use Manager_clearScopedHotkey to remove the binding.
;;
;; Without the pairing, a forgotten Hotkey IfWinActive lingers and
;; silently scopes every subsequent Hotkey registration to a window
;; that may no longer exist (caught by Copilot review on PR #70).
Manager_setScopedHotkey(hwnd, key, handler) {
  Hotkey, IfWinActive, % "ahk_id " . hwnd
  Hotkey, %key%, %handler%, On
  Hotkey, IfWinActive
}

Manager_clearScopedHotkey(hwnd, key) {
  Hotkey, IfWinActive, % "ahk_id " . hwnd
  Hotkey, %key%, , Off
  Hotkey, IfWinActive
}

;; OK button / Enter key. Reads the edit, dismisses the Gui, applies
;; the rename and rebuilds bars on success.
Manager_renameViewSubmit:
  Gui, RenameView: Default
  Gui, Submit, NoHide
  Manager_renameView_dismiss()
  If Manager_applyViewRename(Manager_renameView_aView, Manager_renameView_input) {
    Loop, % Manager_monitorCount
      Bar_init(A_Index)
    Loop, % Manager_monitorCount {
      Bar_updateView(A_Index, Monitor_#%A_Index%_aView_#1)
      Bar_updateLayout(A_Index)
    }
    Bar_updateStatus()
    Bar_updateTitle()
  }
Return

;; Cancel button.
Manager_renameViewCancel:
  Manager_renameView_dismiss()
Return

;; +LabelManager_renameViewGui auto-routes Escape and Close to these
;; labels (mirrors the Help_GuiEscape / Help_GuiClose pattern).
;; GuiEscape is unreliable on Win11 for our config — Esc is bound
;; explicitly above as a per-dialog hotkey — but keep this label in
;; case AHK's bubble-up ever does fire.
Manager_renameViewGuiEscape:
  Manager_renameView_dismiss()
Return

Manager_renameViewGuiClose:
  Manager_renameView_dismiss()
Return

;; Pure post-dialog half of Manager_renameView, exposed for Yunit and
;; for Bench_runRename. Validates input, mutates Config_viewNames_#aView,
;; sets Manager_layoutDirty. Returns True if applied.
Manager_applyViewRename(aView, newName) {
  Global
  Local current

  current := Config_viewNames_#%aView%
  If (newName = "")
    Return False
  If (newName = current)
    Return False

  Config_viewNames_#%aView% := newName
  Manager_layoutDirty := 1
  Return True
}

Manager_setViewMonitor(i, d = 0) {
  Local aView, aWndId, v, wndIds

  aView := Monitor_#%Manager_aMonitor%_aView_#1
  If (Manager_monitorCount > 1) And View_#%Manager_aMonitor%_#%aView%_wndIds {
    If (i = 0)
      i := Manager_aMonitor
    i := Manager_loop(i, d, 1, Manager_monitorCount)
    v := Monitor_#%i%_aView_#1
    View_#%i%_#%v%_wndIds := View_#%Manager_aMonitor%_#%aView%_wndIds View_#%i%_#%v%_wndIds

    StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%aView%_wndIds, 1
    Loop, PARSE, wndIds, `;
    {
      Loop, % Config_viewCount {
        StringReplace, View_#%Manager_aMonitor%_#%A_Index%_wndIds, View_#%Manager_aMonitor%_#%A_Index%_wndIds, %A_LoopField%`;,
        StringReplace, View_#%Manager_aMonitor%_#%A_Index%_aWndIds, View_#%Manager_aMonitor%_#%A_Index%_aWndIds, %A_LoopField%`;,
      }
      Window_#%A_LoopField%_monitor := i
      Window_#%A_LoopField%_tags := 1 << v - 1
    }
    View_arrange(Manager_aMonitor, aView)
    Loop, % Config_viewCount {
      Bar_updateView(Manager_aMonitor, A_Index)
    }

    ;; Manually set the active monitor.
    Manager_aMonitor := i
    View_arrange(i, v)
    WinGet, aWndId, ID, A
    Manager_winActivate(aWndId)
    Bar_updateView(i, v)
  }
}

Manager_setWindowBorders()
{
  Local ncm, ncmSize

  If Config_selBorderColor
  {
    SetFormat, Integer, hex
    Manager_normBorderColor := DllCall("GetSysColor", "Int", 10)
    SetFormat, Integer, d
    DllCall("SetSysColors", "Int", 1, "Int*", 10, "UInt*", Config_selBorderColor)
  }
  If (Config_borderWidth > 0) Or (Config_borderPadding >= 0 And A_OSVersion = "WIN_VISTA")
  {
    ncmSize := VarSetCapacity(ncm, 4 * (A_OSVersion = "WIN_VISTA" ? 11 : 10) + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), 0)
    NumPut(ncmSize, ncm, 0, "UInt")
    DllCall("SystemParametersInfo", "UInt", 0x0029, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
    Manager_borderWidth := NumGet(ncm, 4, "Int")
    Manager_borderPadding := NumGet(ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
    If (Config_borderWidth > 0)
      NumPut(Config_borderWidth, ncm, 4, "Int")
    If (Config_borderPadding >= 0 And A_OSVersion = "WIN_VISTA")
      NumPut(Config_borderPadding, ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
    DllCall("SystemParametersInfo", "UInt", 0x002a, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
  }
}

Manager_setWindowMonitor(i, d = 0) {
  Local aWndId, v

  WinGet, aWndId, ID, A
  If (Manager_monitorCount > 1 And InStr(Manager_managedWndIds, aWndId ";")) {
    Loop, % Config_viewCount {
      StringReplace, View_#%Manager_aMonitor%_#%A_Index%_wndIds, View_#%Manager_aMonitor%_#%A_Index%_wndIds, %aWndId%`;,
      StringReplace, View_#%Manager_aMonitor%_#%A_Index%_aWndIds, View_#%Manager_aMonitor%_#%A_Index%_aWndIds, %aWndId%`;, All
      Bar_updateView(Manager_aMonitor, A_Index)
    }
    If Config_dynamicTiling
      View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)

    ;; Manually set the active monitor.
    If (i = 0)
      i := Manager_aMonitor
    Manager_aMonitor := Manager_loop(i, d, 1, Manager_monitorCount)
    Window_#%aWndId%_monitor := Manager_aMonitor
    v := Monitor_#%Manager_aMonitor%_aView_#1
    Window_#%aWndId%_tags := 1 << v - 1
    View_#%Manager_aMonitor%_#%v%_wndIds := aWndId ";" View_#%Manager_aMonitor%_#%v%_wndIds
    View_setActiveWindow(Manager_aMonitor, v, aWndId)
    If Config_dynamicTiling
      View_arrange(Manager_aMonitor, v)
    Manager_winActivate(aWndId)
    Bar_updateView(Manager_aMonitor, v)
  }
}

Manager_sizeWindow() {
  Local aWndId, SC_SIZE, WM_SYSCOMMAND

  WinGet, aWndId, ID, A
  If InStr(Manager_managedWndIds, aWndId . ";") And Not Window_#%aWndId%_isFloating
    View_toggleFloatingWindow(aWndId)
  Window_set(aWndId, "Top", "")

  WM_SYSCOMMAND = 0x112
  SC_SIZE       = 0xF000
  SendMessage, WM_SYSCOMMAND, SC_SIZE, , , ahk_id %aWndId%
}

;; No windows are known to the system yet.
;; Try to do something smart with the initial layout.
Manager_initial_sync(doRestore) {
  Local wndId, wndId0, wnd, wndX, wndY, wndW, wndH, x, y, m, len

  ;; Initialize lists
  ;; Note that these variables make this function non-reentrant.
  Loop, % Manager_monitorCount
    Manager_initial_sync_m#%A_Index%_wndList := ""

  ;; Use saved window placement settings to first determine
  ;;   which monitor/view a window should be attached to.
  If doRestore
    Manager__restoreWindowState(Main_autoWindowState)

  ;; Check all remaining visible windows against the known windows
  WinGet, wndId, List, , ,
  Loop, % wndId {
    ;; Based on some analysis here, determine which monitors and layouts would best
    ;; serve existing windows. Do not override configuration settings.

    ;; Which monitor is it on?
    wnd := wndId%A_Index%
    WinGetPos, wndX, wndY, wndW, wndH, ahk_id %wnd%

    x := wndX + wndW/2
    y := wndY + wndH/2

    m := Monitor_get(x, y)
    If m > 0
      Manager_initial_sync_m#%m%_wndList .= wndId%A_Index% ";"

  }

  Loop, % Manager_monitorCount {
    m := A_Index
    StringTrimRight, wndIds, Manager_initial_sync_m#%m%_wndList, 1
    StringSplit, wndId, wndIds, `;
    Loop, % wndId0
      Manager_manage(m, 1, wndId%A_Index%)
  }
}

;; Pure classifier for Manager_sync's "already managed but reactivated"
;; branch. Extracted so tests can pin this gate without faking WinGet.
;; Reports True only when wndId is the active window and not hung —
;; matches the loop's intent ("was brought into focus by something").
Manager_syncShouldReportActive(wndId, activeId, isHung) {
  Return (wndId = activeId) And (Not isHung)
}

;; Pure classifier for the Config_onActiveHiddenWnds="view" branch of
;; Manager_onShellMessage (#43). Reports True when a candidate view
;; switch is a stale echo of our own reveal — the shell event arrived
;; for a window we just made visible on the current view, after
;; Manager_hideShow cleared but before HSHELL stopped firing.
;;
;; Stale requires all three:
;;   1. candidate view equals the one we just left (aView_#2),
;;   2. the new-hidden window sync flagged IS the shell event source
;;      (wndId == lParam) — otherwise the event is unrelated to what
;;      sync found and tells us nothing about whether to switch,
;;   3. the event source already lives in the current view's wndIds.
;;
;; Wrap currentViewWndIds with ";" delimiters so the membership test
;; can't match a suffix substring (e.g. lParam=7890 falsely matching
;; "67890;").
Manager_isStaleViewBounce(candidateView, prevView, currentViewWndIds, wndId, lParam) {
  Return (candidateView = prevView)
    And (wndId = lParam)
    And InStr(";" . currentViewWndIds, ";" . lParam . ";")
}

;; @todo: This constantly tries to re-add windows that are never going to be manageable.
;;   Manager_manage should probably ignore all windows that are already in Manager_allWndIds.
;;   The problem was, that i. a. claws-mail triggers Manager_sync, but the application window
;;   would not be ready for being managed, i. e. class and title were not available. Therefore more
;;   attempts were needed.
;;   Perhaps this method can be refined by not adding any window to Manager_allWndIds, but only
;;   those, which have at least a title or class.
Manager_sync(ByRef wndIds = "")
{
  Local a, activeId, flag, shownWndIds, v, wndId
  Perf_start("Manager_sync")
  a := 0

  WinGet, activeId, ID, A
  shownWndIds := ""
  Loop, % Manager_monitorCount
  {
    v := Monitor_#%A_Index%_aView_#1
    shownWndIds .= View_#%A_Index%_#%v%_wndIds
  }
  ;; Classify newly-appeared visible windows; note already-managed
  ;; windows that gained focus (returned via wndIds for the activation
  ;; handling in Manager_onShellMessage). Orphan cleanup is no longer
  ;; performed here -- it's the responsibility of Manager_validateAlive,
  ;; scheduled deferred via Manager_validateAliveTimer 200 ms after
  ;; shell events.
  WinGet, wndId, List, , ,
  Loop, % wndId
  {
    If Not InStr(shownWndIds, wndId%A_Index% ";")
    {
      If Not InStr(Manager_managedWndIds, wndId%A_Index% ";")
      {
        flag := Manager_manage(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1, wndId%A_Index%)
        If flag
          a := 1
      }
      Else If Manager_syncShouldReportActive(wndId%A_Index%, activeId, Window_isHung(wndId%A_Index%))
      {
        ;; This is a window that is already managed but was brought into focus by something.
        ;; Maybe it would be useful to do something with it.
        wndIds .= wndId%A_Index% ";"
      }
    }
  }

  Perf_end("Manager_sync")
  Return, a
}

;; Manager_validateAlive: walk every managed HWND across all views and
;; unmanage any whose window no longer exists. Catches orphans where
;; the WINDOWDESTROYED event was missed (e.g. while Manager_hideShow=True
;; mid-arrange, or for force-killed processes that don't fire clean
;; shell events).
;;
;; Scheduled via Manager_validateAliveTimer (deferred -200 ms after
;; shell events) so this work happens off the shell-event hot path
;; rather than synchronously inside Manager_sync. Returns the set of
;; affected monitors as a ";m1;m2;" string (or "" if nothing pruned);
;; caller iterates that set and arranges/refreshes each monitor's
;; visible view. Pre-#59 returned a bool and the timer blindly
;; re-arranged Manager_aMonitor, missing sibling monitors that owned
;; the dead windows.
Manager_validateAlive() {
  Local affected, deadWndIds, m, mgrTrimmed, prevDetect

  Perf_start("Manager_validateAlive")
  affected := ""
  prevDetect := A_DetectHiddenWindows
  DetectHiddenWindows, On
  deadWndIds := ""
  StringTrimRight, mgrTrimmed, Manager_managedWndIds, 1
  Loop, PARSE, mgrTrimmed, `;
  {
    If A_LoopField And Not WinExist("ahk_id " . A_LoopField)
      deadWndIds .= A_LoopField . ";"
  }
  DetectHiddenWindows, %prevDetect%
  StringTrimRight, deadWndIds, deadWndIds, 1
  Loop, PARSE, deadWndIds, `;
  {
    If Not A_LoopField
      Continue
    m := Manager_unmanage(A_LoopField)
    If m And Not InStr(affected, ";" m ";")
      affected .= ";" m ";"
  }
  Perf_end("Manager_validateAlive")
  Return affected
}

;; Unmanage a window: strip it from every view on the monitor it
;; belonged to, clear its per-window globals, and remove it from
;; the managed/all lists. Returns the monitor the window lived on
;; (or 0 if Window_#%wndId%_monitor was unset, e.g. a stale double-
;; unmanage call). Callers (Manager_winHideDeferred queue,
;; Manager_validateAlive) use the returned monitor to schedule a
;; View_arrange + Bar_updateView for the *affected* monitor's
;; visible view rather than blindly refreshing Manager_aMonitor.
;;
;; Before #59 this used Manager_aMonitor for the strip loop and
;; Bar_updateView call, which silently corrupted state on a
;; non-active monitor when EVENT_OBJECT_HIDE or Manager_validateAlive
;; fired for a window living elsewhere — invisible on single-monitor
;; setups, ghost wndId + stale bar count on multi-monitor.
Manager_unmanage(wndId) {
  Local m

  m := Window_#%wndId%_monitor
  If m {
    Loop, % Config_viewCount {
      If (Window_#%wndId%_tags & 1 << A_Index - 1) {
        StringReplace, View_#%m%_#%A_Index%_wndIds, View_#%m%_#%A_Index%_wndIds, % wndId ";",, All
        StringReplace, View_#%m%_#%A_Index%_aWndIds, View_#%m%_#%A_Index%_aWndIds, % wndId ";",, All
        ;; If the unmanaged window was the only urgent on this view, drop
        ;; the view's urgency flag — otherwise the bar stays red with
        ;; no underlying window to surface (issue #69).
        If View_#%m%_#%A_Index%_isUrgent
          Manager_recomputeViewUrgent(m, A_Index)
        Bar_updateView(m, A_Index)
      }
    }
  }
  ;; Dequeue from the Win+U cycle — a stale entry would survive into
  ;; the next press and operate on a window whose _monitor / _tags
  ;; globals are about to be wiped (issue #69).
  Manager_dequeueUrgent(wndId)
  Window_#%wndId%_monitor     :=
  Window_#%wndId%_tags        :=
  Window_#%wndId%_isDecorated :=
  Window_#%wndId%_isFloating  :=
  Window_#%wndId%_isUrgent    :=
  Window_#%wndId%_area        :=
  ;; Last-queued-tile-target state used by Tiler_stackTiles in-place skip
  ;; check. If the wndId is later recycled by a new top-level window,
  ;; stale lqt would lie about that hwnd's queue history.
  Window_#%wndId%_lqtX        :=
  Window_#%wndId%_lqtY        :=
  Window_#%wndId%_lqtW        :=
  Window_#%wndId%_lqtH        :=
  StringReplace, Bar_hideTitleWndIds, Bar_hideTitleWndIds, %wndId%`;,
  StringReplace, Manager_allWndIds, Manager_allWndIds, %wndId%`;,
  StringReplace, Manager_managedWndIds, Manager_managedWndIds, %wndId%`;, , All

  Return, m ? m : 0
}

Manager_winActivate(wndId) {
  Global Manager_aMonitor

  Perf_start("Manager_winActivate")
  Manager_setCursor(wndId)
  Debug_logMessage("DEBUG[1] Activating window: " wndId, 1)
  If Not wndId {
    wndId := WinExist("bug.n_BAR_" . Manager_aMonitor)
    Debug_logMessage("DEBUG[1] Activating Desktop: " wndId, 1)
  }

  If Window_activate(wndId) {
    Perf_end("Manager_winActivate")
    Return, 1
  } Else {
    Bar_updateTitle()
    Perf_end("Manager_winActivate")
    Return 0
  }
}

Manager_windowNotMaximized(width, height) {
  Global
  Return, (width < 0.99 * Monitor_#%Manager_aMonitor%_width Or height < 0.99 * Monitor_#%Manager_aMonitor%_height)
}

Manager_activateViewByMouse(d) {
	Local mousePositionX, mousePositionY, window, windowTitle
	MouseGetPos, mousePositionX, mousePositionY, window
	WinGetTitle windowTitle, ahk_id %Window%
	if( InStr(windowTitle, "bug.n_BAR_") = 1 ) {
		Monitor_activateView(0, d)
	}
}

;; If wndId names a managed window, return its entry exactly as stored
;; in Manager_managedWndIds (which may be hex or decimal depending on
;; the SetFormat state when Manager__setWinProperties ran). Otherwise
;; return "". Numeric comparison so callers can pass either format —
;; lParam from the shell hook arrives hex-formatted by the SetFormat
;; dance at the top of Manager_onShellMessage, but synthesized Yunit
;; tests pass decimal HWNDs; both must resolve to the same managed
;; entry.
;;
;; Returning the stored-key string (not just a bool) lets the caller
;; pass that exact string to dynamic-variable consumers like
;; Manager_markUrgent, whose Window_#%wndId%_monitor / _tags / _isUrgent
;; lookups only match if wndId has the same format the manage path
;; used when it created those globals.
Manager_isManaged(wndId) {
  Global Manager_managedWndIds

  target := wndId + 0
  StringTrimRight, trimmed, Manager_managedWndIds, 1
  Loop, PARSE, trimmed, `;
  {
    If A_LoopField And ((A_LoopField + 0) = target)
      Return A_LoopField
  }
  Return ""
}

;; Mark a window's non-active views as urgent, so their bar entries can
;; light up red. Called from the HSHELL_FLASH dispatch in
;; Manager_onShellMessage when a managed window is flashing its taskbar
;; entry. Active view is skipped — if the user is already looking at the
;; window, there is nothing to draw attention to.
Manager_markUrgent(wndId) {
  Global Config_viewCount, Manager_urgentWndIds

  wndMon := Window_#%wndId%_monitor
  aView  := Monitor_#%wndMon%_aView_#1
  marked := False
  Loop, % Config_viewCount {
    viewBit := 1 << (A_Index - 1)
    If (Window_#%wndId%_tags & viewBit) And Not (A_Index = aView) {
      Window_#%wndId%_isUrgent           := True
      View_#%wndMon%_#%A_Index%_isUrgent := True
      Bar_updateView(wndMon, A_Index)
      marked := True
    }
  }
  ;; Append to the cycle queue so Win+U can walk every pending urgent
  ;; in mark-order (issue #69). Dedupe re-flashes: a noisy app blinking
  ;; 5x should be one queue entry, not five (AwesomeWM semantics).
  If marked And Not Manager_isInUrgentQueue(wndId)
    Manager_urgentWndIds .= wndId . ";"
}

;; Delimiter-aware membership check for Manager_urgentWndIds. Mirrors
;; Manager_isManaged's loop+PARSE numeric-compare so a naive substring
;; match can't false-positive across suffix-colliding HWNDs (e.g.
;; mistaking "12;" for being inside "412;"). Numeric compare also
;; handles the hex-vs-decimal storage drift between production
;; (typically hex) and Yunit tests (decimal).
Manager_isInUrgentQueue(wndId) {
  Global Manager_urgentWndIds

  target := wndId + 0
  StringTrimRight, trimmed, Manager_urgentWndIds, 1
  Loop, PARSE, trimmed, `;
  {
    If A_LoopField And ((A_LoopField + 0) = target)
      Return True
  }
  Return False
}

;; Delimiter-aware removal for Manager_urgentWndIds. Rebuilds the queue
;; without entries that numerically equal wndId — naive StringReplace
;; corrupted suffix-sharing neighbors ("412;12;" minus "12;" became "4")
;; and could silently land Win+U on the wrong window.
Manager_dequeueUrgent(wndId) {
  Global Manager_urgentWndIds

  target := wndId + 0
  newQueue := ""
  StringTrimRight, trimmed, Manager_urgentWndIds, 1
  Loop, PARSE, trimmed, `;
  {
    If A_LoopField And ((A_LoopField + 0) != target)
      newQueue .= A_LoopField . ";"
  }
  Manager_urgentWndIds := newQueue
}

;; Win+U: pop the oldest entry from Manager_urgentWndIds belonging to
;; the active monitor, switch to its view without clearing sibling
;; urgents on that view (Monitor_activateView's third arg = False),
;; promote it to the head of aWndIds, focus it, and clear only its
;; own _isUrgent flag. Repeated presses walk the queue in mark-order —
;; including multiple urgents on the same view (issue #69).
;;
;; Scope is monitor-local in v1; cross-monitor cycling is tracked
;; separately in issue #91.
Manager_activateUrgentView() {
  Global Config_viewCount, Manager_aMonitor, Manager_urgentWndIds

  aMonitor    := Manager_aMonitor
  urgentWndId := ""
  StringTrimRight, queue, Manager_urgentWndIds, 1
  Loop, PARSE, queue, `;
  {
    If A_LoopField And (Window_#%A_LoopField%_monitor = aMonitor) {
      urgentWndId := A_LoopField
      Break
    }
  }
  If Not urgentWndId
    Return

  ;; Pick the first tagged view that isn't already active. If the
  ;; window only lives on the active view, just focus it in-place.
  aView    := Monitor_#%aMonitor%_aView_#1
  destView := 0
  Loop, % Config_viewCount {
    If (Window_#%urgentWndId%_tags & 1 << A_Index - 1) And Not (A_Index = aView) {
      destView := A_Index
      Break
    }
  }
  If Not destView
    destView := aView

  ;; Promote first so Monitor_activateView's final winActivate resolves
  ;; to the urgent window, not whichever was most-recently-active.
  View_setActiveWindow(aMonitor, destView, urgentWndId)
  If (destView != aView)
    Monitor_activateView(destView, 0, False)

  Manager_clearUrgentWindow(urgentWndId)

  ;; Pre-show via SW_SHOWNA so WinActivate has a visible target. Skip if
  ;; hung — ShowWindow can block, and Manager_winActivate would no-op on
  ;; a hung target anyway (Window_activate's Window_isHung guard).
  If Not Window_isHung(urgentWndId)
    DllCall("ShowWindow", "Ptr", urgentWndId, "Int", 8)
  Manager_winActivate(urgentWndId)
}

;; Clear a single window's urgency: drop its flag, dequeue from the
;; Win+U cycle, and recompute the view-level _isUrgent flag for every
;; view the window was tagged on (a view stays urgent if any of its
;; other windows are still urgent).
Manager_clearUrgentWindow(wndId) {
  Global Config_viewCount, Manager_urgentWndIds

  Window_#%wndId%_isUrgent := False
  Manager_dequeueUrgent(wndId)
  wndMon := Window_#%wndId%_monitor
  Loop, % Config_viewCount {
    If (Window_#%wndId%_tags & 1 << A_Index - 1)
      Manager_recomputeViewUrgent(wndMon, A_Index)
  }
}

;; View is urgent iff at least one of its windows still has its urgent
;; flag set. Walks View_#m_#i_wndIds and flips View_#m_#i_isUrgent if
;; it diverges from that truth, refreshing the bar entry on change.
Manager_recomputeViewUrgent(m, i) {
  Local wndIds, stillUrgent

  StringTrimRight, wndIds, View_#%m%_#%i%_wndIds, 1
  stillUrgent := False
  Loop, PARSE, wndIds, `;
  {
    If A_LoopField And Window_#%A_LoopField%_isUrgent {
      stillUrgent := True
      Break
    }
  }
  If (View_#%m%_#%i%_isUrgent != stillUrgent) {
    View_#%m%_#%i%_isUrgent := stillUrgent
    Bar_updateView(m, i)
  }
}