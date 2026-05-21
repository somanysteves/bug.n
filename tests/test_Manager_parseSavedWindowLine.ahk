/*
  Tests for Manager__parseSavedWindowLine (src/Manager.ahk).

  Locks the _WindowState.ini "Window ..." line schema in place so a
  future column-order shuffle can't silently break restore. Covers:

    - 8-column lines (current format, written since PR #62 dropped the
      trailing title fetch that caused the reconnect hang)
    - 9-column lines (legacy format with trailing title) — restore must
      stay backward-compatible with INI files saved before the upgrade
    - Short lines (< 8 columns) — must be rejected, not silently parsed
*/

class TestManagerParseSavedWindowLine
{
  ;; Each Window line in _WindowState.ini looks like (without the
  ;; "Window " prefix that Manager__restoreWindowState strips before
  ;; calling the parser):
  ;;   wndId;processName;monitor;tags;isFloating;isDecorated;hideTitle;isManaged[;title]

  EightColumns_NewFormat_ParsesAllFields()
  {
    ok := Manager__parseSavedWindowLine("0xa00c6;explorer.exe;1;2;0;1;0;1", wndId, processName, monitor, tags, isFloating, isDecorated, hideTitle, isManaged)
    Yunit.Assert(ok = True, "expected True, got '" . ok . "'")
    Yunit.Assert(wndId = "0xa00c6", "wndId: '" . wndId . "'")
    Yunit.Assert(processName = "explorer.exe", "processName: '" . processName . "'")
    Yunit.Assert(monitor = "1", "monitor: '" . monitor . "'")
    Yunit.Assert(tags = "2", "tags: '" . tags . "'")
    Yunit.Assert(isFloating = "0", "isFloating: '" . isFloating . "'")
    Yunit.Assert(isDecorated = "1", "isDecorated: '" . isDecorated . "'")
    Yunit.Assert(hideTitle = "0", "hideTitle: '" . hideTitle . "'")
    Yunit.Assert(isManaged = "1", "isManaged: '" . isManaged . "'")
  }

  ;; A file written by a pre-PR#62 build of bug.n carries a 9th field
  ;; (the window title, captured for human readability). The parser
  ;; must accept the line and ignore the trailing field — otherwise
  ;; the first restore after upgrading would discard every saved
  ;; window with "could not be processed due to parse error".
  NineColumns_LegacyFormat_ParsesFirstEightIgnoresTitle()
  {
    line := "0x6012a;chrome.exe;2;4;1;0;1;0;Some Window Title - Chrome"
    ok := Manager__parseSavedWindowLine(line, wndId, processName, monitor, tags, isFloating, isDecorated, hideTitle, isManaged)
    Yunit.Assert(ok = True, "expected True, got '" . ok . "'")
    Yunit.Assert(wndId = "0x6012a", "wndId: '" . wndId . "'")
    Yunit.Assert(processName = "chrome.exe", "processName: '" . processName . "'")
    Yunit.Assert(monitor = "2", "monitor: '" . monitor . "'")
    Yunit.Assert(tags = "4", "tags: '" . tags . "'")
    Yunit.Assert(isFloating = "1", "isFloating: '" . isFloating . "'")
    Yunit.Assert(isDecorated = "0", "isDecorated: '" . isDecorated . "'")
    Yunit.Assert(hideTitle = "1", "hideTitle: '" . hideTitle . "'")
    Yunit.Assert(isManaged = "0", "isManaged: '" . isManaged . "'")
  }

  ;; Unmanaged windows are saved with empty positional fields for
  ;; monitor/tags/floating/decorated (see Manager_saveWindowState's
  ;; ";;;;" branch). Make sure those parse without crashing.
  EightColumns_UnmanagedRow_EmptyMiddleFields()
  {
    ok := Manager__parseSavedWindowLine("0x10362;notepad.exe;;;;;0;0", wndId, processName, monitor, tags, isFloating, isDecorated, hideTitle, isManaged)
    Yunit.Assert(ok = True, "expected True, got '" . ok . "'")
    Yunit.Assert(wndId = "0x10362", "wndId: '" . wndId . "'")
    Yunit.Assert(processName = "notepad.exe", "processName: '" . processName . "'")
    Yunit.Assert(monitor = "", "monitor: '" . monitor . "'")
    Yunit.Assert(tags = "", "tags: '" . tags . "'")
    Yunit.Assert(isFloating = "", "isFloating: '" . isFloating . "'")
    Yunit.Assert(isDecorated = "", "isDecorated: '" . isDecorated . "'")
    Yunit.Assert(hideTitle = "0", "hideTitle: '" . hideTitle . "'")
    Yunit.Assert(isManaged = "0", "isManaged: '" . isManaged . "'")
  }

  SevenColumns_Rejected()
  {
    ok := Manager__parseSavedWindowLine("0xa00c6;explorer.exe;1;2;0;1;0", wndId, processName, monitor, tags, isFloating, isDecorated, hideTitle, isManaged)
    Yunit.Assert(ok = False, "7-column line must be rejected, got '" . ok . "'")
  }

  EmptyLine_Rejected()
  {
    ok := Manager__parseSavedWindowLine("", wndId, processName, monitor, tags, isFloating, isDecorated, hideTitle, isManaged)
    Yunit.Assert(ok = False, "empty line must be rejected, got '" . ok . "'")
  }
}
