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
. (Join-Path $PSScriptRoot 'Analogy.ps1')
. (Join-Path $PSScriptRoot 'Expectations.ps1')

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

    $currentFeatures = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $CurrentRepresentation) {
        foreach ($feature in $CurrentRepresentation.Features) { [void]$currentFeatures.Add($feature) }
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
    $currentFeatures = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $CurrentRepresentation) {
        foreach ($feature in $CurrentRepresentation.Features) { [void]$currentFeatures.Add($feature) }
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
        [int]$MaxIterations = 20,
        [scriptblock]$MeasureRepresentation = $null,
        [switch]$GreedyBest,
        [ValidateRange(1,100)][int]$MaxAdmissions = 100
    )

    $measure=if ($null -ne $MeasureRepresentation) {$MeasureRepresentation} else {'Measure-Representation'}
    $currentRep = $InitialRepresentation
    $currentMeasure = & $measure -History $Experience -Rep $currentRep -RepVersion "V_Initial"

    if ($null -eq $Store) {
        $Store = New-PerceptionStore -InitialRepresentation $currentRep -InitialDelta $currentMeasure
    } else {
        # A new specimen may start with a different projection. Preserve learned
        # ancestry while recording the caller's baseline using existing mutations.
        $baseline=$Store.Current.Representation
        foreach ($feature in @($baseline.Features)) {
            if ($feature -notin $currentRep.Features) {
                $reset=[RepresentationMutation]::new('RemoveFeature',@($feature))
                $baseline=Invoke-ApplyMutation $baseline $reset
                [void]$Store.RecordTransition($Store.Current,$baseline,@(),@(),$Store.Current.DeltaAfter,$currentMeasure,'kept',$reset)
            }
        }
        foreach ($feature in $currentRep.Features) {
            if ($feature -notin $baseline.Features) {
                $reset=[RepresentationMutation]::new('AddFeature',@($feature))
                $baseline=Invoke-ApplyMutation $baseline $reset
                [void]$Store.RecordTransition($Store.Current,$baseline,@(),@(),$Store.Current.DeltaAfter,$currentMeasure,'kept',$reset)
            }
        }
    }

    $remainingNeutralBudget = $NeutralBudget
    $refineIterations = 0
    $triedMutationsOnNode = @{}
    $candidateEvaluations = 0
    $reusedRejections = 0
    $admissions = 0

    # Chronological backtracking: stack of kept state nodes in the provenance graph.
    # A dead end pops the most recent node; it does not trace justifications to a culprit.
    $stateStack = [System.Collections.Generic.Stack[PerceptionProvenanceNode]]::new()
    $stateStack.Push($Store.Current)

    while ($refineIterations -lt $MaxIterations) {
        $refineIterations++

        # Capture predictions before their corresponding outcomes in the replay.
        # Observation adapters may supply data-only structural justification;
        # the engine owns expectation construction, attribution, and retrieval.
        $attributions=[Collections.Generic.List[object]]::new()
        for ($i=0;$i -lt $Experience.Count;$i++) {
            $record=$Experience[$i];$prediction=$currentMeasure.ReplayHistory[$i]
            $claims=@();$dependencies=@()
            if ($null -ne $record.PSObject.Properties['Justifications']) { $claims=@($record.Justifications) }
            if ($null -ne $record.PSObject.Properties['ActiveAssumptions']) { $dependencies=@($record.ActiveAssumptions) }
            $claims+= [pscustomobject]@{Id='/refine/prediction';DependsOn=$dependencies;Relation=$null;From=$null;To=$null}
            $expected=[Convert]::ToString($prediction.PredictedDelta,[Globalization.CultureInfo]::InvariantCulture)
            $observed=[Convert]::ToString($prediction.ActualDelta,[Globalization.CultureInfo]::InvariantCulture)
            $expectation=New-PerceptExpectation -Specimen $record.SpecimenName -RepresentationId $Store.Current.Id -PredictedOutcome $expected -ActiveAssumptions @('/refine/prediction') -Justifications $claims
            $surprise=Measure-PerceptSurprise $expectation $observed
            $attribution=Get-SurpriseAttribution $surprise
            if ($surprise.Mismatch) { $attributions.Add($attribution) }
            $Store.RecordReceipt((New-PerceptionReceipt -Case ('prediction:'+ $record.SpecimenName) -ReferenceChoice $observed -CandidateChoice $expected -Before $expectation -After $surprise -Outcome $(if ($surprise.Mismatch) {'rejected'} else {'kept'}) -CompiledConsequence $attribution))
        }
        $pattern=@()
        foreach ($attribution in $attributions) {
            if ($attribution.Pattern.Count -gt 0) { $pattern=$attribution.Pattern;break }
        }

        # Target: zero contradictions and calibrated predictions
        if ($currentMeasure.Contradictions -eq 0 -and $currentMeasure.PredictionError -eq 0) {
            break
        }

        # Step 1: Localize the delta
        $collisions = @(Get-CollidingObservations -Experience $Experience -Representation $currentRep)

        # Step 2: Classify the delta (wrong value, representation collision, or missing operation)
        $classification = Get-DeltaClassification -Measure $currentMeasure -Collisions $collisions -Experience $Experience

        if ($classification -eq 'wrong value' -and $null -eq $MeasureRepresentation) {
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
        if ($null -ne $currentMeasure.PSObject.Properties['CandidateAttributes']) {
            $diffAttrs=[string[]]@($diffAttrs | Where-Object {$_ -cin $currentMeasure.CandidateAttributes})
        }
        if ($null -ne $currentMeasure.PSObject.Properties['FeaturePriority']) {
            $priority=[string[]]@($currentMeasure.FeaturePriority)
            $diffAttrs=[string[]]@($diffAttrs | Sort-Object @{Expression={ $index=[array]::IndexOf($priority,$_);if ($index -lt 0) {2147483647} else {$index} }})
        }

        if ($diffAttrs.Length -eq 0) {
            # No differing attributes among colliding observations; backtrack chronologically to the previous kept node
            if ($stateStack.Count -gt 1) {
                [void]$stateStack.Pop()
                $previousNode = $stateStack.Peek()
                $currentRep = $previousNode.Representation
                $currentMeasure = & $measure -History $Experience -Rep $currentRep -RepVersion "V_ChronologicalBacktrack"
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

        if ($pattern.Count -gt 0) {
            $retrieved=Get-AnalogicalPerceptProposals -Pattern $pattern -Store $Store -InferRelationBindings
            foreach ($bound in $retrieved.Proposals) {
                $candidate=$bound.Mutation
                if (@($candidate.Arguments | Where-Object { $_ -notin $diffAttrs }).Count -eq 0 -and -not $triedMutationsOnNode[$activeNode.Id].Contains($candidate.ToString())) {
                    $candidateProposals.Add($candidate)
                }
            }
        }

        # 3a. Propose from store first
        $node=$Store.Current;$nodesVisited=0
        while ($null -ne $node -and $nodesVisited++ -lt 256) {
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
            $node=if ($node.Parents.Count -gt 0) {$node.Parents[0]} else {$null}
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
                $currentMeasure = & $measure -History $Experience -Rep $currentRep -RepVersion "V_ChronologicalBacktrack"
                $Store.Current = $previousNode
                continue
            }
            break
        }

        # Existing rejection identities cover the default judge only.
        $evidenceIdentity = if ($null -eq $MeasureRepresentation) { Get-RefinementEvidenceIdentity -Experience $Experience -Representation $currentRep } elseif ($null -ne $currentMeasure.PSObject.Properties['EvidenceIdentity']) { $currentMeasure.EvidenceIdentity } else { '' }
        $proposal = $null
        $selectedMeasure=$null;$selectedRep=$null
        $evaluated=[Collections.Generic.List[object]]::new()
        foreach ($candidate in $candidateProposals) {
            if ($null -ne $currentMeasure.PSObject.Properties['AllowedMutationVerbs'] -and $candidate.Verb -cnotin $currentMeasure.AllowedMutationVerbs) { continue }
            if ($triedMutationsOnNode[$activeNode.Id].Contains($candidate.ToString())) { continue }
            $priorEvidence = Get-PerceptProposalHistory -Mutation $candidate -Store $Store -EvidenceIdentity $evidenceIdentity
            if ($priorEvidence.ReusableRejections -gt 0) {
                $reusedRejections++
                [void]$triedMutationsOnNode[$activeNode.Id].Add($candidate.ToString())
                continue
            }
            if (-not $GreedyBest) { $proposal=$candidate;break }
            [void]$triedMutationsOnNode[$activeNode.Id].Add($candidate.ToString())
            $candidate.EvidenceIdentity=$evidenceIdentity
            $candidate.Pattern=@($pattern);$candidate.Evidence=[string[]]@($Experience.SpecimenName)
            $testedRep=Invoke-ApplyMutation $currentRep $candidate
            $testedMeasure=& $measure -History $Experience -Rep $testedRep -RepVersion 'V_Candidate'
            $candidateEvaluations++
            $allowed=($null -eq $testedMeasure.PSObject.Properties['AdmissionAllowed'] -or $testedMeasure.AdmissionAllowed)
            $improves=($testedMeasure.Contradictions -lt $currentMeasure.Contradictions -or ($testedMeasure.Contradictions -eq $currentMeasure.Contradictions -and $testedMeasure.PredictionError -lt $currentMeasure.PredictionError))
            $evaluated.Add([pscustomobject]@{Proposal=$candidate;Representation=$testedRep;Measure=$testedMeasure;Reusable=(-not ($allowed -and $improves))})
            if ($allowed -and $improves -and ($null -eq $selectedMeasure -or $testedMeasure.Contradictions -lt $selectedMeasure.Contradictions -or ($testedMeasure.Contradictions -eq $selectedMeasure.Contradictions -and ($testedMeasure.PredictionError -lt $selectedMeasure.PredictionError -or ($testedMeasure.PredictionError -eq $selectedMeasure.PredictionError -and $testedMeasure.RepresentationComplexity -lt $selectedMeasure.RepresentationComplexity))))) {
                $proposal=$candidate;$selectedMeasure=$testedMeasure;$selectedRep=$testedRep
            }
        }
        foreach ($tested in $evaluated) {
            if ([object]::ReferenceEquals($tested.Proposal,$proposal)) { continue }
            $tested.Proposal.ReusableRejection=$tested.Reusable
            [void]$Store.RecordTransition($activeNode,$tested.Representation,$tested.Proposal.Arguments,$attributions.ToArray(),$currentMeasure,$tested.Measure,'rejected',$tested.Proposal)
        }
        if ($null -eq $proposal) { if ($GreedyBest) {break};continue }
        $proposal.EvidenceIdentity = $evidenceIdentity
        $proposal.Pattern=@($pattern)
        $proposal.Evidence=[string[]]@($Experience.SpecimenName)
        [void]$triedMutationsOnNode[$activeNode.Id].Add($proposal.ToString())

        # Step 4: Apply reversibly
        $previousRep = $currentRep
        $candidateRep = if ($null -ne $selectedRep) {$selectedRep} else {Invoke-ApplyMutation -Representation $currentRep -Mutation $proposal}

        # Step 5: Gate
        # Strictly lexicographic ordering:
        # 1. Contradictions (lower is strictly better)
        # 2. PredictionError (lower is strictly better)
        # 3. Complexity (lower is strictly better, when Contradictions == 0)
        # Fixed budget of neutral moves
        $candidateMeasure = if ($null -ne $selectedMeasure) {$selectedMeasure} else {& $measure -History $Experience -Rep $candidateRep -RepVersion 'V_Candidate'}
        if ($null -eq $selectedMeasure) { $candidateEvaluations++ }

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

        if ($null -ne $candidateMeasure.PSObject.Properties['AdmissionAllowed'] -and -not $candidateMeasure.AdmissionAllowed) { $isBetter=$false;$isNeutral=$false }
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
        # Neutral-budget rejection is not evidence of a failed distinction.
        $proposal.ReusableRejection = ($outcome -eq 'rejected' -and -not $isNeutral)
        $perceptsIntroduced = [string[]]@($proposal.Arguments)
        $contradictionKeys = @($collisions | ForEach-Object { $_.ConditionKey } | Select-Object -Unique)+$attributions.ToArray()

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
            $admissions++
            if ($admissions -ge $MaxAdmissions) { break }
        }
    }

    return [pscustomobject]@{
        FinalRepresentation       = $currentRep
        FinalMeasure              = $currentMeasure
        Store                     = $Store
        Iterations                = $refineIterations
        ReachedZeroContradictions = ($currentMeasure.Contradictions -eq 0)
        RemainingNeutralBudget    = $remainingNeutralBudget
        CandidateEvaluations      = $candidateEvaluations
        ReusedRejections          = $reusedRejections
        Admissions                = $admissions
    }
}
