[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "--- Gate 8: Counterexample-Guided Refine Loop (mechanics only) ---"

. (Join-Path $PSScriptRoot '../src/LinearState.ps1')
. (Join-Path $PSScriptRoot '../src/Representation.ps1')
. (Join-Path $PSScriptRoot '../src/ObservationRecord.ps1')
. (Join-Path $PSScriptRoot '../src/Prediction.ps1')
. (Join-Path $PSScriptRoot '../src/Search.ps1')
. (Join-Path $PSScriptRoot '../src/Proposal.ps1')
. (Join-Path $PSScriptRoot '../src/Store.ps1')
. (Join-Path $PSScriptRoot '../src/Refine.ps1')

# Small synthetic case labeled "mechanics only"
# State features:
#   X: Position
#   Direction: Causal distinction separating deltas
#   ConstantTag: Invariant attribute across colliding observations (to verify candidate pruning)
$history = [System.Collections.Generic.List[object]]::new()

$s1 = [pscustomobject]@{ X = 5; Direction = 1; ConstantTag = 'Static' }
$history.Add([pscustomobject]@{
    SpecimenName = 'synthetic_case_1'
    CanonicalBefore = $s1
    Action = 'Step'
    ActualDelta = 1
})

$s2 = [pscustomobject]@{ X = 5; Direction = -1; ConstantTag = 'Static' }
$history.Add([pscustomobject]@{
    SpecimenName = 'synthetic_case_2'
    CanonicalBefore = $s2
    Action = 'Step'
    ActualDelta = -1
})

$s3 = [pscustomobject]@{ X = 6; Direction = 1; ConstantTag = 'Static' }
$history.Add([pscustomobject]@{
    SpecimenName = 'synthetic_case_3'
    CanonicalBefore = $s3
    Action = 'Step'
    ActualDelta = 1
})

# Initial crippled representation R0 = { X }
$r0 = [Representation]::new([string[]]@('X'))
$initialMeasure = Measure-Representation -History $history -Rep $r0 -RepVersion "R0"
if ($initialMeasure.Contradictions -eq 0) {
    throw "Precondition failure: Expected contradictions under R0."
}

# 1. Exhaustive search as reference for small case
$allFeatures = @('X', 'Direction', 'ConstantTag')
$exhaustiveResult = Invoke-RepresentationSearch -History $history -AllFeatures $allFeatures
if (-not $exhaustiveResult.ReachedExhaustiveOptimum) {
    throw "Exhaustive search failed to reach optimum."
}

# 2. Refine loop
$refineResult = Invoke-PerceptRefine -Experience $history -InitialRepresentation $r0 -NeutralBudget 2 -MaxIterations 10

# Invariant 1: Loop reaches the same result as exhaustive search
if ($refineResult.FinalMeasure.Contradictions -ne $exhaustiveResult.FinalMeasure.Contradictions) {
    throw "Refine loop contradictions ($($refineResult.FinalMeasure.Contradictions)) did not match exhaustive ($($exhaustiveResult.FinalMeasure.Contradictions))."
}
if ($refineResult.FinalMeasure.PredictionError -ne $exhaustiveResult.FinalMeasure.PredictionError) {
    throw "Refine loop prediction error ($($refineResult.FinalMeasure.PredictionError)) did not match exhaustive ($($exhaustiveResult.FinalMeasure.PredictionError))."
}

# Invariant 2: Percept candidates came only from attributes on which colliding observations differ
$store = $refineResult.Store
$keptPercepts = $store.GetKeptPercepts()
if ('Direction' -notin $keptPercepts -and 'Direction' -notin $refineResult.FinalRepresentation.Features) {
    throw "Refine loop did not discover 'Direction'."
}
if ('ConstantTag' -in $keptPercepts -or 'ConstantTag' -in $refineResult.FinalRepresentation.Features) {
    throw "Refine loop proposed non-differing attribute 'ConstantTag'."
}

# Invariant 3: Store provenance graph records rejected moves too
$spuriousProposal = [RepresentationMutation]::new('AddFeature', @('SpuriousFeature'))
$rejectedNode = $store.RecordTransition(
    $store.Current,
    $refineResult.FinalRepresentation,
    @('SpuriousFeature'),
    @('X=5|Action=Step'),
    $refineResult.FinalMeasure,
    $refineResult.FinalMeasure,
    'rejected',
    $spuriousProposal
)
$rejectedTransitions = $store.GetRejectedTransitions()
if ($rejectedTransitions.Length -eq 0) {
    throw "Store failed to record rejected transition."
}
if ($rejectedTransitions[0].Outcome -cne 'rejected') {
    throw "Rejected transition outcome is '$($rejectedTransitions[0].Outcome)', expected 'rejected'."
}

# Invariant 4: Replaying the store from scratch reproduces the same final state (skipping rejected moves)
$replayedRep = $store.ReplayFromScratch()
$expectedFeatures = [string[]]@($refineResult.FinalRepresentation.Features | Sort-Object)
$actualFeatures = [string[]]@($replayedRep.Features | Sort-Object)

if (($expectedFeatures -join ',') -cne ($actualFeatures -join ',')) {
    throw "Replaying store from scratch yielded [$($actualFeatures -join ',')], expected [$($expectedFeatures -join ',')]."
}

$replayedMeasure = Measure-Representation -History $history -Rep $replayedRep -RepVersion "V_Replay"
if ($replayedMeasure.Contradictions -ne $refineResult.FinalMeasure.Contradictions) {
    throw "Replayed contradictions ($($replayedMeasure.Contradictions)) do not match final ($($refineResult.FinalMeasure.Contradictions))."
}
if ($replayedMeasure.PredictionError -ne $refineResult.FinalMeasure.PredictionError) {
    throw "Replayed prediction error ($($replayedMeasure.PredictionError)) do not match final ($($refineResult.FinalMeasure.PredictionError))."
}

# Invariant 5: Provenance graph recorded live objects without JSON
if ($store.AllNodes.Count -eq 0) {
    throw "Store recorded zero nodes."
}
if ($store.Receipts.Count -eq 0) {
    throw "Store recorded zero receipts."
}

Write-Host "  Synthetic Case: mechanics only"
Write-Host "  Initial Contradictions: $($initialMeasure.Contradictions)"
Write-Host "  Exhaustive Optimum Contradictions: $($exhaustiveResult.FinalMeasure.Contradictions)"
Write-Host "  Refine Loop Contradictions: $($refineResult.FinalMeasure.Contradictions)"
Write-Host "  Store Replayed Features: $($actualFeatures -join ', ')"
Write-Host "  Store Provenance Nodes: $($store.AllNodes.Count) (Kept: $(@($store.AllNodes | Where-Object { $_.Outcome -eq 'kept' }).Count), Rejected: $($rejectedTransitions.Length))"
Write-Host "GATE8_REFINE_LOOP=PASS"
