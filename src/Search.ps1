function Invoke-RepresentationSearch {
    param([array]$History, [string[]]$AllFeatures)

    $evaluations = 0
    # Start with empty representation
    $selected = [System.Collections.Generic.HashSet[string]]::new()
    
    $currentRep = [Representation]::new([string[]]@($selected))
    $currentMeasure = Measure-Experience -History $History -Rep $currentRep -RepVersion "V_Current"
    $evaluations++

    $searchHistory = [System.Collections.Generic.List[object]]::new()

    while ($true) {
        $best = $null
        foreach ($feature in $AllFeatures) {
            if ($selected.Contains($feature)) { continue }

            $trialSelection = [System.Collections.Generic.HashSet[string]]::new($selected)
            $null = $trialSelection.Add($feature)
            $trialRep = [Representation]::new([string[]]@($trialSelection))
            
            $trialMeasure = Measure-Experience -History $History -Rep $trialRep -RepVersion "V_Trial"
            $evaluations++

            # Lexicographic score: 1. Contradictions (lower better), 2. PredictionError (lower better), 3. Complexity (lower better)
            # We want to maximize score, so we compare negative values.
            # strict improvement required.
            $isBetter = $false
            if ($null -eq $best) {
                $isBetter = $true
            } else {
                if ($trialMeasure.Contradictions -lt $best.Measure.Contradictions) { $isBetter = $true }
                elseif ($trialMeasure.Contradictions -eq $best.Measure.Contradictions) {
                    if ($trialMeasure.PredictionError -lt $best.Measure.PredictionError) { $isBetter = $true }
                    elseif ($trialMeasure.PredictionError -eq $best.Measure.PredictionError) {
                        if ($trialMeasure.RepresentationComplexity -lt $best.Measure.RepresentationComplexity) { $isBetter = $true }
                    }
                }
            }

            if ($isBetter) {
                $best = [pscustomobject]@{
                    Feature = $feature
                    Rep = $trialRep
                    Measure = $trialMeasure
                }
            }
        }

        # Compare best neighbor to current
        $improvesCurrent = $false
        if ($best) {
            if ($best.Measure.Contradictions -lt $currentMeasure.Contradictions) { $improvesCurrent = $true }
            elseif ($best.Measure.Contradictions -eq $currentMeasure.Contradictions) {
                if ($best.Measure.PredictionError -lt $currentMeasure.PredictionError) { $improvesCurrent = $true }
                elseif ($best.Measure.PredictionError -eq $currentMeasure.PredictionError) {
                    if ($best.Measure.RepresentationComplexity -lt $currentMeasure.RepresentationComplexity) { $improvesCurrent = $true }
                }
            }
        }

        if (-not $improvesCurrent) { break }

        $null = $selected.Add($best.Feature)
        $searchHistory.Add([pscustomobject]@{
            AddedFeature = $best.Feature
            BeforeMeasure = $currentMeasure
            AfterMeasure = $best.Measure
        })
        $currentRep = $best.Rep
        $currentMeasure = $best.Measure
    }

    # Exhaustive oracle
    $combinationCount = [math]::Pow(2, $AllFeatures.Length)
    $oracleBest = $null

    for ($mask = 0; $mask -lt $combinationCount; $mask++) {
        $oracleSelected = [System.Collections.Generic.HashSet[string]]::new()
        for ($index = 0; $index -lt $AllFeatures.Length; $index++) {
            if ($mask -band (1 -shl $index)) { $null = $oracleSelected.Add($AllFeatures[$index]) }
        }
        
        $oracleRep = [Representation]::new([string[]]@($oracleSelected))
        $measure = Measure-Experience -History $History -Rep $oracleRep -RepVersion "V_Oracle"
        
        $isBetter = $false
        if ($null -eq $oracleBest) {
            $isBetter = $true
        } else {
            if ($measure.Contradictions -lt $oracleBest.Contradictions) { $isBetter = $true }
            elseif ($measure.Contradictions -eq $oracleBest.Contradictions) {
                if ($measure.PredictionError -lt $oracleBest.PredictionError) { $isBetter = $true }
                elseif ($measure.PredictionError -eq $oracleBest.PredictionError) {
                    if ($measure.RepresentationComplexity -lt $oracleBest.RepresentationComplexity) { $isBetter = $true }
                }
            }
        }

        if ($isBetter) {
            $oracleBest = $measure
        }
    }

    $reachedOracle = $false
    if ($currentMeasure.Contradictions -eq $oracleBest.Contradictions -and
        $currentMeasure.PredictionError -eq $oracleBest.PredictionError -and
        $currentMeasure.RepresentationComplexity -eq $oracleBest.RepresentationComplexity) {
        $reachedOracle = $true
    }

    [pscustomobject]@{
        FinalRep = $currentRep
        FinalMeasure = $currentMeasure
        History = $searchHistory.ToArray()
        Evaluations = $evaluations
        ExhaustiveEvaluations = [int]$combinationCount
        OracleBestMeasure = $oracleBest
        ReachedOracle = $reachedOracle
    }
}
