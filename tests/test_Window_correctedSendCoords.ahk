/*
  Tests for Window_correctedSendCoords (src/Window.ahk).

  Pure ByRef math: given a target visible rect and the window's per-side
  invisible-border offsets, populate the SetWindowPos-bound sendX/Y/W/H.
  Both Window_moveAsync and the Tiler's DeferWindowPos batch route through
  this helper, so a single sign error here would break tiling positioning
  everywhere -- exactly the regression caught by dogfood on PR #38 before
  this helper was extracted. These tests pin the formula.

  Per-side rather than symmetric: Win10/11 non-maximized windows have
  top = 0 and left/right/bottom ≈ 8 px, so the previous symmetric-average
  formula landed every stack tile 4 px above its target. #41 surfaced
  this; the per-side correction lands the visible rect at the target
  exactly under that condition.
*/

class TestWindowCorrectedSendCoords
{
  ZeroOffsets_PassesThroughUnchanged()
  {
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(100, 200, 300, 400, 0, 0, 0, 0, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = 100 And sendY = 200 And sendW = 300 And sendH = 400
      , "zero offsets should pass through unchanged; got (" . sendX . "," . sendY . "," . sendW . "," . sendH . ")")
  }

  SymmetricShadow_ShiftsAndGrows()
  {
    ;; Maximized Win11 window or pre-Win10 app: invisible border on all
    ;; four sides. GWR origin moves up-left by the border, GWR dimensions
    ;; grow by 2x border so visible rect lands at target.
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(100, 200, 800, 600, 5, 7, 5, 7, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = 93,  "symmetric: left-offset 7 should shift GWR.left to target - 7; got sendX=" . sendX)
    Yunit.Assert(sendY = 195, "symmetric: top-offset 5 should shift GWR.top to target - 5; got sendY=" . sendY)
    Yunit.Assert(sendW = 814, "symmetric: width grows by left+right = 14; got sendW=" . sendW)
    Yunit.Assert(sendH = 610, "symmetric: height grows by top+bottom = 10; got sendH=" . sendH)
  }

  Win11NonMaximized_TopZeroBottomEight_LandsAtTarget()
  {
    ;; The bug #41 caught. Top=0 (resize handle inside title bar),
    ;; left/right/bottom=8 (drop shadow). Old symmetric formula averaged
    ;; (0 + 8)/2 = 4 and shifted sendY up by 4, landing the visible rect
    ;; 4 px above target. Per-side formula leaves sendY = target since
    ;; top_off = 0; sendH grows by (0 + 8) = 8 to absorb the bottom shadow.
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(1896, 12, 1896, 413, 0, 8, 8, 8, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = 1888, "win11 non-max: sendX = target - left_off (8); got sendX=" . sendX)
    Yunit.Assert(sendY = 12,   "win11 non-max: sendY = target since top_off = 0; got sendY=" . sendY)
    Yunit.Assert(sendW = 1912, "win11 non-max: sendW = target + left + right (16); got sendW=" . sendW)
    Yunit.Assert(sendH = 421,  "win11 non-max: sendH = target + top + bottom (8); got sendH=" . sendH)
  }

  AsymmetricLeftRight_AppliesIndependently()
  {
    ;; Hypothetical: left and right borders differ (e.g. an oddly-themed
    ;; window). sendX uses left_off only, sendW uses left+right.
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(0, 0, 1000, 500, 3, 12, 3, 4, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = -4,   "asymmetric LR: sendX = -left_off; got sendX=" . sendX)
    Yunit.Assert(sendY = -3,   "asymmetric LR: sendY = -top_off; got sendY=" . sendY)
    Yunit.Assert(sendW = 1016, "asymmetric LR: sendW = 1000 + 4 + 12; got sendW=" . sendW)
    Yunit.Assert(sendH = 506,  "asymmetric LR: sendH = 500 + 3 + 3; got sendH=" . sendH)
  }
}
