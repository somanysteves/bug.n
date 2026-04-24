/*
  bug.n test runner.

  Loads Yunit, the source files under test (via stubs for load-time
  external refs), and each test suite, then prints results to stdout and
  exits with the failure count.

  Run via test.bat or directly:
    "C:\Program Files\AutoHotkey\v1.1.37.02\AutoHotkeyU64.exe" tests\run.ahk
*/

#NoEnv
#SingleInstance Off
SetBatchLines, -1

;; Yunit framework
#Include %A_ScriptDir%\vendor\Yunit\Yunit.ahk
#Include %A_ScriptDir%\CIReporter.ahk

;; Stubs must load before source files that reference the stubbed symbols.
#Include %A_ScriptDir%\stubs.ahk

;; Source files under test
#Include %A_ScriptDir%\..\src\Tiler.ahk

;; Test suites
#Include %A_ScriptDir%\test_Tiler.ahk

;; ---- execute ----
Yunit.Use(CIReporter).Test(TestTiler)

total := TEST_PASS_COUNT + TEST_FAIL_COUNT
FileAppend, % "`n--- " . TEST_PASS_COUNT . " passed, " . TEST_FAIL_COUNT . " failed (" . total . " total) ---`n", *

ExitApp, % TEST_FAIL_COUNT
