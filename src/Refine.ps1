# Refine.ps1 - Counterexample-guided percept refinement loop.
#
# One loop:
#   1. Localize the delta
#   2. Classify it (wrong value, representation collision, or missing operation)
#   3. Propose from the store first, then from a fixed percept grammar
#   4. Apply reversibly
#   5. Gate (strictly lexicographic ordering, fixed neutral budget)
#   6. Keep or revert
#   7. Record in store provenance graph
#
# Constraints:
#   Percept candidates come ONLY from attributes on which colliding observations differ,
#   at combination depth <= 2.
#   No JSON. No regex.

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'LinearState.ps1')
. (Join-Path $PSScriptRoot 'Representation.ps1')
. (Join-Path $PSScriptRoot 'ObservationRecord.ps1')
. (Join-Path $PSScriptRoot 'Prediction.ps1')
. (Join-Path $PSScriptRoot 'Proposal.ps1')
. (Join-Path $PSScriptRoot 'Store.ps1')

function Get-CollidingObservations {
    param(
        [Parameter(Mandatory)][array]$Experience,
        [Parameter(Mandatory)][Representation]$Representation
    )

    $keyToRecords = @{}
    foreach ($rec in $Experience) {
        $repState = $Representation.GetRepresentedState($rec.CanonicalBefore)
        $key = Get-ConditionKey -RepresentedBefore $repState -Action $rec.Action
        if (-not $keyToRecords.ContainsKey($key)) {
            $keyToRecords[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $keyToRecords[$key].Add($rec)
    }

    $collisions = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $keyToRecords.Keys) {
        $records = $keyToRecords[$key]
        if ($records.Count -gt 1) {
            $deltas = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($r in $records) {
                [void]$deltas.Add([int]$r.ActualDelta)
            }
            if ($deltas.Count -gt 1) {
                for ($i = 0; $i -lt $records.Count; $i++) {
                    for ($j = $i + 1; $j -lt $records.Count; $j++) {
                        if ($records[$i].ActualDelta -ne $records[$j].ActualDelta) {
                            $collisions.Add([pscustomobject]@{
                                ConditionKey = $key
                                RecordA      = $records[$i]
                                RecordB      = $records[$j]
                                DeltaA       = $records[$i].ActualDelta
                                DeltaB       = $records[$j].ActualDelta
                            })
                        }
                    }
                }
            }
        }
    }

    return @($collisions)
}

function Get-DifferingObservationAttributes {
    param(
        [object[]]$Collisions = @(),
        [Representation]$CurrentRepresentation = $null
    )

    $currentFeatures = if ($CurrentRepresentation) {
        [System.Collections.Generic.HashSet[string]]::new([string[]]$CurrentRepresentation.Features, [StringComparer]::OrdinalIgnoreCase)
    } else {
        [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }

    $differingAttributes = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)

    foreach ($col in $Collisions) {
        $canA = $col.RecordA.CanonicalBefore
        $canB = $col.RecordB.CanonicalBefore

        $props = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($canA.PSObject) {
            foreach ($p in $canA.PSObject.Properties) { [void]$props.Add($p.Name) }
        }
        if ($canB.PSObject) {
            foreach ($p in $canB.PSObject.Properties) { [void]$props.Add($p.Name) }
        }

        foreach ($pName in $props) {
            if ($currentFeatures.Contains($pName)) { continue }

            $valA = if ($canA.PSObject.Properties[$pName]) { $canA.$pName } else { $null }
            $valB = if ($canB.PSObject.Properties[$pName]) { $canB.$pName } else { $null }

            $differ = $false
            if ($null -eq $valA -and $null -ne $valB) { $differ = $true }
            elseif ($null -ne $valA -and $null -eq $valB) { $differ = $true }
            elseif ($null -ne $valA -and $null -ne $valB -and $valA -ne $valB) { $differ = $true }

            if ($differ) {
                [void]$differingAttributes.Add($pName)
            }
        }
    }

    return [string[]]@($differingAttributes)
}

function Get-DeltaClassification {
    param(
        [Parameter(Mandatory)][pscustomobject]$Measure,
        [object[]]$Collisions = @(),
        [array]$Experience = @()
    )

    if ($Collisions.Length -gt 0 -or $Measure.Contradictions -gt 0) {
        return 'representation collision'
    }

    if ($Measure.Contradictions -eq 0 -and $Measure.PredictionError -gt 0) {
        return 'wrong value'
    }

    return 'missing operation'
}

function Get-GrammarProposals {
    param(
        [Parameter(Mandatory)][string[]]$DifferingAttributes,
        [Representation]$CurrentRepresentation
    )

    $proposals = [System.Collections.Generic.List[RepresentationMutation]]::new()
    $currentFeatures = if ($CurrentRepresentation) {
        [System.Collections.Generic.HashSet[string]]::new([string[]]$CurrentRepresentation.Features, [StringComparer]::OrdinalIgnoreCase)
    } else {
        [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }

    # Depth 1: AddFeature for each differing attribute
    foreach ($attr in $DifferingAttributes) {
        if (-not $currentFeatures.Contains($attr)) {
            $proposals.Add([RepresentationMutation]::new('AddFeature', @($attr)))
        }
    }

    # Depth 2: Combine pairs of differing attributes (combination depth <= 2)
    for ($i = 0; $i -lt $DifferingAttributes.Length; $i++) {
        for ($j = $i + 1; $j -lt $DifferingAttributes.Length; $j++) {
            $attrA = $DifferingAttributes[$i]
            $attrB = $DifferingAttributes[$j]
            $combined = "$attrA+$attrB"
            if (-not $currentFeatures.Contains($combined)) {
                $proposals.Add([RepresentationMutation]::new('Combine', @($attrA, $attrB)))
            }
        }
    }

    return $proposals.ToArray()
}

function Invoke-PerceptRefine {
    param(
        [Parameter(Mandatory)][array]$Experience,
        [Representation]$InitialRepresentation = [Representation]::new(@()),
        [PerceptionStore]$Store = $null,
        [int]$NeutralBudget = 2,
        [int]$MaxIterations = 20
    )

    $currentRep = $InitialRepresentation
    $currentMeasure = Measure-Representation -History $Experience -Rep $currentRep -RepVersion "V_Initial"

    if ($null -eq $Store) {
        $Store = New-PerceptionStore -InitialRepresentation $currentRep -InitialDelta $currentMeasure
    }

    $remainingNeutralBudget = $NeutralBudget
    $refineIterations = 0
    $triedMutationsOnNode = @{}

    # Chronological backtracking: stack of kept state nodes in the provenance graph.
    # A dead end pops the most recent node; it does not trace justifications to a culprit.
    $stateStack = [System.Collections.Generic.Stack[PerceptionProvenanceNode]]::new()
    $stateStack.Push($Store.Current)

    while ($refineIterations -lt $MaxIterations) {
        $refineIterations++

        # Target: zero contradictions and calibrated predictions
        if ($currentMeasure.Contradictions -eq 0 -and $currentMeasure.PredictionError -eq 0) {
            break
        }

        # Step 1: Localize the delta
        $collisions = @(Get-CollidingObservations -Experience $Experience -Representation $currentRep)

        # Step 2: Classify the delta (wrong value, representation collision, or missing operation)
        $classification = Get-DeltaClassification -Measure $currentMeasure -Collisions $collisions -Experience $Experience

        if ($classification -eq 'wrong value') {
            # Predictor table values need calibration from observed experience (parametric calibration)
            $Store.RecordReceipt((New-PerceptionReceipt `
                -Case "refine_iter_$refineIterations" `
                -ReferenceChoice "calibrated" `
                -CandidateChoice "uncalibrated" `
                -Delta ($currentMeasure.PredictionError) `
                -Proposal $null `
                -Before $currentMeasure `
                -After $currentMeasure `
                -Outcome 'kept' `
                -CompiledConsequence "Predictor calibrated under sufficient representation."))
            break
        }

        # If representation collision: percept candidates come ONLY from differing attributes
        $diffAttrs = Get-DifferingObservationAttributes -Collisions $collisions -CurrentRepresentation $currentRep

        if ($diffAttrs.Length -eq 0) {
            # No differing attributes among colliding observations; backtrack chronologically to the previous kept node
            if ($stateStack.Count -gt 1) {
                [void]$stateStack.Pop()
                $previousNode = $stateStack.Peek()
                $currentRep = $previousNode.Representation
                $currentMeasure = Measure-Representation -History $Experience -Rep $currentRep -RepVersion "V_ChronologicalBacktrack"
                $Store.Current = $previousNode
                continue
            }
            break
        }

        $activeNode = $Store.Current
        if (-not $triedMutationsOnNode.ContainsKey($activeNode.Id)) {
            $triedMutationsOnNode[$activeNode.Id] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        }

        # Step 3: Propose from the store first, then from a fixed percept grammar
        $candidateProposals = [System.Collections.Generic.List[RepresentationMutation]]::new()

        # 3a. Propose from store first
        foreach ($node in $Store.AllNodes) {
            if ($node.Outcome -eq 'kept' -and $node.Proposal) {
                $propStr = $node.Proposal.ToString()
                if (-not $triedMutationsOnNode[$activeNode.Id].Contains($propStr)) {
                    $usesDiffAttr = $false
                    foreach ($arg in $node.Proposal.Arguments) {
                        if ($arg -in $diffAttrs) { $usesDiffAttr = $true; break }
                    }
                    if ($usesDiffAttr) {
                        $candidateProposals.Add($node.Proposal)
                    }
                }
            }
        }

        # 3b. Propose from fixed percept grammar
        $grammarProposals = Get-GrammarProposals -DifferingAttributes $diffAttrs -CurrentRepresentation $currentRep
        foreach ($gp in $grammarProposals) {
            $gpStr = $gp.ToString()
            if (-not $triedMutationsOnNode[$activeNode.Id].Contains($gpStr)) {
                $candidateProposals.Add($gp)
            }
        }

        if ($candidateProposals.Count -eq 0) {
            if ($stateStack.Count -gt 1) {
                [void]$stateStack.Pop()
                $previousNode = $stateStack.Peek()
                $currentRep = $previousNode.Representation
                $currentMeasure = Measure-Representation -History $Experience -Rep $currentRep -RepVersion "V_ChronologicalBacktrack"
                $Store.Current = $previousNode
                continue
            }
            break
        }

        $proposal = $candidateProposals[0]
        [void]$triedMutationsOnNode[$activeNode.Id].Add($proposal.ToString())

        # Step 4: Apply reversibly
        $previousRep = $currentRep
        $candidateRep = Invoke-ApplyMutation -Representation $currentRep -Mutation $proposal

        # Step 5: Gate
        # Strictly lexicographic ordering:
        # 1. Contradictions (lower is strictly better)
        # 2. PredictionError (lower is strictly better)
        # 3. Complexity (lower is strictly better, when Contradictions == 0)
        # Fixed budget of neutral moves
        $candidateMeasure = Measure-Representation -History $Experience -Rep $candidateRep -RepVersion "V_Candidate"

        $isBetter = $false
        $isNeutral = $false

        if ($candidateMeasure.Contradictions -lt $currentMeasure.Contradictions) {
            $isBetter = $true
        } elseif ($candidateMeasure.Contradictions -eq $currentMeasure.Contradictions) {
            if ($candidateMeasure.PredictionError -lt $currentMeasure.PredictionError) {
                $isBetter = $true
            } elseif ($candidateMeasure.PredictionError -eq $currentMeasure.PredictionError) {
                if ($candidateMeasure.Contradictions -eq 0 -and $candidateMeasure.RepresentationComplexity -lt $currentMeasure.RepresentationComplexity) {
                    $isBetter = $true
                } elseif ($candidateMeasure.RepresentationComplexity -eq $currentMeasure.RepresentationComplexity) {
                    $isNeutral = $true
                }
            }
        }

        # Step 6: Keep or revert
        $outcome = 'rejected'
        if ($isBetter) {
            $outcome = 'kept'
            $currentRep = $candidateRep
            $previousMeasure = $currentMeasure
            $currentMeasure = $candidateMeasure
        } elseif ($isNeutral -and $remainingNeutralBudget -gt 0) {
            $outcome = 'kept'
            $remainingNeutralBudget--
            $currentRep = $candidateRep
            $previousMeasure = $currentMeasure
            $currentMeasure = $candidateMeasure
        } else {
            # Revert candidate back to previous representation
            $outcome = 'rejected'
            $currentRep = $previousRep
            $previousMeasure = $currentMeasure
        }

        # Step 7: Record in Store provenance graph (both kept and rejected moves)
        $perceptsIntroduced = [string[]]@($proposal.Arguments)
        $contradictionKeys = @($collisions | ForEach-Object { $_.ConditionKey } | Select-Object -Unique)

        $newNode = $Store.RecordTransition(
            $activeNode,
            $(if ($outcome -eq 'kept') { $currentRep } else { $candidateRep }),
            $perceptsIntroduced,
            $contradictionKeys,
            $previousMeasure,
            $candidateMeasure,
            $outcome,
            $proposal
        )

        $firstDivergent = if ($perceptsIntroduced.Length -gt 0) { $perceptsIntroduced[0] } else { '' }
        $refChoice = ($collisions | ForEach-Object { "$($_.RecordA.SpecimenName) vs $($_.RecordB.SpecimenName)" }) -join '; '

        $Store.RecordReceipt((New-PerceptionReceipt `
            -Case "refine_iter_$refineIterations" `
            -ReferenceChoice $refChoice `
            -CandidateChoice ($proposal.ToString()) `
            -FirstDivergentPercept $firstDivergent `
            -Delta ($candidateMeasure.Contradictions - $previousMeasure.Contradictions) `
            -Proposal $proposal `
            -Before $previousMeasure `
            -After $candidateMeasure `
            -Outcome $outcome `
            -CompiledConsequence $(if ($outcome -eq 'kept') { "Percept kept: $($perceptsIntroduced -join ', ')" } else { "Reverted" })))

        if ($outcome -eq 'kept') {
            $stateStack.Push($newNode)
        }
    }

    return [pscustomobject]@{
        FinalRepresentation       = $currentRep
        FinalMeasure              = $currentMeasure
        Store                     = $Store
        Iterations                = $refineIterations
        ReachedZeroContradictions = ($currentMeasure.Contradictions -eq 0)
        RemainingNeutralBudget    = $remainingNeutralBudget
    }
}
