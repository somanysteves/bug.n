# bug.n Improvement Plan

## 1. Build System — Admin Exe
- [x] Install AutoHotkey 1.1.x (installed v1.1.37.02 via direct download)
- [x] Create `build.bat` in repo root (ahk2exe wrapper)
- [x] Add `build.ps1` for reliable CI/subprocess builds (build.bat unreliable via cmd /c)
- [x] Removed `@Ahk2Exe-UpdateManifest 1` — broke Ahk2Exe in subprocess; use gsudo to elevate at runtime instead
- [x] Verify: `bugn.exe` can manage elevated windows (run via gsudo)

## 2. Keybindings — AwesomeWM Style
Remaining items migrated to GitHub issue #33 (`somanysteves/bug.n`).

## 3. Tiling Defaults — Match AwesomeWM Stock Tile
Remaining verify item migrated to GitHub issue #33 (`somanysteves/bug.n`).

## 4. Performance — Workspace Switch & Window Move Lag
Migrated to GitHub issues. See umbrella issue #32 (`somanysteves/bug.n`) for phases 4.1–4.7.
