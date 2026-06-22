;; bug.n test runner. Includes every src/*.ahk except Main.ahk.
;; Auto-execute at top, #Include at bottom — see tests/README.md.

#NoEnv
#SingleInstance Off
SetBatchLines, -1

;; ---- auto-execute ----
TEST_PASS_COUNT := 0
TEST_FAIL_COUNT := 0

Yunit.Use(CIReporter).Test(TestTiler, TestManagerLoop, TestViewShuffleWindow, TestManagerDisplayChange, TestManagerUrgentView, TestConfigUrgentPalette, TestManagerSync, TestHelp, TestBarSetViewHighlight, TestManagerBarTitleAction, TestManagerBarTitleDispatch, TestWindowCorrectedSendCoords, TestWindowGetTitleNonBlocking, TestManagerModifiersFromHotkey, TestViewCycleDrain, TestManagerStaleBounce, TestManagerClassifyHideEvent, TestManagerIsManagedDestroy, TestManagerShouldResetDebouncedTimer, TestManagerParseSavedWindowLine, TestManagerUnmanage, TestManagerProcessHideQueue, TestManagerValidateAlive, TestManagerApplyViewRename, TestConfigViewNamesPersistence, TestManagerShouldReintegrateOnRestore, TestManagerRestoreExcludedByRules)

total := TEST_PASS_COUNT + TEST_FAIL_COUNT
FileAppend, % "`n--- " . TEST_PASS_COUNT . " passed, " . TEST_FAIL_COUNT . " failed (" . total . " total) ---`n", *

ExitApp, % TEST_FAIL_COUNT

;; ---- library + test definitions (parsed, not auto-executed) ----

;; Yunit framework
#Include %A_ScriptDir%\vendor\Yunit\Yunit.ahk
#Include %A_ScriptDir%\CIReporter.ahk

;; Stubs for Main.ahk-resident symbols
#Include %A_ScriptDir%\stubs.ahk

;; Stubs for IO-heavy src/ symbols (View_arrange, Manager_setCursor).
;; Loaded *instead of* src/View_arrange.ahk and src/Manager_setCursor.ahk
;; — those real files are intentionally NOT #Included below.
#Include %A_ScriptDir%\stubs_io.ahk

;; src/*.ahk (everything except Main.ahk, View_arrange.ahk, Manager_setCursor.ahk)
#Include %A_ScriptDir%\..\src\Bar.ahk
#Include %A_ScriptDir%\..\src\Config.ahk
#Include %A_ScriptDir%\..\src\Debug.ahk
#Include %A_ScriptDir%\..\src\Help.ahk
#Include %A_ScriptDir%\..\src\Manager.ahk
#Include %A_ScriptDir%\..\src\Monitor.ahk
#Include %A_ScriptDir%\..\src\Perf.ahk
;; Resolves Bench_assertTiled referenced from Perf_runBench (see Main.ahk note).
#Include %A_ScriptDir%\..\src\Bench_geometry.ahk
#Include %A_ScriptDir%\..\src\MonitorManager.ahk
#Include %A_ScriptDir%\..\src\ResourceMonitor.ahk
#Include %A_ScriptDir%\..\src\Tiler.ahk
#Include %A_ScriptDir%\..\src\View.ahk
#Include %A_ScriptDir%\..\src\Window.ahk

;; Test helpers
#Include %A_ScriptDir%\helpers\view_state.ahk

;; Test suites
#Include %A_ScriptDir%\test_Tiler.ahk
#Include %A_ScriptDir%\test_Manager_loop.ahk
#Include %A_ScriptDir%\test_View_shuffleWindow.ahk
#Include %A_ScriptDir%\test_Manager_displayChange.ahk
#Include %A_ScriptDir%\test_Manager_urgentView.ahk
#Include %A_ScriptDir%\test_Config_urgentPalette.ahk
#Include %A_ScriptDir%\test_Manager_sync.ahk
#Include %A_ScriptDir%\test_Help.ahk
#Include %A_ScriptDir%\test_Bar_setViewHighlight.ahk
#Include %A_ScriptDir%\test_Manager_barTitleAction.ahk
#Include %A_ScriptDir%\test_Manager_barTitleDispatch.ahk
#Include %A_ScriptDir%\test_Window_correctedSendCoords.ahk
#Include %A_ScriptDir%\test_Window_getTitleNonBlocking.ahk
#Include %A_ScriptDir%\test_Manager_modifiersFromHotkey.ahk
#Include %A_ScriptDir%\test_View_cycleDrain.ahk
#Include %A_ScriptDir%\test_Manager_staleBounce.ahk
#Include %A_ScriptDir%\test_Manager_classifyHideEvent.ahk
#Include %A_ScriptDir%\test_Manager_isManagedDestroy.ahk
#Include %A_ScriptDir%\test_Manager_shouldResetDebouncedTimer.ahk
#Include %A_ScriptDir%\test_Manager_parseSavedWindowLine.ahk
#Include %A_ScriptDir%\test_Manager_unmanage.ahk
#Include %A_ScriptDir%\test_Manager_processHideQueue.ahk
#Include %A_ScriptDir%\test_Manager_validateAlive.ahk
#Include %A_ScriptDir%\test_Manager_applyViewRename.ahk
#Include %A_ScriptDir%\test_Config_viewNamesPersistence.ahk
#Include %A_ScriptDir%\test_Manager_shouldReintegrateOnRestore.ahk
#Include %A_ScriptDir%\test_Manager_restoreExcludedByRules.ahk
