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
- [x] Add StackMX grid: `#^h` / `#^;` (increase/decrease stack columns)
- [x] Add minimize: `#+n`
- [x] Remap move window: `!Down/!Up` → `!j/!k`
- [x] Remap maximize: `!+Enter` → `!+m`
- [x] Remap reset layout: `#^Backspace` → `#+r`
- [x] Remap margins toggle: `#+n` → `#+b`
- [x] Remap debug help: `#^h` → `#^+h` (freed `#^h` for StackMX)
- [ ] Zoom: `#+Enter` → TBD (marked TODO in code)
- [ ] Remap layout cycle: `#Space` → next, `#+Space` → prev (currently taskbar/bar toggle)
- [ ] Remap floating toggle to `#^Space` (currently `#+f`)
- [ ] Remap bar toggle to `#+b` (currently `#+Space`; `#+b` is margins)
- [ ] Remap quit: `#^q` → `#+q`
- [x] Add spawn terminal: `#Return` → `Run, alacritty`
- [ ] Remap prev view: `#BackSpace` → `#Escape`
- [ ] Verify all bindings work end-to-end

## 3. Tiling Defaults — Match AwesomeWM Stock Tile
- [ ] Change `Config_layoutMFactor` from `0.6` → `0.55`
- [ ] Change `Config_layoutGapWidth` from `0` → `4`
- [ ] Verify layout: master left (~55%), stack top-to-bottom on right, 4px gaps
