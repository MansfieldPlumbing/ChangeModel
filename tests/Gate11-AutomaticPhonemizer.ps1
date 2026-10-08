param(
    [string]$DataRoot=(Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\WikipediaHomographData\data'),
    [string]$GoldPath=(Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_gold.json'),
    [string]$SilverPath=(Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_silver.json'),
    [string]$OutputDirectory=(Join-Path $env:LOCALAPPDATA 'Build\PSPerception\gates\automatic-phonemizer')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Input identities freeze the measurement, not the learned choice.
$pins=@{Gold='DC414872A49A28AE6C141463D502FD945F3B2FDE040484FDC47D00CC4612686F';Silver='DE8F67BE911BB6C659187B4A65FD966B6A30E56350E0F790D763210B053AC475';Metadata='ED5F8AE577DB2E9500523EA2EF9F0BE3241C28764D02BD42121371A277512439';Evaluation='F124E90C1583CC8B2D1F284297E0D9ABBE3F53BDD692145FA55975CC8A36D4E5'}
foreach ($inputFile in @(@{Path=$GoldPath;Hash=$pins.Gold},@{Path=$SilverPath;Hash=$pins.Silver},@{Path=(Join-Path $DataRoot 'wordids.tsv');Hash=$pins.Metadata})) {
    if ((Get-FileHash -LiteralPath $inputFile.Path -Algorithm SHA256).Hash -cne $inputFile.Hash) {throw 'Frozen input digest mismatch.'}
}
$evalFiles=@(Get-ChildItem -LiteralPath (Join-Path $DataRoot 'eval') -Filter *.tsv | Sort-Object Name)
if ($evalFiles.Count -ne 162) {throw 'Frozen evaluation file count changed.'}
$evalIdentity=($evalFiles | ForEach-Object {$_.Name+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}) -join "`n"
if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($evalIdentity))) -cne $pins.Evaluation) {throw 'Frozen evaluation digest mismatch.'}
$buildRoot=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Build\PSPerception'))+[IO.Path]::DirectorySeparatorChar
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)) {throw 'Gate output must stay under the project build directory.'}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
. (Join-Path $PSScriptRoot '..\src\GetSmaPhonemes.ps1')
$data=$DataRoot
$ctx=Initialize-Phonemizer -GoldPath $GoldPath -SilverPath $SilverPath
# Preserve the original conservative label-to-lexicon reference policy.
# A homograph family is scorable only when every sense maps to a distinct phone string.
$references=@{}
$metadata=@(Import-Csv -LiteralPath (Join-Path $data 'wordids.tsv') -Delimiter "`t")
foreach ($group in ($metadata | Group-Object homograph)) {
    $entry=$ctx.Gold[$group.Name]
    if ($entry -isnot [Collections.IDictionary]) {continue}
    $mapped=@{};$valid=$true
    foreach ($sense in $group.Group) {
        $key=$null
        if ($sense.label -ceq 'verb') {$key=if ($entry.ContainsKey('VERB')) {'VERB'} else {'DEFAULT'}}
        elseif ($sense.label -cin @('noun','adjective','adjective-noun')) {$key=if ($sense.label -ceq 'noun' -and $entry.ContainsKey('NOUN')) {'NOUN'} elseif ($sense.label -ceq 'adjective' -and $entry.ContainsKey('ADJ')) {'ADJ'} else {'DEFAULT'}}
        elseif ($sense.label -ceq 'past tense verb') {$key=if ($entry.ContainsKey('VBD')) {'VBD'} else {$null}}
        elseif ($sense.label -ceq 'present tense verb') {$key='DEFAULT'}
        if ($null -eq $key -or -not $entry.ContainsKey($key)) {$valid=$false;break}
        $mapped[$sense.wordid]=$key
    }
    if (@($mapped.Values | ForEach-Object {$entry[$_]} | Sort-Object -Unique -CaseSensitive).Count -ne $group.Count) {$valid=$false}
    if ($valid) {foreach ($id in $mapped.Keys) {$references[$id]=$mapped[$id]}}
}
$rows=@(foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $data 'eval') -Filter *.tsv | Sort-Object Name)) {
    $index=0
    foreach ($row in (Import-Csv -LiteralPath $file.FullName -Delimiter "`t")) {
        $index++
        if (-not $references.ContainsKey($row.wordid)) { continue }
        $visible=Get-SmaPhonemes $row.sentence -Context $ctx
        if (@($visible.AmbiguousDecisions | Where-Object {$_.Word.ToLowerInvariant() -ceq $row.homograph}).Count -eq 0) { continue }
        $id=$file.BaseName+'-'+$index
        $wordHash=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($row.homograph.ToLowerInvariant()))
        $caseHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($id)))
        [pscustomobject]@{SpecimenName=$id;Word=$row.homograph;ExpectedKey=$references[$row.wordid];Sentence=$row.sentence;TargetStart=[int]$row.start;Partition=($wordHash[0] -band 1);Order=$caseHash}
    }
})
$construction=@($rows | Where-Object Partition -eq 0 | Sort-Object Order | Select-Object -First 128)
$admission=@($rows | Where-Object Partition -eq 1 | Sort-Object Order | Select-Object -First 128)
$construction | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'construction.csv')
$admission | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'admission.csv')
'Construction='+$construction.Count+'; Admission='+$admission.Count+'; Evaluation='+$rows.Count
# Warm this exact caller before experience changes the live context.
$liveCaller={param($sentence,$context) Get-SmaPhonemes -Text $sentence -Context $context}
$runtimeErrors=@(foreach ($row in $construction) {
    $before=& $liveCaller $row.Sentence $ctx
    $target=Get-PhonemizerTarget $before $row
    if ($target.Pronunciation -cne $ctx.Gold[$row.Word][$row.ExpectedKey] -and $target.SourceStart -eq $row.TargetStart) {
        [pscustomobject]@{Row=$row;Before=$before.KokoroPhones}
    }
})
if ($runtimeErrors.Count -eq 0) {throw 'No demonstrated error for live execution assertion.'}
$ctx=Initialize-Phonemizer -Context $ctx -Experience $construction -ValidationExperience $admission -EvaluationExperience $rows -MinimumNetFixes 2 -MinimumTransferIdentities 2 -MaximumRegressionRate 0.01 -MaxLearningIterations 16
$ctx.LearningCurve | Select-Object Iteration,Micro,Macro,Fixes,Regressions,NetFixes,TransferredIdentities,CandidateEvaluations,Complexity,@{Name='Percept';Expression={$_.Percept -join ','}} | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'learning-curve.csv')
Get-Content -LiteralPath (Join-Path $OutputDirectory 'learning-curve.csv')
'Termination='+$ctx.LearningTermination
'FinalAttemptEvaluations='+$ctx.RefinementResult.CandidateEvaluations+'; ReusedRejections='+$ctx.RefinementResult.ReusedRejections
if ($ctx.LearningCurve.Count -lt 2) { throw 'No automatic transferable improvement was admitted.' }
foreach ($point in @($ctx.LearningCurve | Where-Object Iteration -gt 0)) {
    if ($point.Admission.NetFixes -lt 2 -or $point.Admission.TransferredIdentities -lt 2) { throw 'Admission gate violated.' }
}
'AUTOMATIC_PHONEMIZER_CYCLE=PASS'

$firstCurve=@($ctx.LearningCurve)
$firstEvaluations=$ctx.RefinementResult.CandidateEvaluations
$firstFeatures=[string[]]@($ctx.RefinementStore.Current.Representation.Features)
$firstCurve | ForEach-Object {
    if ($_.Iteration -gt 0) {
        [pscustomobject]@{Iteration=$_.Iteration;Net=$_.Admission.NetFixes;Fixes=$_.Admission.Fixes;Regressions=$_.Admission.Regressions;Identities=$_.Admission.TransferredIdentities;Percept=($_.Percept -join ',')}
    }
} | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'admission-receipts.csv')
$fresh=Initialize-Phonemizer -GoldPath $GoldPath -SilverPath $SilverPath
$runtimeCase=$null;$runtimeResult=$null
foreach ($errorCase in $runtimeErrors) {
    $after=& $liveCaller $errorCase.Row.Sentence $ctx
    $target=Get-PhonemizerTarget $after $errorCase.Row
    if ($target.Pronunciation -ceq $ctx.Gold[$errorCase.Row.Word][$errorCase.Row.ExpectedKey] -and $target.DeltaId -ceq 'ExecutableRetainedPercept') {$runtimeCase=$errorCase;$runtimeResult=$after;break}
}
if ($null -eq $runtimeCase -or $null -eq (Get-TypeData -TypeName $ctx.RuntimeTypeName)) {throw 'Experience did not materialize normal-path ETS behavior.'}
if ((& $liveCaller $runtimeCase.Row.Sentence $fresh).KokoroPhones -cne $runtimeCase.Before) {throw 'Context-scoped behavior leaked.'}
$runtimeEvaluations=$ctx.RefinementResult.CandidateEvaluations
if ((& $liveCaller $runtimeCase.Row.Sentence $ctx).KokoroPhones -cne $runtimeResult.KokoroPhones -or $ctx.RefinementResult.CandidateEvaluations -ne $runtimeEvaluations) {throw 'Runtime use repeated search or changed output.'}
$baseline=@(foreach ($row in $rows) {(Get-SmaPhonemes $row.Sentence -Context $fresh).KokoroPhones})
$saved=$ctx.RefinementStore.Current
$rootNode=$saved
while ($rootNode.Parents.Count -gt 0) {$rootNode=$rootNode.Parents[0]}
try {
    $ctx.RefinementStore.Current=$rootNode
    if ((& $liveCaller $runtimeCase.Row.Sentence $ctx).KokoroPhones -cne $runtimeCase.Before -or $null -ne (Get-TypeData -TypeName $ctx.RuntimeTypeName)) {throw 'Compiled caller retained withdrawn ETS behavior.'}
    $removed=@(foreach ($row in $rows) {(Get-SmaPhonemes $row.Sentence -Context $ctx).KokoroPhones})
    if (($removed -join '|') -cne ($baseline -join '|')) {throw 'Whole-corpus removal failed.'}
} finally {$ctx.RefinementStore.Current=$saved}
if ((& $liveCaller $runtimeCase.Row.Sentence $ctx).KokoroPhones -cne $runtimeResult.KokoroPhones) {throw 'Retained behavior did not rematerialize.'}
'ExperienceToEtsExecution=PASS; CompiledCallerWithdrawal=PASS; ContextIsolation=PASS; AdditionalSearch=0; Word='+$runtimeCase.Row.Word
'FullCorpusRemoval=PASS; Cases='+$rows.Count
$ctx=Initialize-Phonemizer -Context $ctx -Experience $construction -ValidationExperience $admission -EvaluationExperience $rows -MinimumNetFixes 2 -MinimumTransferIdentities 2 -MaximumRegressionRate 0.01 -MaxLearningIterations 16
if ($ctx.LearningCurve.Count -ne 1 -or (@($ctx.RefinementStore.Current.Representation.Features) -join '|') -cne ($firstFeatures -join '|')) {throw 'Terminal rerun changed learned representation.'}
if ($firstEvaluations -gt 0 -and $ctx.RefinementResult.CandidateEvaluations -ge $firstEvaluations) {throw 'Rejected experience did not reduce terminal search.'}
'TerminalCandidateEvaluations='+$firstEvaluations+' -> '+$ctx.RefinementResult.CandidateEvaluations+'; ReusedRejections='+$ctx.RefinementResult.ReusedRejections
$overlapRejected=$false
try { $null=Initialize-Phonemizer -Context $fresh -Experience @($construction[0]) -ValidationExperience @($construction[0]) } catch {
    if ($_.Exception.Message -cne 'Construction and admission lexical identities overlap.') {throw}
    $overlapRejected=$true
}
if (-not $overlapRejected) {throw 'Lexical overlap accepted.'}
'LexicalDisjointness=PASS'
Get-Content -LiteralPath (Join-Path $OutputDirectory 'admission-receipts.csv')
'AUTOMATIC_CYCLE_BEHAVIORAL_GATE=PASS'

if ($rows.Count -ne 1187 -or $firstCurve.Count -ne 3) {throw 'Frozen coverage or trajectory changed.'}
$expected=@(
    @{Micro=67.98652064026959;Macro=68.2500580227853;Fixes=0;Regressions=0;Evaluations=0;Percept=''},
    @{Micro=73.12552653748946;Macro=73.33040696677061;Fixes=62;Regressions=1;Evaluations=4;Percept='DeterminerContext|NOUN'},
    @{Micro=77.33782645324347;Macro=77.53478844387934;Fixes=52;Regressions=2;Evaluations=3;Percept='InfinitivalVerbContext|VERB'}
)
for ($i=0;$i -lt $expected.Count;$i++) {
    $actual=$firstCurve[$i];$want=$expected[$i]
    if ([math]::Abs($actual.Micro-$want.Micro) -gt 1e-8 -or [math]::Abs($actual.Macro-$want.Macro) -gt 1e-8 -or $actual.Fixes -ne $want.Fixes -or $actual.Regressions -ne $want.Regressions -or $actual.CandidateEvaluations -ne $want.Evaluations -or ($actual.Percept -join ',') -cne $want.Percept -or $actual.Complexity -ne $i) {throw 'Frozen two-percept trajectory changed.'}
}
if ($firstCurve[1].Admission.Fixes -ne 6 -or $firstCurve[1].Admission.Regressions -ne 0 -or $firstCurve[1].Admission.TransferredIdentities -ne 6 -or $firstCurve[2].Admission.Fixes -ne 4 -or $firstCurve[2].Admission.Regressions -ne 0 -or $firstCurve[2].Admission.TransferredIdentities -ne 3) {throw 'Frozen lexical admission changed.'}
if ($firstEvaluations -ne 2 -or $ctx.RefinementResult.CandidateEvaluations -ne 0 -or $ctx.RefinementResult.ReusedRejections -ne 2 -or $ctx.LearningTermination -cne 'NoAdmissibleCandidateInCurrentPerceptLanguage') {throw 'Frozen terminal search changed.'}
$firstCurve | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'trajectory.json') -Encoding utf8
'GATE_AUTOMATIC_PHONEMIZER=PASS; ExactTrajectory=PASS'
