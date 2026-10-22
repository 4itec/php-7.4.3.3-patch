#requires -Version 7.2
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lock = Get-Content (Join-Path $root 'sources.lock.json') -Raw | ConvertFrom-Json
$src = Join-Path $root 'work/php-src'
$builder = Join-Path $root 'work/builder'
$audit = Join-Path $root 'reports'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $audit,$dist | Out-Null
function Invoke-GitCommand {
    param([string]$Directory, [string[]]$Arguments)
    $output = & git -C $Directory @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($Arguments -join ' ')" }
    return $output
}
function WriteUtf8 {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
foreach ($entry in @(@{Path=$src;Sha=$lock.php_base_sha},@{Path=$builder;Sha=$lock.builder_sha})) {
    $actual = (Invoke-GitCommand $entry.Path @('rev-parse','HEAD')).Trim()
    if ($actual -ne $entry.Sha) { throw "Unexpected checkout: $actual" }
    if (Invoke-GitCommand $entry.Path @('status','--porcelain')) { throw "Checkout is not clean: $($entry.Path)" }
}
$headers = @{Accept='application/vnd.github+json';Authorization="Bearer $env:GH_TOKEN"}
$baseInfo = Invoke-RestMethod "https://api.github.com/repos/php/php-src/git/tags/$($lock.php_base_tag_object)" -Headers $headers
if (-not $baseInfo.verification.verified -or $baseInfo.object.sha -ne $lock.php_base_sha -or $baseInfo.tag -ne $lock.php_base_tag) {
    throw 'The official release tag or its GitHub signature verification does not match.'
}
$patchInfo = Invoke-RestMethod "https://api.github.com/repos/php/php-src/commits/$($lock.patch_sha)" -Headers $headers
if (-not $patchInfo.commit.verification.verified -or $patchInfo.sha -ne $lock.patch_sha -or $patchInfo.parents[0].sha -ne $lock.patch_parent_sha) {
    throw 'The official patch or its GitHub signature verification does not match.'
}
WriteUtf8 (Join-Path $audit 'official-tag.json') ($baseInfo | ConvertTo-Json -Depth 20)
WriteUtf8 (Join-Path $audit 'official-patch.json') ($patchInfo | ConvertTo-Json -Depth 20)
$null = Invoke-GitCommand $src @('fetch','--no-tags','--depth=1','origin',$lock.patch_parent_sha)
$null = Invoke-GitCommand $src @('fetch','--no-tags','--depth=1','origin',$lock.patch_sha)
$changed = @(Invoke-GitCommand $src @('diff','--name-only',$lock.patch_parent_sha,$lock.patch_sha))
$differences = Compare-Object @($lock.patch_files | Sort-Object) @($changed | Sort-Object)
if ($differences) { throw 'The official patch file list does not match the lock.' }
$patch = Join-Path $audit 'official-security.patch'
$null = Invoke-GitCommand $src @('diff','--binary','--full-index',"--output=$patch",$lock.patch_parent_sha,$lock.patch_sha)
$null = Invoke-GitCommand $src @('apply','--check','--index',$patch)
$null = Invoke-GitCommand $src @('apply','--index',$patch)
$verified = foreach ($file in $changed) {
    $actual = (Invoke-GitCommand $src @('rev-parse',":$file")).Trim()
    $expected = (Invoke-GitCommand $src @('rev-parse',"$($lock.patch_sha):$file")).Trim()
    if ($actual -ne $expected) { throw "Patched blob mismatch: $file" }
    [ordered]@{path=$file;git_blob_sha=$actual}
}
# Index contains only the security patch at this point; version changes are separate.
$version = $lock.build_version
$changes = @(
    @{Path='configure.ac';Pattern='AC_INIT\(\[PHP\],\[[^\]]+\]';Replacement="AC_INIT([PHP],[$version]"},
    @{Path='main/php_version.h';Pattern='#define PHP_MAJOR_VERSION \d+';Replacement='#define PHP_MAJOR_VERSION 7'},
    @{Path='main/php_version.h';Pattern='#define PHP_MINOR_VERSION \d+';Replacement='#define PHP_MINOR_VERSION 4'},
    @{Path='main/php_version.h';Pattern='#define PHP_RELEASE_VERSION \d+';Replacement='#define PHP_RELEASE_VERSION 33'},
    @{Path='main/php_version.h';Pattern='#define PHP_EXTRA_VERSION "[^"]*"';Replacement='#define PHP_EXTRA_VERSION "-pl1"'},
    @{Path='main/php_version.h';Pattern='#define PHP_VERSION "[^"]*"';Replacement=('#define PHP_VERSION "' + $version + '"')},
    @{Path='main/php_version.h';Pattern='#define PHP_VERSION_ID \d+';Replacement='#define PHP_VERSION_ID 70433'}
)
foreach ($change in $changes) {
    $path = Join-Path $src $change.Path
    $text = [IO.File]::ReadAllText($path)
    if ([regex]::Matches($text,$change.Pattern).Count -ne 1) { throw "Version pattern mismatch: $($change.Path)" }
    WriteUtf8 $path ([regex]::Replace($text,$change.Pattern,$change.Replacement))
}
$null = Invoke-GitCommand $src @('diff','--binary',"--output=$(Join-Path $audit 'build-identity.patch')")
$null = Invoke-GitCommand $src @('add','configure.ac','main/php_version.h')
$tree = (Invoke-GitCommand $src @('write-tree')).Trim()
$sourceZip = Join-Path $dist "php-$version-source.zip"
$null = Invoke-GitCommand $src @('archive','--format=zip',"--output=$sourceZip",$tree)
$manifest = [ordered]@{
    status='prepared-not-built';version=$version;base_sha=$lock.php_base_sha
    patch_sha=$lock.patch_sha;builder_sha=$lock.builder_sha;source_tree_sha=$tree
    patched_blobs=$verified;signature_check='GitHub API verification; not local GPG verification'
}
WriteUtf8 (Join-Path $audit 'prepared-source.json') ($manifest | ConvertTo-Json -Depth 10)
Write-Host "Official patch applied and all $($changed.Count) upstream blobs verified."

