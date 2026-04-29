# Claude Code → bug.n urgent-view hook

This integrates Claude Code's notification events with bug.n's urgent-view feature: when
Claude is waiting on you (permission prompt, follow-up question, idle await), the alacritty
terminal hosting that Claude session flashes its taskbar entry, which bug.n picks up via
HSHELL_FLASH and lights the holding view red on the bar. Win+U jumps to it.

## How it works

`flash-window.ps1 -AncestorProcess alacritty` walks up the parent process chain from the
PowerShell hook process (hook PowerShell → claude.exe → ... → alacritty.exe) until it hits
the named ancestor, then calls FlashWindowEx on a top-level window owned by that PID. The
ancestor walk is necessary because Claude Code's Notification hook payload does not include
a terminal PID — only `session_id`, `cwd`, etc.

bug.n catches HSHELL_FLASH in `Manager_onShellMessage` and routes it to `Manager_markUrgent`,
which marks every non-active view holding the flashing window as urgent.

## Setup on a new machine

Add this to `~/.claude/settings.json` (user-level, so it fires anywhere you run Claude):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          {
            "type": "command",
            "shell": "powershell",
            "command": "& 'PATH\\TO\\bug.n\\tools\\flash-window.ps1' -AncestorProcess alacritty -DelaySeconds 0"
          }
        ]
      }
    ]
  }
}
```

Replace `PATH\\TO\\bug.n` with this machine's checkout (double-escape backslashes for JSON).
If you use a different terminal, change `-AncestorProcess alacritty` to its process name —
e.g. `wt`, `WindowsTerminal`, `conhost`, `pwsh`. Verify the chain first by running
`flash-window.ps1 -Process <name>` from a Claude session in that terminal; if the manual
flash works, the hook will too.

After saving, run `/hooks` in an existing Claude session to force a config reload, or
restart Claude Code. Test by switching to a non-active bug.n view and prompting Claude.

## Why these matchers only

`permission_prompt` and `idle_prompt` are the two Notification types where Claude is
genuinely waiting on you. The others (`auth_success`, `elicitation_*`) fire for events that
are either ephemeral or already user-visible inline — including them produces incidental
flashes.

## Troubleshooting

- **Nothing flashes:** restart Claude Code. The settings watcher only watches `.claude/`
  directories that already had a settings file when the session started.
- **"No ancestor named 'alacritty' found"** in stderr: you launched Claude in a different
  terminal. Update `-AncestorProcess` or override per-machine.
- **Bar doesn't light red:** the alacritty window's view is the active view. Urgent-view
  only marks non-active views (matches AwesomeWM behavior).
