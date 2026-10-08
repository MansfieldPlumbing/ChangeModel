class BooleanPredicate {
    [string]$Kind       # 'Atom', 'Not', 'And', 'Or'
    [string]$FeatureA
    [string]$FeatureB
    [string]$Name
    [int]$Complexity

    BooleanPredicate([string]$kind, [string]$featA) {
        $this.Kind = $kind
        $this.FeatureA = $featA
        $this.FeatureB = $null
        if ($kind -eq 'Atom') {
            $this.Name = "Atom($featA)"
            $this.Complexity = 1
        } elseif ($kind -eq 'Not') {
            $this.Name = "Not($featA)"
            $this.Complexity = 2
        } else {
            throw "Invalid unary predicate kind: $kind"
        }
    }

    BooleanPredicate([string]$kind, [string]$featA, [string]$featB) {
        $this.Kind = $kind
        $this.FeatureA = $featA
        $this.FeatureB = $featB
        $this.Complexity = 2
        if ($kind -in @('And', 'Or')) {
            $this.Name = "$kind($featA, $featB)"
        } else {
            throw "Invalid binary predicate kind: $kind"
        }
    }

    [int] Evaluate([object]$canonical) {
        $valA = if ($canonical.PSObject.Properties[$this.FeatureA]) { [int]$canonical.($this.FeatureA) } else { 0 }
        
        switch ($this.Kind) {
            'Atom' { return $valA }
            'Not'  { if ($valA -eq 0) { return 1 } else { return 0 } }
            'And'  {
                $valB = if ($canonical.PSObject.Properties[$this.FeatureB]) { [int]$canonical.($this.FeatureB) } else { 0 }
                if ($valA -eq 1 -and $valB -eq 1) { return 1 } else { return 0 }
            }
            'Or'   {
                $valB = if ($canonical.PSObject.Properties[$this.FeatureB]) { [int]$canonical.($this.FeatureB) } else { 0 }
                if ($valA -eq 1 -or $valB -eq 1) { return 1 } else { return 0 }
            }
        }
        return 0
    }

    [string] ToPredicateString() {
        switch ($this.Kind) {
            'Atom' { return "`$this.$($this.FeatureA) -eq 1" }
            'Not'  { return "`$this.$($this.FeatureA) -ne 1" }
            'And'  { return "(`$this.$($this.FeatureA) -eq 1 -and `$this.$($this.FeatureB) -eq 1)" }
            'Or'   { return "(`$this.$($this.FeatureA) -eq 1 -or `$this.$($this.FeatureB) -eq 1)" }
        }
        return '$false'
    }
}

function Get-CandidatePredicates {
    param([Parameter(Mandatory)][string[]]$AtomicFeatures)

    $predicates = [System.Collections.Generic.List[BooleanPredicate]]::new()

    # 1. Unary atoms and nots
    foreach ($feat in $AtomicFeatures) {
        $predicates.Add([BooleanPredicate]::new('Atom', $feat))
        $predicates.Add([BooleanPredicate]::new('Not', $feat))
    }

    # 2. Binary compositions (And, Or)
    for ($i = 0; $i -lt $AtomicFeatures.Length; $i++) {
        for ($j = $i + 1; $j -lt $AtomicFeatures.Length; $j++) {
            $fA = $AtomicFeatures[$i]
            $fB = $AtomicFeatures[$j]
            $predicates.Add([BooleanPredicate]::new('And', $fA, $fB))
            $predicates.Add([BooleanPredicate]::new('Or', $fA, $fB))
        }
    }

    return $predicates.ToArray()
}

function Measure-PredicateSufficiency {
    param(
        [Parameter(Mandatory)][array]$History,
        [Parameter(Mandatory)][BooleanPredicate]$Predicate
    )

    $keyToDeltas = @{}
    $contradictions = 0
    $totalError = 0
    $predictorTable = @{}

    foreach ($record in $History) {
        $canonical = $record.CanonicalBefore
        $predVal = $Predicate.Evaluate($canonical)
        $key = "Predicate=$predVal|Action=$($record.Action)"
        $actual = $record.ActualDelta

        # Deterministic prediction
        $pred = if ($predictorTable.ContainsKey($key)) { $predictorTable[$key] } else { 2 }
        $totalError += [math]::Abs($pred - $actual)
        $predictorTable[$key] = $actual

        # Contradiction tracking
        if (-not $keyToDeltas.ContainsKey($key)) {
            $keyToDeltas[$key] = [System.Collections.Generic.HashSet[int]]::new()
        } elseif (-not $keyToDeltas[$key].Contains($actual) -or $keyToDeltas[$key].Count -gt 1) {
            $contradictions++
        }
        $null = $keyToDeltas[$key].Add($actual)
    }

    return [pscustomobject]@{
        PredicateName = $Predicate.Name
        Contradictions = $contradictions
        PredictionError = $totalError
        Complexity = $Predicate.Complexity
        PredictorTable = $predictorTable
    }
}

function Invoke-PredicateSearch {
    param(
        [Parameter(Mandatory)][array]$History,
        [Parameter(Mandatory)][BooleanPredicate[]]$CandidatePredicates,
        [Parameter(Mandatory)][string[]]$AtomicFeatures
    )

    $bestPredicate = $null
    $bestScore = $null
    $allScores = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $CandidatePredicates) {
        $score = Measure-PredicateSufficiency -History $History -Predicate $p
        $allScores.Add([pscustomobject]@{ Predicate = $p; Score = $score })

        # Lexicographic selection:
        # 1. Contradictions (lower is better)
        # 2. PredictionError (lower is better)
        # 3. Complexity (lower is better)
        $isBetter = $false
        if ($null -eq $bestScore) {
            $isBetter = $true
        } else {
            if ($score.Contradictions -lt $bestScore.Contradictions) {
                $isBetter = $true
            } elseif ($score.Contradictions -eq $bestScore.Contradictions) {
                if ($score.PredictionError -lt $bestScore.PredictionError) {
                    $isBetter = $true
                } elseif ($score.PredictionError -eq $bestScore.PredictionError) {
                    if ($score.Complexity -lt $bestScore.Complexity) {
                        $isBetter = $true
                    }
                }
            }
        }

        if ($isBetter) {
            $bestPredicate = $p
            $bestScore = $score
        }
    }

    # Bounded exhaustive optimum: enumerated and scored independently of the
    # candidate list, BooleanPredicate.Evaluate and Measure-PredicateSufficiency.
    $exhaustive = Get-ExhaustivePredicateOptimum -History $History -AtomicFeatures $AtomicFeatures
    $winnerByExhaustive = $exhaustive.Scores[$bestPredicate.Name]

    $reachedOptimum = $false
    if ($null -ne $winnerByExhaustive -and
        $winnerByExhaustive.Contradictions -eq $bestScore.Contradictions -and
        $winnerByExhaustive.PredictionError -eq $bestScore.PredictionError -and
        $winnerByExhaustive.Complexity -eq $bestScore.Complexity -and
        $winnerByExhaustive.Contradictions -eq $exhaustive.Best.Contradictions -and
        $winnerByExhaustive.PredictionError -eq $exhaustive.Best.PredictionError -and
        $winnerByExhaustive.Complexity -eq $exhaustive.Best.Complexity) {
        $reachedOptimum = $true
    }

    return [pscustomobject]@{
        WinningPredicate = $bestPredicate
        WinningMeasure = $bestScore
        ReachedExhaustiveOptimum = $reachedOptimum
        ExhaustiveBestMeasure = $exhaustive.Best
        ExhaustiveOptimumNames = $exhaustive.OptimumNames
        ExhaustiveScores = $exhaustive.Scores
        ExhaustiveEvaluations = $exhaustive.Scores.Count
        AllCandidatesCount = $CandidatePredicates.Length
        AllEvaluations = $allScores.ToArray()
    }
}

# Reference exhaustive ground truth for Invoke-PredicateSearch. Enumerates the bounded predicate
# language (Atom, Not over each feature; And, Or over each unordered pair) from
# the feature list alone, evaluates predicates as truth tables over raw feature
# values, and restates the measure's definitions:
#   - prediction: the last delta seen for the key, 2 when the key is unseen;
#   - contradiction: a record whose key was seen before and whose key has more
#     than one distinct delta once this record is included.
function Get-ExhaustivePredicateOptimum {
    param(
        [Parameter(Mandatory)][array]$History,
        [Parameter(Mandatory)][string[]]$AtomicFeatures
    )

    # Truth tables indexed [a][b]; unary operators ignore b.
    $operators = [ordered]@{
        Atom = @{ Arity = 1; Complexity = 1; Table = @(@(0, 0), @(1, 1)) }
        Not  = @{ Arity = 1; Complexity = 2; Table = @(@(1, 1), @(0, 0)) }
        And  = @{ Arity = 2; Complexity = 2; Table = @(@(0, 0), @(0, 1)) }
        Or   = @{ Arity = 2; Complexity = 2; Table = @(@(0, 1), @(1, 1)) }
    }

    $bit = {
        param($canonical, [string]$feature)
        $property = $canonical.PSObject.Properties[$feature]
        if ($null -eq $property) { return 0 }
        if ([int]$property.Value -eq 1) { return 1 }
        return 0
    }

    $space = [System.Collections.Generic.List[object]]::new()
    foreach ($opName in $operators.Keys) {
        $op = $operators[$opName]
        if ($op.Arity -eq 1) {
            foreach ($a in $AtomicFeatures) {
                $space.Add(@{ Name = "$opName($a)"; Op = $op; A = $a; B = $null })
            }
        } else {
            for ($i = 0; $i -lt $AtomicFeatures.Length; $i++) {
                for ($j = $i + 1; $j -lt $AtomicFeatures.Length; $j++) {
                    $a = $AtomicFeatures[$i]; $b = $AtomicFeatures[$j]
                    $space.Add(@{ Name = "$opName($a, $b)"; Op = $op; A = $a; B = $b })
                }
            }
        }
    }

    $scores = @{}
    $best = $null
    foreach ($entry in $space) {
        $lastDelta = @{}
        $distinct = @{}
        $contradictions = 0
        $totalError = 0
        foreach ($record in $History) {
            $bitA = & $bit $record.CanonicalBefore $entry.A
            $bitB = if ($null -eq $entry.B) { 0 } else { & $bit $record.CanonicalBefore $entry.B }
            $key = '{0}|{1}' -f $entry.Op.Table[$bitA][$bitB], $record.Action
            $actual = [int]$record.ActualDelta

            $seen = $lastDelta.ContainsKey($key)
            $predicted = if ($seen) { $lastDelta[$key] } else { 2 }
            $totalError += [math]::Abs($predicted - $actual)
            $lastDelta[$key] = $actual

            if (-not $distinct.ContainsKey($key)) { $distinct[$key] = @{} }
            $distinct[$key][$actual] = $true
            if ($seen -and $distinct[$key].Count -gt 1) { $contradictions++ }
        }

        $score = [pscustomobject]@{
            PredicateName = $entry.Name
            Contradictions = $contradictions
            PredictionError = $totalError
            Complexity = $entry.Op.Complexity
        }
        $scores[$entry.Name] = $score

        if ($null -eq $best -or
            $score.Contradictions -lt $best.Contradictions -or
            ($score.Contradictions -eq $best.Contradictions -and
            ($score.PredictionError -lt $best.PredictionError -or
            ($score.PredictionError -eq $best.PredictionError -and $score.Complexity -lt $best.Complexity)))) {
            $best = $score
        }
    }

    $optimumNames = @($scores.Values | Where-Object {
        $_.Contradictions -eq $best.Contradictions -and
        $_.PredictionError -eq $best.PredictionError -and
        $_.Complexity -eq $best.Complexity
    } | ForEach-Object PredicateName | Sort-Object)

    return [pscustomobject]@{
        Best = $best
        OptimumNames = $optimumNames
        Scores = $scores
    }
}

function Install-RuntimePredicate {
    param(
        [Parameter(Mandatory)][string]$TypeName,
        [Parameter(Mandatory)][BooleanPredicate]$Predicate
    )

    # TypeData clones script bodies; bind predicate data through ETS rather than
    # relying on captured script scope or evaluating generated source strings.
    Update-TypeData -TypeName $TypeName -MemberType NoteProperty -MemberName 'RuntimePredicate' -Value $Predicate -Force
    
    # 1. ScriptProperty: SemanticEffect ('Breaking' vs 'Preserving')
    $effectScript = { if ($this.RuntimePredicate.Evaluate($this) -eq 1) { 'Breaking' } else { 'Preserving' } }
    Update-TypeData -TypeName $TypeName -MemberType ScriptProperty -MemberName 'SemanticEffect' -Value $effectScript -Force

    # 2. ScriptMethod: PredictBehavior() (1 vs 0)
    $methodScript = { $this.RuntimePredicate.Evaluate($this) }
    Update-TypeData -TypeName $TypeName -MemberType ScriptMethod -MemberName 'PredictBehavior' -Value $methodScript -Force
}

function Uninstall-RuntimePredicate {
    param([Parameter(Mandatory)][string]$TypeName)

    Remove-TypeData -TypeName $TypeName -ErrorAction SilentlyContinue
}
