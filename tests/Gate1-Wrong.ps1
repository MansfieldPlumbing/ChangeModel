. $PSScriptRoot\..\src\World.ps1
. $PSScriptRoot\..\src\Representation.ps1
. $PSScriptRoot\..\src\Experience.ps1
. $PSScriptRoot\..\src\Prediction.ps1

$history = [System.Collections.Generic.List[object]]::new()
$heldOut = [System.Collections.Generic.List[object]]::new()

# Generate history
for ($i = 0; $i -lt 10; $i++) {
    $s = [WorldState]::new()
    $s.X = $i
    $s.Direction = if ($i % 2 -eq 0) { 1 } else { -1 }
    $next = Invoke-WorldStep $s
    $history.Add([pscustomobject]@{ CanonicalBefore = $s; Action = 'Step'; ActualDelta = ($next.X - $s.X) })
}

# Generate held-out
for ($i = 10; $i -lt 15; $i++) {
    $s = [WorldState]::new()
    $s.X = $i
    $s.Direction = if ($i % 2 -eq 0) { 1 } else { -1 }
    $next = Invoke-WorldStep $s
    $heldOut.Add([pscustomobject]@{ CanonicalBefore = $s; Action = 'Step'; ActualDelta = ($next.X - $s.X) })
}

$rep = [Representation]::new([string[]]@('X', 'Direction'))
$measure = Measure-Experience -History $history -Rep $rep -RepVersion "R1"

if ($measure.Contradictions -ne 0) { throw "Expected 0 contradictions, got $($measure.Contradictions)" }
if ($measure.PredictionError -eq 0) { throw "Expected initial prediction error > 0" }

# Now predict on held-out using a predictor trained on history (it learned Magnitude = 1)
$magnitude = 1

$heldOutError = 0
foreach ($record in $heldOut) {
    $canonical = $record.CanonicalBefore
    $repState = $rep.GetRepresentedState($canonical)
    
    $dir = 1
    if ($repState.ContainsKey('Direction')) {
        $dir = $repState['Direction']
    }
    $predDelta = $magnitude * $dir

    $heldOutError += [math]::Abs($predDelta - $record.ActualDelta)
}

if ($heldOutError -ne 0) { throw "Expected 0 error on held-out, got $heldOutError" }

Write-Host "GATE1_WRONG=PASS"
