/*
  Tests for Manager_consumeSpawnPin (src/Manager.ahk).

  The spawn-pin file (Main_dataDir\spawn-pins.txt) carries one
  "<refHwnd> <unixEpochSecondsUTC>" request per line. consumeSpawnPin
  takes the oldest fresh line whose refHwnd is a managed window, copies
  that window's monitor + tag bitmask into m/tags, and returns True.
  Stale (>15s) lines and lines whose reference isn't managed are dropped;
  a line taken mid-file leaves the remainder intact (FIFO).

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
    FileAppend, % this.RefDec . " " . this.FreshTs . "`n", % this.PinFile

    applied := Manager_consumeSpawnPin(m, tags)

    Yunit.Assert(applied = True, "fresh managed pin must be applied")
    Yunit.Assert(m = 2, "monitor must be copied from the reference (2), got '" . m . "'")
    Yunit.Assert(tags = 4, "tags must be copied from the reference (4), got '" . tags . "'")
  }

  ConsumedPin_RemovedFromFile()
  {
    m := 9, tags := 0
    FileAppend, % this.RefDec . " " . this.FreshTs . "`n", % this.PinFile

    Manager_consumeSpawnPin(m, tags)

    Yunit.Assert(Not FileExist(this.PinFile), "sole consumed line must leave no file behind")
  }

  StalePin_Ignored_AndDropped()
  {
    m := 9, tags := 0
    FileAppend, % this.RefDec . " " . this.StaleTs . "`n", % this.PinFile

    applied := Manager_consumeSpawnPin(m, tags)

    Yunit.Assert(applied = False, "stale pin must not be applied")
    Yunit.Assert(m = 9, "m must be untouched when nothing applies, got '" . m . "'")
    Yunit.Assert(tags = 0, "tags must be untouched when nothing applies, got '" . tags . "'")
    Yunit.Assert(Not FileExist(this.PinFile), "stale line must be dropped from the file")
  }

  UnmanagedRef_Ignored_AndDropped()
  {
    m := 9, tags := 0
    FileAppend, % "999999 " . this.FreshTs . "`n", % this.PinFile

    applied := Manager_consumeSpawnPin(m, tags)

    Yunit.Assert(applied = False, "fresh pin for an unmanaged ref must not be applied")
    Yunit.Assert(Not FileExist(this.PinFile), "unmanaged-ref line must be dropped")
  }

  NoFile_ReturnsFalse()
  {
    m := 9, tags := 0
    applied := Manager_consumeSpawnPin(m, tags)

    Yunit.Assert(applied = False, "absent pin file must yield False")
    Yunit.Assert(m = 9, "m must be untouched, got '" . m . "'")
  }

  Fifo_TakesOldest_PreservesRemainder()
  {
    m := 9, tags := 0
    FileAppend, % this.RefDec . " " . this.FreshTs . "`n", % this.PinFile
    FileAppend, % "222222 " . this.FreshTs . "`n", % this.PinFile

    applied := Manager_consumeSpawnPin(m, tags)

    Yunit.Assert(applied = True, "oldest managed pin must be applied")
    Yunit.Assert(m = 2 And tags = 4, "monitor/tags must come from the first line's ref")
    FileRead, content, % this.PinFile
    Yunit.Assert(InStr(content, "222222") > 0, "unused second line must be preserved, got:`n" . content)
    Yunit.Assert(InStr(content, this.RefDec) = 0, "consumed first line must be gone, got:`n" . content)
  }

  StaleBeforeFresh_SkipsStale_AppliesFresh()
  {
    m := 9, tags := 0
    FileAppend, % this.RefDec . " " . this.StaleTs . "`n", % this.PinFile
    FileAppend, % this.RefDec . " " . this.FreshTs . "`n", % this.PinFile

    applied := Manager_consumeSpawnPin(m, tags)

    Yunit.Assert(applied = True, "fresh line after a stale one must still apply")
    Yunit.Assert(m = 2 And tags = 4, "monitor/tags must be set from the fresh line")
    Yunit.Assert(Not FileExist(this.PinFile), "stale (dropped) + fresh (consumed) must leave no file")
  }
}
