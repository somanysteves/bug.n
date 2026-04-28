/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3
  @version 9.2.0

  Main_evalCommand.ahk -- dispatcher for Config-defined hotkey commands
  and Bar click handlers. Lives in its own file so Bench_main.ahk can
  swap in a no-op stub instead of including this one (the bench process
  receives hotkeys via Manager_init's Config_restoreConfig but should
  never act on them -- the user's running bug.n owns real keypresses).
*/

Main_evalCommand(command)
{
  type := SubStr(command, 1, 5)
  If (type = "Run, ")
  {
    parameters := SubStr(command, 6)
    If InStr(parameters, ", ")
    {
      StringSplit, parameter, parameters, `,
      If (parameter0 = 2)
      {
        StringTrimLeft, parameter2, parameter2, 1
        Run, %parameter1%, %parameter2%
      }
      Else If (parameter0 > 2)
      {
        StringTrimLeft, parameter2, parameter2, 1
        StringTrimLeft, parameter3, parameter3, 1
        Run, %parameter1%, %parameter2%, %parameter3%
      }
    }
    Else
      Run, %parameters%
  }
  Else If (type = "Send ")
    Send % SubStr(command, 6)
  Else If (command = "Reload")
    Reload
  Else If (command = "ExitApp")
    ExitApp
  Else
  {
    i := InStr(command, "(")
    j := InStr(command, ")", False, i)
    If i And j
    {
      functionName := SubStr(command, 1, i - 1)
      functionArguments := SubStr(command, i + 1, j - (i + 1))
      StringReplace, functionArguments, functionArguments, %A_SPACE%, , All
      StringSplit, functionArgument, functionArguments, `,
      Debug_logMessage("DEBUG[1] Main_evalCommand: " functionName "(" functionArguments ")", 1)
      If (functionArgument0 = 0)
        %functionName%()
      Else If (functionArgument0 = 1)
        %functionName%(functionArguments)
      Else If (functionArgument0 = 2)
        %functionName%(functionArgument1, functionArgument2)
      Else If (functionArgument0 = 3)
        %functionName%(functionArgument1, functionArgument2, functionArgument3)
      Else If (functionArgument0 = 4)
        %functionName%(functionArgument1, functionArgument2, functionArgument3, functionArgument4)
    }
  }
}
