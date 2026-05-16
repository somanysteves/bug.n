/*
  Tests for Manager_modifiersFromHotkey (src/Manager.ahk).

  Pure parser: given an AHK hotkey string, returns a SendInput-compatible
  key-up sequence for each modifier prefix (# ! ^ +). Used by
  Manager_closeWindow to drain WM_KEYUP messages that would otherwise be
  swallowed by the closed window, leaving phantom modifier state held.
*/

class TestManagerModifiersFromHotkey
{
  EmptyHotkey_ReturnsEmpty()
  {
    Yunit.Assert(Manager_modifiersFromHotkey("") = ""
      , "empty hotkey should return ''; got '" . Manager_modifiersFromHotkey("") . "'")
  }

  NoModifier_ReturnsEmpty()
  {
    Yunit.Assert(Manager_modifiersFromHotkey("F1") = ""
      , "no modifier prefix should return ''; got '" . Manager_modifiersFromHotkey("F1") . "'")
  }

  WinPrefix_ReturnsLWinAndRWinUp()
  {
    Yunit.Assert(Manager_modifiersFromHotkey("#c") = "{LWin up}{RWin up}"
      , "# prefix; got '" . Manager_modifiersFromHotkey("#c") . "'")
  }

  ShiftPrefix_ReturnsLShiftAndRShiftUp()
  {
    Yunit.Assert(Manager_modifiersFromHotkey("+c") = "{LShift up}{RShift up}"
      , "+ prefix; got '" . Manager_modifiersFromHotkey("+c") . "'")
  }

  CtrlPrefix_ReturnsLCtrlAndRCtrlUp()
  {
    Yunit.Assert(Manager_modifiersFromHotkey("^c") = "{LCtrl up}{RCtrl up}"
      , "^ prefix; got '" . Manager_modifiersFromHotkey("^c") . "'")
  }

  AltPrefix_ReturnsLAltAndRAltUp()
  {
    Yunit.Assert(Manager_modifiersFromHotkey("!c") = "{LAlt up}{RAlt up}"
      , "! prefix; got '" . Manager_modifiersFromHotkey("!c") . "'")
  }

  ShiftWin_BothModifiers()
  {
    ;; The user's actual close hotkey: Shift+Win+C.
    Yunit.Assert(Manager_modifiersFromHotkey("#+c") = "{LWin up}{RWin up}{LShift up}{RShift up}"
      , "#+ prefix; got '" . Manager_modifiersFromHotkey("#+c") . "'")
  }

  AllFourModifiers_AllKeysUp()
  {
    Local expected
    expected := "{LWin up}{RWin up}{LShift up}{RShift up}{LCtrl up}{RCtrl up}{LAlt up}{RAlt up}"
    Yunit.Assert(Manager_modifiersFromHotkey("#+^!c") = expected
      , "#+^! prefix; got '" . Manager_modifiersFromHotkey("#+^!c") . "'")
  }

  TildePrefix_Skipped()
  {
    ;; ~ means "fire native behavior too" -- not a modifier.
    Yunit.Assert(Manager_modifiersFromHotkey("~#c") = "{LWin up}{RWin up}"
      , "~ prefix should be skipped; got '" . Manager_modifiersFromHotkey("~#c") . "'")
  }

  AsteriskPrefix_Skipped()
  {
    ;; * means "wildcard" -- not a modifier.
    Yunit.Assert(Manager_modifiersFromHotkey("*#c") = "{LWin up}{RWin up}"
      , "* prefix should be skipped; got '" . Manager_modifiersFromHotkey("*#c") . "'")
  }

  DollarPrefix_Skipped()
  {
    ;; $ means "use keyboard hook" -- not a modifier.
    Yunit.Assert(Manager_modifiersFromHotkey("$#c") = "{LWin up}{RWin up}"
      , "$ prefix should be skipped; got '" . Manager_modifiersFromHotkey("$#c") . "'")
  }

  LeftVariantPrefix_Skipped()
  {
    ;; < means "left-modifier variant" of the next prefix. We send both
    ;; left and right keys up regardless, so the < itself is just skipped.
    Yunit.Assert(Manager_modifiersFromHotkey("<^c") = "{LCtrl up}{RCtrl up}"
      , "< prefix should be skipped; got '" . Manager_modifiersFromHotkey("<^c") . "'")
  }

  PreservesInputOrder()
  {
    ;; The function emits key-ups in the order the modifiers appear in the
    ;; hotkey string. Order of release doesn't matter to the OS (each
    ;; modifier is released independently), but documenting the contract:
    ;; we don't sort.
    Yunit.Assert(Manager_modifiersFromHotkey("^#c") = "{LCtrl up}{RCtrl up}{LWin up}{RWin up}"
      , "^# preserves input order; got '" . Manager_modifiersFromHotkey("^#c") . "'")
    Yunit.Assert(Manager_modifiersFromHotkey("#^c") = "{LWin up}{RWin up}{LCtrl up}{RCtrl up}"
      , "#^ preserves input order; got '" . Manager_modifiersFromHotkey("#^c") . "'")
  }

  StopsAtKeyName_NoFalsePositives()
  {
    ;; Make sure a key name that happens to start with a modifier-like char
    ;; doesn't confuse the parser. NumpadAdd starts with N -- not a prefix.
    Yunit.Assert(Manager_modifiersFromHotkey("#NumpadAdd") = "{LWin up}{RWin up}"
      , "multi-char key name; got '" . Manager_modifiersFromHotkey("#NumpadAdd") . "'")
  }
}
