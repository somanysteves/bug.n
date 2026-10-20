/*
  Tests for Manager_consumeSpawnPin (src/Manager.ahk).

  The spawn-pin file (Main_dataDir\spawn-pins.txt) carries one
  "<refHwnd> <unixEpochSecondsUTC> <matchExe> <matchClass>" request per
  line. consumeSpawnPin is handed the new window's exe + class and takes
  the oldest fresh line whose declared match fits it and whose refHwnd is
  a managed window, copies that window's monitor + tag bitmask into
  m/tags, and returns True. Stale (>15s) lines and matching lines whose
  reference isn't managed are dropped; fresh lines declared for some other
  window are left for it. "*" or an absent field is a wildcard, so a
  legacy 2-field line matches any window.

  Tests point Main_dataDir at A_Temp and manage a single window
  (0xb00b1, decimal 721073) on monitor 2 / view 3 (tags = 4). The
  decimal form in the file also exercises Manager_isManaged's hex/decimal
  coercion.
*/

class TestManagerConsumeSpawnPin
{
  Begin()
  {
    Global Main_dataDir, Manager_managedWndIds
    Global Window_#0xb00b1_monitor, Window_#0xb00b1_tags

    Main_dataDir          := A_Temp
    Manager_managedWndIds := "0xb00b1;"
    Window_#0xb00b1_monitor := 2
    Window_#0xb00b1_tags    := 4   ;; 1 << (3-1) -> view 3 only

    this.RefKey  := "0xb00b1"
    this.RefDec  := 721073         ;; 0xb00b1 as decimal, the producer's form
    this.PinFile := A_Temp . "\spawn-pins.txt"

    now := A_NowUTC
    now -= 19700101000000, Seconds
    this.FreshTs := now
    this.StaleTs := now - 100      ;; well past the 15s freshness window

    If FileExist(this.PinFile)
      FileDelete, % this.PinFile
  }

  End()
  {
    If FileExist(this.PinFile)
      FileDelete, % this.PinFile
  }

  FreshManagedPin_SetsMonitorAndTags_ReturnsTrue()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "alacritty.exe Window Class")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = True, "fresh managed pin must be applied")
    Yunit.Assert(m = 2, "monitor must be copied from the reference (2), got '" . m . "'")
    Yunit.Assert(tags = 4, "tags must be copied from the reference (4), got '" . tags . "'")
  }

  ConsumedPin_RemovedFromFile()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "chrome.exe Chrome_WidgetWin_1")

    Manager_consumeSpawnPin(m, tags, "chrome.exe", "Chrome_WidgetWin_1")

    Yunit.Assert(Not FileExist(this.PinFile), "sole consumed line must leave no file behind")
  }

  ExeMatchIsCaseInsensitive()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "Chrome.EXE Chrome_WidgetWin_1")

    applied := Manager_consumeSpawnPin(m, tags, "chrome.exe", "Chrome_WidgetWin_1")

    Yunit.Assert(applied = True, "exe comparison must ignore case")
  }

  ClassMatchIsCaseSensitive()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "chrome.exe chrome_widgetwin_1")

    applied := Manager_consumeSpawnPin(m, tags, "chrome.exe", "Chrome_WidgetWin_1")

    Yunit.Assert(applied = False, "class comparison must be exact")
  }

  NonMatchingFreshPin_Preserved()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "chrome.exe Chrome_WidgetWin_1")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = False, "a chrome pin must not be consumed by an alacritty window")
    Yunit.Assert(m = 9 And tags = 0, "m/tags must be untouched when nothing applies")
    Yunit.Assert(InStr(SpawnPinTest_read(this.PinFile), "Chrome_WidgetWin_1") > 0, "non-matching fresh line must stay for its own window, got:`n" . SpawnPinTest_read(this.PinFile))
  }

  SiblingClass_DoesNotConsume()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "alacritty.exe Window Class")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Winit Thread Event Target")

    Yunit.Assert(applied = False, "a winit sibling window (same exe, other class) must not consume the pin")
    Yunit.Assert(InStr(SpawnPinTest_read(this.PinFile), "Window Class") > 0, "pin must survive for the real terminal")
  }

  ForeignChromium_DoesNotConsume()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "chrome.exe Chrome_WidgetWin_1")

    applied := Manager_consumeSpawnPin(m, tags, "Code.exe", "Chrome_WidgetWin_1")

    Yunit.Assert(applied = False, "same class from another exe must not consume the pin")
  }

  NonMatchingThenMatching_TakesMatch_PreservesOther()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, "222222", this.FreshTs, "chrome.exe Chrome_WidgetWin_1")
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "alacritty.exe Window Class")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = True, "the matching line behind a non-matching one must apply")
    Yunit.Assert(m = 2 And tags = 4, "monitor/tags must come from the matching line's ref")
    content := SpawnPinTest_read(this.PinFile)
    Yunit.Assert(InStr(content, "222222 ") = 1, "non-matching earlier line must be preserved, got:`n" . content)
    Yunit.Assert(InStr(content, this.RefDec) = 0, "consumed line must be gone, got:`n" . content)
  }

  ExeWildcard_Matches()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "* Chrome_WidgetWin_1")

    applied := Manager_consumeSpawnPin(m, tags, "msedge.exe", "Chrome_WidgetWin_1")

    Yunit.Assert(applied = True, "'*' exe must match any exe")
  }

  ClassWildcard_Matches()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "SumatraPDF.exe *")

    applied := Manager_consumeSpawnPin(m, tags, "SumatraPDF.exe", "SUMATRA_PDF_FRAME")

    Yunit.Assert(applied = True, "'*' class must match any class")
  }

  ExeOnly_ClassAbsent_MatchesAnyClass()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "SumatraPDF.exe")

    applied := Manager_consumeSpawnPin(m, tags, "SumatraPDF.exe", "SUMATRA_PDF_FRAME")

    Yunit.Assert(applied = True, "an absent class field must match any class")
  }

  LegacyLine_MatchesAnyWindow()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs)

    applied := Manager_consumeSpawnPin(m, tags, "chrome.exe", "Chrome_WidgetWin_1")

    Yunit.Assert(applied = True, "a legacy 2-field line must be consumed by any window")
    Yunit.Assert(m = 2 And tags = 4, "monitor/tags must come from the legacy line's ref")
    Yunit.Assert(Not FileExist(this.PinFile), "consumed legacy line must be removed")
  }

  StalePin_Ignored_AndDropped()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.StaleTs, "alacritty.exe Window Class")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = False, "stale pin must not be applied")
    Yunit.Assert(m = 9, "m must be untouched when nothing applies, got '" . m . "'")
    Yunit.Assert(tags = 0, "tags must be untouched when nothing applies, got '" . tags . "'")
    Yunit.Assert(Not FileExist(this.PinFile), "stale line must be dropped from the file")
  }

  StaleNonMatchingPin_StillDropped()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.StaleTs, "chrome.exe Chrome_WidgetWin_1")

    Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(Not FileExist(this.PinFile), "any window's pass must sweep stale lines, matching or not")
  }

  UnmanagedRef_Ignored_AndDropped()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, "999999", this.FreshTs, "alacritty.exe Window Class")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = False, "fresh pin for an unmanaged ref must not be applied")
    Yunit.Assert(Not FileExist(this.PinFile), "unmanaged-ref line must be dropped")
  }

  MalformedLine_Dropped()
  {
    m := 9, tags := 0
    FileAppend, % "garbage`n", % this.PinFile

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = False, "a malformed line must not apply")
    Yunit.Assert(Not FileExist(this.PinFile), "a malformed line must be dropped")
  }

  NoFile_ReturnsFalse()
  {
    m := 9, tags := 0
    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = False, "absent pin file must yield False")
    Yunit.Assert(m = 9, "m must be untouched, got '" . m . "'")
  }

  Fifo_TakesOldestMatch_PreservesRemainder()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "alacritty.exe Window Class")
    SpawnPinTest_pin(this.PinFile, "222222", this.FreshTs, "alacritty.exe Window Class")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = True, "oldest matching pin must be applied")
    Yunit.Assert(m = 2 And tags = 4, "monitor/tags must come from the first line's ref")
    content := SpawnPinTest_read(this.PinFile)
    Yunit.Assert(InStr(content, "222222") > 0, "unused second line must be preserved, got:`n" . content)
    Yunit.Assert(InStr(content, this.RefDec) = 0, "consumed first line must be gone, got:`n" . content)
  }

  StaleBeforeFresh_SkipsStale_AppliesFresh()
  {
    m := 9, tags := 0
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.StaleTs, "alacritty.exe Window Class")
    SpawnPinTest_pin(this.PinFile, this.RefDec, this.FreshTs, "alacritty.exe Window Class")

    applied := Manager_consumeSpawnPin(m, tags, "alacritty.exe", "Window Class")

    Yunit.Assert(applied = True, "fresh line after a stale one must still apply")
    Yunit.Assert(m = 2 And tags = 4, "monitor/tags must be set from the fresh line")
    Yunit.Assert(Not FileExist(this.PinFile), "stale (dropped) + fresh (consumed) must leave no file")
  }
}

;; Helpers live outside the class: Yunit runs every class method as a test.
SpawnPinTest_pin(file, ref, ts, match := "")
{
  FileAppend, % ref . " " . ts . (match = "" ? "" : " " . match) . "`n", %file%
}

SpawnPinTest_read(file)
{
  If Not FileExist(file)
    Return ""
  FileRead, content, %file%
  Return content
}
