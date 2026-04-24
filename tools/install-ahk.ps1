#Requires -Version 5.1
<#
  Downloads AutoHotkey v1.1.x from autohotkey.com, extracts it to -OutDir,
  and resolves the paths for AHK_EXE / AHK2EXE / AHK_V1_BIN by locating the
  binaries inside the extracted tree (so the script tolerates zip-layout
  changes across versions).

  Emits the resolved paths as PowerShell variables on stdout, and — if
  $env:GITHUB_ENV is set — appends them to the GitHub Actions env file so
  later workflow steps inherit them.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$OutDir,
  [string]$Version = '1.1.37.02',
  [string]$ZipUrl,
  [string]$ZipCache
)

$ErrorActionPreference = 'Stop'

if (-not $ZipUrl) {
  $ZipUrl = "https://www.autohotkey.com/download/1.1/AutoHotkey_$Version.zip"
}
if (-not $ZipCache) {
  $ZipCache = Join-Path $env:TEMP "AutoHotkey_$Version.zip"
}

if (Test-Path $ZipCache) {
  Write-Host "Using cached zip: $ZipCache"
} else {
  Write-Host "Downloading $ZipUrl"
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipCache -UseBasicParsing
}

if (Test-Path $OutDir) {
  Write-Host "Clearing existing $OutDir"
  Remove-Item -Path $OutDir -Recurse -Force
}
New-Item -Path $OutDir -ItemType Directory -Force | Out-Null

Write-Host "Extracting to $OutDir"
Expand-Archive -Path $ZipCache -DestinationPath $OutDir -Force

function Find-One {
  param([string]$Root, [string]$Filter, [string]$Label)
  $hit = Get-ChildItem -Path $Root -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if (-not $hit) {
    throw "Could not locate $Label ($Filter) under $Root"
  }
  return $hit.FullName
}

$ahkExe    = Find-One -Root $OutDir -Filter 'AutoHotkeyU64.exe' -Label 'AutoHotkey interpreter (U64)'
$ahk2Exe   = Find-One -Root $OutDir -Filter 'Ahk2Exe.exe'       -Label 'Ahk2Exe compiler'
$ahkV1Bin  = Find-One -Root $OutDir -Filter 'Unicode 64-bit.bin' -Label 'Unicode 64-bit base file'

Write-Host ''
Write-Host 'Resolved paths:'
Write-Host "  AHK_EXE    = $ahkExe"
Write-Host "  AHK2EXE    = $ahk2Exe"
Write-Host "  AHK_V1_BIN = $ahkV1Bin"

if ($env:GITHUB_ENV) {
  "AHK_EXE=$ahkExe"       | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  "AHK2EXE=$ahk2Exe"      | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  "AHK_V1_BIN=$ahkV1Bin"  | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  Write-Host 'Exported to $GITHUB_ENV for subsequent steps.'
}

[pscustomobject]@{
  AHK_EXE    = $ahkExe
  AHK2EXE    = $ahk2Exe
  AHK_V1_BIN = $ahkV1Bin
}
