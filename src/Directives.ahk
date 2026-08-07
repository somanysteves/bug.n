/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3

  Directives.ahk -- script-wide directives that MUST be identical in
  bugn.exe (Main.ahk) and bugn-bench.exe (Bench_main.ahk). Single-sourced
  here and #Included by both so the Bench_hotkeyDrop scenario genuinely
  guards the production setting: drop the directive and both the shipped
  binary and the bench that proves it lose the behaviour together.

  Contains only directives (no executable statements), so it is safe to
  #Include from either entry point's header.
*/

;; Queue a hotkey press that can't launch immediately (its own subroutine
;; still running, e.g. under a shell-event storm) instead of silently
;; discarding it. Without this a single-shot like #/ (rename) is lost
;; under load; see Bench_hotkeyDrop.ahk and Manager_renameView.
#MaxThreadsBuffer On
