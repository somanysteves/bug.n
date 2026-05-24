/*
  Tests for Manager_applyViewRename (src/Manager.ahk).

  Manager_applyViewRename(aView, newName) is the pure post-dialog
  helper extracted from Manager_renameView. It performs the guard
  checks and the state mutation; it does NOT pop the InputBox or
  rebuild the bar (those stay in Manager_renameView).

  Returns True if the rename was applied (and sets Manager_layoutDirty),
  False otherwise.
*/

class TestManagerApplyViewRename
{
  Begin()
  {
    Global Config_viewNames_#3, Config_viewNames_#5, Manager_layoutDirty

    Config_viewNames_#3 := "3"
    Config_viewNames_#5 := "5"
    Manager_layoutDirty := 0
  }

  EmptyName_NoOp()
  {
    Global Config_viewNames_#3, Manager_layoutDirty
    result := Manager_applyViewRename(3, "")
    Yunit.Assert(result = False, "empty name must return False, got '" . result . "'")
    Yunit.Assert(Config_viewNames_#3 = "3", "empty name must not mutate, got '" . Config_viewNames_#3 . "'")
    Yunit.Assert(Manager_layoutDirty = 0, "empty name must not set dirty, got '" . Manager_layoutDirty . "'")
  }

  UnchangedName_NoOp()
  {
    Global Config_viewNames_#3, Manager_layoutDirty
    result := Manager_applyViewRename(3, "3")
    Yunit.Assert(result = False, "unchanged name must return False, got '" . result . "'")
    Yunit.Assert(Config_viewNames_#3 = "3", "unchanged name must not mutate, got '" . Config_viewNames_#3 . "'")
    Yunit.Assert(Manager_layoutDirty = 0, "unchanged name must not set dirty, got '" . Manager_layoutDirty . "'")
  }

  NewName_Mutates()
  {
    Global Config_viewNames_#3, Manager_layoutDirty
    result := Manager_applyViewRename(3, "important")
    Yunit.Assert(result = True, "new name must return True, got '" . result . "'")
    Yunit.Assert(Config_viewNames_#3 = "important", "new name must mutate global, got '" . Config_viewNames_#3 . "'")
    Yunit.Assert(Manager_layoutDirty = 1, "new name must set dirty=1, got '" . Manager_layoutDirty . "'")
  }

  NewName_OnlyTargetViewMutates()
  {
    Global Config_viewNames_#3, Config_viewNames_#5
    Manager_applyViewRename(3, "important")
    Yunit.Assert(Config_viewNames_#3 = "important", "target view 3 must mutate, got '" . Config_viewNames_#3 . "'")
    Yunit.Assert(Config_viewNames_#5 = "5", "neighbour view 5 must be untouched, got '" . Config_viewNames_#5 . "'")
  }

  DifferentView_TargetsCorrectGlobal()
  {
    Global Config_viewNames_#3, Config_viewNames_#5
    Manager_applyViewRename(5, "scratch")
    Yunit.Assert(Config_viewNames_#5 = "scratch", "view 5 must mutate, got '" . Config_viewNames_#5 . "'")
    Yunit.Assert(Config_viewNames_#3 = "3", "view 3 must be untouched, got '" . Config_viewNames_#3 . "'")
  }
}
