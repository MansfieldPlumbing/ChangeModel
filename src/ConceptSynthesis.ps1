class Concept {
    [string]$Kind       # 'Atom', 'Not', 'And', 'Or'
    [string]$FeatureA
    [string]$FeatureB
    [string]$Name
    [int]$Complexity

    Concept([string]$kind, [string]$featA) {
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
            throw "Invalid unary concept kind: $kind"
        }
    }

    Concept([string]$kind, [string]$featA, [string]$featB) {
        $this.Kind = $kind
        $this.FeatureA = $featA
        $this.FeatureB = $featB
        $this.Complexity = 2
        if ($kind -in @('And', 'Or')) {
            $this.Name = "$kind($featA, $featB)"
        } else {
            throw "Invalid binary concept kind: $kind"
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

function Get-CandidateConcepts {
    param([Parameter(Mandatory)][string[]]$AtomicFeatures)

    $concepts = [System.Collections.Generic.List[Concept]]::new()

    # 1. Unary atoms and nots
    foreach ($feat in $AtomicFeatures) {
        $concepts.Add([Concept]::new('Atom', $feat))
        $concepts.Add([Concept]::new('Not', $feat))
    }

    # 2. Binary compositions (And, Or)
    for ($i = 0; $i -lt $AtomicFeatures.Length; $i++) {
        for ($j = $i + 1; $j -lt $AtomicFeatures.Length; $j++) {
            $fA = $AtomicFeatures[$i]
            $fB = $AtomicFeatures[$j]
            $concepts.Add([Concept]::new('And', $fA, $fB))
            $concepts.Add([Concept]::new('Or', $fA, $fB))
        }
    }

    return $concepts.ToArray()
}

function Measure-ConceptSufficiency {
    param(
        [Parameter(Mandatory)][array]$History,
        [Parameter(Mandatory)][Concept]$Concept
    )

    $keyToDeltas = @{}
    $contradictions = 0
    $totalError = 0
    $predictorTable = @{}

    foreach ($record in $History) {
        $canonical = $record.CanonicalBefore
        $conceptVal = $Concept.Evaluate($canonical)
        $key = "Concept=$conceptVal|Action=$($record.Action)"
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
        ConceptName = $Concept.Name
        Contradictions = $contradictions
        PredictionError = $totalError
        Complexity = $Concept.Complexity
        PredictorTable = $predictorTable
    }
}

function Invoke-ConceptSearch {
    param(
        [Parameter(Mandatory)][array]$History,
        [Parameter(Mandatory)][Concept[]]$CandidateConcepts,
        [Parameter(Mandatory)][string[]]$AtomicFeatures
    )

    $bestConcept = $null
    $bestScore = $null
    $allScores = [System.Collections.Generic.List[object]]::new()

    foreach ($c in $CandidateConcepts) {
        $score = Measure-ConceptSufficiency -History $History -Concept $c
        $allScores.Add([pscustomobject]@{ Concept = $c; Score = $score })

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
            $bestConcept = $c
            $bestScore = $score
        }
    }

    # Bounded exhaustive oracle: enumerated and scored independently of the
    # candidate list, Concept.Evaluate and Measure-ConceptSufficiency.
    $oracle = Get-ConceptOracleOptimum -History $History -AtomicFeatures $AtomicFeatures
    $winnerByOracle = $oracle.Scores[$bestConcept.Name]

    $reachedOracle = $false
    if ($null -ne $winnerByOracle -and
        $winnerByOracle.Contradictions -eq $bestScore.Contradictions -and
        $winnerByOracle.PredictionError -eq $bestScore.PredictionError -and
        $winnerByOracle.Complexity -eq $bestScore.Complexity -and
        $winnerByOracle.Contradictions -eq $oracle.Best.Contradictions -and
        $winnerByOracle.PredictionError -eq $oracle.Best.PredictionError -and
        $winnerByOracle.Complexity -eq $oracle.Best.Complexity) {
        $reachedOracle = $true
    }

    return [pscustomobject]@{
        WinningConcept = $bestConcept
        WinningMeasure = $bestScore
        ReachedOracle = $reachedOracle
        OracleBestMeasure = $oracle.Best
        OracleOptimumNames = $oracle.OptimumNames
        OracleScores = $oracle.Scores
        ExhaustiveEvaluations = $oracle.Scores.Count
        AllCandidatesCount = $CandidateConcepts.Length
        AllEvaluations = $allScores.ToArray()
    }
}

# Reference oracle for Invoke-ConceptSearch. Enumerates the bounded concept
# language (Atom, Not over each feature; And, Or over each unordered pair) from
# the feature list alone, evaluates concepts as truth tables over raw feature
# values, and restates the measure's definitions:
#   - prediction: the last delta seen for the key, 2 when the key is unseen;
#   - contradiction: a record whose key was seen before and whose key has more
#     than one distinct delta once this record is included.
function Get-ConceptOracleOptimum {
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
            ConceptName = $entry.Name
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
    } | ForEach-Object ConceptName | Sort-Object)

    return [pscustomobject]@{
        Best = $best
        OptimumNames = $optimumNames
        Scores = $scores
    }
}

function Install-RuntimeConcept {
    param(
        [Parameter(Mandatory)][string]$TypeName,
        [Parameter(Mandatory)][Concept]$Concept
    )

    $predicateStr = $Concept.ToPredicateString()
    
    # 1. ScriptProperty: SemanticEffect ('Breaking' vs 'Preserving')
    $effectScript = [scriptblock]::Create("if ($predicateStr) { 'Breaking' } else { 'Preserving' }")
    Update-TypeData -TypeName $TypeName -MemberType ScriptProperty -MemberName 'SemanticEffect' -Value $effectScript -Force

    # 2. ScriptMethod: PredictBehavior() (1 vs 0)
    $methodScript = [scriptblock]::Create("if ($predicateStr) { 1 } else { 0 }")
    Update-TypeData -TypeName $TypeName -MemberType ScriptMethod -MemberName 'PredictBehavior' -Value $methodScript -Force
}

function Uninstall-RuntimeConcept {
    param([Parameter(Mandatory)][string]$TypeName)

    Remove-TypeData -TypeName $TypeName -ErrorAction SilentlyContinue
}
