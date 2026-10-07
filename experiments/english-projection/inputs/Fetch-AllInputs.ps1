#requires -Version 7.4
# Orchestrator to materialize and verify all external input datasets:
# 1. WikipediaHomographData (8f008f02...)
# 2. Universal Dependencies English-EWT (b7711cce...)
# 3. Project Gutenberg 40-book snapshot
# 4. Misaki lexicon data (fba12365...)
param()
$ErrorActionPreference = 'Stop'

Write-Host "=== Fetching & Verifying WikipediaHomographData ==="
& (Join-Path $PSScriptRoot 'Fetch-WikipediaHomographData.ps1')

Write-Host "`n=== Fetching & Verifying UD EWT r2.18 ==="
& (Join-Path $PSScriptRoot 'Fetch-UdEwt.ps1')

Write-Host "`n=== Fetching & Verifying Gutenberg Snapshot ==="
& (Join-Path $PSScriptRoot 'Fetch-Gutenberg.ps1')

Write-Host "`n=== Fetching & Verifying Misaki Lexicon ==="
& (Join-Path $PSScriptRoot 'Fetch-Misaki.ps1')

Write-Host "`nAll input sources successfully fetched and verified against pinned SHA-256 manifests."
