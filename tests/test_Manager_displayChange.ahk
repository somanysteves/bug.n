/*
  Tests for the WM_DISPLAYCHANGE decision logic and session-choice
  recording in src/Manager.ahk.

  The dialog itself (Manager_displayChangePrompt) is a Gui modal and is
  not exercised here — these tests cover the pure decision function
  (Manager_displayChangeDecide) and the session-storage helper
  (Manager_displayChangeRecordSessionChoice) that together drive what
  happens when the user ticks "Remember this decision for this session".
*/

class TestManagerDisplayChange
{
  ;; --- Manager_displayChangeDecide: persistent config, no session override ---

  Decide_PromptWhenAskAndNoSession()
  {
    Yunit.Assert(Manager_displayChangeDecide("ask", "") = "prompt"
      , "config=ask + no session choice should prompt; got " . Manager_displayChangeDecide("ask", ""))
  }

  Decide_ResetWhenConfigOn()
  {
    Yunit.Assert(Manager_displayChangeDecide("on", "") = "reset"
      , "config=on should reset; got " . Manager_displayChangeDecide("on", ""))
  }

  Decide_IgnoreWhenConfigOff()
  {
    Yunit.Assert(Manager_displayChangeDecide("off", "") = "ignore"
      , "config=off should ignore; got " . Manager_displayChangeDecide("off", ""))
  }

  Decide_IgnoreWhenConfigZero()
  {
    ;; Legacy: numeric 0 is accepted as a synonym for "off" (Manager.ahk:692).
    Yunit.Assert(Manager_displayChangeDecide(0, "") = "ignore"
      , "config=0 should ignore; got " . Manager_displayChangeDecide(0, ""))
  }

  ;; --- Manager_displayChangeDecide: session override beats config ---

  Decide_SessionYesOverridesAsk()
  {
    Yunit.Assert(Manager_displayChangeDecide("ask", "yes") = "reset"
      , "session=yes should reset even when config=ask; got " . Manager_displayChangeDecide("ask", "yes"))
  }

  Decide_SessionNoOverridesAsk()
  {
    Yunit.Assert(Manager_displayChangeDecide("ask", "no") = "rearrange"
      , "session=no should rearrange even when config=ask; got " . Manager_displayChangeDecide("ask", "no"))
  }

  Decide_SessionCancelOverridesAsk()
  {
    Yunit.Assert(Manager_displayChangeDecide("ask", "cancel") = "ignore"
      , "session=cancel should ignore even when config=ask; got " . Manager_displayChangeDecide("ask", "cancel"))
  }

  ;; Session override beats *any* config value, not just "ask". Not reachable
  ;; in normal use (the prompt only fires when config=ask), but the function
  ;; contract is "session wins" — locks in the precedence.
  Decide_SessionBeatsConflictingConfig()
  {
    Yunit.Assert(Manager_displayChangeDecide("on", "cancel") = "ignore"
      , "session=cancel must beat config=on; got " . Manager_displayChangeDecide("on", "cancel"))
    Yunit.Assert(Manager_displayChangeDecide("off", "yes") = "reset"
      , "session=yes must beat config=off; got " . Manager_displayChangeDecide("off", "yes"))
  }

  ;; --- Manager_displayChangeRecordSessionChoice ---

  Record_RememberStoresYes()
  {
    Global Manager_displayChangeSessionChoice
    Manager_displayChangeSessionChoice := ""
    Manager_displayChangeRecordSessionChoice("yes", True)
    Yunit.Assert(Manager_displayChangeSessionChoice = "yes"
      , "remember=True with choice=yes should store 'yes'; got '" . Manager_displayChangeSessionChoice . "'")
  }

  Record_RememberStoresNo()
  {
    Global Manager_displayChangeSessionChoice
    Manager_displayChangeSessionChoice := ""
    Manager_displayChangeRecordSessionChoice("no", True)
    Yunit.Assert(Manager_displayChangeSessionChoice = "no"
      , "remember=True with choice=no should store 'no'; got '" . Manager_displayChangeSessionChoice . "'")
  }

  Record_RememberStoresCancel()
  {
    Global Manager_displayChangeSessionChoice
    Manager_displayChangeSessionChoice := ""
    Manager_displayChangeRecordSessionChoice("cancel", True)
    Yunit.Assert(Manager_displayChangeSessionChoice = "cancel"
      , "remember=True with choice=cancel should store 'cancel'; got '" . Manager_displayChangeSessionChoice . "'")
  }

  Record_NoRememberLeavesUnchanged()
  {
    Global Manager_displayChangeSessionChoice
    Manager_displayChangeSessionChoice := ""
    Manager_displayChangeRecordSessionChoice("yes", False)
    Yunit.Assert(Manager_displayChangeSessionChoice = ""
      , "remember=False must not store choice; got '" . Manager_displayChangeSessionChoice . "'")
  }

  Record_NoRememberPreservesPriorSession()
  {
    ;; If a previous prompt set "no" with remember=True, an unticked
    ;; "yes" on a later prompt must not overwrite it.
    Global Manager_displayChangeSessionChoice
    Manager_displayChangeSessionChoice := "no"
    Manager_displayChangeRecordSessionChoice("yes", False)
    Yunit.Assert(Manager_displayChangeSessionChoice = "no"
      , "remember=False must preserve prior session choice; got '" . Manager_displayChangeSessionChoice . "'")
  }

  Record_RememberOverwritesPrevious()
  {
    Global Manager_displayChangeSessionChoice
    Manager_displayChangeSessionChoice := "no"
    Manager_displayChangeRecordSessionChoice("yes", True)
    Yunit.Assert(Manager_displayChangeSessionChoice = "yes"
      , "remember=True must overwrite prior session choice; got '" . Manager_displayChangeSessionChoice . "'")
  }
}
