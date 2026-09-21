. $PSScriptRoot\..\src\World.ps1
. $PSScriptRoot\..\src\Representation.ps1
. $PSScriptRoot\..\src\Experience.ps1
. $PSScriptRoot\..\src\Prediction.ps1
. $PSScriptRoot\..\src\Search.ps1

$history = [System.Collections.Generic.List[object]]::new()

# Generate history where same X has different Directions to create contradiction
$s1 = [WorldState]::new(); $s1.X = 5; $s1.Direction = 1; $next1 = Invoke-WorldStep $s1
$history.Add([pscustomobject]@{ CanonicalBefore = $s1; Action = 'Step'; ActualDelta = ($next1.X - $s1.X) })

$s2 = [WorldState]::new(); $s2.X = 5; $s2.Direction = -1; $next2 = Invoke-WorldStep $s2
$history.Add([pscustomobject]@{ CanonicalBefore = $s2; Action = 'Step'; ActualDelta = ($next2.X - $s2.X) })

$s3 = [WorldState]::new(); $s3.X = 6; $s3.Direction = 1; $next3 = Invoke-WorldStep $s3
$history.Add([pscustomobject]@{ CanonicalBefore = $s3; Action = 'Step'; ActualDelta = ($next3.X - $s3.X) })

# R1 (Clipped representation)
$r1 = [Representation]::new([string[]]@('X'))
$measureR1 = Measure-Experience -History $history -Rep $r1 -RepVersion "R1"

if ($measureR1.Contradictions -eq 0) { throw "Expected contradictions under R1" }

# Search for R2
$allFeatures = @('X', 'Direction')
$searchResult = Invoke-RepresentationSearch -History $history -AllFeatures $allFeatures

if (-not $searchResult.ReachedOracle) { throw "Search did not reach exhaustive optimum" }
$finalMeasure = $searchResult.FinalMeasure
if ($finalMeasure.Contradictions -ne 0) { throw "Expected 0 contradictions under final representation" }

$hasDirection = $false
foreach ($f in $searchResult.FinalRep.Features) {
    if ($f -eq 'Direction') { $hasDirection = $true }
}
if (-not $hasDirection) { throw "Final representation did not discover 'Direction'" }

Write-Host "GATE2_NOT_EVEN_WRONG=PASS"
