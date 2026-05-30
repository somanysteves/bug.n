/*
  Tests for Manager_shouldResetDebouncedTimer (src/Manager.ahk).

  Pure decision for the "debounce with maxWait" pattern (lodash-style
  `_.debounce(fn, wait, { maxWait })`) used by Manager_armDebouncedTimer.
  The raw `SetTimer, ..., -N` debounce in AHK resets the one-shot to
  "fire N ms from now" on every arm, so under sustained re-arming the
  timer is pushed forward indefinitely. This helper gates whether a
  re-arm should reset the pending timer (in-burst, OK to coalesce) or
  leave it alone (cap exceeded, let it fire on schedule).

  Drove the #86 fix (alacritty windows never adopted on a busy machine
  because sustained cross-process EVENT_OBJECT_CREATE/SHOW kept the
  deferred sync timer pinned). The arming wrapper Manager_armDebouncedTimer
  uses this helper; we test the pure decision here so the logic is
  covered without invoking AHK's SetTimer infrastructure.
*/

class TestManagerShouldResetDebouncedTimer
{
  FirstArm_ReturnsTrue()
  {
    ;; firstArmedTick = 0 means "no timer pending"; the caller will record
    ;; the new arm time and SetTimer.
    Yunit.Assert(Manager_shouldResetDebouncedTimer(0, 1000, 250) = True
      , "first arm of a fresh burst must return True")
  }

  UninitializedTick_ReturnsTrue()
  {
    ;; The caller stores firstArmedTick in a dynamic global. An
    ;; uninitialized AHK global reads as "" (empty string), not 0. In
    ;; expression mode `"" = 0` evaluates False (alphabetic fallback),
    ;; so a literal-zero check would treat "" as a stale tick and refuse
    ;; to ever re-arm — the live regression caught by bgEventStorm
    ;; before this test was added.
    Yunit.Assert(Manager_shouldResetDebouncedTimer("", 1000, 250) = True
      , "empty-string firstArmedTick (uninitialized dynamic global) must return True")
  }

  InBurst_ReturnsTrue()
  {
    ;; Subsequent events within the cap reset the timer so the burst
    ;; continues to coalesce into a single deferred fire.
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 1100, 250) = True
      , "event 100 ms into burst (cap 250) must reset timer")
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 1249, 250) = True
      , "event 249 ms into burst (cap 250) must reset timer")
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 1000, 250) = True
      , "event at the same tick as first arm must reset timer")
  }

  CapExceeded_ReturnsFalse()
  {
    ;; Once the cap is reached, leave the pending timer alone so the
    ;; deferred fire can finally happen. This is the core #86 fix —
    ;; without it, sustained events push the one-shot forward indefinitely.
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 1250, 250) = False
      , "event at exactly the cap must not reset timer")
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 5000, 250) = False
      , "event well past the cap must not reset timer")
  }

  NaiveMode_AlwaysResets()
  {
    ;; maxDelayMs = 0 is the opt-out: callers that don't want the cap
    ;; (every other deferred timer in Manager.ahk, pre-migration) get the
    ;; current naive-debounce behavior — always reset, no upper bound.
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 1100, 0) = True
      , "naive mode (maxDelay=0) must reset within nominal burst")
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 999999, 0) = True
      , "naive mode (maxDelay=0) must reset even at arbitrary delta")
  }

  TickWraparound_ReturnsFalse()
  {
    ;; A_TickCount is 32-bit and rolls over every ~49.7 days. If a wrap
    ;; lands inside an active burst (firstArmedTick near max, now small)
    ;; the subtraction is negative — treat as cap-exceeded so the pending
    ;; timer fires and the next event starts a fresh burst in the new
    ;; tick range.
    Yunit.Assert(Manager_shouldResetDebouncedTimer(4294967200, 100, 250) = False
      , "negative delta from A_TickCount wrap must return False")
  }

  CustomMaxDelay_IsRespected()
  {
    ;; The cap is parameterized — caller chooses the policy. Verify the
    ;; comparison uses the passed value, not a hard-coded constant.
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 1099, 100) = True
      , "99 ms into burst with cap 100 must reset")
    Yunit.Assert(Manager_shouldResetDebouncedTimer(1000, 1100, 100) = False
      , "100 ms into burst with cap 100 must not reset")
  }
}
