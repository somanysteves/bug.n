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

## 4. Performance — Workspace Switch & Window Move Lag
Goal: noticeably snappier than the AHK1 baseline (and snappier than a v2 port alone would deliver). The bottlenecks are architectural, not language-version, so this work lives in v1.

Land each phase as its own commit/PR with a before/after measurement so we can stop once it feels right.

### 4.1 Measure first
- [ ] Add `A_TickCount` timing wrappers around `Monitor_activateView`, `View_arrange`, `Manager_sync`, `Tiler_stackTiles`; gated on `Config_logLevel`
- [ ] Add a `--bench` startup flag in `src/Main.ahk` that parses `A_Args` early, skips normal init (no shell hook, no user hotkeys, no bar), and runs a fixed scenario:
  - Optional args: `--out path.csv` (default: `bench/perf.csv`), `--windows N` (default 8), `--iterations M` (default 50)
  - Spawns N Notepad windows, waits for them to register as managed
  - Runs scenarios: view A↔B switch ×M, move focused window between views ×M, full arrange after add
  - Writes one CSV row per `(scenario, phase)` with `commit, window_count, min_ms, median_ms, p95_ms, max_ms`
  - Kills spawned windows, `ExitApp`
- [ ] Document fixed local test setup so manual runs are also comparable (number of monitors, resolution)
- [ ] Capture baseline numbers locally: 1-monitor / 8 windows, 2-monitor / 12 windows, plus a move-heavy run

### 4.2 Quick wins (config + one-liners)
- [ ] `Config_shellMsgDelay` 350 → 50 (`src/Config.ahk:80`) — debounce, not a paced delay
- [ ] `SetWinDelay, 10` → `SetWinDelay, 0` global default (`src/Main.ahk:24`)
- [ ] Drop the per-loop `SetWinDelay 0/10` toggles in `Monitor_activateView` (`src/Monitor.ahk:79,86,95,101`) once the global is 0
- [ ] Audit the `DetectHiddenWindows On/Off` toggle around `View_getActiveWindow` (`src/Monitor.ahk:87-93`); keep only if load-bearing
- [ ] Re-measure; commit if no regressions on multi-monitor

### 4.3 Split visibility from layout
- [ ] In `Monitor_activateView` (`src/Monitor.ahk:41-110`), separate "hide/show windows" from "recompute tile layout"
- [ ] Cache last-arranged geometry per `(monitor, view)`; invalidate on window add/remove/resize/layout-change
- [ ] On a view switch with a valid cache, skip `View_arrange` entirely — just toggle visibility
- [ ] Re-measure

### 4.4 Batch the Win32 calls
- [ ] Replace per-window `WinMove` loop in `Tiler_stackTiles` (`src/Tiler.ahk:350-382`) with `BeginDeferWindowPos` / `DeferWindowPos` / `EndDeferWindowPos` via DllCall — single atomic repaint
- [ ] In `Monitor_activateView` hide/show loops, collect HWNDs and issue one batched pass (consider `ShowWindowAsync` for non-blocking)
- [ ] Test: multi-monitor, mixed DPI, watch for flicker / wrong-monitor placement

### 4.5 Coalesce shell events
- [ ] In `Manager_onShellMessage` (`src/Manager.ahk:566-741`), if another event arrives within ~50ms, mark dirty and bail; flush via short-fuse `SetTimer`
- [ ] Skip full `Manager_sync` for events that don't change managed-window membership (e.g. focus-only)
- [ ] Re-measure

### 4.6 Selective re-tile (stretch)
- [ ] When `Config_syncMonitorViews` is on, only re-tile the affected monitor, not all of them
- [ ] Skip `View_arrange` entirely when neither layout nor window-set changed for that view

### 4.7 CI perf job (advisory)
- [ ] Add `bench:` job to `.github/workflows/ci.yml`, depends on `build-and-test`, runs on `windows-latest`
- [ ] Job: download `bugn-exe` artifact → run `bugn.exe --bench --out perf.csv` 3× → take median of medians → upload `perf.csv` as artifact
- [ ] On PRs, compare against `bench/baseline.csv` committed to the repo; post diff as a PR comment via `gh`
- [ ] Start non-blocking (advisory only); promote to a gate (`fail if median > baseline × 1.5`) once numbers are trusted
- [ ] Refresh `bench/baseline.csv` manually after intentional perf-affecting merges (not every commit)
- [ ] Caveats to keep in mind, not block on:
  - Single-monitor only (runner has one display) — multi-monitor regressions won't be caught
  - Numbers are relative-to-self on the runner; don't transfer to user machines
  - Shared-runner noise: ~5% deltas are not signal, ~30%+ are

### Out of scope (here)
- AHK1 → v2 port — separate effort; perf wins should land in v1 first so users benefit immediately
- Bar redraw optimization — likely cheap relative to tiling work; revisit only if 4.1 measurements point at it
