<#
  Flash a window's taskbar entry, firing HSHELL_FLASH which bug.n catches
  via Manager_onShellMessage and routes to Manager_markUrgent.

  Usage:
    .\tools\flash-window.ps1 -Process notepad
    .\tools\flash-window.ps1 -Process notepad -DelaySeconds 10 -Count 8

  Run it, switch the target window to a non-active view, then sit on a
  different view. After -DelaySeconds, the target's taskbar entry will
  flash -Count times — bug.n's bar should light up red on the view that
  holds the target window.
#>

param(
  [string] $Process,
  [string] $TitlePattern,
  [int] $DelaySeconds = 8,
  [int] $Count = 6,
  [int] $TimeoutMs = 500
)

if (-not $Process -and -not $TitlePattern) {
  Write-Error "Provide -Process <name> and/or -TitlePattern <regex>."
  exit 1
}

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class FlashApi {
  [StructLayout(LayoutKind.Sequential)]
  public struct FLASHWINFO {
    public uint cbSize;
    public IntPtr hwnd;
    public uint dwFlags;
    public uint uCount;
    public uint dwTimeout;
  }
  public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hwnd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder s, int n);

  // Find first top-level window whose pid is in pidSet (any allowed) AND
  // whose title matches titleRegex (if non-null). Hidden windows count.
  public static IntPtr FindMatching(System.Collections.Generic.HashSet<uint> pidSet, System.Text.RegularExpressions.Regex titleRegex) {
    IntPtr found = IntPtr.Zero;
    EnumWindowsProc cb = (h, l) => {
      uint wpid; GetWindowThreadProcessId(h, out wpid);
      if (pidSet != null && !pidSet.Contains(wpid)) return true;
      int len = GetWindowTextLength(h);
      if (len <= 0) return true;
      string t = GetTitle(h);
      if (titleRegex != null && !titleRegex.IsMatch(t)) return true;
      found = h;
      return false;
    };
    EnumWindows(cb, IntPtr.Zero);
    return found;
  }

  public static string GetTitle(IntPtr hwnd) {
    int len = GetWindowTextLength(hwnd);
    StringBuilder sb = new StringBuilder(len + 1);
    GetWindowText(hwnd, sb, sb.Capacity);
    return sb.ToString();
  }
}
"@

$pidSet = $null
if ($Process) {
  $procs = @(Get-Process -Name $Process -ErrorAction SilentlyContinue)
  if ($procs.Count -eq 0) {
    Write-Error "No process named '$Process'. Open it first (or use -TitlePattern)."
    exit 1
  }
  $pidSet = New-Object 'System.Collections.Generic.HashSet[uint32]'
  foreach ($p in $procs) { [void]$pidSet.Add([uint32]$p.Id) }
}
$titleRegex = $null
if ($TitlePattern) {
  $titleRegex = New-Object System.Text.RegularExpressions.Regex($TitlePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

$hwnd = [FlashApi]::FindMatching($pidSet, $titleRegex)
if ($hwnd -eq [IntPtr]::Zero) {
  $criteria = @()
  if ($Process)      { $criteria += "process=$Process (pids=$($pidSet -join ','))" }
  if ($TitlePattern) { $criteria += "title~/$TitlePattern/" }
  Write-Error "No top-level window matched: $($criteria -join '; ')"
  exit 1
}
$title = [FlashApi]::GetTitle($hwnd)

Write-Host "Target: HWND $hwnd, '$title'"
Write-Host "Move it to a non-active view, then switch away. Flashing in $DelaySeconds seconds..."
Start-Sleep -Seconds $DelaySeconds

$fwi = New-Object FlashApi+FLASHWINFO
$fwi.cbSize    = [System.Runtime.InteropServices.Marshal]::SizeOf([type][FlashApi+FLASHWINFO])
$fwi.hwnd      = $hwnd
$fwi.dwFlags   = 3            # FLASHW_ALL = caption + taskbar
$fwi.uCount    = [uint32]$Count
$fwi.dwTimeout = [uint32]$TimeoutMs

[FlashApi]::FlashWindowEx([ref]$fwi) | Out-Null
Write-Host "Flashed $Count times."
