$root   = $PSScriptRoot
$ahk2exe = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
$bin     = 'C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 64-bit.bin'

if (-not (Test-Path $ahk2exe)) { Write-Error "Ahk2Exe not found: $ahk2exe"; exit 1 }
if (-not (Test-Path $bin))     { Write-Error "AHK v1 bin not found: $bin";   exit 1 }

Stop-Process -Name bugn -ErrorAction SilentlyContinue

Start-Process -FilePath $ahk2exe -ArgumentList "/in","`"$root\src\Main.ahk`"","/out","`"$root\bugn.exe`"","/icon","`"$root\src\logo.ico`"","/bin","`"$bin`"" -Wait -NoNewWindow

if (Test-Path "$root\bugn.exe") {
    Write-Host "Build complete: bugn.exe"
} else {
    Write-Error "Build failed: bugn.exe was not created"
    exit 1
}
