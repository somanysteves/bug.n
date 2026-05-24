/*
  Tests for view-name persistence in Config_saveSession and
  Config_restoreLayout (src/Config.ahk).

  Manager_renameView mutates Config_viewNames_#N globals; persistence
  flows through Manager_saveState -> Config_saveSession (writes lines
  diverging from Config_viewNames baseline) and back through
  Monitor_init -> Config_restoreLayout (reads them).

  Tests use a temp file in A_Temp to avoid touching real bug.n state.
*/

class TestConfigViewNamesPersistence
{
  Begin()
  {
    Global Manager_monitorCount, Config_viewCount, Config_viewNames
    Global Config_viewNames_#1, Config_viewNames_#2, Config_viewNames_#3
    Global Config_layoutAxis_#1, Config_layoutAxis_#2, Config_layoutAxis_#3
    Global Config_layoutGapWidth, Config_layoutMFactor
    Global Config_layoutStackMX, Config_layoutStackMY, Config_showBar
    Global Monitor_#1_aView_#1, Monitor_#1_aView_#2, Monitor_#1_showBar

    Manager_monitorCount := 1
    Config_viewCount     := 3
    Config_viewNames     := "1;2;3"
    Config_viewNames_#1  := "1"
    Config_viewNames_#2  := "2"
    Config_viewNames_#3  := "3"

    ;; Match Config_init defaults so the per-view diff lines are skipped.
    Config_layoutAxis_#1 := 1
    Config_layoutAxis_#2 := 2
    Config_layoutAxis_#3 := 2
    Config_layoutGapWidth := 0
    Config_layoutMFactor  := 0.55
    Config_layoutStackMX  := 1
    Config_layoutStackMY  := 1
    Config_showBar        := True

    Monitor_#1_aView_#1 := 1
    Monitor_#1_aView_#2 := 1
    Monitor_#1_showBar  := Config_showBar

    Loop, % Config_viewCount
      View_init(1, A_Index)

    this.TempFile := A_Temp . "\bugn_test_persistence.ini"
    ;; AHK commands throw under Yunit's try-wrapped tests when ErrorLevel
    ;; is set. Config_saveSession's FileDelete on the .tmp companion would
    ;; throw if the file doesn't exist; pre-create empty stubs so both
    ;; deletes succeed.
    FileAppend, , % this.TempFile
    FileAppend, , % this.TempFile . ".tmp"
  }

  End()
  {
    If FileExist(this.TempFile)
      FileDelete, % this.TempFile
    If FileExist(this.TempFile . ".tmp")
      FileDelete, % this.TempFile . ".tmp"
  }

  Save_DivergedValue_Emitted()
  {
    Global Config_viewNames_#3
    Config_viewNames_#3 := "important"

    Config_saveSession("", this.TempFile)

    FileRead, content, % this.TempFile
    Yunit.Assert(InStr(content, "Config_viewNames_#3=important") > 0, "diverged view name must be emitted; file content was:`n" . content)
  }

  Save_BaselineValue_Skipped()
  {
    ;; All three views still match baseline "1;2;3" — none should be emitted.
    Config_saveSession("", this.TempFile)

    FileRead, content, % this.TempFile
    Yunit.Assert(InStr(content, "Config_viewNames_#1=") = 0, "baseline view 1 must NOT be emitted; got:`n" . content)
    Yunit.Assert(InStr(content, "Config_viewNames_#2=") = 0, "baseline view 2 must NOT be emitted; got:`n" . content)
    Yunit.Assert(InStr(content, "Config_viewNames_#3=") = 0, "baseline view 3 must NOT be emitted; got:`n" . content)
  }

  Save_MultipleDiverged_AllEmitted()
  {
    Global Config_viewNames_#1, Config_viewNames_#3
    Config_viewNames_#1 := "alpha"
    Config_viewNames_#3 := "gamma"

    Config_saveSession("", this.TempFile)

    FileRead, content, % this.TempFile
    Yunit.Assert(InStr(content, "Config_viewNames_#1=alpha") > 0, "view 1 must be emitted; got:`n" . content)
    Yunit.Assert(InStr(content, "Config_viewNames_#2=") = 0, "view 2 (baseline) must NOT be emitted; got:`n" . content)
    Yunit.Assert(InStr(content, "Config_viewNames_#3=gamma") > 0, "view 3 must be emitted; got:`n" . content)
  }

  Restore_LoadsViewNames()
  {
    Global Config_viewNames_#3
    Config_viewNames_#3 := "stale"

    FileAppend,
    (
Config_viewNames_#3=restored
    ), % this.TempFile

    Config_restoreLayout(this.TempFile, 1)

    Yunit.Assert(Config_viewNames_#3 = "restored", "restore must load Config_viewNames_#3 from file, got '" . Config_viewNames_#3 . "'")
  }

  RoundTrip_RenameSurvivesSaveAndRestore()
  {
    Global Config_viewNames_#2
    Config_viewNames_#2 := "work"

    Config_saveSession("", this.TempFile)

    ;; Simulate restart: globals get reset by Config_init's StringSplit.
    Config_viewNames_#2 := "2"

    Config_restoreLayout(this.TempFile, 1)

    Yunit.Assert(Config_viewNames_#2 = "work", "round-trip must preserve 'work', got '" . Config_viewNames_#2 . "'")
  }
}
