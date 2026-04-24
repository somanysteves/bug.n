#Requires -Version 5.1
<#
  Local dryrun of the CI pipeline: installs AutoHotkey v1.1.x into a cache
  under $env:TEMP, points AHK_EXE / AHK2EXE / AHK_V1_BIN at it for the
  current process only (your system install is untouched), then runs
  build.bat and test.bat. Exits with the test runner's exit code.

  Intended for verifying CI changes without having to push to GitHub.
#>
[CmdletBinding()]
param(
  [string]$Version  = '1.1.37.02',
  [string]$AhkDir,
  [switch]$SkipInstall,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $PSScriptRoot 'install-ahk.ps1'

if (-not $AhkDir) {
  $AhkDir = Join-Path $env:TEMP "bugn-ci-ahk-$Version"
}

if ($SkipInstall -and -not (Test-Path $AhkDir)) {
  throw "-SkipInstall given but $AhkDir does not exist. Run once without the flag first."
}

if (-not $SkipInstall) {
  Write-Host '=== install AutoHotkey ===' -ForegroundColor Cyan
  & $installer -OutDir $AhkDir -Version $Version
  if ($LASTEXITCODE) { throw "install-ahk.ps1 failed with exit $LASTEXITCODE" }
}

function Find-One {
  param([string]$Root, [string]$Filter)
  (Get-ChildItem -Path $Root -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue |
    Select-Object -First 1).FullName
}

$env:AHK_EXE    = Find-One $AhkDir 'AutoHotkeyU64.exe'
$env:AHK2EXE    = Find-One $AhkDir 'Ahk2Exe.exe'
$env:AHK_V1_BIN = Find-One $AhkDir 'Unicode 64-bit.bin'

if (-not $env:AHK_EXE -or -not $env:AHK2EXE -or -not $env:AHK_V1_BIN) {
  throw "Could not resolve one or more AHK paths under $AhkDir"
}

Write-Host ''
Write-Host 'Using:'
Write-Host "  AHK_EXE    = $env:AHK_EXE"
Write-Host "  AHK2EXE    = $env:AHK2EXE"
Write-Host "  AHK_V1_BIN = $env:AHK_V1_BIN"

if (-not $SkipBuild) {
  Write-Host ''
  Write-Host '=== build.bat ===' -ForegroundColor Cyan
  & cmd.exe /c (Join-Path $repoRoot 'build.bat')
  if ($LASTEXITCODE) { throw "build.bat failed with exit $LASTEXITCODE" }
}

Write-Host ''
Write-Host '=== test.bat ===' -ForegroundColor Cyan
& cmd.exe /c (Join-Path $repoRoot 'test.bat')
$testRc = $LASTEXITCODE

Write-Host ''
if ($testRc -eq 0) {
  Write-Host 'CI dryrun succeeded.' -ForegroundColor Green
} else {
  Write-Host "CI dryrun failed: test.bat exited $testRc" -ForegroundColor Red
}
exit $testRc
