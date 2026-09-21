$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\src\Representation.ps1
. $PSScriptRoot\..\src\Experience.ps1
. $PSScriptRoot\..\src\Prediction.ps1
. $PSScriptRoot\..\src\Search.ps1
. $PSScriptRoot\..\src\Proposal.ps1
. $PSScriptRoot\..\src\ExpressionFeatures.ps1
. $PSScriptRoot\..\src\SmaContentfulDataset.ps1

Write-Host "--- Gate 5: Contentful SMA Delta ---"

# 1. Generate authentic SMA training and held-out datasets with canonical evidence
$trainingDataset = New-SmaContentfulDataset
$heldOutDataset  = New-SmaContentfulDataset -SpecimenPairs (Get-SmaContentfulHeldOutPairs)

# Verify canonical evidence retention on every record
foreach ($rec in $trainingDataset) {
    if (-not $rec.CanonicalBefore.ExpressionBeforeFingerprint -or -not $rec.CanonicalBefore.ExpressionAfterFingerprint) {
        throw "Canonical evidence violation: Missing expression fingerprints on specimen '$($rec.SpecimenName)'."
    }
}

# 2. Verify Quadrants across training corpus
$q1Count = @($trainingDataset | Where-Object { $_.CanonicalBefore.CoarseDeltaExpression -eq 0 -and $_.ActualDelta -eq 0 }).Count
$q2Count = @($trainingDataset | Where-Object { $_.CanonicalBefore.CoarseDeltaExpression -eq 1 -and $_.ActualDelta -eq 0 }).Count
$q3Count = @($trainingDataset | Where-Object { $_.CanonicalBefore.CoarseDeltaExpression -eq 1 -and $_.ActualDelta -eq 1 }).Count
$q4Count = @($trainingDataset | Where-Object { $_.CanonicalBefore.CoarseDeltaExpression -eq 0 -and $_.ActualDelta -eq 1 }).Count

Write-Host "Quadrant Distribution:"
Write-Host "  Q1 (Expr unchanged / Beh unchanged): $q1Count"
Write-Host "  Q2 (Expr changed   / Beh unchanged): $q2Count"
Write-Host "  Q3 (Expr changed   / Beh changed)  : $q3Count"
Write-Host "  Q4 (Expr unchanged / Beh changed)  : $q4Count (Measured fact: 0 for pure closed SMA lowering)"

# Condition 7: Multiple behavior-preserving and multiple behavior-changing specimens both have DeltaExpression = 1
if ($q2Count -lt 2 -or $q3Count -lt 2) {
    throw "Condition 7 Failure: Must have multiple behavior-preserving (found $q2Count >= 2) and multiple behavior-changing (found $q3Count >= 2) specimens with CoarseDeltaExpression=1."
}

# 3. Condition 1: Evaluate impoverished representation R0 = { CoarseDeltaExpression }
$r0 = [Representation]::new([string[]]@('CoarseDeltaExpression'))
$measureR0 = Measure-Experience -History $trainingDataset -Rep $r0 -RepVersion "R0_CoarseDelta"

if ($measureR0.Contradictions -le 0) {
    throw "Condition 1 Failure: Expected structural contradiction under coarse R0, got $($measureR0.Contradictions)."
}

$residualsR0 = Get-Residuals -MeasureResult $measureR0
if (-not $residualsR0.HasStructuralResidual) {
    throw "Condition 1 Failure: Expected structural residual under R0."
}
Write-Host "Confirmed R0 Contradictions: $($measureR0.Contradictions) (Structural Residual Present)"

# 4. Condition 2, 3, 4, 5: Representation search over contentful SMA delta features
$candidateFeatures = @(
    'CoarseDeltaExpression',
    'BinderOperationChanged',
    'ConstantValueChanged',
    'OperandOrderChanged',
    'NodeTypeChanged',
    'CallTargetChanged'
)

$searchResult = Invoke-RepresentationSearch `
    -History $trainingDataset `
    -AllFeatures $candidateFeatures

$winningRep = $searchResult.FinalRep
$winningMeasure = $searchResult.FinalMeasure

Write-Host "Selected Features: $($winningRep.Features -join ', ')"
Write-Host "Winning Measure Contradictions: $($winningMeasure.Contradictions)"
Write-Host "Winning Measure Complexity    : $($winningMeasure.RepresentationComplexity)"
Write-Host "Reached Exhaustive Oracle     : $($searchResult.ReachedOracle)"

# Condition 2: Search selects richer contentful representation (not just coarse delta)
if ($winningRep.Features -contains 'CoarseDeltaExpression' -and $winningRep.Features.Length -eq 1) {
    throw "Condition 2 Failure: Search failed to select a richer contentful representation."
}

# Condition 3: Contradictions reduced to zero on training data
if ($winningMeasure.Contradictions -ne 0) {
    throw "Condition 3 Failure: Expected 0 contradictions under winning representation, got $($winningMeasure.Contradictions)."
}

# Condition 4: Reaches exhaustive optimum over the bounded feature set
if (-not $searchResult.ReachedOracle) {
    throw "Condition 4 Failure: Greedy search result did not reach exhaustive oracle optimum."
}

# Condition 5: Minimal complexity among equally predictive representations
for ($mask = 1; $mask -lt (1 -shl $candidateFeatures.Length); $mask++) {
    $subFeatures = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $candidateFeatures.Length; $i++) {
        if ($mask -band (1 -shl $i)) { $subFeatures.Add($candidateFeatures[$i]) }
    }
    if ($subFeatures.Count -lt $winningRep.Features.Length) {
        $trialRep = [Representation]::new($subFeatures.ToArray())
        $trialMeasure = Measure-Experience -History $trainingDataset -Rep $trialRep -RepVersion "Trial_Check"
        if ($trialMeasure.Contradictions -eq 0) {
            throw "Condition 5 Failure: Found smaller zero-contradiction representation: $($subFeatures -join ', ')"
        }
    }
}
Write-Host "Confirmed Minimal Complexity: $($winningRep.Features.Length) is minimal among all zero-contradiction representations."

# 5. Condition 6: Held-out behavioral predictions under explicitly reported support
# Train predictor on training set under winning representation
$learnedTable = @{}
foreach ($rec in $trainingDataset) {
    $state = $winningRep.GetRepresentedState($rec.CanonicalBefore)
    $key = Get-ContradictionKey -RepresentedBefore $state -Action $rec.Action
    $learnedTable[$key] = $rec.ActualDelta
}

$heldOutCount = $heldOutDataset.Count
$heldOutCorrect = 0
$heldOutError = 0
$heldOutUnseenKeys = 0

foreach ($rec in $heldOutDataset) {
    $state = $winningRep.GetRepresentedState($rec.CanonicalBefore)
    $key = Get-ContradictionKey -RepresentedBefore $state -Action $rec.Action

    if (-not $learnedTable.ContainsKey($key)) {
        $heldOutUnseenKeys++
        Write-Host "  UNSUPPORTED/UNSEEN KEY: $key for specimen '$($rec.SpecimenName)'"
    } else {
        $predicted = $learnedTable[$key]
        if ($predicted -eq $rec.ActualDelta) {
            $heldOutCorrect++
        } else {
            $heldOutError++
        }
    }
}

Write-Host "Held-Out Metrics:"
Write-Host "  HeldOutCount     : $heldOutCount"
Write-Host "  HeldOutCorrect   : $heldOutCorrect"
Write-Host "  HeldOutError     : $heldOutError"
Write-Host "  HeldOutUnseenKeys: $heldOutUnseenKeys"

if ($heldOutUnseenKeys -ne 0) {
    throw "Condition 6 Failure: Held-out evaluation encountered unsupported/unseen representation keys ($heldOutUnseenKeys)."
}

if ($heldOutError -ne 0 -or $heldOutCorrect -ne $heldOutCount) {
    throw "Condition 6 Failure: Held-out predictions were incorrect ($heldOutError errors out of $heldOutCount)."
}

Write-Host "GATE5_CONTENTFUL_DELTA=PASS"
