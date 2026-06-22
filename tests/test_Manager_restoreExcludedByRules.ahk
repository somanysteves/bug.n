/*
  Tests for Manager__restoreExcludedByRules (src/Manager.ahk).

  Gates the "drop this window because current rules exclude it" decision
  inside Manager__restoreWindowState on the restore context:

    - Cold startup / crash recovery (reapplyRules = True): the on-disk
      state may predate a config or rule edit, so re-checking rules and
      dropping a now-excluded window is correct.
    - Live display-change restore (reapplyRules = False): the state was
      written milliseconds earlier by this same process with these same
      rules. A just-reconnected window (Edge/Electron/terminal) often has
      a transiently blank title, so a title-keyed rule check returns
      "not managed" and the window is dropped from every view — invisible
      and unreachable. We must NOT re-check rules here; trust saved state.

  Pure decision factored out of the restore loop so the regression is
  covered without a real WM_DISPLAYCHANGE, a real window, or the
  WinGetTitle inside Manager_applyRules firing.
*/

class TestManagerRestoreExcludedByRules
{
  ;; Cold startup: a window the current rules now exclude must be dropped.
  ColdStartup_RuleExcludes_Dropped()
  {
    Yunit.Assert(Manager__restoreExcludedByRules(True, False)
      , "cold startup must drop a window current rules exclude")
  }

  ;; Cold startup: a window the current rules still manage is kept.
  ColdStartup_RuleManages_Kept()
  {
    Yunit.Assert(Not Manager__restoreExcludedByRules(True, True)
      , "cold startup must keep a window current rules still manage")
  }

  ;; The regression: on a live display-change restore, even a (transiently)
  ;; rule-excluded window must be kept — its title was just unreadable, not
  ;; genuinely unmanaged.
  DisplayChange_RuleExcludes_Kept()
  {
    Yunit.Assert(Not Manager__restoreExcludedByRules(False, False)
      , "display-change restore must NOT drop on a transient rule miss")
  }

  ;; Display-change restore keeps managed windows too (saved isManaged honored).
  DisplayChange_RuleManages_Kept()
  {
    Yunit.Assert(Not Manager__restoreExcludedByRules(False, True)
      , "display-change restore keeps managed windows")
  }
}
