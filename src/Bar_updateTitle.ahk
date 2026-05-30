;; Bar_updateTitle is split out so tests can stub it via
;; tests/stubs_io.ahk -- the real body queries the OS foreground window
;; and updates a real Gui control, which Yunit can't observe. Production
;; #Includes happen in Main.ahk / Bench_main.ahk; tests/run.ahk does
;; NOT include this file (the stub takes its place).
Bar_updateTitle() {
  Local aWndId, aWndTitle, content, GuiN, i, title

  If Not Bar_initialized
    Return

  WinGet, aWndId, ID, A
  aWndTitle := Window_getTitleNonBlocking(aWndId)
  If InStr(Bar_hideTitleWndIds, aWndId ";") Or (aWndTitle = "bug.n_BAR_0")
    aWndTitle := ""
  If aWndId And InStr(Manager_managedWndIds, aWndId . ";") And Window_#%aWndId%_isFloating
    aWndTitle := "~ " aWndTitle
  If (Manager_monitorCount > 1)
    aWndTitle := "[" Manager_aMonitor "] " aWndTitle
  title := " " . aWndTitle . " "

  If (Bar_getTextWidth(title) > Bar_#%Manager_aMonitor%_titleWidth) {
    ;; Shorten the window title if its length exceeds the width of the bar
    i := Bar_getTextWidth(Bar_#%Manager_aMonitor%_titleWidth, True) - 6
    StringLeft, title, aWndTitle, i
    title := " " . title . " ... "
  }
  StringReplace, title, title, &, &&, All     ;; Special character '&', which would underline the next letter.

  Loop, % Manager_monitorCount {
    GuiN := (A_Index - 1) + 1
    Gui, %GuiN%: Default
    GuiControlGet, content, , Bar_#%A_Index%_title
    If (A_Index = Manager_aMonitor) {
      If Not (content = title)
        GuiControl, , Bar_#%A_Index%_title, % title
    } Else If Not (content = "")
      GuiControl, , Bar_#%A_Index%_title,
  }
  Bar_aWndId := aWndId
}
