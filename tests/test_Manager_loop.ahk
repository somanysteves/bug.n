/*
  Tests for src/Manager_loop.ahk.

  Manager_loop(index, increment, lowerBound, upperBound) returns the
  next index when cycling through the inclusive range
  [lowerBound, upperBound], wrapping in either direction. Used for
  cycling through monitors, views, windows, and layouts.

  Returns 0 if the range is empty (upperBound <= 0, or
  upperBound < lowerBound).
*/

class TestManagerLoop
{
  ;; --- forward stepping ---

  ForwardStep_WithinBounds()
  {
    Yunit.Assert(Manager_loop(1, 1, 1, 3) = 2, "loop(1,+1,1,3) expected 2, got " . Manager_loop(1, 1, 1, 3))
    Yunit.Assert(Manager_loop(2, 1, 1, 3) = 3, "loop(2,+1,1,3) expected 3, got " . Manager_loop(2, 1, 1, 3))
  }

  ForwardStep_WrapsAtUpperBound()
  {
    Yunit.Assert(Manager_loop(3, 1, 1, 3) = 1, "loop(3,+1,1,3) expected 1 (wrap), got " . Manager_loop(3, 1, 1, 3))
  }

  ForwardStep_MultiWrap()
  {
    ; index=1, +7 in [1..3] → 1 → 2 → 3 → 1 → 2 → 3 → 1 → 2
    Yunit.Assert(Manager_loop(1, 7, 1, 3) = 2, "loop(1,+7,1,3) expected 2, got " . Manager_loop(1, 7, 1, 3))
  }

  ;; --- backward stepping ---

  BackwardStep_WithinBounds()
  {
    Yunit.Assert(Manager_loop(2, -1, 1, 3) = 1, "loop(2,-1,1,3) expected 1, got " . Manager_loop(2, -1, 1, 3))
    Yunit.Assert(Manager_loop(3, -1, 1, 3) = 2, "loop(3,-1,1,3) expected 2, got " . Manager_loop(3, -1, 1, 3))
  }

  BackwardStep_WrapsAtLowerBound()
  {
    Yunit.Assert(Manager_loop(1, -1, 1, 3) = 3, "loop(1,-1,1,3) expected 3 (wrap), got " . Manager_loop(1, -1, 1, 3))
  }

  BackwardStep_MultiWrap()
  {
    ; index=1, -7 in [1..3] → 1 ← 3 ← 2 ← 1 ← 3 ← 2 ← 1 ← 3
    Yunit.Assert(Manager_loop(1, -7, 1, 3) = 3, "loop(1,-7,1,3) expected 3, got " . Manager_loop(1, -7, 1, 3))
  }

  ;; --- zero increment ---

  ZeroIncrement_ReturnsInputIndex()
  {
    Yunit.Assert(Manager_loop(2, 0, 1, 3) = 2, "loop(2,0,1,3) expected 2, got " . Manager_loop(2, 0, 1, 3))
    Yunit.Assert(Manager_loop(1, 0, 1, 3) = 1, "loop(1,0,1,3) expected 1, got " . Manager_loop(1, 0, 1, 3))
    Yunit.Assert(Manager_loop(3, 0, 1, 3) = 3, "loop(3,0,1,3) expected 3, got " . Manager_loop(3, 0, 1, 3))
  }

  ;; --- non-trivial lowerBound ---

  NonOneLowerBound_ForwardWrap()
  {
    ; range [5..7], wrap from 7 +1 → 5
    Yunit.Assert(Manager_loop(5, 1, 5, 7) = 6, "loop(5,+1,5,7) expected 6, got " . Manager_loop(5, 1, 5, 7))
    Yunit.Assert(Manager_loop(7, 1, 5, 7) = 5, "loop(7,+1,5,7) expected 5 (wrap), got " . Manager_loop(7, 1, 5, 7))
  }

  NonOneLowerBound_BackwardWrap()
  {
    Yunit.Assert(Manager_loop(5, -1, 5, 7) = 7, "loop(5,-1,5,7) expected 7 (wrap), got " . Manager_loop(5, -1, 5, 7))
  }

  ;; --- single-element range ---

  SingleElementRange_ReturnsThatElement()
  {
    Yunit.Assert(Manager_loop(1, 1, 1, 1) = 1, "loop(1,+1,1,1) expected 1, got " . Manager_loop(1, 1, 1, 1))
    Yunit.Assert(Manager_loop(1, -1, 1, 1) = 1, "loop(1,-1,1,1) expected 1, got " . Manager_loop(1, -1, 1, 1))
    Yunit.Assert(Manager_loop(1, 99, 1, 1) = 1, "loop(1,+99,1,1) expected 1, got " . Manager_loop(1, 99, 1, 1))
  }

  ;; --- guards for empty/invalid ranges ---

  UpperBoundZero_ReturnsZero()
  {
    Yunit.Assert(Manager_loop(1, 1, 1, 0) = 0, "loop(1,+1,1,0) expected 0 (ub<=0), got " . Manager_loop(1, 1, 1, 0))
  }

  UpperBoundLessThanLowerBound_ReturnsZero()
  {
    ; e.g. a monitor list that hasn't been initialised yet (0 monitors):
    ; caller passes (1, +1, 1, 0) → 0; or an inverted range (1, +1, 3, 1) → 0.
    Yunit.Assert(Manager_loop(1, 1, 3, 1) = 0, "loop(1,+1,3,1) expected 0 (ub<lb), got " . Manager_loop(1, 1, 3, 1))
  }

  NegativeUpperBound_ReturnsZero()
  {
    Yunit.Assert(Manager_loop(1, 1, 1, -1) = 0, "loop(1,+1,1,-1) expected 0 (ub<=0), got " . Manager_loop(1, 1, 1, -1))
  }
}
