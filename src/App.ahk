/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3
  @version 9.2.0

  App.ahk -- shared scaffolding for bug.n entry points (Main.ahk and
  Bench_main.ahk). Holds the filesystem helpers and the standard init
  sequence so each entry point only has to wire up its own UI and
  lifecycle bits (tray menu, bench timer, custom OnExit cleanup).
*/

;; Standard init sequence: paths -> log -> config -> resource monitor ->
;; manager. Caller must have set Main_appDir before invoking. UI bits
;; (tray menu in Main, perf timer in Bench) are the caller's job and run
;; after this returns.
App_init() {
  Global

  Main_setup()
  Debug_initLog(Main_logFile, 0, False)
  Debug_logMessage("====== Initializing ======", 0)
  Config_filePath := Main_appDir "\Config.ini"
  Config_init()
  ResourceMonitor_init()
  Manager_init()
  Debug_logMessage("====== Running ======", 0)
}

;; Path setup. Populates Main_docDir, Main_logFile, Main_dataDir,
;; Main_autoLayout, Main_autoWindowState, and (if not already set)
;; Main_appDir, then ensures the appdata directories exist.
Main_setup() {
  Local winAppDir

  Main_docDir := A_ScriptDir
  If (SubStr(A_ScriptDir, -3) = "\src")
    Main_docDir .= "\.."
  Main_docDir .= "\doc"

  Main_logFile := ""
  Main_dataDir := ""
  Main_autoLayout := ""
  Main_autoWindowState := ""

  EnvGet, winAppDir, APPDATA

  If (Main_appDir = "")
    Main_appDir := winAppDir . "\bug.n"
  Main_logFile := Main_appDir . "\log.txt"
  Main_dataDir := Main_appDir . "\data"
  Main_autoLayout := Main_dataDir . "\_Layout.ini"
  Main_autoWindowState := Main_dataDir . "\_WindowState.ini"

  Main_makeDir(Main_appDir)
  Main_makeDir(Main_dataDir)
}

;; Create a directory if it doesn't exist; abort with a MsgBox if the
;; path exists as a file.
Main_makeDir(dirName) {
  IfNotExist, %dirName%
  {
    FileCreateDir, %dirName%
    If ErrorLevel
    {
      MsgBox, Error (%ErrorLevel%) when creating '%dirName%'. Aborting.
      ExitApp
    }
  }
  Else
  {
    FileGetAttrib, attrib, %dirName%
    IfNotInString, attrib, D
    {
      MsgBox, The file path '%dirName%' already exists and is not a directory. Aborting.
      ExitApp
    }
  }
}
