#requires -Version 7.2
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root 'work/php-src'
$module = Join-Path $root 'work/builder/php/BuildPhp'
$log = Join-Path $root 'reports/build.log'
$secretValues = @(Get-ChildItem Env: | Where-Object {
    $_.Name -match '(?i)(TOKEN|PASSWORD|SECRET|CREDENTIAL|PRIVATE_KEY)' -and $_.Value.Length -ge 4
} | ForEach-Object Value)
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
    $runtimeHash = (Get-FileHash $zips[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $context = [ordered]@{
        repository=$env:GITHUB_REPOSITORY
        commit=$env:GITHUB_SHA
        run_id=$env:GITHUB_RUN_ID
        run_url="https://github.com/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
        lock_sha256=(Get-FileHash (Join-Path $root 'sources.lock.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        runtime_sha256=$runtimeHash
        source_zip_sha256=(Get-FileHash (Join-Path $root 'dist/php-7.4.33-pl1-source.zip') -Algorithm SHA256).Hash.ToLowerInvariant()
        runner_image=$env:ImageOS
        runner_image_version=$env:ImageVersion
    }
    [IO.File]::WriteAllText((Join-Path $root 'reports/build-context.json'),($context | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    Write-Host "Runtime SHA256: $runtimeHash"
} finally {
    Stop-Transcript | Out-Null
    $transcript = [IO.File]::ReadAllText($log)
    foreach ($secretValue in $secretValues) { $transcript = $transcript.Replace($secretValue, '[REDACTED]') }
    [IO.File]::WriteAllText($log,$transcript,[Text.UTF8Encoding]::new($false))
}

