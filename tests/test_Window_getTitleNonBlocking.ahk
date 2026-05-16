/*
  Tests for Window_getTitleNonBlocking (src/Window.ahk).

  The helper is a SendMessageTimeout wrapper for WM_GETTEXT, used in
  Bar_updateTitle and Manager_applyRules to keep title fetches from
  blocking the AHK thread when the target window proc is slow. These
  tests verify the basic contract against real (hidden tool-window)
  Guis -- the "doesn't hang on a slow cross-process window" property
  is empirical and can't be exercised in-process.
*/

class TestWindowGetTitleNonBlocking
{
  ReturnsExpectedTitleForRealWindow()
  {
    Local hwndOut, result
    hwndOut := 0
    Gui, GetTitleNBTest1: New, +HwndhwndOut +ToolWindow
    Gui, GetTitleNBTest1: Add, Text, , .
    Gui, GetTitleNBTest1: Show, Hide x-9999 y-9999 w50 h30, BugnTitleNB_Known

    result := Window_getTitleNonBlocking(hwndOut)

    Gui, GetTitleNBTest1: Destroy

    Yunit.Assert(result = "BugnTitleNB_Known"
      , "should return actual title; got '" . result . "'")
  }

  ReturnsEmptyForHwndZero()
  {
    Local result
    result := Window_getTitleNonBlocking(0)
    Yunit.Assert(result = ""
      , "HWND 0 should return ''; got '" . result . "'")
  }

  ReflectsPostSetWindowTextTitle()
  {
    ;; SendMessageTimeout asks the WndProc via WM_GETTEXT. SetWindowText
    ;; (the user32 API) updates both the WndProc's stored title and the
    ;; kernel cache, so WM_GETTEXT picks up the new value.
    Local hwndOut, result
    hwndOut := 0
    Gui, GetTitleNBTest2: New, +HwndhwndOut +ToolWindow
    Gui, GetTitleNBTest2: Add, Text, , .
    Gui, GetTitleNBTest2: Show, Hide x-9999 y-9999 w50 h30, InitialTitle

    DllCall("user32\SetWindowTextW", "UPtr", hwndOut, "Str", "UpdatedTitle")
    result := Window_getTitleNonBlocking(hwndOut)

    Gui, GetTitleNBTest2: Destroy

    Yunit.Assert(result = "UpdatedTitle"
      , "should reflect post-SetWindowText title; got '" . result . "'")
  }

  ReturnsEmptyForEmptyTitle()
  {
    Local hwndOut, result
    hwndOut := 0
    Gui, GetTitleNBTest3: New, +HwndhwndOut +ToolWindow
    Gui, GetTitleNBTest3: Add, Text, , .
    Gui, GetTitleNBTest3: Show, Hide x-9999 y-9999 w50 h30, NonEmptyToStart

    DllCall("user32\SetWindowTextW", "UPtr", hwndOut, "Str", "")
    result := Window_getTitleNonBlocking(hwndOut)

    Gui, GetTitleNBTest3: Destroy

    Yunit.Assert(result = ""
      , "empty-title window should return ''; got '" . result . "'")
  }
}
