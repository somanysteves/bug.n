/*
  Tests for Manager_isStaleViewBounce in src/Manager.ahk (#43).

  Pins the predicate used by Manager_onShellMessage's
  Config_onActiveHiddenWnds = "view" branch to suppress late HSHELL
  events that would bounce the user back to the view they just left.

  A bounce is stale when ALL of:
    - candidate view equals the previous view (aView_#2), AND
    - the new-hidden wndId IS the shell event source (wndId == lParam)
      — otherwise the event is unrelated to what sync found, and
      lParam-on-current-view tells us nothing about wndId,
    - lParam is already in the current view's wndIds (matched against
      ";"-wrapped delimiters so suffix substrings don't false-match).

  Pure predicate, no globals — Begin/End not needed.
*/

class TestManagerStaleBounce
{
  StaleBounce_AllConditionsHold_Skips()
  {
    ;; candidate=prev, wndId==lParam, lParam in current view → stale
    Yunit.Assert(Manager_isStaleViewBounce(1, 1, "12345;67890;", 67890, 67890)
      , "candidate==prev AND wndId==lParam AND lParam in current view's wndIds → should skip")
  }

  StaleBounce_LParamNotOnCurrent_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "12345;", 67890, 67890)
      , "candidate==prev but lParam NOT on current view is a real signal; should not skip")
  }

  StaleBounce_CandidateIsOtherView_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(3, 1, "67890;", 67890, 67890)
      , "candidate is some other view (not prev); should not be classified as stale")
  }

  StaleBounce_EmptyWndIds_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "", 67890, 67890)
      , "current view has no windows; cannot be a stale echo; should not skip")
  }

  ;; Regression guard for Copilot review on PR #56: lParam is the shell
  ;; event source, wndId is sync's first-new-hidden — they aren't always
  ;; the same. A late event for an unrelated window X (already on current
  ;; view) must NOT suppress a legitimate switch to the view containing
  ;; an unrelated new-hidden Y that sync happened to discover on the same
  ;; event. The predicate must pin "this exact event is the echo of our
  ;; own reveal" by requiring wndId == lParam.
  StaleBounce_WndIdDiffersFromLParam_Allows()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "67890;", 11111, 67890)
      , "wndId 11111 (sync's new-hidden) differs from lParam 67890 (event source); "
      . "even though lParam is on current view, the event tells us nothing about wndId; "
      . "should not skip")
  }

  ;; Regression guard for Copilot review on PR #56: the membership check
  ;; must use ";"-wrapped delimiters on both sides. Without that, lParam
  ;; 7890 matches as a substring of "67890;" (suffix collision), falsely
  ;; classifying a legitimate bounce as stale.
  StaleBounce_SuffixCollision_AvoidsFalseMatch()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "67890;", 7890, 7890)
      , "lParam 7890 must not match suffix of 67890 in wndIds; should not skip")
  }

  ;; Symmetric guard: prefix substring (lParam 6789 vs "67890;").
  StaleBounce_PrefixCollision_AvoidsFalseMatch()
  {
    Yunit.Assert(Not Manager_isStaleViewBounce(1, 1, "67890;", 6789, 6789)
      , "lParam 6789 must not match prefix of 67890 in wndIds; should not skip")
  }

  ;; First-element membership — guard against off-by-one in the ";"-wrap
  ;; (the prepended ";" must allow head-of-list matches).
  StaleBounce_FirstWndIdInList_Skips()
  {
    Yunit.Assert(Manager_isStaleViewBounce(1, 1, "67890;12345;", 67890, 67890)
      , "lParam at head of currentViewWndIds is a valid membership; should skip")
  }
}
