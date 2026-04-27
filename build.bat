@echo off
setlocal

if not defined AHK2EXE set AHK2EXE=C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe
if not defined AHK_V1_BIN set AHK_V1_BIN=C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 64-bit.bin
rem Strip any surrounding quotes from overrides so we can quote consistently at use time.
set AHK2EXE=%AHK2EXE:"=%
set AHK_V1_BIN=%AHK_V1_BIN:"=%

if not exist "%AHK2EXE%" (
    echo ERROR: Ahk2Exe not found at %AHK2EXE%.
    echo Install AutoHotkey from https://www.autohotkey.com/download/
    echo Or set the AHK2EXE environment variable to an alternate path.
    exit /b 1
)

if not exist "%AHK_V1_BIN%" (
    echo ERROR: AutoHotkey v1 base file not found at %AHK_V1_BIN%.
    echo Install v1.1.x alongside v2, or set AHK_V1_BIN to an alternate path.
    exit /b 1
)

if not exist "%~dp0build" mkdir "%~dp0build"

"%AHK2EXE%" /silent verbose /in "%~dp0src\Main.ahk" /out "%~dp0build\bugn.exe" /icon "%~dp0src\logo.ico" /bin "%AHK_V1_BIN%"
if errorlevel 1 (
    echo ERROR: Build failed with exit code %errorlevel%.
    exit /b 1
)

echo Build complete: build\bugn.exe

"%AHK2EXE%" /silent verbose /in "%~dp0src\Bench_main.ahk" /out "%~dp0build\bugn-bench.exe" /icon "%~dp0src\logo.ico" /bin "%AHK_V1_BIN%"
if errorlevel 1 (
    echo ERROR: Bench build failed with exit code %errorlevel%.
    exit /b 1
)

echo Build complete: build\bugn-bench.exe

if not exist "%~dp0dist" mkdir "%~dp0dist"
copy /Y "%~dp0build\bugn.exe" "%~dp0dist\bugn.exe" >nul
if errorlevel 1 (
    echo WARNING: Could not copy to dist\bugn.exe ^(probably locked by a running bug.n^). Fresh build is in build\bugn.exe.
) else (
    echo Copied to: dist\bugn.exe
)
copy /Y "%~dp0build\bugn-bench.exe" "%~dp0dist\bugn-bench.exe" >nul
if errorlevel 1 (
    echo WARNING: Could not copy to dist\bugn-bench.exe ^(probably locked by a running bench^). Fresh build is in build\bugn-bench.exe.
) else (
    echo Copied to: dist\bugn-bench.exe
)

endlocal
