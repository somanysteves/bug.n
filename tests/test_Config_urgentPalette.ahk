/*
  Schema regression test for the urgent palette (palette #3).

  Bar_updateStatus and Bar_updateView read indexed globals like
  Config_backColor_#3_#1 (view slot) and Config_backColor_#3_#8
  (batteryStatus slot). Those indexed names are produced by
  Config_initColors's StringSplit on `;`. If a future edit to
  src/Config.ahk:228-247 changes the number of `;` placeholders,
  the slot mapping shifts and Bar_updateStatus reads the wrong color.

  These assertions exercise Config_initColors with the production
  literal strings copied here. If you change Config.ahk:228-247,
  update the inputs below to match — the assertions will catch any
  resulting slot drift.

  Schema reference (src/Config.ahk:221):
    <view>;<layout>;<title>;<shebang>;<time>;<date>;<anyText>;<batteryStatus>;<volumeLevel>
*/

class TestConfigUrgentPalette
{
  Begin()
  {
    Global

    ;; Production values from src/Config.ahk:229, 238, 247.
    ;; Sentinels stand in for COLOR_INACTIVECAPTION / COLOR_INACTIVECAPTIONTEXT
    ;; so the test doesn't depend on the runner's system theme.
    Config_backColor_#3 := "cc0000;;;;;;;ff8040;"
    Config_foreColor_#3 := "cc0000;;;;;;;SENTINEL_FORE;"
    Config_fontColor_#3 := "ffffff;;;;;;;SENTINEL_FONT;"

    Config_initColors()
  }

  End()
  {
    Global

    Config_backColor_#3    := ""
    Config_foreColor_#3    := ""
    Config_fontColor_#3    := ""
    Config_backColor_#3_#0 := ""
    Config_foreColor_#3_#0 := ""
    Config_fontColor_#3_#0 := ""
    Loop, 9 {
      Config_backColor_#3_#%A_Index% := ""
      Config_foreColor_#3_#%A_Index% := ""
      Config_fontColor_#3_#%A_Index% := ""
    }
  }

  BackColor_NineSlots()
  {
    Global
    Yunit.Assert(Config_backColor_#3_#0 = 9
      , "expected 9 slots, got " . Config_backColor_#3_#0)
  }

  BackColor_Slot1_View_IsUrgentRed()
  {
    Global
    Yunit.Assert(Config_backColor_#3_#1 = "cc0000"
      , "view slot expected 'cc0000', got '" . Config_backColor_#3_#1 . "'")
  }

  BackColor_Slot8_BatteryStatus_KeepsLowBatteryFill()
  {
    Global
    Yunit.Assert(Config_backColor_#3_#8 = "ff8040"
      , "batteryStatus slot expected 'ff8040', got '" . Config_backColor_#3_#8 . "'")
  }

  BackColor_MiddleSlots_AreEmpty()
  {
    Global
    Loop, 6 {
      idx := A_Index + 1   ; check #2 through #7
      val := Config_backColor_#3_#%idx%
      Yunit.Assert(val = ""
        , "expected slot #" . idx . " empty, got '" . val . "'")
    }
  }

  ForeColor_Slot1_View_IsUrgentRed()
  {
    Global
    Yunit.Assert(Config_foreColor_#3_#1 = "cc0000"
      , "fore view slot expected 'cc0000', got '" . Config_foreColor_#3_#1 . "'")
  }

  ForeColor_Slot8_BatteryStatus_KeepsSentinel()
  {
    Global
    Yunit.Assert(Config_foreColor_#3_#8 = "SENTINEL_FORE"
      , "fore batteryStatus slot expected 'SENTINEL_FORE', got '" . Config_foreColor_#3_#8 . "'")
  }

  FontColor_Slot1_View_IsWhite()
  {
    Global
    Yunit.Assert(Config_fontColor_#3_#1 = "ffffff"
      , "font view slot expected 'ffffff', got '" . Config_fontColor_#3_#1 . "'")
  }

  FontColor_Slot8_BatteryStatus_KeepsSentinel()
  {
    Global
    Yunit.Assert(Config_fontColor_#3_#8 = "SENTINEL_FONT"
      , "font batteryStatus slot expected 'SENTINEL_FONT', got '" . Config_fontColor_#3_#8 . "'")
  }
}
