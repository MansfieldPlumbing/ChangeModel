Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Refine.ps1')
. (Join-Path $root 'src\Expectations.ps1')
$checks=0
function Assert-Transfer([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message };$script:checks++ }

function New-SpecimenFamily {
    param([string[]]$Roles,[string[]]$Relations,[string[]]$Outcomes,[string]$Prefix,[int]$OutcomePosition=1)
    $pattern=@(for ($i=0;$i -lt 3;$i++) { [pscustomobject]@{Relation=$Relations[$i];From=$Roles[$i];To=$Roles[$i+1]} })
    $learning=[Collections.Generic.List[object]]::new();$heldout=[Collections.Generic.List[object]]::new()
    # Complete binary product: only one role determines the reference outcome.
    # The role index is used by the fixture producer and never supplied to the core.
    for ($i=0;$i -lt 16;$i++) {
        $state=[pscustomobject]@{}
        for ($j=0;$j -lt 4;$j++) { $state | Add-Member -NotePropertyName $Roles[$j] -NotePropertyValue (($i -shr $j) -band 1) }
        $row=[pscustomobject]@{Specimen=$Prefix+$i;State=$state;Outcome=$Outcomes[(($i -shr $OutcomePosition) -band 1)]}
        if (($i -band 1) -eq 0) { $learning.Add($row) } else { $heldout.Add($row) }
    }
    [pscustomobject]@{Roles=$Roles;Pattern=$pattern;InitialExpectation=$Outcomes[1];Learning=$learning.ToArray();Heldout=$heldout.ToArray()}
}

function Test-FrozenBehavioralAdmission {
    param([RepresentationMutation]$Mutation,$Family)
    if ($Mutation.Verb -cne 'AddFeature' -or $Mutation.Arguments.Count -ne 1) { return $false }
    $role=$Mutation.Arguments[0]
    if ($role -cnotin $Family.Roles) { return $false }
    # Independent judge: the proposed projection must preserve a deterministic
    # observed dependency and predict every withheld combination from learning support.
    foreach ($a in $Family.Learning) { foreach ($b in $Family.Learning) {
        if ($a.State.$role -eq $b.State.$role -and $a.Outcome -cne $b.Outcome) { return $false }
    } }
    foreach ($row in $Family.Heldout) {
        $support=@($Family.Learning | Where-Object { $_.State.$role -eq $row.State.$role })
        if ($support.Count -eq 0) { return $false }
        foreach ($prior in $support) { if ($prior.Outcome -cne $row.Outcome) { return $false } }
    }
    return $true
}

function Invoke-FixedProposalSearch {
    param($Family,[object[]]$PriorProposals=@())
    $initial=[Representation]::new([string[]]@())
    $queue=[Collections.Generic.List[RepresentationMutation]]::new()
    foreach ($prior in $PriorProposals) { $queue.Add($prior.Mutation) }
    # Keep the existing grammar restriction: attributes must differ in actual
    # colliding learning observations. Withheld outcomes never steer proposals.
    $differences=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($a in $Family.Learning) { foreach ($b in $Family.Learning) {
        if ($a.Outcome -ceq $b.Outcome) { continue }
        foreach ($role in $Family.Roles) { if ($a.State.$role -ne $b.State.$role) { [void]$differences.Add($role) } }
    } }
    foreach ($candidate in (Get-GrammarProposals -DifferingAttributes ([string[]]@($differences)) -CurrentRepresentation $initial)) { $queue.Add($candidate) }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $evaluations=0;$rejected=[Collections.Generic.List[object]]::new()
    foreach ($candidate in $queue) {
        if (-not $seen.Add($candidate.ToString())) { continue }
        $evaluations++
        if (Test-FrozenBehavioralAdmission $candidate $Family) {
            return [pscustomobject]@{Mutation=$candidate;Representation=(Invoke-ApplyMutation $initial $candidate);Evaluations=$evaluations;Rejected=$rejected.ToArray()}
        }
        $rejected.Add($candidate)
    }
    throw 'Fixed grammar did not produce an admitted projection.'
}

function New-DiscoveryStore {
    param($Family)
    $initial=[Representation]::new([string[]]@())
    $store=New-PerceptionStore -InitialRepresentation $initial -InitialDelta ([pscustomobject]@{Explained=$false})
    $claims=@(for ($i=0;$i -lt $Family.Pattern.Count;$i++) {
        $edge=$Family.Pattern[$i]
        [pscustomobject]@{Id='claim-'+$i;DependsOn=$(if ($i+1 -lt $Family.Pattern.Count) {@('claim-'+($i+1))} else {@()});Relation=$edge.Relation;From=$edge.From;To=$edge.To}
    })
    $expectation=New-PerceptExpectation -Specimen $Family.Learning[0].Specimen -RepresentationId $store.Current.Id -PredictedOutcome $Family.InitialExpectation -ActiveAssumptions @('claim-0') -Justifications $claims
    $surprise=Measure-PerceptSurprise $expectation $Family.Learning[0].Outcome
    Assert-Transfer $surprise.Mismatch 'Discovery did not begin with an actual unexpected outcome.'
    $attribution=Get-SurpriseAttribution $surprise
    $discovery=Invoke-FixedProposalSearch $Family
    $discovery.Mutation.Pattern=$attribution.Pattern
    $discovery.Mutation.Evidence=[string[]]@(($Family.Learning+$Family.Heldout).Specimen)
    foreach ($failed in $discovery.Rejected) {
        [void]$store.RecordTransition($store.Current,(Invoke-ApplyMutation $initial $failed),$failed.Arguments,@($expectation.Specimen),$false,$false,'rejected',$failed)
    }
    [void]$store.RecordTransition($store.Current,$discovery.Representation,$discovery.Mutation.Arguments,@($expectation.Specimen),$false,$true,'kept',$discovery.Mutation)
    return $store
}

$discovery=New-SpecimenFamily @('d9','j1','t7','a4') @('h','x','k') @('c0','c1') 'discovery-'
$transfer=New-SpecimenFamily @('r4','z3','b8','m2') @('v','n','w') @('e0','e1') 'transfer-'
$transfer.Pattern=@($transfer.Pattern[2],$transfer.Pattern[0],$transfer.Pattern[1])
Assert-Transfer (@($discovery.Roles | Where-Object { $_ -cin $transfer.Roles }).Count -eq 0) 'Role identities overlap.'
Assert-Transfer (@($discovery.Pattern.Relation | Where-Object { $_ -cin $transfer.Pattern.Relation }).Count -eq 0) 'Relation identities overlap.'
Assert-Transfer (@(($discovery.Learning+$discovery.Heldout).Specimen | Where-Object { $_ -cin ($transfer.Learning+$transfer.Heldout).Specimen }).Count -eq 0) 'Specimen identities overlap.'
Assert-Transfer (@($discovery.Learning.Outcome | Where-Object { $_ -cin $transfer.Learning.Outcome }).Count -eq 0) 'Outcome identities overlap.'
$store=New-DiscoveryStore $discovery
$fresh=Invoke-FixedProposalSearch $transfer
$retrieved=Get-AnalogicalPerceptProposals $transfer.Pattern $store -InferRelationBindings
Assert-Transfer ($retrieved.Proposals.Count -eq 1 -and $retrieved.Proposals[0].RelationBindings.Count -eq 3) 'Topology did not infer role and relation bindings.'
Assert-Transfer ($retrieved.Proposals[0].RelationEquivalence -ceq 'NotProved') 'Structural hypothesis claimed semantic equivalence.'
$experienced=Invoke-FixedProposalSearch $transfer $retrieved.Proposals
Assert-Transfer ($experienced.Evaluations -lt $fresh.Evaluations) 'Prior experience did not reduce unseen candidate evaluations.'
Assert-Transfer ($experienced.Mutation.Arguments[0] -ceq $fresh.Mutation.Arguments[0]) 'Transfer changed the correct admitted result.'

$mismatch=@(
    [pscustomobject]@{Relation='v';From='r4';To='z3'},
    [pscustomobject]@{Relation='n';From='r4';To='b8'},
    [pscustomobject]@{Relation='w';From='r4';To='m2'}
)
$blocked=Get-AnalogicalPerceptProposals $mismatch $store -InferRelationBindings
Assert-Transfer ($blocked.Proposals.Count -eq 0) 'Topology mismatch transferred an explanation.'
$fallback=Invoke-FixedProposalSearch $transfer $blocked.Proposals
Assert-Transfer ($fallback.Evaluations -eq $fresh.Evaluations) 'Blocked transfer altered fresh search.'

$symmetric=New-SpecimenFamily @('f6','q8','s2','l5') @('a','b','c') @('g0','g1') 'symmetric-'
$symmetric.Pattern=@([pscustomobject]@{Relation='p';From='f6';To='q8'},[pscustomobject]@{Relation='p';From='q8';To='f6'})
$symmetricStore=New-DiscoveryStore $symmetric
$ambiguous=@([pscustomobject]@{Relation='y';From='r4';To='z3'},[pscustomobject]@{Relation='y';From='z3';To='r4'})
Assert-Transfer ((Find-PerceptRoleBinding $symmetric.Pattern $ambiguous -InferRelationBindings).Status -ceq 'Ambiguous') 'Ambiguous graph did not abstain.'
Assert-Transfer ((Get-AnalogicalPerceptProposals $ambiguous $symmetricStore -InferRelationBindings).Proposals.Count -eq 0) 'Ambiguous explanation produced a proposal.'

# Same shape can describe different behavior. The judge must reject that transfer.
$differentBehavior=New-SpecimenFamily @('r4','z3','b8','m2') @('v','n','w') @('e0','e1') 'counterexample-' -OutcomePosition 2
Assert-Transfer (-not (Test-FrozenBehavioralAdmission $retrieved.Proposals[0].Mutation $differentBehavior)) 'Isomorphism bypassed behavioral admission.'
$repaired=Invoke-FixedProposalSearch $differentBehavior $retrieved.Proposals
$counterFresh=Invoke-FixedProposalSearch $differentBehavior
Assert-Transfer ($repaired.Mutation.Arguments[0] -ceq $counterFresh.Mutation.Arguments[0]) 'False analogy changed the admitted result.'
'GATE_UNSEEN_ANALOGICAL_SEARCH=PASS; Checks='+$checks
'FreshCandidateEvaluations='+$fresh.Evaluations
'ExperiencedCandidateEvaluations='+$experienced.Evaluations
'SameAdmittedResult=True; SurfaceAndRelationIdentifiersDisjoint=True'
'TopologyMismatch=Blocked; AmbiguousBinding=Abstained; DifferentBehavior=Rejected'
'Scope=Synthetic unseen specimen family; behavioral judge uses withheld combinations; no domain execution or consolidation claim'
