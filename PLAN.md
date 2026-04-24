# bug.n Improvement Plan

## 1. Build System — Admin Exe
- [x] Install AutoHotkey 1.1.x (installed v1.1.37.02 via direct download)
- [x] Create `build.bat` in repo root (ahk2exe wrapper)
- [x] Add `build.ps1` for reliable CI/subprocess builds (build.bat unreliable via cmd /c)
- [x] Removed `@Ahk2Exe-UpdateManifest 1` — broke Ahk2Exe in subprocess; use gsudo to elevate at runtime instead
- [x] Verify: `bugn.exe` can manage elevated windows (run via gsudo)

## 2. Keybindings — AwesomeWM Style
- [x] Remap focus: `#Down/#Up` → `#j/#k`
- [x] Remap swap: `#+Down/+Up` → `#+j/#+k`
- [x] Remap close: `#c` → `#+c`
- [x] Remap master resize: `#Left/#Right` → `#h/#;`
- [x] Add nmaster Y: `#+h` / `#+;` (increase/decrease master row count)
- [x] Add StackMX grid: `#^h` / `#^;` (increase/decrease stack columns — column-first AwesomeWM distribution)
- [x] Add minimize: `#+n`
- [x] Remap move window: `!Down/!Up` → `!j/!k`
- [x] Remap maximize: `!+Enter` → `!+m`
- [x] Remap reset layout: `#^Backspace` → `#+r`
- [x] Remap margins toggle: `#+n` → `#+b`
- [x] Drop margins keybind (margins disabled); `#b` → toggle Windows taskbar (`Monitor_toggleTaskBar`)
- [x] Remap bug.n bar toggle: `#+Space` → `#^b` (`Monitor_toggleBar`)
- [x] Remap debug help: `#^h` → `#^+h` (freed `#^h` for StackMX)
- [ ] Zoom: `#+Enter` → TBD (marked TODO in code)
- [ ] Remap layout cycle: `#Space` → next, `#+Space` → prev (both freed)
- [ ] Remap floating toggle to `#^Space` (currently `#+f`)
- [x] Remap quit: `#^q` → `#+q`
- [x] Add spawn terminal: `#Return` → `Run, alacritty`
- [ ] Remap prev view: `#BackSpace` → `#Escape`
- [ ] Verify all bindings work end-to-end

## 3. Tiling Defaults — Match AwesomeWM Stock Tile
- [x] Change `Config_layoutMFactor` from `0.6` → `0.55`
- [x] ~~Change `Config_layoutGapWidth` from `0` → `4`~~ — keeping gaps at 0 intentionally
- [ ] Verify layout: master left (~55%), stack top-to-bottom on right, no gaps

## 4. Fix Win+Shift+J Wrap + Build View-State Test Harness (TDD)

**Bug:** `Win+Shift+J` (shuffle window down) gets stuck at the bottom instead of
wrapping to the top. `Win+Shift+K` (up) wraps top→bottom correctly. Root cause:
`src/Config.ahk:425` binds `View_shuffleWindow(-1, +1)` — the `-1` threads through
to `Manager_loop(-1, +1, 1, n)`, which always collapses to `n`. Should be
`View_shuffleWindow(0, +1)` to match `#+k`'s `(0, -1)` form and the docs
(`doc/Default_hotkeys.md:37`, `doc/User-hotkeys.md:66`).

**Approach (TDD):** A one-character Config fix isn't directly unit-testable at the
logic layer — `Manager_loop` math doesn't change. To make a red-then-green test
for the behavior, we're investing in reusable test scaffolding for
`View_shuffleWindow` (and most other window-management functions), rather than a
shallow source-parse test. Expected payoff: unlocks unit tests for
`View_activateWindow`, `View_toggleFloatingWindow`, `Manager_moveWindow`,
`Manager_minimizeWindow`, `Manager_closeWindow`, `View_setMFactor`,
`View_setLayout`, `Manager_activateMonitor`, etc.

- [x] Tier A characterization test: `Manager_loop(-1, +1, 1, n) = n` documented
      in `tests/test_Manager_loop.ahk` (uncommitted). Keep for documentation —
      explains the *mechanism* of the J bug even after the hotkey is fixed.
- [ ] **Scaffolding refactor (one commit, no behavior change):**
   - [ ] Add `Window_getActiveId()` wrapper in `src/Window.ahk` around the
         `WinGet, <var>, ID, A` pattern (View.ahk:369 and ~5–8 other call sites
         in functions we want to test — not all ~40 uses at once).
   - [ ] Thread optional `aWndId = ""` parameter through `View_shuffleWindow`
         (and peer functions as needed); falls back to `Window_getActiveId()`
         when omitted so production behavior is unchanged.
   - [ ] Extract `View_arrange` and `Manager_setCursor` into swappable files so
         `tests/run.ahk` can `#Include` stub versions instead — same pattern
         `tests/stubs.ahk` already uses for `Main_evalCommand`.
   - [ ] Full existing test suite stays green after this commit.
- [ ] **Test helpers (one commit):**
   - [ ] `tests/helpers/view_state.ahk` — `setupView(m, v, wndIds, activeWndId)`,
         teardown between tests, captured-calls recorder for `View_arrange`,
         assertion helpers for tiled-list order.
- [ ] **Red-then-green J fix (one commit):**
   - [ ] Failing test: from `j=1` (top) pressing `#+j` lands at `j=2`; from
         `j=n` (bottom) pressing `#+j` wraps to `j=1`. Plus 2–3 tests covering
         `View_activateWindow` or similar to prove the harness works beyond
         one function.
   - [ ] Flip `src/Config.ahk:425` → `View_shuffleWindow(0, +1)`. Tests go green.
   - [ ] `build.bat` + `test.bat` both clean before asking to commit.

**Caveats:**
- Yunit / AHK v1 has no real mocking — stubs are `#Include`-time file swaps.
  Fine for most cases; a test can't flip stub behavior mid-test.
- First 1–2 harness tests may surface unknown global side-effects in
  `View_shuffleWindow`; expect minor follow-up on the setup helpers.
- CI already runs on Windows w/ real AHK; stubbing OS calls means these tests
  don't need a desktop session.
