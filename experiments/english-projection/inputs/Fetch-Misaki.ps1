#requires -Version 7.4
# Fetch and verify misaki lexicon reference data at pinned commit fba1236595f2d2bf21d414ba6e57d25256afada3.
# License: MIT. No regex.
param(
    [string] $Commit = 'fba1236595f2d2bf21d414ba6e57d25256afada3',
    [string] $VendorRepo = 'C:\Dev\.vendor\misaki',
    [string] $OutDir = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki')
)
$ErrorActionPreference = 'Stop'

[void][System.IO.Directory]::CreateDirectory($OutDir)

$pinned = [ordered]@{
    'us_gold.json'   = 'DC414872A49A28AE6C141463D502FD945F3B2FDE040484FDC47D00CC4612686F'
    'us_silver.json' = 'DE8F67BE911BB6C659187B4A65FD966B6A30E56350E0F790D763210B053AC475'
}

foreach ($file in $pinned.Keys) {
    $targetPath = Join-Path $OutDir $file
    $expectedHash = $pinned[$file]

    if (Test-Path $targetPath) {
        $actualHash = (Get-FileHash $targetPath).Hash
        if ($actualHash -eq $expectedHash) {
            Write-Host "Verified existing $file ($expectedHash)"
            continue
        }
    }

    $sourcePath = Join-Path $VendorRepo "misaki\data\$file"
    if (Test-Path $sourcePath) {
        Write-Host "Copying $file from vendor repository..."
        Copy-Item $sourcePath $targetPath -Force
    } else {
        $url = "https://raw.githubusercontent.com/hexgrad/misaki/${Commit}/misaki/data/${file}"
        Write-Host "Downloading $file from $url..."
        Invoke-WebRequest -Uri $url -OutFile $targetPath -UserAgent 'PSPerception research'
    }

    $actualHash = (Get-FileHash $targetPath).Hash
    if ($actualHash -ne $expectedHash) {
        throw "Hash mismatch on $($file): expected $expectedHash, got $actualHash"
    }
    Write-Host "Verified $file ($expectedHash)"
}

Write-Host "Successfully materialized and verified misaki lexicon data ($Commit) [MIT]"
