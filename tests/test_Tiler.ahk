/*
  Tests for src/Tiler.ahk.

  Tiler_splitArea(axis, splitRatio, x, y, w, h, gapW,
                  ByRef x1, ByRef y1, ByRef w1, ByRef h1,
                  ByRef x2, ByRef y2, ByRef w2, ByRef h2)

  Splits a rectangle into two sub-rectangles:
    axis = 0 → split along X (side-by-side)
    axis = 1 → split along Y (stacked)
    splitRatio = 1 → first sub-rect takes everything, second is zero-sized
    gapW → pixels of empty space between sub-rects; each side loses gapW/2
*/

class TestTiler
{
  class SplitArea
  {
    HorizontalHalf()
    {
      Tiler_splitArea(0, 0.5, 0, 0, 1000, 800, 0, x1, y1, w1, h1, x2, y2, w2, h2)
      Yunit.Assert(x1 = 0,   "x1 expected 0, got " . x1)
      Yunit.Assert(y1 = 0,   "y1 expected 0, got " . y1)
      Yunit.Assert(w1 = 500, "w1 expected 500, got " . w1)
      Yunit.Assert(h1 = 800, "h1 expected 800, got " . h1)
      Yunit.Assert(x2 = 500, "x2 expected 500, got " . x2)
      Yunit.Assert(y2 = 0,   "y2 expected 0, got " . y2)
      Yunit.Assert(w2 = 500, "w2 expected 500, got " . w2)
      Yunit.Assert(h2 = 800, "h2 expected 800, got " . h2)
    }

    VerticalHalf()
    {
      Tiler_splitArea(1, 0.5, 0, 0, 1000, 800, 0, x1, y1, w1, h1, x2, y2, w2, h2)
      Yunit.Assert(x1 = 0,    "x1 expected 0, got " . x1)
      Yunit.Assert(y1 = 0,    "y1 expected 0, got " . y1)
      Yunit.Assert(w1 = 1000, "w1 expected 1000, got " . w1)
      Yunit.Assert(h1 = 400,  "h1 expected 400, got " . h1)
      Yunit.Assert(x2 = 0,    "x2 expected 0, got " . x2)
      Yunit.Assert(y2 = 400,  "y2 expected 400, got " . y2)
      Yunit.Assert(w2 = 1000, "w2 expected 1000, got " . w2)
      Yunit.Assert(h2 = 400,  "h2 expected 400, got " . h2)
    }

    RatioOne_FirstTakesAll()
    {
      Tiler_splitArea(0, 1, 10, 20, 800, 600, 5, x1, y1, w1, h1, x2, y2, w2, h2)
      Yunit.Assert(x1 = 10,  "x1 expected 10, got " . x1)
      Yunit.Assert(y1 = 20,  "y1 expected 20, got " . y1)
      Yunit.Assert(w1 = 800, "w1 expected 800, got " . w1)
      Yunit.Assert(h1 = 600, "h1 expected 600, got " . h1)
      Yunit.Assert(w2 = 0,   "w2 expected 0, got " . w2)
      Yunit.Assert(h2 = 0,   "h2 expected 0, got " . h2)
      ; second rect sits at the far corner of the first
      Yunit.Assert(x2 = 810, "x2 expected 810, got " . x2)
      Yunit.Assert(y2 = 620, "y2 expected 620, got " . y2)
    }

    HorizontalWithGap()
    {
      ; axis=0, ratio=0.5, w=1000, gap=20 → each half loses 10px; gap sits between
      Tiler_splitArea(0, 0.5, 0, 0, 1000, 800, 20, x1, y1, w1, h1, x2, y2, w2, h2)
      Yunit.Assert(w1 = 490, "w1 expected 490, got " . w1)
      Yunit.Assert(w2 = 490, "w2 expected 490, got " . w2)
      Yunit.Assert(x2 = 510, "x2 expected 510 (x1+w1+gap), got " . x2)
      ; heights untouched on horizontal split
      Yunit.Assert(h1 = 800, "h1 expected 800, got " . h1)
      Yunit.Assert(h2 = 800, "h2 expected 800, got " . h2)
    }

    VerticalWithGap()
    {
      Tiler_splitArea(1, 0.5, 0, 0, 1000, 800, 20, x1, y1, w1, h1, x2, y2, w2, h2)
      Yunit.Assert(h1 = 390, "h1 expected 390, got " . h1)
      Yunit.Assert(h2 = 390, "h2 expected 390, got " . h2)
      Yunit.Assert(y2 = 410, "y2 expected 410 (y1+h1+gap), got " . y2)
      ; widths untouched on vertical split
      Yunit.Assert(w1 = 1000, "w1 expected 1000, got " . w1)
      Yunit.Assert(w2 = 1000, "w2 expected 1000, got " . w2)
    }

    AsymmetricRatio()
    {
      ; axis=0, ratio=0.3 → w1 = 300, w2 = 700 (no gap)
      Tiler_splitArea(0, 0.3, 0, 0, 1000, 800, 0, x1, y1, w1, h1, x2, y2, w2, h2)
      Yunit.Assert(w1 = 300, "w1 expected 300, got " . w1)
      Yunit.Assert(w2 = 700, "w2 expected 700, got " . w2)
      Yunit.Assert(x2 = 300, "x2 expected 300, got " . x2)
    }

    OffsetOrigin()
    {
      ; Splitting a rect that doesn't start at (0,0) should preserve the offset.
      Tiler_splitArea(0, 0.5, 100, 200, 1000, 800, 0, x1, y1, w1, h1, x2, y2, w2, h2)
      Yunit.Assert(x1 = 100, "x1 expected 100, got " . x1)
      Yunit.Assert(y1 = 200, "y1 expected 200, got " . y1)
      Yunit.Assert(x2 = 600, "x2 expected 600 (100+500), got " . x2)
      Yunit.Assert(y2 = 200, "y2 expected 200, got " . y2)
    }
  }
}
