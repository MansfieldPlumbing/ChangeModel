function New-ExperienceRecord {
    param(
        $RepresentationVersion,
        $CanonicalBefore,
        $RepresentedBefore,
        $Action,
        $PredictedDelta,
        $ActualDelta,
        $PredictionError,
        $ContradictionKey
    )

    [pscustomobject]@{
        RepresentationVersion = $RepresentationVersion
        CanonicalBefore = $CanonicalBefore
        RepresentedBefore = $RepresentedBefore
        Action = $Action
        PredictedDelta = $PredictedDelta
        ActualDelta = $ActualDelta
        PredictionError = $PredictionError
        ContradictionKey = $ContradictionKey
    }
}

function Get-ContradictionKey {
    param([hashtable]$RepresentedBefore, [string]$Action)
    # create a deterministic string key from state + action
    $keys = $RepresentedBefore.Keys | Sort-Object
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $keys) {
        $parts.Add("$k=$($RepresentedBefore[$k])")
    }
    return "$($parts -join ',')|Action=$Action"
}
