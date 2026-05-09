/*
  Unit tests for the Help cheatsheet helpers.

  Help_renderKey, Help_categoryFor, Help_buildSections, and
  Help_renderContent are pure (modulo Help_buildSections's read of
  Config_hotkey_#N_* globals). Begin()/End() seed and tear down the
  globals so each test runs against a known fixture and can't leak
  state into other suites.
*/

class TestHelp
{
  Begin()
  {
    Global

    ;; Three bindings spanning multiple categories, including a
    ;; non-prefixed administrative command (Reload) and one in a
    ;; second category (Manager_*) so build/render exercise grouping.
    Config_hotkeyCount := 3
    Config_hotkey_#1_key     := "#Down"
    Config_hotkey_#1_command := "View_activateWindow(0, +1)"
    Config_hotkey_#2_key     := "#^q"
    Config_hotkey_#2_command := "ExitApp"
    Config_hotkey_#3_key     := "#c"
    Config_hotkey_#3_command := "Manager_closeWindow()"
  }

  End()
  {
    Global

    Config_hotkeyCount := 0
    Config_hotkey_#1_key     := ""
    Config_hotkey_#1_command := ""
    Config_hotkey_#2_key     := ""
    Config_hotkey_#2_command := ""
    Config_hotkey_#3_key     := ""
    Config_hotkey_#3_command := ""
  }

  ;; ---- Help_renderKey ----

  RenderKey_WinPlusBareKey()
  {
    Yunit.Assert(Help_renderKey("#Down") = "Win+Down"
      , "expected 'Win+Down', got '" . Help_renderKey("#Down") . "'")
  }

  RenderKey_AllFourModifiers()
  {
    Yunit.Assert(Help_renderKey("#^!+q") = "Win+Ctrl+Alt+Shift+Q"
      , "expected 'Win+Ctrl+Alt+Shift+Q', got '" . Help_renderKey("#^!+q") . "'")
  }

  RenderKey_SingleLetterIsUppercased()
  {
    Yunit.Assert(Help_renderKey("#q") = "Win+Q"
      , "expected 'Win+Q', got '" . Help_renderKey("#q") . "'")
  }

  RenderKey_MultiCharKeyPassesThrough()
  {
    ;; "Tab" / "BackSpace" are AHK key names — must not be uppercased.
    Yunit.Assert(Help_renderKey("#Tab") = "Win+Tab"
      , "expected 'Win+Tab', got '" . Help_renderKey("#Tab") . "'")
    Yunit.Assert(Help_renderKey("#BackSpace") = "Win+BackSpace"
      , "expected 'Win+BackSpace', got '" . Help_renderKey("#BackSpace") . "'")
  }

  RenderKey_NoModifiers()
  {
    Yunit.Assert(Help_renderKey("F1") = "F1"
      , "expected 'F1', got '" . Help_renderKey("F1") . "'")
  }

  RenderKey_CtrlShiftDigitOrder()
  {
    ;; Modifiers preserve source order; we always render Win/Ctrl/Alt/Shift
    ;; in the order they appear in the raw key.
    Yunit.Assert(Help_renderKey("^+1") = "Ctrl+Shift+1"
      , "expected 'Ctrl+Shift+1', got '" . Help_renderKey("^+1") . "'")
  }

  ;; ---- Help_categoryFor ----

  CategoryFor_ViewMapsToWindowSlashView()
  {
    Yunit.Assert(Help_categoryFor("View_activateWindow(0, +1)") = "Window / view"
      , "got '" . Help_categoryFor("View_activateWindow(0, +1)") . "'")
  }

  CategoryFor_WindowAlsoMapsToWindowSlashView()
  {
    Yunit.Assert(Help_categoryFor("Window_toggleDecor()") = "Window / view"
      , "got '" . Help_categoryFor("Window_toggleDecor()") . "'")
  }

  CategoryFor_ManagerAndMonitorAndDebug()
  {
    Yunit.Assert(Help_categoryFor("Manager_closeWindow()") = "Manager"
      , "Manager: got '" . Help_categoryFor("Manager_closeWindow()") . "'")
    Yunit.Assert(Help_categoryFor("Monitor_activateView(1)") = "Monitor"
      , "Monitor: got '" . Help_categoryFor("Monitor_activateView(1)") . "'")
    Yunit.Assert(Help_categoryFor("Debug_setLogLevel(0, +1)") = "Debug"
      , "Debug: got '" . Help_categoryFor("Debug_setLogLevel(0, +1)") . "'")
  }

  CategoryFor_BarMapsToGui()
  {
    Yunit.Assert(Help_categoryFor("Bar_toggleCommandGui()") = "GUI"
      , "got '" . Help_categoryFor("Bar_toggleCommandGui()") . "'")
  }

  CategoryFor_ReloadAndExitAppAreAdministration()
  {
    Yunit.Assert(Help_categoryFor("Reload") = "Administration"
      , "Reload: got '" . Help_categoryFor("Reload") . "'")
    Yunit.Assert(Help_categoryFor("ExitApp") = "Administration"
      , "ExitApp: got '" . Help_categoryFor("ExitApp") . "'")
  }

  CategoryFor_RunCommandIsAdministration()
  {
    Yunit.Assert(Help_categoryFor("Run, notepad.exe") = "Administration"
      , "got '" . Help_categoryFor("Run, notepad.exe") . "'")
  }

  CategoryFor_UnknownPrefixFallsBackToOther()
  {
    Yunit.Assert(Help_categoryFor("Frobnicate_doIt()") = "Frobnicate"
      , "got '" . Help_categoryFor("Frobnicate_doIt()") . "'")
    Yunit.Assert(Help_categoryFor("LoneCommand") = "Other"
      , "got '" . Help_categoryFor("LoneCommand") . "'")
  }

  ;; ---- Help_buildSections ----

  BuildSections_GroupsByCategoryInDiscoveryOrder()
  {
    Local sections

    sections := Help_buildSections()
    Yunit.Assert(sections.Length() = 3
      , "expected 3 sections, got " . sections.Length())
    Yunit.Assert(sections[1].name = "Window / view"
      , "first section: '" . sections[1].name . "'")
    Yunit.Assert(sections[2].name = "Administration"
      , "second section: '" . sections[2].name . "'")
    Yunit.Assert(sections[3].name = "Manager"
      , "third section: '" . sections[3].name . "'")
  }

  BuildSections_PutsManagerEntryInItsOwnSection()
  {
    Local mgrSection, sections

    sections := Help_buildSections()
    mgrSection := sections[3]
    Yunit.Assert(mgrSection.name = "Manager"
      , "expected 'Manager' as third section, got '" . mgrSection.name . "'")
    Yunit.Assert(mgrSection.rows.Length() = 1
      , "expected 1 row in Manager section, got " . mgrSection.rows.Length())
    Yunit.Assert(mgrSection.rows[1].key = "Win+C"
      , "expected 'Win+C', got '" . mgrSection.rows[1].key . "'")
    Yunit.Assert(mgrSection.rows[1].command = "Manager_closeWindow()"
      , "expected 'Manager_closeWindow()', got '" . mgrSection.rows[1].command . "'")
  }

  BuildSections_RendersKeysAlready()
  {
    Local firstRow, sections

    sections := Help_buildSections()
    firstRow := sections[1].rows[1]
    Yunit.Assert(firstRow.key = "Win+Down"
      , "expected first row key 'Win+Down', got '" . firstRow.key . "'")
  }

  BuildSections_SkipsTombstones()
  {
    Global

    Local sections

    ;; Mirror the state Config_setHotkey leaves after an empty-command
    ;; override unbinds a default: count stays high but the slot's
    ;; key + command are blanked. Help_buildSections must skip these
    ;; rather than rendering an empty row in an "Other" category.
    Config_hotkey_#2_key     := ""
    Config_hotkey_#2_command := ""

    sections := Help_buildSections()
    Yunit.Assert(sections.Length() = 2
      , "tombstone should drop one section, got " . sections.Length())
    Yunit.Assert(sections[1].name = "Window / view"
      , "first section after tombstone: '" . sections[1].name . "'")
    Yunit.Assert(sections[2].name = "Manager"
      , "second section after tombstone: '" . sections[2].name . "'")
  }

  ;; ---- Help_renderContent ----

  RenderContent_EmptyMessageWhenNoBindings()
  {
    Local content, empty

    empty := []
    content := Help_renderContent(empty)
    Yunit.Assert(InStr(content, "No hotkeys configured.") > 0
      , "expected empty message, got '" . content . "'")
  }

  RenderContent_HasSectionHeadersAndRows()
  {
    Local content, sections

    sections := Help_buildSections()
    content := Help_renderContent(sections)
    Yunit.Assert(InStr(content, "[ Window / view ]") > 0
      , "missing section header 'Window / view':`n" . content)
    Yunit.Assert(InStr(content, "[ Administration ]") > 0
      , "missing section header 'Administration':`n" . content)
    Yunit.Assert(InStr(content, "Win+Down") > 0
      , "missing rendered key 'Win+Down':`n" . content)
    Yunit.Assert(InStr(content, "View_activateWindow(0, +1)") > 0
      , "missing command 'View_activateWindow(0, +1)':`n" . content)
  }

  RenderContent_KeyColumnIsLeftPaddedToWidestKey()
  {
    Local content, sections

    sections := Help_buildSections()
    content := Help_renderContent(sections)
    ;; Widest key in fixture is "Win+Ctrl+Q" (10 chars). Every row
    ;; pads its key column to 10. "Win+Down" (8) gets +2 spaces of
    ;; pad, "Win+C" (5) gets +5, and the unpadded widest key butts
    ;; up against the 2-space separator. Asserting these literal
    ;; spacings catches any regression in padRight or render layout.
    Yunit.Assert(InStr(content, "  Win+Ctrl+Q  ExitApp") > 0
      , "Win+Ctrl+Q row spacing wrong (no padding expected, widest key):`n" . content)
    Yunit.Assert(InStr(content, "  Win+Down    View_activateWindow(0, +1)") > 0
      , "Win+Down row not padded to match widest key:`n" . content)
    Yunit.Assert(InStr(content, "  Win+C       Manager_closeWindow()") > 0
      , "Win+C row not padded to match widest key:`n" . content)
  }
}
