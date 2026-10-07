Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Refine.ps1')
$checks=0
function Assert-Transfer([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message };$script:checks++ }
function New-SpecimenFamily {
    param([string[]]$Roles,[string[]]$Relations,[string]$Prefix,[string]$Action)
    $claims=@(for ($i=0;$i -lt 3;$i++) {
        [pscustomobject]@{Id='claim-'+$i;DependsOn=$(if ($i -lt 2) {@('claim-'+($i+1))} else {@()});Relation=$Relations[$i];From=$Roles[$i];To=$Roles[$i+1]}
    })
    $learning=@(foreach ($effect in @(2,-2)) { for ($i=0;$i -lt 4;$i++) {
        $state=[pscustomobject]@{}
        $state | Add-Member -NotePropertyName $Roles[0] -NotePropertyValue 0
        $state | Add-Member -NotePropertyName $Roles[1] -NotePropertyValue $effect
        $state | Add-Member -NotePropertyName $Roles[2] -NotePropertyValue ($i -band 1)
        $state | Add-Member -NotePropertyName $Roles[3] -NotePropertyValue (($i -shr 1) -band 1)
        [pscustomobject]@{SpecimenName=$Prefix+$effect+'-'+$i;CanonicalBefore=$state;Action=$Action;ActualDelta=$effect;Justifications=$claims;ActiveAssumptions=@('claim-0')}
    } })
    $heldout=@(foreach ($effect in @(2,-2)) {
        $state=[pscustomobject]@{}
        $state | Add-Member -NotePropertyName $Roles[0] -NotePropertyValue 7
        $state | Add-Member -NotePropertyName $Roles[1] -NotePropertyValue $effect
        $state | Add-Member -NotePropertyName $Roles[2] -NotePropertyValue 8
        $state | Add-Member -NotePropertyName $Roles[3] -NotePropertyValue 9
        [pscustomobject]@{CanonicalBefore=$state;ActualDelta=$effect}
    })
    [pscustomobject]@{Learning=$learning;Heldout=$heldout;Roles=$Roles;Relations=$Relations}
}
function Test-IndependentAdmission($Result,$Family) {
    # Frozen judge independent of the engine's replay predictor. The retained
    # projection must predict unseen combinations from observed support.
    $features=$Result.FinalRepresentation.Features
    foreach ($row in $Family.Heldout) {
        $support=@($Family.Learning | Where-Object {
            $same=$true
            foreach ($feature in $features) { if ($_.CanonicalBefore.$feature -ne $row.CanonicalBefore.$feature) { $same=$false } }
            $same
        })
        if ($support.Count -eq 0) { return $false }
        foreach ($prior in $support) { if ($prior.ActualDelta -ne $row.ActualDelta) { return $false } }
    }
    return $true
}

$discovery=New-SpecimenFamily @('d9','j1','t7','a4') @('h','x','k') 'discovery-' 'source-action'
$transfer=New-SpecimenFamily @('r4','z3','b8','m2') @('v','n','w') 'transfer-' 'target-action'
Assert-Transfer (@($discovery.Roles+$discovery.Relations | Where-Object { $_ -cin ($transfer.Roles+$transfer.Relations) }).Count -eq 0) 'Surface identities overlap.'
Assert-Transfer (@($discovery.Learning.SpecimenName | Where-Object { $_ -cin $transfer.Learning.SpecimenName }).Count -eq 0) 'Specimen identities overlap.'
$fresh=Invoke-PerceptRefine -Experience $transfer.Learning -NeutralBudget 0
$learned=Invoke-PerceptRefine -Experience $discovery.Learning -NeutralBudget 0
Assert-Transfer (Test-IndependentAdmission $learned $discovery) 'Discovery failed the independent behavioral judge.'
Assert-Transfer ($learned.Store.Current.Proposal.Pattern.Count -eq 3) 'Normal refinement did not retain attributed structure.'
Assert-Transfer (@($learned.Store.Receipts | Where-Object { $_.Case.StartsWith('prediction:') -and $_.After.Mismatch }).Count -gt 0) 'Normal refinement did not retain prediction surprise.'
$experienced=Invoke-PerceptRefine -Experience $transfer.Learning -Store $learned.Store -NeutralBudget 0
Assert-Transfer ($fresh.CandidateEvaluations -eq 3 -and $experienced.CandidateEvaluations -eq 1) 'Normal refinement did not automatically reduce unseen search.'
Assert-Transfer (($fresh.FinalRepresentation.Features -join ',') -ceq ($experienced.FinalRepresentation.Features -join ',')) 'Experience changed the admitted result.'
Assert-Transfer ((Test-IndependentAdmission $fresh $transfer) -and (Test-IndependentAdmission $experienced $transfer)) 'Independent held-out admission failed.'
Assert-Transfer (($experienced.Store.ReplayFromScratch().Features -join ',') -ceq ($experienced.FinalRepresentation.Features -join ',')) 'Cross-specimen initialization lost replay integrity.'

# Remove active ancestry through the existing store boundary. Old kept nodes
# remain for provenance but must no longer influence ordinary proposal order.
$experienced.Store.Current=$experienced.Store.Root
$removed=Invoke-PerceptRefine -Experience $transfer.Learning -Store $experienced.Store -NeutralBudget 0
Assert-Transfer ($removed.CandidateEvaluations -eq $fresh.CandidateEvaluations) 'Removed experience still supplied a search advantage.'

# Same topology with a different observed effect must fail ordinary admission.
$wrong=New-SpecimenFamily @('q0','z9','a9','b9') @('u','o','p') 'different-' 'different-action'
foreach ($row in $wrong.Learning) { $row.ActualDelta=if ($row.CanonicalBefore.a9 -eq 0) {2} else {-2} }
$wrong.Learning=@($wrong.Learning | Sort-Object ActualDelta -Descending)
for ($i=0;$i -lt $wrong.Heldout.Count;$i++) {
    $wrong.Heldout[$i].CanonicalBefore.z9=8
    $wrong.Heldout[$i].CanonicalBefore.a9=$i
    $wrong.Heldout[$i].ActualDelta=if ($i -eq 0) {2} else {-2}
}
$prior=Invoke-PerceptRefine -Experience $discovery.Learning -NeutralBudget 0
$falseAnalogy=Invoke-PerceptRefine -Experience $wrong.Learning -Store $prior.Store -NeutralBudget 0
Assert-Transfer (@($falseAnalogy.Store.GetRejectedTransitions() | Where-Object { $_.Proposal.Arguments[0] -ceq 'z9' }).Count -gt 0) 'Ordinary admission accepted a false analogy.'
Assert-Transfer ($falseAnalogy.FinalMeasure.Contradictions -eq 0 -and $falseAnalogy.FinalRepresentation.Features[0] -ceq 'a9') 'Ordinary fallback did not admit the correct explanation.'
Assert-Transfer (Test-IndependentAdmission $falseAnalogy $wrong) 'False-analogy fallback failed held-out behavioral admission.'
'GATE_UNSEEN_ANALOGICAL_SEARCH=PASS; Checks='+$checks
'CallPath=Invoke-PerceptRefine -> prediction justification -> surprise attribution -> stored analogy -> existing admission -> retained provenance'
'FreshCandidateEvaluations='+$fresh.CandidateEvaluations
'ExperiencedCandidateEvaluations='+$experienced.CandidateEvaluations
'AfterRemovalCandidateEvaluations='+$removed.CandidateEvaluations
'IndependentHeldOutAdmission=PASS; FalseAnalogy=Rejected; Replay=PASS'
'Scope=Integrated ordinary refinement on synthetic unseen families; pronunciation accuracy remains unmeasured'
