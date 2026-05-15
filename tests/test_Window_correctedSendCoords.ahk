/*
  Tests for Window_correctedSendCoords (src/Window.ahk).

  Pure ByRef math: given a target visible rect and the window's DWM
  offsets, populate the SetWindowPos-bound sendX/Y/W/H. Both
  Window_moveAsync and the Tiler's DeferWindowPos batch route through
  this helper, so a single sign error here would break tiling
  positioning everywhere -- exactly the regression caught by dogfood on
  PR #38 before this helper was extracted. These tests pin the formula.
*/

class TestWindowCorrectedSendCoords
{
  ZeroOffset_PassesThroughUnchanged()
  {
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(100, 200, 300, 400, 0, 0, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = 100 And sendY = 200 And sendW = 300 And sendH = 400
      , "zero offset should pass through unchanged; got (" . sendX . "," . sendY . "," . sendW . "," . sendH . ")")
  }

  NegativeOffset_ShiftsGwrLeftAndGrows()
  {
    ;; Win10/11 drop-shadow case: visible rect narrower than GWR, so
    ;; offset = (visible - GWR)/2 < 0. SendX shifts GWR left of target;
    ;; SendW grows GWR to wrap both shadow edges.
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(100, 200, 800, 600, -7, -5, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = 93,  "negative offsetX should shift GWR.left below target; got sendX=" . sendX)
    Yunit.Assert(sendY = 195, "negative offsetY should shift GWR.top above target; got sendY=" . sendY)
    Yunit.Assert(sendW = 814, "negative offsetX should grow GWR.width by 2*|offset|; got sendW=" . sendW)
    Yunit.Assert(sendH = 610, "negative offsetY should grow GWR.height by 2*|offset|; got sendH=" . sendH)
  }

  PositiveOffset_ShiftsGwrRightAndShrinks()
  {
    ;; Hypothetical positive-offset case (visible extends beyond GWR).
    ;; Symmetric flip of the negative case -- verifies the sign math is
    ;; not just coincidentally right for one sign.
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(100, 200, 800, 600, 7, 5, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = 107, "positive offsetX should shift GWR.left above target; got sendX=" . sendX)
    Yunit.Assert(sendY = 205, "positive offsetY should shift GWR.top below target; got sendY=" . sendY)
    Yunit.Assert(sendW = 786, "positive offsetX should shrink GWR.width by 2*offset; got sendW=" . sendW)
    Yunit.Assert(sendH = 590, "positive offsetY should shrink GWR.height by 2*offset; got sendH=" . sendH)
  }

  AsymmetricOffsetXY_AppliesIndependently()
  {
    Local sendX, sendY, sendW, sendH
    Window_correctedSendCoords(0, 0, 1000, 500, -10, 3, sendX, sendY, sendW, sendH)
    Yunit.Assert(sendX = -10,  "asymmetric: sendX=" . sendX)
    Yunit.Assert(sendY = 3,    "asymmetric: sendY=" . sendY)
    Yunit.Assert(sendW = 1020, "asymmetric: sendW=" . sendW)
    Yunit.Assert(sendH = 494,  "asymmetric: sendH=" . sendH)
  }
}
