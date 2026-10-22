#requires -Version 7.2
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root 'work/php-src'
$module = Join-Path $root 'work/builder/php/BuildPhp'
$log = Join-Path $root 'reports/build.log'
Start-Transcript -Path $log -Force | Out-Null
try {
    Import-Module $module -Force
    # Only the official PHP dependency repository is used by the pinned constructor.
    $env:SBOM = 'false'
    Remove-Item Env:LIBS_BUILD_RUNS -ErrorAction SilentlyContinue
    Push-Location $src
    try { Invoke-PhpBuild -Arch x64 -Ts ts } finally { Pop-Location }
    $zips = @(Get-ChildItem (Join-Path $src 'artifacts') -Filter 'php-7.4.33-pl1-Win32-vc15-x64.zip')
    if ($zips.Count -ne 1) { throw 'Expected exactly one TS x64 runtime ZIP.' }
    Copy-Item $zips[0].FullName (Join-Path $root 'dist') -Force
} finally {
    Stop-Transcript | Out-Null
}

