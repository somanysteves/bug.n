/*
  Tests for Manager_isStaleViewBounce in src/Manager.ahk (#43).

  Pins the predicate used by Manager_onShellMessage's
  Config_onActiveHiddenWnds = "view" branch to suppress late HSHELL
  events that would bounce the user back to the view they just left.
  The stale-bounce signature is: candidate view equals the previous
  view (aView_#2) AND the event source (lParam) is already in the
  current view's wndIds — meaning we already revealed it here and
  the HSHELL is just an echo of our own ShowWindowAsync.

  Pure predicate, no globals — Begin/End not needed.
*/

class TestManagerStaleBounce
{
  StaleBounce_CandidateIsPrev_LParamOnCurrent_Skips()
  {
    Yunit.Assert(Manager_isStaleViewBounce(1, 1, "12345;67890;", 67890)
      , "candidate==prev AND lParam in current view's wndIds is stale; should skip")
  }

  StaleBounce_CandidateIsPrev_LParamNotOnCurrent_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "12345;", 67890)
      , "candidate==prev but lParam NOT on current view is a real signal; should not skip")
  }

  StaleBounce_CandidateIsOtherView_LParamOnCurrent_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(3, 1, "67890;", 67890)
      , "candidate is some other view (not prev); should not be classified as stale even if lParam is here")
  }

  StaleBounce_CandidateIsOtherView_LParamNotOnCurrent_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(3, 1, "12345;", 67890)
      , "candidate is unrelated view; should not skip")
  }

  StaleBounce_EmptyWndIds_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "", 67890)
      , "current view has no windows; cannot be a stale echo; should not skip")
  }

  StaleBounce_DelimiterRequired_AvoidsPrefixCollision()
  {
    ;; "67890;" appears, but lParam is 6789 — without the trailing ";"
    ;; we would falsely match the prefix and skip a legitimate bounce.
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "67890;", 6789)
      , "lParam 6789 must not match prefix of 67890 in wndIds; should not skip")
  }
}
