[CmdletBinding()]
param(
    [string] $Js2psRoot = $env:JS2PS_ROOT,
    [string] $Evidence = (Join-Path $PSScriptRoot '../evidence/js2ps-ogl-lexical.json'),
    [string] $OutDir = (Join-Path $PSScriptRoot '../build/gate7')
)

# Gate 7: a representational delta learned from real JS2PS evidence survives process death.
# Two separate pwsh processes: one learns and writes the world tape, the other has never
# seen the learning and must rebuild the same world from S0 plus the tape, then roll back
# to S0 exactly. JS2PS_ROOT must be a JS2PS checkout at the commit the evidence names.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Js2psRoot) { throw 'Set JS2PS_ROOT (or -Js2psRoot) to a JS2PS checkout at the pinned commit.' }
Write-Host '--- Gate 7: World Reconstruction After Process Death ---'

$null = New-Item -ItemType Directory -Force -Path $OutDir
Get-ChildItem -LiteralPath $OutDir -File | Remove-Item
$pwsh = (Get-Process -Id $PID).Path
$phase = Join-Path $PSScriptRoot 'Gate7-Phase.ps1'
foreach ($p in 'Learn', 'Replay') {
    & $pwsh -NoProfile -File $phase -Phase $p -Evidence $Evidence -Js2psRoot $Js2psRoot -OutDir $OutDir
    if ($LASTEXITCODE -ne 0) { throw "Phase $p exited with $LASTEXITCODE." }
}
$learn = Get-Content -Raw (Join-Path $OutDir 'learn-receipt.json') | ConvertFrom-Json
$replay = Get-Content -Raw (Join-Path $OutDir 'replay-receipt.json') | ConvertFrom-Json

$checks = [ordered]@{
    'separate processes' = $learn.ProcessId -ne $replay.ProcessId -and $learn.ProcessId -ne $PID -and $replay.ProcessId -ne $PID
    'same tape bytes' = $learn.TapeSha256 -ceq $replay.TapeSha256
    'fresh S0 equals learned S0' = $replay.S0.World -ceq $learn.S0.World
    'S1 world reconstructed' = $replay.S1.World -ceq $learn.S1.World
    'S1 perception reconstructed' = $replay.S1.Perception -ceq $learn.S1.Perception
    'S1 LINQ availability reconstructed' = ($replay.S1.Linq -join ';') -ceq ($learn.S1.Linq -join ';')
    'SMA perception changed' = $learn.S1.Perception -cne $learn.S0.Perception
    'rollback restores S0 world' = $replay.Restored.World -ceq $learn.S0.World
    'rollback restores S0 perception' = $replay.Restored.Perception -ceq $learn.S0.Perception
    'rollback leaves no DynamicKeywords' = @($replay.Restored.DynamicKeywords).Count -eq 0
}
foreach ($c in $checks.GetEnumerator()) { '  {0,-38} {1}' -f $c.Key, $(if ($c.Value) { 'PASS' } else { 'FAIL' }) | Write-Host }
Write-Host ('  S0 world {0}' -f $learn.S0.World)
Write-Host ('  S1 world {0}' -f $learn.S1.World)
Write-Host ('  tape     {0}' -f $learn.TapeSha256)
Write-Host ('  native contradictions, train:    S0 {0} -> S1 {1}' -f $learn.S0.NativeTrain.Contradictions, $learn.S1.NativeTrain.Contradictions)
Write-Host ('  native contradictions, held-out: S0 {0} -> S1 {1}' -f $learn.S0.NativeHeldOut.Contradictions, $learn.S1.NativeHeldOut.Contradictions)
if (@($checks.Values | Where-Object { -not $_ }).Count) { throw 'GATE7_WORLD_RECONSTRUCTION=FAIL' }
Write-Host 'GATE7_WORLD_RECONSTRUCTION=PASS'
