$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\src\Representation.ps1
. $PSScriptRoot\..\src\Experience.ps1
. $PSScriptRoot\..\src\Prediction.ps1
. $PSScriptRoot\..\src\Search.ps1
. $PSScriptRoot\..\src\Proposal.ps1
. $PSScriptRoot\..\src\SmaDataset.ps1

# 1. Generate authentic experience dataset from SMA compiler lowering & behavior probes
$trainingDataset = New-SmaExperienceDataset
if ($trainingDataset.Count -lt 4) {
    throw "Dataset generation failed: Insufficient records ($($trainingDataset.Count))."
}

# 2. Evaluate under surface syntax representation R1 = { DeltaSource }
$r1 = [Representation]::new([string[]]@('DeltaSource'))
$measureR1 = Measure-Experience -History $trainingDataset -Rep $r1 -RepVersion "R1_SurfaceSource"

if ($measureR1.Contradictions -le 0) {
    throw "Gate 4 Precondition Failure: Expected contradictions under surface syntax representation R1, got $($measureR1.Contradictions)."
}

$residualsR1 = Get-Residuals -MeasureResult $measureR1
if (-not $residualsR1.HasStructuralResidual) {
    throw "Gate 4 Precondition Failure: Expected structural residual under R1."
}

# 3. Perform representation revision search across authentic measured SMA dimensions
$allMeasuredDimensions = @('DeltaSource', 'DeltaTokens', 'DeltaAstExtent', 'DeltaAstStructure', 'DeltaExpression')

$searchResult = Invoke-RepresentationSearch `
    -History $trainingDataset `
    -AllFeatures $allMeasuredDimensions

if (-not $searchResult.ReachedOracle) {
    throw "Representation search failed to reach exhaustive oracle optimum on authentic SMA artifacts."
}

$finalRep = $searchResult.FinalRep
$finalMeasure = $searchResult.FinalMeasure

if ($finalMeasure.Contradictions -ne 0) {
    throw "Expected 0 contradictions under revised representation, got $($finalMeasure.Contradictions)."
}

if (-not ($finalRep.Features -contains 'DeltaExpression')) {
    throw "Revised representation failed to discover necessary authentic SMA lowering dimension 'DeltaExpression'."
}

# 4. Prove minimal complexity among equally predictive representations
if ($finalRep.Features.Length -gt 1) {
    # Check if single feature DeltaExpression alone was sufficient
    $singleExprRep = [Representation]::new([string[]]@('DeltaExpression'))
    $singleMeasure = Measure-Experience -History $trainingDataset -Rep $singleExprRep -RepVersion "R_SingleExpr"
    if ($singleMeasure.Contradictions -eq 0 -and $finalRep.Features.Length -gt 1) {
        throw "Complexity was not minimal: Selected $($finalRep.Features.Length) features when 1 was sufficient."
    }
}

# 5. Held-out validation on unseen authentic SMA transformations
$heldOutPairs = @(
    [pscustomobject]@{
        Name = 'HeldOut_Preserving_CommutativeAddition'
        SourceA = 'param([double]$a, [double]$b) $a + $b'
        SourceB = 'param([double]$a, [double]$b) $b + $a'
    },
    [pscustomobject]@{
        Name = 'HeldOut_Breaking_DivisionVersusAddition'
        SourceA = 'param([double]$a, [double]$b) $a + $b'
        SourceB = 'param([double]$a, [double]$b) $a / $b'
    }
)

$heldOutDataset = New-SmaExperienceDataset -SpecimenPairs $heldOutPairs
$heldOutMeasure = Measure-Experience -History $heldOutDataset -Rep $finalRep -RepVersion "R2_HeldOut"

if ($heldOutMeasure.Contradictions -ne 0) {
    throw "Held-out validation failed: Detected contradictions under revised representation R2."
}

Write-Host "GATE4_SMA_NOT_EVEN_WRONG=PASS"
