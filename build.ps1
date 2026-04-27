$root    = $PSScriptRoot
$ahk2exe = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
$bin     = 'C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 64-bit.bin'

if (-not (Test-Path $ahk2exe)) { Write-Error "Ahk2Exe not found: $ahk2exe"; exit 1 }
if (-not (Test-Path $bin))     { Write-Error "AHK v1 bin not found: $bin";   exit 1 }

$buildDir      = Join-Path $root 'build'
$distDir       = Join-Path $root 'dist'
$buildExe      = Join-Path $buildDir 'bugn.exe'
$distExe       = Join-Path $distDir  'bugn.exe'
$buildBenchExe = Join-Path $buildDir 'bugn-bench.exe'
$distBenchExe  = Join-Path $distDir  'bugn-bench.exe'

if (-not (Test-Path $buildDir)) { New-Item -ItemType Directory -Path $buildDir | Out-Null }

Start-Process -FilePath $ahk2exe -ArgumentList "/in","`"$root\src\Main.ahk`"","/out","`"$buildExe`"","/icon","`"$root\src\logo.ico`"","/bin","`"$bin`"" -Wait -NoNewWindow

if (-not (Test-Path $buildExe)) {
    Write-Error "Build failed: $buildExe was not created"
    exit 1
}
Write-Host "Build complete: build\bugn.exe"

Start-Process -FilePath $ahk2exe -ArgumentList "/in","`"$root\src\Bench_main.ahk`"","/out","`"$buildBenchExe`"","/icon","`"$root\src\logo.ico`"","/bin","`"$bin`"" -Wait -NoNewWindow

if (-not (Test-Path $buildBenchExe)) {
    Write-Error "Bench build failed: $buildBenchExe was not created"
    exit 1
}
Write-Host "Build complete: build\bugn-bench.exe"

if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }
try {
    Copy-Item $buildExe $distExe -Force -ErrorAction Stop
    Write-Host "Copied to: dist\bugn.exe"
} catch {
    Write-Warning "Could not copy to dist\bugn.exe (probably locked by a running bug.n). Fresh build is in build\bugn.exe."
}
try {
    Copy-Item $buildBenchExe $distBenchExe -Force -ErrorAction Stop
    Write-Host "Copied to: dist\bugn-bench.exe"
} catch {
    Write-Warning "Could not copy to dist\bugn-bench.exe (probably locked by a running bench). Fresh build is in build\bugn-bench.exe."
}
