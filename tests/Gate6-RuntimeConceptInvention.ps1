$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\src\Representation.ps1
. $PSScriptRoot\..\src\Experience.ps1
. $PSScriptRoot\..\src\Prediction.ps1
. $PSScriptRoot\..\src\Search.ps1
. $PSScriptRoot\..\src\Proposal.ps1
. $PSScriptRoot\..\src\ExpressionFeatures.ps1
. $PSScriptRoot\..\src\SmaContentfulDataset.ps1
. $PSScriptRoot\..\src\ConceptSynthesis.ps1

Write-Host "--- Gate 6: Runtime Concept Invention ---"

# Step 1: Extract atomic delta features from authentic SMA lowering pairs
$trainingDataset = New-SmaContentfulDataset
$heldOutDataset  = New-SmaContentfulDataset -SpecimenPairs (Get-SmaContentfulHeldOutPairs)

$atomicFeatures = @(
    'BinderOperationChanged',
    'ConstantValueChanged',
    'OperandOrderChanged',
    'NodeTypeChanged',
    'CallTargetChanged'
)

# Verify canonical evidence retention on every record
foreach ($rec in $trainingDataset) {
    if (-not $rec.CanonicalBefore.ExpressionBeforeFingerprint -or -not $rec.CanonicalBefore.ExpressionAfterFingerprint) {
        throw "Canonical evidence violation: Missing expression fingerprints on '$($rec.SpecimenName)'."
    }
}

# Step 2: Enumerate candidate concepts across atomic features
$candidateConcepts = Get-CandidateConcepts -AtomicFeatures $atomicFeatures
Write-Host "Candidate concepts generated: $($candidateConcepts.Length)"

# Baseline test: Prove any single atomic feature alone fails to resolve contradictions
$atomsWithContradictions = 0
foreach ($atom in $atomicFeatures) {
    $atomConcept = [Concept]::new('Atom', $atom)
    $m = Measure-ConceptSufficiency -History $trainingDataset -Concept $atomConcept
    if ($m.Contradictions -gt 0) { $atomsWithContradictions++ }
}
if ($atomsWithContradictions -ne $atomicFeatures.Length) {
    throw "Precondition failure: Expected all individual atomic features to produce contradictions."
}
Write-Host "Confirmed all $($atomicFeatures.Length) individual atomic features suffer from structural residuals."

# Step 3: Search and score candidate concepts against execution evidence
$searchResult = Invoke-ConceptSearch -History $trainingDataset -CandidateConcepts $candidateConcepts -AtomicFeatures $atomicFeatures
$winningConcept = $searchResult.WinningConcept
$winningMeasure = $searchResult.WinningMeasure

Write-Host "Winning Concept: $($winningConcept.Name)"
Write-Host "  Contradictions : $($winningMeasure.Contradictions)"
Write-Host "  PredictionError: $($winningMeasure.PredictionError)"
Write-Host "  Complexity     : $($winningMeasure.Complexity)"
Write-Host "  Reached Oracle : $($searchResult.ReachedOracle)"

# Criterion 1: The winning concept was constructed from lower-level atomic features
if ($winningConcept.Kind -eq 'Atom') {
    throw "Criterion 1 Failure: Winning concept is a primitive atom, not a constructed concept."
}

# Criterion 2: It was not present in the supplied feature vocabulary
if ($atomicFeatures -contains $winningConcept.Name) {
    throw "Criterion 2 Failure: Winning concept was already present in the input feature vocabulary."
}

# Criterion 3: The concept improves predictive sufficiency over the original representation
if ($winningMeasure.Contradictions -ne 0) {
    throw "Criterion 3 Failure: Winning concept failed to reduce contradictions to zero ($($winningMeasure.Contradictions))."
}

# Criterion 4: Its selection is verified against a bounded exhaustive oracle
if (-not $searchResult.ReachedOracle) {
    throw "Criterion 4 Failure: Concept selection did not match exhaustive oracle optimum."
}
if ($searchResult.ExhaustiveEvaluations -ne $candidateConcepts.Length) {
    throw "Criterion 4 Failure: Oracle enumerated $($searchResult.ExhaustiveEvaluations) concepts; the candidate generator produced $($candidateConcepts.Length)."
}
foreach ($evaluation in $searchResult.AllEvaluations) {
    $reference = $searchResult.OracleScores[$evaluation.Concept.Name]
    if ($null -eq $reference -or
        $reference.Contradictions -ne $evaluation.Score.Contradictions -or
        $reference.PredictionError -ne $evaluation.Score.PredictionError -or
        $reference.Complexity -ne $evaluation.Score.Complexity) {
        throw "Criterion 4 Failure: Search and oracle disagree on '$($evaluation.Concept.Name)'."
    }
}

# Criterion 4 negative control: with every oracle-optimal concept withheld from
# the search, the oracle check must report failure.
$withheld = @($candidateConcepts | Where-Object { $_.Name -notin $searchResult.OracleOptimumNames })
if ($withheld.Length -eq $candidateConcepts.Length) {
    throw "Criterion 4 Control Failure: No candidate matched an oracle-optimal name."
}
$controlResult = Invoke-ConceptSearch -History $trainingDataset -CandidateConcepts $withheld -AtomicFeatures $atomicFeatures
if ($controlResult.ReachedOracle) {
    throw "Criterion 4 Control Failure: Oracle check passed with the optimum withheld ($($controlResult.WinningConcept.Name))."
}
Write-Host "Oracle optimum: $($searchResult.OracleOptimumNames -join ', ') over $($searchResult.ExhaustiveEvaluations) concepts"
Write-Host "Control: optimum withheld, search chose $($controlResult.WinningConcept.Name), Reached Oracle = $($controlResult.ReachedOracle)"

# Criterion 5: Held-out behavioral predictions under explicitly reported support
$learnedTable = $winningMeasure.PredictorTable
$heldOutCount = $heldOutDataset.Count
$heldOutCorrect = 0
$heldOutError = 0
$heldOutUnseenKeys = 0

foreach ($r in $heldOutDataset) {
    $conceptVal = $winningConcept.Evaluate($r.CanonicalBefore)
    $key = "Concept=$conceptVal|Action=$($r.Action)"

    if (-not $learnedTable.ContainsKey($key)) {
        $heldOutUnseenKeys++
        Write-Host "  UNSUPPORTED/UNSEEN KEY: $key on specimen '$($r.SpecimenName)'"
    } else {
        $pred = $learnedTable[$key]
        if ($pred -eq $r.ActualDelta) {
            $heldOutCorrect++
        } else {
            $heldOutError++
        }
    }
}

Write-Host "Held-Out Support Metrics:"
Write-Host "  HeldOutCount     : $heldOutCount"
Write-Host "  HeldOutCorrect   : $heldOutCorrect"
Write-Host "  HeldOutError     : $heldOutError"
Write-Host "  HeldOutUnseenKeys: $heldOutUnseenKeys"

if ($heldOutUnseenKeys -ne 0 -or $heldOutError -ne 0 -or $heldOutCorrect -ne $heldOutCount) {
    throw "Criterion 5 Failure: Held-out predictions failed support or correctness checks."
}

# Step 5, 6, 7: Materialize into live PowerShell ETS, test pre-compiled ScriptBlock, and prove reversibility
$syntheticTypeName = "ChangeModel.Concept.SemanticMutation.$([math]::Abs($winningConcept.Name.GetHashCode()))"

$deltaPreserving = $trainingDataset[0].CanonicalBefore
$deltaBreaking   = $trainingDataset[5].CanonicalBefore

# Assign synthetic PSTypeName
$deltaPreserving.PSObject.TypeNames.Insert(0, $syntheticTypeName)
$deltaBreaking.PSObject.TypeNames.Insert(0, $syntheticTypeName)

# Criterion 7: A ScriptBlock created before installation cannot use the concept before installation
$preCompiledScript = {
    param($delta)
    $delta.SemanticEffect
}

$beforePreserving = & $preCompiledScript $deltaPreserving
$beforeBreaking   = & $preCompiledScript $deltaBreaking

if ($null -ne $beforePreserving -or $null -ne $beforeBreaking) {
    throw "Criterion 7 Failure: Concept resolved before it was installed in the runtime type system."
}
Write-Host "Confirmed: Pre-compiled ScriptBlock cannot resolve SemanticEffect prior to installation."

# Criterion 6: Materialize into live PowerShell type system
Install-RuntimeConcept -TypeName $syntheticTypeName -Concept $winningConcept

# Criterion 8: The exact same ScriptBlock instance can use the concept after installation
$afterPreserving = & $preCompiledScript $deltaPreserving
$afterBreaking   = & $preCompiledScript $deltaBreaking

if ($afterPreserving -ne 'Preserving') {
    throw "Criterion 8 Failure: Preserving delta resolved to '$afterPreserving' instead of 'Preserving'."
}
if ($afterBreaking -ne 'Breaking') {
    throw "Criterion 8 Failure: Breaking delta resolved to '$afterBreaking' instead of 'Breaking'."
}

$methodPreserving = $deltaPreserving.PredictBehavior()
$methodBreaking   = $deltaBreaking.PredictBehavior()

if ($methodPreserving -ne 0 -or $methodBreaking -ne 1) {
    throw "Criterion 8 Failure: PredictBehavior() method returned incorrect values ($methodPreserving, $methodBreaking)."
}
Write-Host "Confirmed: EXACT SAME ScriptBlock instance resolved newly materialized concept without recompilation."

# Criterion 9: Removing the concept reverses that behavior
Uninstall-RuntimeConcept -TypeName $syntheticTypeName

$afterRemovalPreserving = & $preCompiledScript $deltaPreserving
$afterRemovalBreaking   = & $preCompiledScript $deltaBreaking

if ($null -ne $afterRemovalPreserving -or $null -ne $afterRemovalBreaking) {
    throw "Criterion 9 Failure: Concept remained active after uninstallation from the runtime type system."
}
Write-Host "Confirmed: Semantic reversibility proven — property access reverted to null on exact same ScriptBlock."

Write-Host "GATE6_RUNTIME_CONCEPT_INVENTION=PASS"
