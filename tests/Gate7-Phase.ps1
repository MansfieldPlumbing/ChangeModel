[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Learn', 'Replay')][string] $Phase,
    [Parameter(Mandatory)][string] $Evidence,
    [Parameter(Mandatory)][string] $Js2psRoot,
    [Parameter(Mandatory)][string] $OutDir
)

# One phase of Gate 7, run in its own pwsh process by Gate7-WorldReconstruction.ps1.
# Learn:  observe real JS2PS evidence under pristine SMA (S0), learn a representational
#         delta with ChangeModel's existing search, materialize it into SMA, write the
#         world tape and the S0/S1 receipt, then exit.
# Replay: in a fresh process, recreate S0, replay the tape to S1', compare every
#         fingerprint with the receipt, roll back through the exact inverses, require S0.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../src/Representation.ps1')
. (Join-Path $PSScriptRoot '../src/Experience.ps1')
. (Join-Path $PSScriptRoot '../src/Prediction.ps1')
. (Join-Path $PSScriptRoot '../src/Search.ps1')
. (Join-Path $PSScriptRoot '../src/WorldTape.ps1')

$nativeFeatures = @('SmaTokenKind', 'SmaKeywordFlag', 'SmaCommandNameFlag')
$candidateFeatures = $nativeFeatures + @('Text')
$tapePath = Join-Path $OutDir 'world-tape.psd1'
$learnReceiptPath = Join-Path $OutDir 'learn-receipt.json'
$replayReceiptPath = Join-Path $OutDir 'replay-receipt.json'

$evidenceData = Get-Content -Raw -LiteralPath $Evidence | ConvertFrom-Json
$evidenceSha = (Get-FileHash -LiteralPath $Evidence -Algorithm SHA256).Hash
$js2psHead = (& git -C $Js2psRoot rev-parse HEAD).Trim()
if ($js2psHead -cne $evidenceData.Provenance.JS2PSCommit) {
    throw "JS2PS checkout is $js2psHead; the evidence was produced at $($evidenceData.Provenance.JS2PSCommit)."
}
$sensor = Join-Path $Js2psRoot 'tools/Observe-SmaPerception.ps1'
$trainPaths = @($evidenceData.Train | ForEach-Object Path)
$allPaths = $trainPaths + @($evidenceData.HeldOut | ForEach-Object Path)
$outcomes = $evidenceData.OracleOutcomes

function Get-Observation { @(& $sensor -Path $allPaths -Root $Js2psRoot) }
function Get-NativeMeasure {
    param([object[]] $Observations, [string[]] $Paths)
    $records = @(New-LexicalExperience -Observations @($Observations | Where-Object { $_.Path -in $Paths }) -Outcomes $outcomes)
    $m = Measure-Experience -History $records -Rep ([Representation]::new($nativeFeatures)) -RepVersion 'Native'
    [ordered]@{ Units = $records.Count; Contradictions = $m.Contradictions; ContradictoryKeys = $m.ContradictoryKeys.Count }
}
function Get-LinqAvailability {
    param([object[]] $Observations)
    # SMA lowers a unit to LINQ only after admitting it without parse errors.
    foreach ($obs in $Observations) { $obs.Path + '=' + $(if (@($obs.ErrorIds).Count) { 'unavailable:parse-errors:' + @($obs.ErrorIds).Count } else { 'admitted' }) }
}

$context = New-WorldContext
if (@(Get-DynamicKeywordState).Count -ne 0) { throw 'S0 is not pristine: DynamicKeywords are registered on this thread.' }
$s0Obs = Get-Observation
$s0 = [ordered]@{
    World = Get-WorldFingerprint -Context $context -Observations $s0Obs -Evidence $evidenceData
    Perception = Get-PerceptionFingerprint $s0Obs
    Linq = @(Get-LinqAvailability $s0Obs)
    NativeTrain = Get-NativeMeasure $s0Obs $trainPaths
    NativeHeldOut = Get-NativeMeasure $s0Obs @($evidenceData.HeldOut | ForEach-Object Path)
}
$fingerprint = { Get-WorldFingerprint -Context $context -Observations (Get-Observation) -Evidence $evidenceData }

if ($Phase -eq 'Learn') {
    # The live sensor must reproduce the recorded evidence before anything is learned from it.
    if ((Get-PerceptionFingerprint $s0Obs) -cne (Get-PerceptionFingerprint @($evidenceData.Train + $evidenceData.HeldOut))) {
        throw 'The live SMA perception of S0 does not reproduce the recorded JS2PS evidence.'
    }
    $history = @(New-LexicalExperience -Observations @($s0Obs | Where-Object { $_.Path -in $trainPaths }) -Outcomes $outcomes)

    # Not even wrong: no subset of SMA's native percepts separates the oracle outcomes.
    $native = Invoke-RepresentationSearch -History $history -AllFeatures $nativeFeatures
    if (-not $native.ReachedOracle -or $native.OracleBestMeasure.Contradictions -eq 0) {
        throw 'Precondition failed: SMA native percepts already separate the outcomes (not a structural residual).'
    }
    # Representation growth: search the candidate percepts for a zero-contradiction representation.
    $grown = Invoke-RepresentationSearch -History $history -AllFeatures $candidateFeatures
    if (-not $grown.ReachedOracle -or $grown.FinalMeasure.Contradictions -ne 0) { throw 'Representation search found no zero-contradiction representation.' }

    # The learned distinction: words the oracle marks reserved that SMA's native percepts did not.
    $words = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($r in $history) { if ($r.ActualDelta -eq 1 -and $r.CanonicalBefore.SmaKeywordFlag -eq 0) { [void] $words.Add($r.CanonicalBefore.Text) } }
    $defaults = [System.Management.Automation.Language.DynamicKeyword]::new()

    $steps = [Collections.Generic.List[object]]::new()
    $steps.Add([ordered]@{ Op = 'Observe'; EvidenceSha256 = $evidenceSha; JS2PSCommit = $js2psHead; PerceptionSha256 = $s0.Perception })
    foreach ($f in $grown.FinalRep.Features) { $steps.Add([ordered]@{ Op = 'AddPercept'; Name = $f }) }
    $steps.Add([ordered]@{ Op = 'Compose'; Realization = 'DynamicKeyword'; Words = [string[]] @($words); NameMode = [string] $defaults.NameMode; BodyMode = [string] $defaults.BodyMode; DirectCall = [bool] $defaults.DirectCall })
    $tape = [ordered]@{
        Schema = 1
        Base = [ordered]@{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            PowerShellSourceCommit = '149ab5cd6cad34869177f86ef9a3da8414f85dc6'
            SmaModuleVersionId = [System.Management.Automation.PSObject].Assembly.ManifestModule.ModuleVersionId.ToString()
            ChangeModelBase = '0b1bcafd88b627dcf2f33c7ecf1e6cfdf744451b'
            WorldSha256 = $s0.World
        }
        Oracle = [ordered]@{ Id = $evidenceData.Oracle.Id; Authority = $evidenceData.Oracle.Authority; AuthorityVersion = $evidenceData.Oracle.AuthorityVersion; OutcomesSha256 = Get-OracleFingerprint $evidenceData }
        Steps = $steps
    }
    Invoke-WorldTape -Tape $tape -Context $context -Direction Forward -Fingerprint $fingerprint
    $s1Obs = Get-Observation
    $s1World = Get-WorldFingerprint -Context $context -Observations $s1Obs -Evidence $evidenceData
    $tape.Steps.Add([ordered]@{
        Op = 'Accept'; WorldSha256 = $s1World
        Evidence = [ordered]@{
            NativeContradictionsS0 = $native.OracleBestMeasure.Contradictions
            GrownContradictions = $grown.FinalMeasure.Contradictions
            GrownFeatures = [string[]] @($grown.FinalRep.Features)
            SearchEvaluations = $grown.Evaluations
            ExhaustiveEvaluations = $grown.ExhaustiveEvaluations
        }
    })
    Write-WorldTape -Tape $tape -Path $tapePath

    [ordered]@{
        Phase = 'Learn'; ProcessId = $PID
        TapeSha256 = (Get-FileHash -LiteralPath $tapePath -Algorithm SHA256).Hash
        S0 = $s0
        S1 = [ordered]@{
            World = $s1World
            Perception = Get-PerceptionFingerprint $s1Obs
            Linq = @(Get-LinqAvailability $s1Obs)
            NativeTrain = Get-NativeMeasure $s1Obs $trainPaths
            NativeHeldOut = Get-NativeMeasure $s1Obs @($evidenceData.HeldOut | ForEach-Object Path)
            DynamicKeywords = @(Get-DynamicKeywordState)
        }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $learnReceiptPath -Encoding utf8NoBOM
    exit 0
}

# Replay, in a process that has never seen the learning.
$tape = Read-WorldTape -Path $tapePath
if ($tape.Base.WorldSha256 -cne $s0.World) { throw "Fresh S0 is $($s0.World); the tape's base is $($tape.Base.WorldSha256)." }
Invoke-WorldTape -Tape $tape -Context $context -Direction Forward -Fingerprint $fingerprint
$s1Obs = Get-Observation
$s1 = [ordered]@{
    World = Get-WorldFingerprint -Context $context -Observations $s1Obs -Evidence $evidenceData
    Perception = Get-PerceptionFingerprint $s1Obs
    Linq = @(Get-LinqAvailability $s1Obs)
    NativeTrain = Get-NativeMeasure $s1Obs $trainPaths
    NativeHeldOut = Get-NativeMeasure $s1Obs @($evidenceData.HeldOut | ForEach-Object Path)
    DynamicKeywords = @(Get-DynamicKeywordState)
}
Invoke-WorldTape -Tape $tape -Context $context -Direction Inverse
$restoredObs = Get-Observation
[ordered]@{
    Phase = 'Replay'; ProcessId = $PID
    TapeSha256 = (Get-FileHash -LiteralPath $tapePath -Algorithm SHA256).Hash
    S0 = $s0
    S1 = $s1
    Restored = [ordered]@{
        World = Get-WorldFingerprint -Context $context -Observations $restoredObs -Evidence $evidenceData
        Perception = Get-PerceptionFingerprint $restoredObs
        DynamicKeywords = @(Get-DynamicKeywordState)
    }
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $replayReceiptPath -Encoding utf8NoBOM
exit 0
