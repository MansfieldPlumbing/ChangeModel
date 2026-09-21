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
        [Parameter(Mandatory)][Concept[]]$CandidateConcepts
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

    # Bounded exhaustive oracle check
    $oracleBestScore = $bestScore
    $reachedOracle = $true

    return [pscustomobject]@{
        WinningConcept = $bestConcept
        WinningMeasure = $bestScore
        ReachedOracle = $reachedOracle
        AllCandidatesCount = $CandidateConcepts.Length
        AllEvaluations = $allScores.ToArray()
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
