function Get-ActualDelta {
    param([WorldState]$Before, [WorldState]$After)
    return $After.X - $Before.X
}

function Measure-Experience {
    param([array]$History, [Representation]$Rep, [string]$RepVersion)

    # Replay experience against representation
    $replayHistory = [System.Collections.Generic.List[object]]::new()
    
    # Track observed deltas for contradictions
    $keyToDeltas = @{}
    $totalError = 0
    $contradictions = 0

    # Predictor parameters:
    $magnitude = 2
    $predictorTable = @{}

    foreach ($record in $History) {
        $canonical = $record.CanonicalBefore
        $repState = $Rep.GetRepresentedState($canonical)
        $key = Get-ContradictionKey -RepresentedBefore $repState -Action $record.Action
        
        # Predict
        if ($repState.ContainsKey('Direction')) {
            $dir = $repState['Direction']
            $predDelta = $magnitude * $dir
        } elseif ($predictorTable.ContainsKey($key)) {
            $predDelta = $predictorTable[$key]
        } else {
            # Deliberately incorrect initial prediction
            $predDelta = 2
        }
        
        $actualDelta = $record.ActualDelta
        $error = [math]::Abs($predDelta - $actualDelta)
        $totalError += $error

        $replayHistory.Add((New-ExperienceRecord `
            -RepresentationVersion $RepVersion `
            -CanonicalBefore $canonical `
            -RepresentedBefore $repState `
            -Action $record.Action `
            -PredictedDelta $predDelta `
            -ActualDelta $actualDelta `
            -PredictionError $error `
            -ContradictionKey $key))

        # Learn for next time
        if ($repState.ContainsKey('Direction')) {
            $dir = $repState['Direction']
            if ($dir -ne 0) {
                $magnitude = $actualDelta / $dir
            }
        } else {
            $predictorTable[$key] = $actualDelta
        }

        if (-not $keyToDeltas.ContainsKey($key)) {
            $keyToDeltas[$key] = [System.Collections.Generic.HashSet[int]]::new()
        } elseif (-not $keyToDeltas[$key].Contains($actualDelta) -or $keyToDeltas[$key].Count -gt 1) {
            $contradictions += 1
        }
        $null = $keyToDeltas[$key].Add($actualDelta)
    }

    $contradictoryKeys = [System.Collections.Generic.List[string]]::new()
    $contradictionDetails = @{}
    foreach ($k in $keyToDeltas.Keys) {
        if ($keyToDeltas[$k].Count -gt 1) {
            $contradictoryKeys.Add($k)
            $contradictionDetails[$k] = @($keyToDeltas[$k])
        }
    }

    return [pscustomobject]@{
        PredictionError = $totalError
        Contradictions = $contradictions
        ContradictoryKeys = $contradictoryKeys.ToArray()
        ContradictionDetails = $contradictionDetails
        RepresentationComplexity = $Rep.Features.Count
        ReplayHistory = $replayHistory
    }
}
