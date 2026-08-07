/*
  bug.n -- tiling window management
  Copyright (c) 2010-2019 Joshua Fuhs, joten

  @license GNU General Public License version 3

  Bench_hotkeyDrop.ahk -- functional guard for the #MaxThreadsBuffer On
  directive (see Directives.ahk). That directive keeps a hotkey press
  arriving while its own subroutine is still running from being silently
  discarded (default #MaxThreadsBuffer Off drops it) -- the failure that
  made a single #/ (rename) press do nothing under load.

  This drives the real keyboard-hook buffer, which Yunit cannot reach
  (Yunit calls functions directly, never launching a hotkey thread through
  the hook). It runs on throwaway hotkeys bound to F14/F15 -- non-modifier
  keys absent from real keyboards, so injecting them has no OS effect and
  no stuck-modifier risk (unlike Win/Ctrl/Alt).

  Determinism: each handler injects one colliding press of its OWN key, via
  SendEvent, from INSIDE the still-running first handler. At that point
  #MaxThreadsPerHotkey=1 is already reached, so the injected press is
  guaranteed to hit the buffer/drop decision -- no reliance on
  send-two-presses-fast timing. SendLevel 1 lets the generated event
  trigger our own hook hotkey (its level must exceed the hotkey InputLevel).

    F14  no per-hotkey option -> inherits global buffer On -> 2 fires
    F15  registered with B0    -> buffering forced off      -> 1 fire (dropped)

  F15 is a negative control: it proves the collision really occurred and a
  drop is detectable. If F15 shows 2 the collision never happened and the
  run is inconclusive -> fail, so F14 can never false-pass.

  Exits 0 on pass, 1 on fail. Invoked via
  `bugn-bench.exe --scenario hotkeyDrop`.
*/

Bench_runHotkeyDrop() {
  Global Bench_hkDrop_bufferedFires, Bench_hkDrop_controlFires

  Bench_hkDrop_bufferedFires := 0
  Bench_hkDrop_controlFires  := 0

  ;; $ forces the keyboard hook so the SendEvents below can trigger our own
  ;; hotkeys (SendInput/SendPlay deliberately bypass the script's hooks).
  Hotkey, $F14, Bench_hkDrop_buffered, On
  Hotkey, $F15, Bench_hkDrop_control, On B0

  SendLevel, 1   ;; generated input must outrank the hotkeys' InputLevel (0)

  ;; Buffered case: F14 inherits the global #MaxThreadsBuffer On.
  SendEvent {F14}
  Sleep, 300     ;; allow the buffered second launch to drain

  ;; Control case: F15's B0 forces buffering off regardless of the global.
  SendEvent {F15}
  Sleep, 300

  Hotkey, $F14, , Off
  Hotkey, $F15, , Off

  failures := 0

  ;; Negative control first: no drop here means the collision never
  ;; happened, so the buffered assertion below would be meaningless.
  If (Bench_hkDrop_controlFires != 1) {
    Debug_logMessage("DEBUG[0] Bench_runHotkeyDrop INCONCLUSIVE: B0 control fired " . Bench_hkDrop_controlFires . "x, expected 1 (collision not reproduced)", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runHotkeyDrop: OK B0 control dropped the collided press (1 fire)", 0)
  }

  If (Bench_hkDrop_bufferedFires != 2) {
    Debug_logMessage("DEBUG[0] Bench_runHotkeyDrop FAIL: buffered hotkey fired " . Bench_hkDrop_bufferedFires . "x, expected 2 -- is #MaxThreadsBuffer On in effect?", 0)
    failures += 1
  } Else {
    Debug_logMessage("DEBUG[0] Bench_runHotkeyDrop: OK buffered hotkey queued the collided press (2 fires)", 0)
  }

  If failures {
    Debug_logMessage("DEBUG[0] Bench_runHotkeyDrop: " . failures . " assertion(s) failed", 0)
    ExitApp, 1
  }
  Debug_logMessage("DEBUG[0] Bench_runHotkeyDrop: PASS", 0)
  ExitApp, 0
}

Bench_hkDrop_buffered:
  Bench_hkDrop_bufferedFires += 1
  If (Bench_hkDrop_bufferedFires = 1) {
    ;; Still inside thread #1; the per-hotkey max (1) is reached, so this
    ;; press can only be buffered (global On) or dropped (were it off).
    SendLevel, 1
    SendEvent {F14}
    Sleep, 60      ;; stay running so the injected press actually collides
  }
Return

Bench_hkDrop_control:
  Bench_hkDrop_controlFires += 1
  If (Bench_hkDrop_controlFires = 1) {
    SendLevel, 1
    SendEvent {F15}
    Sleep, 60
  }
Return
