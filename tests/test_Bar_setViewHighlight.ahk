/*
  Tests for src/Bar.ahk:Bar_resolveViewHighlight branch + scope correctness.

  Bar_resolveViewHighlight reads three categories of script-level globals:
    - Static names: Config_backColor_#1_#1, Config_backColor_#2_#1,
      Config_backColor_#3_#1 (and the foreColor / fontColor variants).
    - Dynamic names: Monitor_#%m%_aView_#1, View_#%m%_#%v%_isUrgent.

  AHK v1's variable scope inside a function depends on whether ANY
  declaration (Local / Global / Static) is present. With no declaration the
  function operates in pure assume-local mode and static-name reads of
  script-level globals resolve to local-empty — even though dynamic-name
  reads work via runtime lookup. The empirical behavior was confirmed
  during the perf-instrument-gaps regression (2026-05-10): the resolver's
  predecessor entered the active branch correctly (dynamic read worked)
  but fed empty color args downstream (static read failed), painting
  active views as black squares.

  The `Global` declaration on Bar_resolveViewHighlight is the fix; these
  tests hold it in place by exercising each branch and asserting on the
  resolved background color.

  Bar_setViewHighlight (the GuiControl wrapper) isn't tested here because
  GuiControl in the test environment has no controls to operate on and
  would throw — the resolver/applier split exists to make the resolver
  pure and testable.
*/

class TestBarSetViewHighlight
{
  ResolvesActiveBackColor_WhenViewMatchesMonitorActive()
  {
    Global Config_backColor_#2_#1, Config_foreColor_#2_#1, Config_fontColor_#2_#1
    Global Monitor_#1_aView_#1, View_#1_#5_isUrgent
    Config_backColor_#2_#1 := "active_back"
    Config_foreColor_#2_#1 := "active_fore"
    Config_fontColor_#2_#1 := "active_font"
    Monitor_#1_aView_#1    := 5
    View_#1_#5_isUrgent    := False

    Bar_resolveViewHighlight(1, 5, back, fore, font)
    Yunit.Assert(back = "active_back" && fore = "active_fore" && font = "active_font"
        , "Active branch returned (back='" . back . "', fore='" . fore . "', font='" . font . "'), "
        . "expected ('active_back', 'active_fore', 'active_font'). If empty, the function is "
        . "missing its `Global` declaration and AHK assume-local mode is hiding script-level "
        . "Config_*Color_#2_#1 from static-name reads — Bar_setViewHighlight would then feed "
        . "GuiControl empty color args, rendering the active view as a black square.")
  }

  ResolvesUrgentBackColor_WhenViewIsUrgentNotActive()
  {
    Global Config_backColor_#3_#1, Monitor_#1_aView_#1, View_#1_#3_isUrgent
    Config_backColor_#3_#1 := "urgent_back"
    Monitor_#1_aView_#1    := 5
    View_#1_#3_isUrgent    := True

    Bar_resolveViewHighlight(1, 3, back, fore, font)
    Yunit.Assert(back = "urgent_back"
        , "Urgent branch returned back='" . back . "', expected 'urgent_back'. Empty value "
        . "indicates broken scope; mismatch indicates the wrong branch was taken (likely "
        . "View_#1_#3_isUrgent didn't resolve to the script-level global).")
  }

  ResolvesIdleBackColor_WhenViewIsNeitherActiveNorUrgent()
  {
    Global Config_backColor_#1_#1, Monitor_#1_aView_#1, View_#1_#3_isUrgent
    Config_backColor_#1_#1 := "idle_back"
    Monitor_#1_aView_#1    := 5
    View_#1_#3_isUrgent    := False

    Bar_resolveViewHighlight(1, 3, back, fore, font)
    Yunit.Assert(back = "idle_back"
        , "Idle branch returned back='" . back . "', expected 'idle_back'. Empty value indicates "
        . "broken scope.")
  }
}
