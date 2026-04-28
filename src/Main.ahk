/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  @license GNU General Public License version 3
           ../LICENSE.md or <http://www.gnu.org/licenses/>

  @version 9.2.0
*/

NAME    := "bug.n"
VERSION := "9.2.0"

;; Script settings
OnExit, Main_cleanup
SetBatchLines, -1
SetTitleMatchMode, 3
SetTitleMatchMode, fast
SetWinDelay, 10
#NoEnv
#SingleInstance force
;#Warn                         ; Enable warnings to assist with detecting common errors.
#WinActivateForce

;; Pseudo main function
  Main_appDir := ""
  If 0 = 1
    Main_appDir = %1%

  App_init()

  Menu, Tray, Tip, %NAME% %VERSION%
  If A_IsCompiled
    Menu, Tray, Icon, %A_ScriptFullPath%, -159
  If FileExist(A_ScriptDir . "\logo.ico")
    Menu, Tray, Icon, % A_ScriptDir . "\logo.ico"
  Menu, Tray, NoStandard
  Menu, Tray, Add, Toggle bar, Main_toggleBar
  Menu, Tray, Add, Help, Main_help
  Menu, Tray, Add,
  Menu, Tray, Add, Exit, Main_quit
Return          ;; end of the auto-execute section

;; Function & label definitions
Main_cleanup:
  Debug_logMessage("====== Cleaning up ======", 0)
  ;; Config_autoSaveSession as False is deprecated.
  If Not (Config_autoSaveSession = "off") And Not (Config_autoSaveSession = "False")
    Manager_saveState()
  Manager_cleanup()
  ResourceMonitor_cleanup()
  Debug_logMessage("====== Exiting bug.n ======", 0)
ExitApp

Main_help:
  Run, explore %Main_docDir%
Return

Main_quit:
  ExitApp
Return

Main_toggleBar:
  Monitor_toggleBar()
Return

#Include %A_ScriptDir%\App.ahk
#Include %A_ScriptDir%\Main_evalCommand.ahk
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
