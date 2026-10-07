$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\src\Representation.ps1
. $PSScriptRoot\..\src\ObservationRecord.ps1
. $PSScriptRoot\..\src\Prediction.ps1
. $PSScriptRoot\..\src\Search.ps1
. $PSScriptRoot\..\src\Proposal.ps1
. $PSScriptRoot\..\src\ExpressionFeatures.ps1
. $PSScriptRoot\..\src\SmaContentfulDataset.ps1
. $PSScriptRoot\..\src\PredicateSynthesis.ps1

Write-Host "--- Gate 6: Predicate Synthesis ---"

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
    if (-not $rec.CanonicalBefore.ExpressionBeforeSignature -or -not $rec.CanonicalBefore.ExpressionAfterSignature) {
        throw "Canonical evidence violation: Missing expression signatures on '$($rec.SpecimenName)'."
    }
}

# Step 2: Enumerate candidate predicates across atomic features
$candidatePredicates = Get-CandidatePredicates -AtomicFeatures $atomicFeatures
Write-Host "Candidate predicates generated: $($candidatePredicates.Length)"

# Baseline test: Prove any single atomic feature alone fails to resolve contradictions
$atomsWithContradictions = 0
foreach ($atom in $atomicFeatures) {
    $atomPred = [BooleanPredicate]::new('Atom', $atom)
    $m = Measure-PredicateSufficiency -History $trainingDataset -Predicate $atomPred
    if ($m.Contradictions -gt 0) { $atomsWithContradictions++ }
}
if ($atomsWithContradictions -ne $atomicFeatures.Length) {
    throw "Precondition failure: Expected all individual atomic features to produce contradictions."
}
Write-Host "Confirmed all $($atomicFeatures.Length) individual atomic features suffer from structural residuals."

# Step 3: Search and score candidate predicates against execution evidence
$searchResult = Invoke-PredicateSearch -History $trainingDataset -CandidatePredicates $candidatePredicates -AtomicFeatures $atomicFeatures
$winningPred = $searchResult.WinningPredicate
$winningMeasure = $searchResult.WinningMeasure

Write-Host "Winning Predicate: $($winningPred.Name)"
Write-Host "  Contradictions : $($winningMeasure.Contradictions)"
Write-Host "  PredictionError: $($winningMeasure.PredictionError)"
Write-Host "  Complexity     : $($winningMeasure.Complexity)"
Write-Host "  Reached Optimum: $($searchResult.ReachedExhaustiveOptimum)"

# Criterion 1: The winning predicate was constructed from lower-level atomic features
if ($winningPred.Kind -eq 'Atom') {
    throw "Criterion 1 Failure: Winning predicate is a primitive atom, not a constructed predicate."
}

# Criterion 2: It was not present in the supplied feature vocabulary
if ($atomicFeatures -contains $winningPred.Name) {
    throw "Criterion 2 Failure: Winning predicate was already present in the input feature vocabulary."
}

# Criterion 3: The predicate improves predictive sufficiency over the original representation
if ($winningMeasure.Contradictions -ne 0) {
    throw "Criterion 3 Failure: Winning predicate failed to reduce contradictions to zero ($($winningMeasure.Contradictions))."
}

# Criterion 4: Its selection is verified against a bounded exhaustive optimum
if (-not $searchResult.ReachedExhaustiveOptimum) {
    throw "Criterion 4 Failure: Predicate selection did not match exhaustive optimum."
}
if ($searchResult.ExhaustiveEvaluations -ne $candidatePredicates.Length) {
    throw "Criterion 4 Failure: Exhaustive search evaluated $($searchResult.ExhaustiveEvaluations) predicates; the candidate generator produced $($candidatePredicates.Length)."
}
foreach ($evaluation in $searchResult.AllEvaluations) {
    $reference = $searchResult.ExhaustiveScores[$evaluation.Predicate.Name]
    if ($null -eq $reference -or
        $reference.Contradictions -ne $evaluation.Score.Contradictions -or
        $reference.PredictionError -ne $evaluation.Score.PredictionError -or
        $reference.Complexity -ne $evaluation.Score.Complexity) {
        throw "Criterion 4 Failure: Search and exhaustive optimum disagree on '$($evaluation.Predicate.Name)'."
    }
}

# Criterion 4 negative control: with every exhaustive-optimal predicate withheld from
# the search, the optimum check must report failure.
$withheld = @($candidatePredicates | Where-Object { $_.Name -notin $searchResult.ExhaustiveOptimumNames })
if ($withheld.Length -eq $candidatePredicates.Length) {
    throw "Criterion 4 Control Failure: No candidate matched an exhaustive-optimal name."
}
$controlResult = Invoke-PredicateSearch -History $trainingDataset -CandidatePredicates $withheld -AtomicFeatures $atomicFeatures
if ($controlResult.ReachedExhaustiveOptimum) {
    throw "Criterion 4 Control Failure: Exhaustive check passed with the optimum withheld ($($controlResult.WinningPredicate.Name))."
}
Write-Host "Exhaustive optimum: $($searchResult.ExhaustiveOptimumNames -join ', ') over $($searchResult.ExhaustiveEvaluations) predicates"
Write-Host "Control: optimum withheld, search chose $($controlResult.WinningPredicate.Name), Reached Optimum = $($controlResult.ReachedExhaustiveOptimum)"

# Criterion 5: Held-out behavioral predictions under explicitly reported support
$learnedTable = $winningMeasure.PredictorTable
$heldOutCount = $heldOutDataset.Count
$heldOutCorrect = 0
$heldOutError = 0
$heldOutUnseenKeys = 0

foreach ($r in $heldOutDataset) {
    $predVal = $winningPred.Evaluate($r.CanonicalBefore)
    $key = "Predicate=$predVal|Action=$($r.Action)"

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
$syntheticTypeName = "Dev.MansfieldPlumbing.PowerShell.Perception.Predicate.SemanticMutation.$([math]::Abs($winningPred.Name.GetHashCode()))"

$deltaPreserving = $trainingDataset[0].CanonicalBefore
$deltaBreaking   = $trainingDataset[5].CanonicalBefore

# Assign synthetic PSTypeName
$deltaPreserving.PSObject.TypeNames.Insert(0, $syntheticTypeName)
$deltaBreaking.PSObject.TypeNames.Insert(0, $syntheticTypeName)

# Criterion 7: A ScriptBlock created before installation cannot use the predicate before installation
$preCompiledScript = {
    param($delta)
    $delta.SemanticEffect
}

$beforePreserving = & $preCompiledScript $deltaPreserving
$beforeBreaking   = & $preCompiledScript $deltaBreaking

if ($null -ne $beforePreserving -or $null -ne $beforeBreaking) {
    throw "Criterion 7 Failure: Predicate resolved before it was installed in the runtime type system."
}
Write-Host "Confirmed: Pre-compiled ScriptBlock cannot resolve SemanticEffect prior to installation."

# Criterion 6: Materialize into live PowerShell type system
Install-RuntimePredicate -TypeName $syntheticTypeName -Predicate $winningPred

# Criterion 8: The exact same ScriptBlock instance can use the predicate after installation
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
Write-Host "Confirmed: EXACT SAME ScriptBlock instance resolved newly materialized predicate without recompilation."

# Criterion 9: Removing the predicate reverses that behavior
Uninstall-RuntimePredicate -TypeName $syntheticTypeName

$afterRemovalPreserving = & $preCompiledScript $deltaPreserving
$afterRemovalBreaking   = & $preCompiledScript $deltaBreaking

if ($null -ne $afterRemovalPreserving -or $null -ne $afterRemovalBreaking) {
    throw "Criterion 9 Failure: Predicate remained active after uninstallation from the runtime type system."
}
Write-Host "Confirmed: Semantic reversibility proven — property access reverted to null on exact same ScriptBlock."

Write-Host "GATE6_PREDICATE_SYNTHESIS: WinningPredicate=$($winningPred.Name), Complexity=$($winningPred.Complexity), Contradictions=$($winningMeasure.Contradictions), PredictionError=$($winningMeasure.PredictionError), SemanticReversibility=Verified"
