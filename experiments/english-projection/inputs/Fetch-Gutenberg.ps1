#requires -Version 7.4
# Fetch and verify Gutenberg snapshot books against inputs/gutenberg/MANIFEST.tsv.
# Polite download or copy from cache, verifies SHA-256 for all 40 books. No regex.
param(
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'gutenberg\MANIFEST.tsv'),
    [string] $CacheDir = 'C:\TEMP\sma-english-projection\inputs\gutenberg',
    [string] $OutDir = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\gutenberg')
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

[void][System.IO.Directory]::CreateDirectory($OutDir)

$manifestLines = [System.IO.File]::ReadAllLines($ManifestPath)
$expected = [ordered]@{}
foreach ($line in ($manifestLines | Select-Object -Skip 1)) {
    $parts = $line.Split("`t")
    if ($parts.Count -ge 4) {
        $expected[$parts[0]] = @{ Bytes = [long]$parts[1]; Hash = $parts[2]; Url = $parts[3] }
    }
}

Write-Host "Verifying / materializing $($expected.Count) Gutenberg books..."

foreach ($id in $expected.Keys) {
    $clean = Join-Path $OutDir "pg$id.txt"
    $exp = $expected[$id]

    if (Test-Path $clean) {
        $h = (Get-FileHash $clean).Hash
        if ($h -eq $exp.Hash) {
            continue
        }
    }

    # Check cache
    $cacheClean = Join-Path $CacheDir "pg$id.txt"
    if (Test-Path $cacheClean) {
        $h = (Get-FileHash $cacheClean).Hash
        if ($h -eq $exp.Hash) {
            Copy-Item $cacheClean $clean -Force
            continue
        }
    }

    # Download raw and clean
    $raw = Join-Path $OutDir "pg$id.raw.txt"
    $url = $exp.Url
    Write-Host "Downloading pg$id from $url..."
    Invoke-WebRequest -Uri $url -OutFile $raw -UserAgent 'PSPerception research (polite fetch)'
    Start-Sleep -Seconds 2

    $text = [System.IO.File]::ReadAllText($raw)
    $a = $text.IndexOf('*** START OF', [System.StringComparison]::Ordinal)
    $b = $text.IndexOf('*** END OF', [System.StringComparison]::Ordinal)
    if ($a -lt 0 -or $b -le $a) {
        throw "Missing START/END markers in pg$id"
    }
    $a = $text.IndexOf("`n", $a) + 1
    [System.IO.File]::WriteAllText($clean, $text.Substring($a, $b - $a))

    $h = (Get-FileHash $clean).Hash
    if ($h -ne $exp.Hash) {
        throw "Hash mismatch on pg$($id): expected $($exp.Hash), got $h"
    }
}

Write-Host "Successfully verified all $($expected.Count) Gutenberg books in $OutDir"
