# bug.n Improvement Plan

## 1. Build System — Admin Exe
- [x] Install AutoHotkey 1.1.x (installed v1.1.37.02 via direct download)
- [x] Add `; @Ahk2Exe-UpdateManifest 1` to `src/Main.ahk` (embeds UAC elevation manifest)
- [x] Create `build.bat` in repo root (simple ahk2exe wrapper)
- [ ] Verify: `bugn.exe` triggers UAC prompt on launch and can manage elevated windows

## 2. Keybindings — Stock AwesomeWM Defaults
- [ ] Remap focus: `#Down/#Up` → `#j/#k`
- [ ] Remap swap: `#+Down/+Up` → `#+j/#+k`
- [ ] Remap zoom: `#+Enter` → `#^Return`
- [ ] Remap close: `#c` → `#+c`
- [ ] Remap master resize: `#Left/#Right` → `#h/#l`
- [ ] Add nmaster: `#+h` / `#+l` (increase/decrease master count)
- [ ] Remap layout cycle: `#Space` → next layout, `#+Space` → prev layout
- [ ] Remap floating toggle: `#^Space` (was `#f`)
- [ ] Remap bar toggle: `#+b` (free up `#+Space`)
- [ ] Remap quit: `#^q` → `#+q`
- [ ] Add minimize: `#n`
- [ ] Add spawn terminal: `#Return` → `Run, wt.exe`
- [ ] Remap prev view: `#BackSpace` → `#Escape`
- [ ] Verify all bindings work end-to-end

## 3. Tiling Defaults — Match AwesomeWM Stock Tile
- [ ] Change `Config_layoutMFactor` from `0.6` → `0.55`
- [ ] Change `Config_layoutGapWidth` from `0` → `4`
- [ ] Verify layout: master left (~55%), stack top-to-bottom on right, 4px gaps
