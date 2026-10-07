#requires -Version 7.4
# Fetch and verify Universal Dependencies English-EWT at pinned commit b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c
# License: CC BY-SA 4.0 (experiments only). No regex.
param(
    [string] $Commit = 'b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c',
    [string] $OutDir = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\ud-ewt-r2.18')
)
$ErrorActionPreference = 'Stop'

[void][System.IO.Directory]::CreateDirectory($OutDir)

$pinned = [ordered]@{
    'en_ewt-ud-train.conllu' = 'D68E06122A702464C613076523D56740F047E5BBE89DD90EC32737E04D952143'
    'en_ewt-ud-dev.conllu'   = '39239E0A60DB3AE68F4B7036189F11B6692741D10FF8240DD91F74F2760D90F8'
}

$cacheSource = 'C:\TEMP\sma-english-projection\inputs\ud-ewt-r2.18'

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

    # Fetch from local cache or upstream
    if (Test-Path (Join-Path $cacheSource $file)) {
        Write-Host "Copying $file from local cache..."
        Copy-Item (Join-Path $cacheSource $file) $targetPath -Force
    } else {
        $url = "https://raw.githubusercontent.com/UniversalDependencies/UD_English-EWT/${Commit}/${file}"
        Write-Host "Downloading $file from $url..."
        Invoke-WebRequest -Uri $url -OutFile $targetPath -UserAgent 'PSPerception research'
    }

    $actualHash = (Get-FileHash $targetPath).Hash
    if ($actualHash -ne $expectedHash) {
        throw "Hash mismatch on $($file): expected $expectedHash, got $actualHash"
    }
    Write-Host "Verified $file ($expectedHash)"
}

Write-Host "Successfully materialized and verified UD EWT r2.18 ($Commit) [CC BY-SA 4.0 experiments only]"
