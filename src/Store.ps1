# Store.ps1 - In-memory provenance graph of live objects for percept refinement.
#
# Records every kept and rejected move in a provenance graph.
# No JSON anywhere. No regex.

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Representation.ps1')
. (Join-Path $PSScriptRoot 'Proposal.ps1')

class PerceptionProvenanceNode {
    [string]$Id
    [System.Collections.Generic.List[PerceptionProvenanceNode]]$Parents
    [System.Collections.Generic.List[PerceptionProvenanceNode]]$Dependents
    [string[]]$PerceptsIntroduced
    [object[]]$JustifyingContradictions
    [object]$DeltaBefore
    [object]$DeltaAfter
    [string]$Outcome  # 'kept', 'rejected', 'inapplicable'
    [object]$Proposal
    [Representation]$Representation

    PerceptionProvenanceNode(
        [string]$id,
        [Representation]$representation,
        [string[]]$perceptsIntroduced,
        [object[]]$justifyingContradictions,
        [object]$deltaBefore,
        [object]$deltaAfter,
        [string]$outcome,
        [object]$proposal
    ) {
        $this.Id = $id
        $this.Representation = $representation
        $this.Parents = [System.Collections.Generic.List[PerceptionProvenanceNode]]::new()
        $this.Dependents = [System.Collections.Generic.List[PerceptionProvenanceNode]]::new()
        $this.PerceptsIntroduced = if ($perceptsIntroduced) { [string[]]@($perceptsIntroduced) } else { [string[]]@() }
        $this.JustifyingContradictions = if ($justifyingContradictions) { [object[]]@($justifyingContradictions) } else { [object[]]@() }
        $this.DeltaBefore = $deltaBefore
        $this.DeltaAfter = $deltaAfter
        $this.Outcome = $outcome
        $this.Proposal = $proposal
    }
}

class PerceptionReceipt {
    [string]$Case
    [object]$ReferenceChoice
    [object]$CandidateChoice
    [string]$FirstDivergentPercept
    [object]$Delta
    [object]$Proposal
    [object]$Before
    [object]$After
    [string]$Outcome
    [object]$CompiledConsequence

    PerceptionReceipt(
        [string]$caseId,
        [object]$referenceChoice,
        [object]$candidateChoice,
        [string]$firstDivergentPercept,
        [object]$delta,
        [object]$proposal,
        [object]$before,
        [object]$after,
        [string]$outcome,
        [object]$compiledConsequence
    ) {
        $this.Case = $caseId
        $this.ReferenceChoice = $referenceChoice
        $this.CandidateChoice = $candidateChoice
        $this.FirstDivergentPercept = $firstDivergentPercept
        $this.Delta = $delta
        $this.Proposal = $proposal
        $this.Before = $before
        $this.After = $after
        $this.Outcome = $outcome
        $this.CompiledConsequence = $compiledConsequence
    }
}

class PerceptionStore {
    [PerceptionProvenanceNode]$Root
    [PerceptionProvenanceNode]$Current
    [System.Collections.Generic.List[PerceptionProvenanceNode]]$AllNodes
    [System.Collections.Generic.List[PerceptionReceipt]]$Receipts
    [int]$NextId

    PerceptionStore([Representation]$initialRepresentation, [object]$initialDelta) {
        $this.NextId = 0
        $this.AllNodes = [System.Collections.Generic.List[PerceptionProvenanceNode]]::new()
        $this.Receipts = [System.Collections.Generic.List[PerceptionReceipt]]::new()
        $id = "state_" + $this.NextId
        $this.NextId = $this.NextId + 1
        $this.Root = [PerceptionProvenanceNode]::new(
            $id,
            $initialRepresentation,
            @(),
            @(),
            $null,
            $initialDelta,
            'kept',
            $null
        )
        $this.Current = $this.Root
        $this.AllNodes.Add($this.Root)
    }

    [PerceptionProvenanceNode] RecordTransition(
        [PerceptionProvenanceNode]$parentNode,
        [Representation]$resultingRepresentation,
        [string[]]$perceptsIntroduced,
        [object[]]$justifyingContradictions,
        [object]$deltaBefore,
        [object]$deltaAfter,
        [string]$outcome,
        [object]$proposal
    ) {
        if ($outcome -notin @('kept', 'rejected', 'inapplicable')) {
            throw "Invalid outcome: '$outcome'. Must be 'kept', 'rejected', or 'inapplicable'."
        }

        $id = "state_" + $this.NextId
        $this.NextId = $this.NextId + 1
        $node = [PerceptionProvenanceNode]::new(
            $id,
            $resultingRepresentation,
            $perceptsIntroduced,
            $justifyingContradictions,
            $deltaBefore,
            $deltaAfter,
            $outcome,
            $proposal
        )

        if ($parentNode) {
            $node.Parents.Add($parentNode)
            $parentNode.Dependents.Add($node)
        }

        $this.AllNodes.Add($node)

        if ($outcome -eq 'kept') {
            $this.Current = $node
        }

        return $node
    }

    [void] RecordReceipt([PerceptionReceipt]$receipt) {
        $this.Receipts.Add($receipt)
    }

    [string[]] GetKeptPercepts() {
        $percepts = [System.Collections.Generic.List[string]]::new()
        $path = [System.Collections.Generic.List[PerceptionProvenanceNode]]::new()
        $curr = $this.Current
        while ($curr) {
            $path.Add($curr)
            if ($curr.Parents.Count -gt 0) {
                $curr = $curr.Parents[0]
            } else {
                break
            }
        }
        $path.Reverse()
        foreach ($n in $path) {
            foreach ($p in $n.PerceptsIntroduced) {
                if (-not $percepts.Contains($p)) {
                    $percepts.Add($p)
                }
            }
        }
        return $percepts.ToArray()
    }

    [PerceptionProvenanceNode[]] GetRejectedTransitions() {
        $rejected = [System.Collections.Generic.List[PerceptionProvenanceNode]]::new()
        foreach ($node in $this.AllNodes) {
            if ($node.Outcome -eq 'rejected') {
                $rejected.Add($node)
            }
        }
        return $rejected.ToArray()
    }

    [Representation] ReplayFromScratch() {
        $rep = [Representation]::new([string[]]@($this.Root.Representation.Features))
        $path = [System.Collections.Generic.List[PerceptionProvenanceNode]]::new()
        $curr = $this.Current
        while ($curr -and $curr.Id -ne $this.Root.Id) {
            $path.Add($curr)
            if ($curr.Parents.Count -gt 0) {
                $curr = $curr.Parents[0]
            } else {
                break
            }
        }
        $path.Reverse()

        foreach ($node in $path) {
            if ($node.Outcome -eq 'kept') {
                if ($node.Proposal) {
                    $rep = Invoke-ApplyMutation -Representation $rep -Mutation $node.Proposal
                } elseif ($node.PerceptsIntroduced.Length -gt 0) {
                    $mut = [RepresentationMutation]::new('AddFeature', $node.PerceptsIntroduced)
                    $rep = Invoke-ApplyMutation -Representation $rep -Mutation $mut
                }
            }
        }

        return $rep
    }
}

function New-PerceptionStore {
    param(
        [Parameter(Mandatory)][Representation]$InitialRepresentation,
        [Parameter(Mandatory)][object]$InitialDelta
    )
    return [PerceptionStore]::new($InitialRepresentation, $InitialDelta)
}

function New-PerceptionReceipt {
    param(
        [Parameter(Mandatory)][string]$Case,
        [object]$ReferenceChoice,
        [object]$CandidateChoice,
        [string]$FirstDivergentPercept = '',
        [object]$Delta,
        [object]$Proposal,
        [object]$Before,
        [object]$After,
        [Parameter(Mandatory)][string]$Outcome,
        [object]$CompiledConsequence = $null
    )

    return [PerceptionReceipt]::new(
        $Case,
        $ReferenceChoice,
        $CandidateChoice,
        $FirstDivergentPercept,
        $Delta,
        $Proposal,
        $Before,
        $After,
        $Outcome,
        $CompiledConsequence
    )
}
