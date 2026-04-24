@echo off
setlocal

if not defined AHK_EXE set AHK_EXE=C:\Program Files\AutoHotkey\v1.1.37.02\AutoHotkeyU64.exe
rem Strip any surrounding quotes from an override so we can quote consistently at use time.
set AHK_EXE=%AHK_EXE:"=%

if not exist "%AHK_EXE%" (
    echo ERROR: AutoHotkey v1.1 interpreter not found at %AHK_EXE%.
    echo Install AutoHotkey v1.1.x from https://www.autohotkey.com/download/
    echo Or set the AHK_EXE environment variable to an alternate path.
    exit /b 1
)

if not exist "%~dp0tests\vendor\Yunit\Yunit.ahk" (
    echo Yunit submodule not initialized; running git submodule update --init...
    pushd "%~dp0"
    git submodule update --init --recursive
    popd
    if not exist "%~dp0tests\vendor\Yunit\Yunit.ahk" (
        echo ERROR: Yunit submodule not available. Run: git submodule update --init --recursive
        exit /b 1
    )
)

"%AHK_EXE%" /ErrorStdOut "%~dp0tests\run.ahk"
set RC=%errorlevel%

if %RC%==0 (
    echo All tests passed.
) else (
    echo %RC% test^(s^) failed.
)

endlocal & exit /b %RC%
