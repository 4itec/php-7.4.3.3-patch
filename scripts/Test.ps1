#requires -Version 7.2
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$audit = Join-Path $root 'reports'
$dist = Join-Path $root 'dist'
$lock = Get-Content (Join-Path $root 'sources.lock.json') -Raw | ConvertFrom-Json
$runtime = Join-Path $root 'work/test-runtime'
$state = Join-Path $root 'work/test-state'
$zip = Join-Path $dist "php-$($lock.build_version)-Win32-vc15-x64.zip"
New-Item -ItemType Directory -Force -Path $runtime,$state | Out-Null
function WriteUtf8 {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
function Start-PhpProcess {
    param([string[]]$Arguments)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $runtime 'php.exe'
    $info.WorkingDirectory = $runtime
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Cannot start compiled PHP.' }
    return $process
}
function Invoke-PhpProcess {
    param([string[]]$Arguments, [string]$LogName)
    $process = Start-PhpProcess $Arguments
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(120000)) {
        $process.Kill($true)
        throw "PHP timed out: $LogName"
    }
    $result = [ordered]@{
        exit_code=$process.ExitCode
        stdout=$stdout.GetAwaiter().GetResult()
        stderr=$stderr.GetAwaiter().GetResult()
    }
    WriteUtf8 (Join-Path $audit "$LogName.json") ($result | ConvertTo-Json -Depth 5)
    $process.Dispose()
    return [pscustomobject]$result
}
function Assert-CleanExit {
    param($Result, [string]$Name)
    if ($Result.exit_code -ne 0 -or $Result.stderr.Trim()) {
        throw "$Name failed or produced diagnostics. See reports."
    }
}
Start-Transcript -Path (Join-Path $audit 'tests.log') -Force | Out-Null
try {
    Import-Module (Join-Path $root 'work/builder/php/BuildPhp') -Force
    Invoke-PhpSmokeTests -ArtifactsDirectory (Join-Path $root 'work/php-src/artifacts') -Arch x64 -Ts ts
    Expand-Archive -Path $zip -DestinationPath $runtime -Force
    foreach ($file in @('php.exe','php7ts.dll','php7apache2_4.dll','license.txt')) {
        if (-not (Test-Path (Join-Path $runtime $file))) { throw "Missing runtime file: $file" }
    }
    $env:PATH = "$runtime;$env:PATH"
    $env:PHP_INI_SCAN_DIR = ''
    $ext = (Join-Path $runtime 'ext').Replace('\','/')
    $ini = Join-Path $state 'php.ini'
    $settings = @(
        ('extension_dir="{0}"' -f $ext)
        'error_reporting=-1'
        'display_errors=stderr'
        'log_errors=0'
        'date.timezone=UTC'
        'opcache.enable_cli=1'
        ('session.save_path="{0}"' -f $state.Replace('\','/'))
        # Intentionally enabled here: the upstream C patch must suppress it anyway.
        'session.upload_progress.enabled=1'
        'session.upload_progress.cleanup=0'
    )
    Get-ChildItem (Join-Path $runtime 'ext') -Filter 'php_*.dll' -File |
        Sort-Object Name | ForEach-Object {
            if ($_.Name -in @('php_pdo_firebird.dll','php_snmp.dll','php_pdo_oci.dll') -or $_.Name -like 'php_oci8*.dll') {
                Write-Host "Skipping external-client extension: $($_.Name)"
            } elseif ($_.Name -eq 'php_opcache.dll') {
                $settings += ('zend_extension={0}' -f $_.Name)
            } else {
                $settings += ('extension={0}' -f $_.Name)
            }
        }
    WriteUtf8 $ini (($settings -join [Environment]::NewLine) + [Environment]::NewLine)
    $common = @('-c',$ini)
    $info = Invoke-PhpProcess ($common + @('-i')) 'php-info'
    Assert-CleanExit $info 'php -i'
    if ($info.stdout -notmatch 'Compiler => MSVC15 \(Visual C\+\+ 2017\)') {
        throw 'Unexpected PHP compiler identity.'
    }
    $functional = Invoke-PhpProcess ($common + @((Join-Path $root 'tests/functional.php'),$state)) 'functional'
    Assert-CleanExit $functional 'Functional tests'
    $functionalData = $functional.stdout | ConvertFrom-Json
    if ($functionalData.status -ne 'passed') { throw 'Functional assertions failed.' }

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $server = Start-PhpProcess ($common + @('-S',"127.0.0.1:$port",'-t',(Join-Path $root 'tests')))
    $serverOut = $server.StandardOutput.ReadToEndAsync()
    $serverErr = $server.StandardError.ReadToEndAsync()
    $url = "http://127.0.0.1:$port/http-probe.php"
    try {
        $ready = $false
        for ($attempt=0; $attempt -lt 30; $attempt++) {
            if ($server.HasExited) { throw 'Test HTTP server exited before startup.' }
            try {
                $null = Invoke-RestMethod $url -TimeoutSec 2 -NoProxy
                $ready = $true
                break
            } catch {
                Start-Sleep -Milliseconds 200
            }
        }
        if (-not $ready) { throw 'Test HTTP server did not become ready.' }
        $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
        $first = Invoke-RestMethod $url -WebSession $session -NoProxy -TimeoutSec 10
        if ($first.version -ne $lock.build_version -or $first.method -ne 'GET') {
            throw 'HTTP runtime identity failed.'
        }
        $form = Invoke-RestMethod $url -Method Post -WebSession $session -NoProxy -TimeoutSec 10 -Body @{field='normal-form'}
        if ($form.method -ne 'POST' -or $form.field -ne 'normal-form' -or $form.previous -ne 'persisted') {
            throw 'Normal form or HTTP session persistence failed.'
        }
        $upload = Join-Path $state 'upload.txt'
        WriteUtf8 $upload ('ordinary upload ' * 128)
        $multipart = Invoke-RestMethod $url -Method Post -WebSession $session -NoProxy -TimeoutSec 10 -Form @{
            field='multipart-form'
            PHP_SESSION_UPLOAD_PROGRESS='probe'
            upload=(Get-Item $upload)
        }
        if (-not $multipart.uploaded -or $multipart.field -ne 'multipart-form' -or $multipart.previous -ne 'persisted') {
            throw 'Multipart form or HTTP session persistence failed.'
        }
        if ($multipart.progress_present) { throw 'Session upload progress was not disabled by the patch.' }
        WriteUtf8 (Join-Path $audit 'http-tests.json') (@{
            status='passed';get=$first;form=$form;multipart=$multipart
        } | ConvertTo-Json -Depth 10)
    } finally {
        if (-not $server.HasExited) { $server.Kill($true) }
        $server.WaitForExit()
        WriteUtf8 (Join-Path $audit 'http-server.stdout.log') ($serverOut.GetAwaiter().GetResult())
        WriteUtf8 (Join-Path $audit 'http-server.stderr.log') ($serverErr.GetAwaiter().GetResult())
        $server.Dispose()
    }

    $marker = Join-Path $state 'unexpected-shutdown-callback.txt'
    if (Test-Path $marker) { throw 'OOM marker already exists; isolated state required.' }
    $oom = Invoke-PhpProcess ($common + @('-d','memory_limit=16M',(Join-Path $root 'tests/oom.php'),$marker)) 'oom'
    if ($oom.exit_code -ne 1 -or ($oom.stdout + $oom.stderr) -notmatch 'Allowed memory size.*exhausted' -or (Test-Path $marker)) {
        throw 'Official OOM exit behavior regression check failed.'
    }
    $inventory = @(Get-ChildItem $runtime -Recurse -File | Where-Object { $_.Extension -in @('.dll','.exe') } | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path=[IO.Path]::GetRelativePath($runtime,$_.FullName).Replace('\','/')
            sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            file_version=$_.VersionInfo.FileVersion
            product_version=$_.VersionInfo.ProductVersion
        }
    })
    $manifest = [ordered]@{
        schema=1;status='build-and-listed-tests-passed';version=$lock.build_version
        sources=$lock
        source_verification=(Get-Content (Join-Path $audit 'prepared-source.json') -Raw | ConvertFrom-Json)
        runtime_sha256=(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        source_zip_sha256=(Get-FileHash (Join-Path $dist "php-$($lock.build_version)-source.zip") -Algorithm SHA256).Hash.ToLowerInvariant()
        build_repository=$env:GITHUB_REPOSITORY;build_commit=$env:GITHUB_SHA
        run_url="https://github.com/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
        runner_image=$env:ImageOS;runner_image_version=$env:ImageVersion
        functional=$functionalData;binary_inventory=$inventory
        validation_limits='Isolated CLI and built-in HTTP tests; Apache module presence only. Actual Wampserver deployment and full application compatibility are not tested here. Not a complete vulnerability audit.'
    }
    WriteUtf8 (Join-Path $dist 'manifest.json') ($manifest | ConvertTo-Json -Depth 25)
    $hashes = @(Get-ChildItem $dist -File | Where-Object Name -ne 'SHA256SUMS' | Sort-Object Name | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$_.Name
    })
    WriteUtf8 (Join-Path $dist 'SHA256SUMS') (($hashes -join [char]10) + [char]10)
    Write-Host 'Official smoke, functional, HTTP, multipart and OOM checks passed.'
} finally {
    Stop-Transcript | Out-Null
}
