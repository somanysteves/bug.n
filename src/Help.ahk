/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>

  @version 9.3.0

  Help.ahk -- in-app hotkey cheatsheet popup. Reads the bindings
  registered by Config_restoreConfig (Config_hotkey_#N_key /
  Config_hotkey_#N_command) and renders them grouped by command
  prefix in a borderless always-on-top GUI on the active monitor.
  Bind a hotkey from Config.ini to invoke Help_toggle(), e.g.
    Config_hotkey=#s::Help_toggle()
  (mirrors AwesomeWM's Win+S cheatsheet; pick a different key if
  you want to keep Windows' built-in Win+S search bar.)
  Phase 1 shows raw command strings; phase 2 (issue #22) layers
  human-readable descriptions parsed from Default_hotkeys.md.
*/

Help_isVisible := False
Help_hwnd      := 0

;; Public toggle entry point. Bound from Config.ini via Main_evalCommand.
Help_toggle() {
  Global Help_isVisible

  If Help_isVisible
    Help_hide()
  Else
    Help_show()
}

Help_show() {
  Global

  Local content, m, mX, mY, mW, mH, popupW, popupH, sections, x, y

  sections := Help_buildSections()
  content  := Help_renderContent(sections)

  ;; Named GUI ("HelpCheatsheet") avoids collision with Bar's
  ;; numeric GUIs (1..N per-monitor + 99 for the command popup).
  Gui, HelpCheatsheet: Default
  Gui, +LabelHelp_Gui
  Gui, Destroy
  Gui, +LastFound -Caption +ToolWindow +AlwaysOnTop +Border +OwnDialogs
  Help_hwnd := WinExist()
  Gui, Color, %Config_backColor_#1_#3%
  Gui, Margin, 16, 16
  Gui, Font, c%Config_fontColor_#1_#3% s%Config_fontSize%, %Config_fontName%

  ;; Edit control: built-in scrollable, monospace, selectable text.
  ;; ReadOnly disables typing; -E0x200 strips the sunken border that
  ;; would otherwise clash with the borderless popup chrome.
  Gui, Add, Edit, w800 h500 ReadOnly -E0x200 Background%Config_backColor_#1_#3% vHelp_content, % content

  ;; Center on the active monitor.
  m := Manager_aMonitor
  mX := Monitor_#%m%_x
  mY := Monitor_#%m%_y
  mW := Monitor_#%m%_width
  mH := Monitor_#%m%_height
  popupW := 832
  popupH := 532
  x := mX + (mW - popupW) / 2
  y := mY + (mH - popupH) / 2

  Gui, Show, x%x% y%y% w%popupW% h%popupH%, bug.n_HELP
  Help_isVisible := True

  ;; Clear the all-text selection that AHK gives a focused Edit on
  ;; Show. EM_SETSEL (0xB1) with wParam=0 lParam=0 collapses the
  ;; selection to position 0 with no highlight, so the popup reads
  ;; as plain text instead of a giant highlighted block.
  SendMessage, 0xB1, 0, 0, Edit1, bug.n_HELP

  ;; Hide on focus loss. WM_ACTIVATE wParam = WA_INACTIVE (0) means
  ;; the popup just lost activation; filter by hwnd so this doesn't
  ;; fire for any other GUI in the script.
  OnMessage(0x06, "Help_onActivate")
}

Help_hide() {
  Global Help_isVisible

  Gui, HelpCheatsheet: Default
  Gui, Cancel
  Help_isVisible := False
  OnMessage(0x06, "")
}

;; ---- pure helpers (unit-tested in tests/test_Help.ahk) ----

;; Translate AHK modifier prefixes (#, ^, !, +) into "Win+Ctrl+Alt+Shift+"
;; form and append the bare key. Single-letter keys are uppercased so
;; "#q" reads "Win+Q", not "Win+q".
Help_renderKey(rawKey) {
  Local c, i, modifiers, rest

  modifiers := ""
  i := 1
  Loop {
    c := SubStr(rawKey, i, 1)
    If (c = "#") {
      modifiers .= "Win+"
      i += 1
    } Else If (c = "^") {
      modifiers .= "Ctrl+"
      i += 1
    } Else If (c = "!") {
      modifiers .= "Alt+"
      i += 1
    } Else If (c = "+") {
      modifiers .= "Shift+"
      i += 1
    } Else
      Break
  }
  rest := SubStr(rawKey, i)
  If (StrLen(rest) = 1)
    StringUpper, rest, rest
  Return modifiers . rest
}

;; Map a command string to a section heading using the function-name
;; prefix before the underscore. Built-in non-prefixed commands
;; (Reload / ExitApp / Run, ... / Send ...) go to "Administration".
Help_categoryFor(command) {
  Local funcName, parenIdx, prefix, underscoreIdx

  If (command = "Reload" Or command = "ExitApp")
    Return "Administration"
  If (SubStr(command, 1, 5) = "Run, " Or SubStr(command, 1, 5) = "Send ")
    Return "Administration"

  parenIdx := InStr(command, "(")
  funcName := parenIdx ? SubStr(command, 1, parenIdx - 1) : command
  underscoreIdx := InStr(funcName, "_")
  If !underscoreIdx
    Return "Other"
  prefix := SubStr(funcName, 1, underscoreIdx - 1)
  If (prefix = "View" Or prefix = "Window")
    Return "Window / view"
  If (prefix = "Bar")
    Return "GUI"
  If (prefix = "Config")
    Return "Administration"
  Return prefix
}

;; Read Config_hotkey_#N_* globals and return an ordered list of
;; sections: [{name, rows: [{key, command}, ...]}, ...]. Section
;; order matches the order of first occurrence in Config_hotkey_*,
;; which itself reflects Config.ini source order.
Help_buildSections() {
  Global

  Local catKeys, catName, categories, command, i, idx, key, rendered, sections

  categories := {}
  catKeys := []
  Loop, % Config_hotkeyCount {
    i := A_Index
    key := Config_hotkey_#%i%_key
    command := Config_hotkey_#%i%_command
    ;; Skip tombstones left behind when Config.ini overrides a default
    ;; with an empty command (Config_setHotkey clears both fields but
    ;; doesn't compact the array).
    If (key = "" Or command = "")
      Continue
    catName := Help_categoryFor(command)
    If !categories.HasKey(catName) {
      categories[catName] := []
      catKeys.Push(catName)
    }
    rendered := Help_renderKey(key)
    categories[catName].Push({key: rendered, command: command})
  }
  sections := []
  Loop, % catKeys.Length() {
    idx := A_Index
    catName := catKeys[idx]
    sections.Push({name: catName, rows: categories[catName]})
  }
  Return sections
}

;; Format a list of sections into a single text block. Pads the key
;; column to the widest rendered key across all sections so commands
;; align in a single column regardless of section.
Help_renderContent(sections) {
  Local content, i, j, keyCol, maxKeyWidth, row, section

  If (!sections.Length()) {
    Return "No hotkeys configured.`r`nAdd Config_hotkey=... lines to your Config.ini."
  }

  maxKeyWidth := 0
  Loop, % sections.Length() {
    i := A_Index
    section := sections[i]
    Loop, % section.rows.Length() {
      j := A_Index
      row := section.rows[j]
      If (StrLen(row.key) > maxKeyWidth)
        maxKeyWidth := StrLen(row.key)
    }
  }

  content := ""
  Loop, % sections.Length() {
    i := A_Index
    section := sections[i]
    content .= "[ " . section.name . " ]`r`n"
    Loop, % section.rows.Length() {
      j := A_Index
      row := section.rows[j]
      keyCol := Help_padRight(row.key, maxKeyWidth)
      content .= "  " . keyCol . "  " . row.command . "`r`n"
    }
    content .= "`r`n"
  }
  Return RTrim(content, "`r`n")
}

Help_padRight(s, width) {
  Local pad

  pad := width - StrLen(s)
  If (pad <= 0)
    Return s
  Loop, %pad%
    s .= " "
  Return s
}

;; ---- GUI labels ----

Help_GuiEscape:
  Help_hide()
Return

Help_GuiClose:
  Help_hide()
Return

Help_onActivate(wParam, lParam, msg, hwnd) {
  Global Help_hwnd, Help_isVisible

  ;; wParam == 0 is WA_INACTIVE for the receiving window. Filter by
  ;; hwnd so we don't react to deactivation of other GUIs in the
  ;; script (the bar, the command popup, etc).
  If (hwnd = Help_hwnd && wParam = 0 && Help_isVisible)
    Help_hide()
}
