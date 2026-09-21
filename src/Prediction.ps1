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

    # Predictor logic: we have a Magnitude parameter.
    $magnitude = 2

    foreach ($record in $History) {
        $canonical = $record.CanonicalBefore
        $repState = $Rep.GetRepresentedState($canonical)
        $key = Get-ContradictionKey -RepresentedBefore $repState -Action $record.Action
        
        # Predict
        $dir = 1
        if ($repState.ContainsKey('Direction')) {
            $dir = $repState['Direction']
        }
        $predDelta = $magnitude * $dir
        
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

        # Learn for next time (simple update for our toy model)
        if ($dir -ne 0) {
            $magnitude = $actualDelta / $dir
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
