@echo off
setlocal

set AHK2EXE="C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
set AHK_V1_BIN="C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 64-bit.bin"

if not exist %AHK2EXE% (
    echo ERROR: Ahk2Exe not found. Install AutoHotkey from https://www.autohotkey.com/download/
    exit /b 1
)

if not exist %AHK_V1_BIN% (
    echo ERROR: AutoHotkey v1 not found. Install v1.1.x alongside v2.
    exit /b 1
)

%AHK2EXE% /in src\Main.ahk /out bugn.exe /icon src\logo.ico /bin %AHK_V1_BIN%
if errorlevel 1 (
    echo ERROR: Build failed.
    exit /b 1
)

echo Build complete: bugn.exe
endlocal
