Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Refine.ps1')
. (Join-Path $root 'src\Expectations.ps1')
. (Join-Path $root 'src\Analogy.ps1')
$checks=0
function Assert-That([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message };$script:checks++ }
function Assert-Rejected([scriptblock]$Action,[string]$Message) { $rejected=$false;try { &$Action | Out-Null } catch {$rejected=$true};Assert-That $rejected $Message }
$claims=@(
    [pscustomobject]@{Id='expectation';DependsOn=@('role');Relation='DependsOn';From='Projection';To='ReceiverIdentity'},
    [pscustomobject]@{Id='role';DependsOn=@();Relation='Distinguishes';From='ReceiverIdentity';To='Outcome'},
    [pscustomobject]@{Id='unused';DependsOn=@();Relation='Decorates';From='Comment';To='Projection'}
)
$expectation=New-PerceptExpectation -Specimen 'discovery' -RepresentationId 'r0' -PredictedOutcome 'same' -ActiveAssumptions @('expectation') -Justifications $claims -OutcomeSupport @{same=0.85;different=0.15}
$surprise=Measure-PerceptSurprise $expectation 'different'
Assert-That ([math]::Abs($surprise.SurprisalBits-2.736965594166206) -lt 1e-10) 'Independent surprisal fixture differs.'
$attribution=Get-SurpriseAttribution $surprise
Assert-That ($attribution.ImplicatedAssumptions.Count -eq 2 -and 'unused' -notin $attribution.ImplicatedAssumptions) 'Inactive justification was implicated.'
Assert-That ($attribution.CausalResponsibility -ceq 'Unproved') 'Dependency closure claimed causal proof.'
$deterministic=New-PerceptExpectation -Specimen 'deterministic' -RepresentationId 'r0' -PredictedOutcome 'same'
Assert-That ($null -eq (Measure-PerceptSurprise $deterministic 'different').SurprisalBits) 'A probability was invented.'
Assert-That ((Measure-PerceptSurprise $expectation 'third').SupportStatus -ceq 'OutcomeOutsideDeclaredSupport') 'Unknown outcome was silently assigned zero.'
Assert-That ((Get-SurpriseAttribution (Measure-PerceptSurprise $expectation 'same')).Pattern.Count -eq 0) 'Correct prediction triggered contradiction attribution.'
Assert-Rejected { New-PerceptExpectation -Specimen 'bad' -RepresentationId 'r0' -PredictedOutcome 'same' -OutcomeSupport @{same=0.9;different=0.9} } 'Unnormalized support was accepted.'
$cycle=@([pscustomobject]@{Id='cycle';DependsOn=@('cycle');Relation=$null;From=$null;To=$null})
Assert-Rejected { New-PerceptExpectation -Specimen 'bad' -RepresentationId 'r0' -PredictedOutcome 'same' -Justifications $cycle } 'Cyclic justification was accepted.'
$initial=[Representation]::new([string[]]@('X'))
$store=New-PerceptionStore -InitialRepresentation $initial -InitialDelta ([pscustomobject]@{Contradictions=1})
$mutation=[RepresentationMutation]::new('AddFeature',[string[]]@('ReceiverIdentity'))
$mutation.Pattern=$attribution.Pattern;$mutation.Evidence=@('discovery')
$changed=Invoke-ApplyMutation $initial $mutation
$node=$store.RecordTransition($store.Current,$changed,@('ReceiverIdentity'),@('discovery'),1,0,'kept',$mutation)
$mutation.Pattern[0].From='changed-after-retention'
$mutation.Evidence[0]='changed-after-retention'
Assert-That ($node.Proposal.Pattern[0].From -cne 'changed-after-retention' -and $node.Proposal.Evidence[0] -ceq 'discovery') 'Store explanation shared mutable proposal inputs.'
$target=@(
    [pscustomobject]@{Relation='Distinguishes';From='GrammaticalRole';To='Pronunciation'},
    [pscustomobject]@{Relation='DependsOn';From='Phrase';To='GrammaticalRole'}
)
$retrieval=Get-AnalogicalPerceptProposals $target $store
Assert-That ($retrieval.Proposals.Count -eq 1) 'Renamed, reordered graph did not retrieve its percept.'
Assert-That ($retrieval.Proposals[0].Mutation.Arguments[0] -ceq 'GrammaticalRole') 'Mutation was not rebound structurally.'
Assert-That ($retrieval.Admission -ceq 'NotPerformed') 'Retrieval claimed admission.'
Assert-That ((Get-AnalogicalPerceptProposals $target $store -NodeBudget 1).SearchStatus -ceq 'NodeBudgetExhausted') 'Ancestry traversal ignored its budget.'
$broken=@(
    [pscustomobject]@{Relation='Distinguishes';From='GrammaticalRole';To='Pronunciation'},
    [pscustomobject]@{Relation='DependsOn';From='Phrase';To='DifferentRole'}
)
Assert-That ((Get-AnalogicalPerceptProposals $broken $store).Proposals.Count -eq 0) 'Relation bag matched incompatible topology.'
$ambiguousSource=@([pscustomobject]@{Relation='Link';From='A';To='B'},[pscustomobject]@{Relation='Link';From='B';To='A'})
$ambiguousTarget=@([pscustomobject]@{Relation='Link';From='X';To='Y'},[pscustomobject]@{Relation='Link';From='Y';To='X'})
Assert-That ((Find-PerceptRoleBinding $ambiguousSource $ambiguousTarget).Status -ceq 'Ambiguous') 'Ambiguous role mapping was silently selected.'
Assert-That ((Find-PerceptRoleBinding $attribution.Pattern $target -BindingBudget 1).Status -ceq 'BudgetExhausted') 'Binding budget was not enforced.'
$store.Current=$store.Root
Assert-That ((Get-AnalogicalPerceptProposals $target $store).Proposals.Count -eq 0) 'Abandoned kept branch was retrieved as active knowledge.'
$experience=@(
    [pscustomobject]@{SpecimenName='a';CanonicalBefore=[pscustomobject]@{X=5;ANoise=1;Direction=1};Action='Step';ActualDelta=1},
    [pscustomobject]@{SpecimenName='b';CanonicalBefore=[pscustomobject]@{X=5;ANoise=2;Direction=1};Action='Step';ActualDelta=1},
    [pscustomobject]@{SpecimenName='c';CanonicalBefore=[pscustomobject]@{X=5;ANoise=1;Direction=-1};Action='Step';ActualDelta=-1},
    [pscustomobject]@{SpecimenName='d';CanonicalBefore=[pscustomobject]@{X=5;ANoise=2;Direction=-1};Action='Step';ActualDelta=-1}
)
$cold=Invoke-PerceptRefine -Experience $experience -InitialRepresentation $initial -MaxIterations 2
$first=Invoke-PerceptRefine -Experience $experience -InitialRepresentation $initial -MaxIterations 1
Assert-That ($first.Store.Current.Id -ceq 'state_0' -and $first.CandidateEvaluations -eq 1) 'Fixture did not retain an actual failed proposal.'
$continued=Invoke-PerceptRefine -Experience $experience -InitialRepresentation $initial -Store $first.Store -MaxIterations 2
Assert-That ($cold.CandidateEvaluations -eq 2 -and $continued.CandidateEvaluations -eq 1 -and $continued.ReusedRejections -eq 1) 'Experience did not eliminate the repeated failed evaluation.'
Assert-That ($continued.FinalMeasure.Contradictions -eq $cold.FinalMeasure.Contradictions -and $continued.FinalMeasure.PredictionError -eq $cold.FinalMeasure.PredictionError) 'Proposal reuse changed the admitted result.'
$failed=$first.Store.GetRejectedTransitions()[0]
$candidate=[RepresentationMutation]::new('AddFeature',[string[]]@('ANoise'))
$first.Store.Current=$first.Store.Root
$identity=Get-RefinementEvidenceIdentity $experience $initial
Assert-That ((Get-PerceptProposalHistory $candidate $first.Store $identity).ReusableRejections -eq 1) 'Exact rejection evidence was not retrieved.'
$experience[3].ActualDelta=-2
$changedIdentity=Get-RefinementEvidenceIdentity $experience $initial
Assert-That ($identity -cne $changedIdentity -and (Get-PerceptProposalHistory $candidate $first.Store $changedIdentity).ReusableRejections -eq 0) 'Changed outcomes inherited a rejection from another context.'
$experience[3].ActualDelta=-1
$failed.Proposal.ReusableRejection=$false
Assert-That ((Get-PerceptProposalHistory $candidate $first.Store $identity).ReusableRejections -eq 0) 'A neutral-budget rejection was treated as failed knowledge.'
$experience[0].CanonicalBefore | Add-Member -NotePropertyName Unsupported -NotePropertyValue ([pscustomobject]@{Nested=1})
Assert-That ((Get-RefinementEvidenceIdentity $experience $initial) -ceq '') 'Unsupported state silently gained a cache identity.'
'SameContextCandidateEvaluations='+$cold.CandidateEvaluations+' -> '+$continued.CandidateEvaluations
'GATE_INFERENCE_CONTRACT=PASS; Checks='+$checks
'Scope=Expectation provenance and relation retrieval; synthetic schema fixtures; no domain correctness claim'
