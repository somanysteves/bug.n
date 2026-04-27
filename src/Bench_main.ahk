/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3
  @version 9.1.0

  Bench_main.ahk -- separate compilation entry point for performance
  benchmarking. Builds to bugn-bench.exe so it can coexist with the
  shipped bugn.exe (different exe names = independent #SingleInstance
  scopes). The bench runs against real bug.n state -- real Manager,
  real shell hook, real Win32 calls -- so its measurements reflect
  production behavior. It operates only on empty playground views
  (the last two; see Perf_runBench) and Bench_cleanup never calls
  Manager_saveState, so the user's saved session is never touched.

  Invocation: bugn-bench.exe [--out path.csv] [--windows N]
                             [--iterations M] [--commit hash] [appDir]
*/

NAME    := "bug.n-bench"
VERSION := "9.1.0"

;; Script settings -- mirror Main.ahk except for #SingleInstance, where
;; the bench gets its own (different exe) and is not affected by the
;; running bug.n's `force` directive.
OnExit, Bench_cleanup
SetBatchLines, -1
SetTitleMatchMode, 3
SetTitleMatchMode, fast
SetWinDelay, 10
#NoEnv
#SingleInstance off
#WinActivateForce

;; Pseudo main function
  Main_appDir      := ""
  Bench_out        := ""
  Bench_windows    := 8
  Bench_iterations := 50
  Bench_commit     := ""
  argCount := A_Args.MaxIndex()
  If argCount {
    argIdx := 1
    While (argIdx <= argCount) {
      arg := A_Args[argIdx]
      If (arg = "--out") {
        argIdx += 1
        Bench_out := A_Args[argIdx]
      } Else If (arg = "--windows") {
        argIdx += 1
        Bench_windows := A_Args[argIdx] + 0
      } Else If (arg = "--iterations") {
        argIdx += 1
        Bench_iterations := A_Args[argIdx] + 0
      } Else If (arg = "--commit") {
        argIdx += 1
        Bench_commit := A_Args[argIdx]
      } Else If (Main_appDir = "") {
        Main_appDir := arg
      }
      argIdx += 1
    }
  }
  If (Bench_out = "")
    Bench_out := A_ScriptDir . "\..\bench\perf.csv"

  App_init()

  SplitPath, Bench_out, , Bench_outDir
  If Bench_outDir
    Main_makeDir(Bench_outDir)
  Perf_init(True, Bench_out, Bench_commit)
  Debug_logMessage("====== Bench mode: " . Bench_windows . " windows x " . Bench_iterations . " iterations -> " . Bench_out . " ======", 0)
  SetTimer, Bench_kick, -500
Return          ;; end of the auto-execute section

Bench_kick:
  Perf_runBench(Bench_windows, Bench_iterations)
Return

Bench_cleanup:
  Debug_logMessage("====== Cleaning up (bench) ======", 0)
  ;; Deliberately NO Manager_saveState -- the bench's playground view
  ;; layout would clobber the user's saved session on disk.
  Manager_cleanup()
  ResourceMonitor_cleanup()
  Debug_logMessage("====== Exiting bug.n-bench ======", 0)
ExitApp

;; No-op stub for Main_evalCommand. Manager_init installs hotkeys via
;; Config_restoreConfig that ultimately call Main_evalCommand. The bench
;; process should never act on user keypresses -- the user's running
;; bug.n owns those. Bench_main.ahk deliberately does NOT include
;; Main_evalCommand.ahk so this stub stands in instead.
Main_evalCommand(command) {
}

#Include %A_ScriptDir%\App.ahk
#Include %A_ScriptDir%\Bar.ahk
#Include %A_ScriptDir%\Config.ahk
#Include %A_ScriptDir%\Debug.ahk
#Include %A_ScriptDir%\Manager.ahk
#Include %A_ScriptDir%\Perf.ahk
#Include %A_ScriptDir%\Manager_setCursor.ahk
#Include %A_ScriptDir%\Monitor.ahk
#Include %A_ScriptDir%\ResourceMonitor.ahk
#Include %A_ScriptDir%\Tiler.ahk
#Include %A_ScriptDir%\View.ahk
#Include %A_ScriptDir%\View_arrange.ahk
#Include %A_ScriptDir%\View_getTiledWndIds.ahk
#Include %A_ScriptDir%\Window.ahk
#Include %A_ScriptDir%\MonitorManager.ahk
