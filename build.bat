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

if not exist "%~dp0build" mkdir "%~dp0build"

%AHK2EXE% /silent verbose /in "%~dp0src\Main.ahk" /out "%~dp0build\bugn.exe" /icon "%~dp0src\logo.ico" /bin %AHK_V1_BIN%
if errorlevel 1 (
    echo ERROR: Build failed with exit code %errorlevel%.
    exit /b 1
)

echo Build complete: build\bugn.exe

if not exist "%~dp0dist" mkdir "%~dp0dist"
copy /Y "%~dp0build\bugn.exe" "%~dp0dist\bugn.exe" >nul
if errorlevel 1 (
    echo WARNING: Could not copy to dist\bugn.exe ^(probably locked by a running bug.n^). Fresh build is in build\bugn.exe.
) else (
    echo Copied to: dist\bugn.exe
)

endlocal
