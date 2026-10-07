#requires -Version 7.4
# Fetch and verify WikipediaHomographData at pinned commit 8f008f021e88f8b71118a27ae655f1f3121162bc
# Verifies all 329 files against inputs/MANIFEST.tsv (SHA-256). No regex.
param(
    [string] $Commit = '8f008f021e88f8b71118a27ae655f1f3121162bc',
    [string] $VendorRepo = 'C:\Dev\.vendor\WikipediaHomographData',
    [string] $CacheDir = 'C:\TEMP\sma-english-projection\inputs\WikipediaHomographData',
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'MANIFEST.tsv'),
    [string] $OutDir = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\WikipediaHomographData')
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

[void][System.IO.Directory]::CreateDirectory($OutDir)

# Read manifest entries: SHA256 `t RelativePath `t Length
$manifestLines = [System.IO.File]::ReadAllLines($ManifestPath)
$expected = [ordered]@{}
foreach ($line in $manifestLines) {
    if ($line.StartsWith('Commit:') -or $line.StartsWith('FileCount:') -or $line.StartsWith('SHA256')) {
        continue
    }
    $parts = $line.Split("`t")
    if ($parts.Count -ge 2) {
        $sha = $parts[0].Trim()
        $rel = $parts[1].Trim().Replace('/', '\')
        $expected[$rel] = $sha
    }
}

Write-Host "Verifying / materializing $($expected.Count) files from WikipediaHomographData ($Commit)..."

foreach ($entry in $expected.GetEnumerator()) {
    $relPath = $entry.Key
    $dest = Join-Path $OutDir $relPath
    $expHash = $entry.Value

    if (Test-Path $dest) {
        $h = (Get-FileHash $dest).Hash
        if ($h -eq $expHash) {
            continue
        }
    }

    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { [void][System.IO.Directory]::CreateDirectory($parent) }

    # Check local cache first
    $cached = Join-Path $CacheDir $relPath
    if (Test-Path $cached) {
        $h = (Get-FileHash $cached).Hash
        if ($h -eq $expHash) {
            Copy-Item $cached $dest -Force
            continue
        }
    }

    # Fallback to vendor git repo
    $gitPath = $relPath.Replace('\', '/')
    $content = (git -C $VendorRepo show "${Commit}:${gitPath}") -join "`n"
    [System.IO.File]::WriteAllText($dest, $content, [System.Text.Encoding]::UTF8)

    $h = (Get-FileHash $dest).Hash
    if ($h -ne $expHash) {
        throw "Hash mismatch on $($relPath): expected $expHash, got $h"
    }
}

# Verify all hashes
$verified = 0
foreach ($entry in $expected.GetEnumerator()) {
    $dest = Join-Path $OutDir $entry.Key
    $h = (Get-FileHash $dest).Hash
    if ($h -ne $entry.Value) {
        throw "Verification failed for $($entry.Key): expected $($entry.Value), got $h"
    }
    $verified++
}

Write-Host "Successfully verified $verified / $($expected.Count) WikipediaHomographData files in $OutDir"
