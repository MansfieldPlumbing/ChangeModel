[CmdletBinding()]
param(
    [string] $Js2psRoot = $env:JS2PS_ROOT,
    [string] $Evidence = (Join-Path $PSScriptRoot '../evidence/js2ps-ogl-lexical.psd1'),
    [string] $OutDir = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Build\PSPerception\gate7' } else { Join-Path $PSScriptRoot '../build/gate7' })
)

# Gate 7: a representational delta learned from real JS2PS evidence survives process death.
# Two separate pwsh processes: one learns and writes the .psd1 mutation journal, the other has never
# seen the learning and must rebuild the same state from S0 plus the journal, then roll back
# to S0 exactly. The journal is the only state that crosses processes; the replay process runs
# every check on live objects and reports through its exit code.
# JS2PS_ROOT must be a JS2PS checkout at the commit the evidence names.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Js2psRoot) {
    Write-Host 'GATE7_STATE_RECONSTRUCTION=NOT RUN (set JS2PS_ROOT to a JS2PS checkout at the pinned commit)'
    return
}
Write-Host '--- Gate 7: State Reconstruction After Process Death ---'

$null = New-Item -ItemType Directory -Force -Path $OutDir
Get-ChildItem -LiteralPath $OutDir -File | Remove-Item
$pwsh = (Get-Process -Id $PID).Path
$phase = Join-Path $PSScriptRoot 'Gate7-Phase.ps1'
function Invoke-Phase {
    param([string] $Name, [string[]] $Extra = @())
    $argList = @('-NoProfile', '-File', ('"{0}"' -f $phase), '-Phase', $Name,
        '-Evidence', ('"{0}"' -f $Evidence), '-Js2psRoot', ('"{0}"' -f $Js2psRoot), '-OutDir', ('"{0}"' -f $OutDir)) + $Extra
    Start-Process -FilePath $pwsh -ArgumentList $argList -NoNewWindow -Wait -PassThru
}
$learn = Invoke-Phase 'Learn'
if ($learn.ExitCode -ne 0) { throw "Phase Learn exited with $($learn.ExitCode)." }
$replay = Invoke-Phase 'Replay' @('-LearnProcessId', [string] $learn.Id, '-ParentProcessId', [string] $PID)
if ($replay.ExitCode -eq 2) { throw 'GATE7_STATE_RECONSTRUCTION=FAIL' }
if ($replay.ExitCode -ne 0) { throw "Phase Replay exited with $($replay.ExitCode)." }
Write-Host 'GATE7_STATE_RECONSTRUCTION=PASS'
