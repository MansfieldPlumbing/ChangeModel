#requires -Version 7.4
# Dev.MansfieldPlumbing.PowerShell.Perception - Frontend Phonemizer
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\experiments\english-projection\expB\Projection.ps1')
. (Join-Path $PSScriptRoot '..\src\Refine.ps1')

class PhonemeResult {
    [string]$OriginalText
    [string]$ProjectedText
    [bool]$Reversible
    [System.Collections.Generic.List[object]]$Tokens
    [string]$KokoroPhones
    [System.Collections.Generic.List[object]]$AmbiguousDecisions
    [System.Collections.Generic.List[object]]$OovSpans
    [System.Collections.Generic.List[object]]$UnresolvedSpans
    [bool]$Complete
    [System.Collections.Generic.List[string]]$Provenance
    [pscustomobject]$Timing

    PhonemeResult() {
        $this.Tokens = [System.Collections.Generic.List[object]]::new()
        $this.AmbiguousDecisions = [System.Collections.Generic.List[object]]::new()
        $this.OovSpans = [System.Collections.Generic.List[object]]::new()
        $this.UnresolvedSpans = [System.Collections.Generic.List[object]]::new()
        $this.Provenance = [System.Collections.Generic.List[string]]::new()
    }
}

class PhonemizerContext {
    [hashtable]$Gold
    [hashtable]$Silver
    [hashtable]$DecisionModels  # Homograph decision models
    [object]$RefinementStore
    [object]$CandidateRepresentation
    [object]$RuntimeNode
    [string]$RuntimeTypeName
    [scriptblock]$RuntimeProgram
    [object]$RefinementResult
    [object[]]$LearningValidation = @()
    [object]$AdmissionBaseline
    [object]$LearningCurve
    [string]$LearningTermination
    [string[]]$OutcomeKeys = @('DEFAULT','VERB')
    [string[]]$ClusterPriority = @()
    [string[]]$SelectionCandidates = @()
    [string]$LearningSignature
    [string]$TokenizationPolicy = 'SourceBoundaries'
    [int]$MinimumNetFixes = 2
    [int]$MinimumTransferIdentities = 2
    [double]$MaximumRegressionRate = 0.01
    [System.Collections.Generic.HashSet[char]]$KokoroVocab
    [System.Collections.Generic.HashSet[string]]$MultiWords

    PhonemizerContext() {
        $this.RuntimeTypeName = 'Dev.MansfieldPlumbing.PowerShell.Perception.Pronunciation.'+[guid]::NewGuid().ToString('N')
        $this.KokoroVocab = [System.Collections.Generic.HashSet[char]]::new()
        # US lexicon phones; presentation tokens verified against Kokoro-82M
        # config f3ff3571791e39611d31c381e3a41a3af07b4987 (SHA256
        # 5ABB01E2403B072BF03D04FDE160443E209D7A0DAD49A423BE15196B9B43C17F).
        foreach ($c in 'AIOWYbdfhijklmnpstuvwzæðŋɑɔəɛɜɡɪɹɾʃʊʌʒʤʧˈˌθᵊᵻʔɐ'.ToCharArray()) {
            [void]$this.KokoroVocab.Add($c)
        }
        foreach ($c in ' ;:,.!?—…"()'.ToCharArray()) {[void]$this.KokoroVocab.Add($c)}
        $this.MultiWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    [void] LoadLexicons([string]$GoldPath, [string]$SilverPath) {
        if (Test-Path $GoldPath) {
            $this.Gold = Get-Content $GoldPath -Raw | ConvertFrom-Json -AsHashtable
            foreach ($k in $this.Gold.Keys) {
                $val = $this.Gold[$k]
                if ($val -is [System.Collections.IDictionary]) {
                    $distinct = [System.Collections.Generic.HashSet[string]]::new()
                    foreach ($p in $val.Values) {
                        if ($p -is [string] -and $p.Length -gt 0) { [void]$distinct.Add($p) }
                    }
                    if ($distinct.Count -gt 1) {
                        [void]$this.MultiWords.Add($k)
                    }
                }
            }
        }
        if (Test-Path $SilverPath) {
            $this.Silver = Get-Content $SilverPath -Raw | ConvertFrom-Json -AsHashtable
        }
    }
}

$script:GlobalContext = $null

# Read boundaries from original text through the reversible projection map.
# Known entries (including contractions/compounds) take precedence over splitting.
# This is a lexicon-tailored scanner, not a claim of complete UAX #29 conformance.
function Get-PhonemizerSourceWords {
    param([string]$Text,[object]$Projection,[PhonemizerContext]$Context)
    $words=[Collections.Generic.List[object]]::new()
    $groupIndex=-1
    foreach ($group in (Get-ProjectedWords $Projection)) {
        $groupIndex++
        $groupBegin=$words.Count
        $positions=@($group.Start..($group.End-1) | Where-Object {$Projection.Map[$_] -ge 0})
        if ($positions.Count -eq 0) {continue}
        $start=$Projection.Map[$positions[0]];$end=$Projection.Map[$positions[-1]]+1
        $at=$start
        while ($at -lt $end) {
            $begin=$at;$kind='Word'
            if ([char]::IsLetterOrDigit($Text[$at])) {
                # Try a whole remaining lexicon entry before opening its boundaries.
                $last=$end
                while ($last -gt $at -and -not [char]::IsLetterOrDigit($Text[$last-1])) {$last--}
                $whole=$Text.Substring($at,$last-$at)
                $known=(($null -ne $Context.Gold -and ($Context.Gold.ContainsKey($whole) -or $Context.Gold.ContainsKey($whole.ToLowerInvariant()))) -or ($null -ne $Context.Silver -and ($Context.Silver.ContainsKey($whole) -or $Context.Silver.ContainsKey($whole.ToLowerInvariant()))))
                if ($known) {$at=$last}
                else {
                    $at++
                    while ($at -lt $end) {
                        $ch=$Text[$at];$category=[char]::GetUnicodeCategory($ch)
                        if ([char]::IsLetterOrDigit($ch) -or $category -in @([Globalization.UnicodeCategory]::NonSpacingMark,[Globalization.UnicodeCategory]::SpacingCombiningMark)) {$at++;continue}
                        if ($ch -cin @([char]39,[char]0x2019) -and $at+1 -lt $end -and [char]::IsLetterOrDigit($Text[$at+1])) {$at++;continue}
                        break
                    }
                }
            } else {$kind='Boundary';$at++}
            $pa=$positions[0]+($begin-$start);$pb=$pa+($at-$begin)
            $words.Add([pscustomobject]@{Text=$Text.Substring($begin,$at-$begin);Start=$pa;End=$pb;SourceStart=$begin;SourceEnd=$at;Kind=$kind;GroupIndex=$groupIndex;IsComponent=$false})
        }
        $wordCount=0
        for ($part=$groupBegin;$part -lt $words.Count;$part++) {if ($words[$part].Kind -ceq 'Word') {$wordCount++}}
        if ($wordCount -gt 1) {for ($part=$groupBegin;$part -lt $words.Count;$part++) {$words[$part].IsComponent=$true}}
    }
    return $words.ToArray()
}

# Materialize admitted selections once per retained node. Closures bind data to
# file-authored code; no source strings, parser changes, or binder patches.
function Sync-PhonemizerRuntime([PhonemizerContext]$Context) {
    $node=if ($null -ne $Context.RefinementStore) {$Context.RefinementStore.Current} else {$null}
    if ([object]::ReferenceEquals($node,$Context.RuntimeNode)) {return}
    if ($null -ne (Get-TypeData -TypeName $Context.RuntimeTypeName)) {
        Remove-TypeData -TypeName $Context.RuntimeTypeName -ErrorAction Stop
    }
    $Context.RuntimeNode=$null
    $Context.RuntimeProgram=$null
    if ($null -eq $node -or $node.Representation.Features.Count -eq 0) {
        $Context.RuntimeNode=$node
        return
    }
    $program={param($canonical,$entry) $null}
    for ($i=$node.Representation.Features.Count-1;$i -ge 0;$i--) {
        $feature=$node.Representation.Features[$i]
        $parts=$feature.Split('|')
        if ($parts.Count -gt 2 -or $parts[0] -cnotin @('AstArrayMembership','DeterminerContext','InfinitivalVerbContext')) {throw 'Unsupported runtime selection percept.'}
        $observable=$parts[0]
        $outcome=if ($parts.Count -eq 2) {$parts[1]} else {'VERB'}
        if ([string]::IsNullOrEmpty($outcome)) {throw 'Empty runtime selection outcome.'}
        $next=$program
        $program={
            param($canonical,$entry)
            if ($canonical.$observable -eq 1 -and $entry.ContainsKey($outcome)) {
                return [pscustomobject]@{Key=$outcome;Feature=$feature}
            }
            & $next $canonical $entry
        }.GetNewClosure()
    }
    $method={
        param($canonical,$entry)
        # Retained identity is the guard; stale observations cannot execute a
        # withdrawn percept even before the next product call synchronizes ETS.
        if ($null -eq $this.CandidateRepresentation -and $null -ne $this.RefinementStore -and [object]::ReferenceEquals($this.RefinementStore.Current,$this.RuntimeNode)) {
            & $this.RuntimeProgram $canonical $entry
        }
    }
    if (-not $Context.PSObject.TypeNames.Contains($Context.RuntimeTypeName)) {$Context.PSObject.TypeNames.Insert(0,$Context.RuntimeTypeName)}
    Update-TypeData -TypeName $Context.RuntimeTypeName -MemberType ScriptMethod -MemberName 'ChoosePercept' -Value $method -ErrorAction Stop
    $Context.RuntimeProgram=$program
    $Context.RuntimeNode=$node
}

function Initialize-Phonemizer {
    param(
        [string]$GoldPath = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_gold.json'),
        [string]$SilverPath = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_silver.json'),
        [object[]]$Experience = @(),
        [PhonemizerContext]$Context = $null,
        [ValidateSet('SourceBoundaries','ProjectedWhitespace')][string]$TokenizationPolicy = 'SourceBoundaries',
        [object[]]$ValidationExperience = @(),
        [object[]]$EvaluationExperience = @(),
        [ValidateRange(1,32)][int]$MaxLearningIterations = 16,
        [ValidateRange(1,128)][int]$MinimumNetFixes = 2,
        [ValidateRange(2,128)][int]$MinimumTransferIdentities = 2,
        [ValidateRange(0,1)][double]$MaximumRegressionRate = 0.01
    )

    $ctx = if ($null -ne $Context) {$Context} else {[PhonemizerContext]::new()}
    if ($null -eq $Context) { $ctx.LoadLexicons($GoldPath, $SilverPath);$ctx.TokenizationPolicy=$TokenizationPolicy }
    $script:GlobalContext = $ctx
    if ($ValidationExperience.Count -gt 0) {
        $ctx.LearningTermination=''
        if ($Experience.Count -eq 0 -or $Experience.Count -gt 128 -or $ValidationExperience.Count -gt 128) { throw 'Automatic learning requires bounded construction and admission sets.' }
        $constructionWords=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $Experience) { [void]$constructionWords.Add($row.Word) }
        foreach ($row in $ValidationExperience) { if ($constructionWords.Contains($row.Word)) { throw 'Construction and admission lexical identities overlap.' } }
        $ctx.OutcomeKeys=[string[]]@(($Experience+$ValidationExperience).ExpectedKey | Sort-Object -Unique -CaseSensitive)
        $ctx.MinimumNetFixes=$MinimumNetFixes;$ctx.MinimumTransferIdentities=$MinimumTransferIdentities;$ctx.MaximumRegressionRate=$MaximumRegressionRate
        $construction=Get-PhonemizerObservations $Experience $ctx
        $ctx.LearningValidation=Get-PhonemizerObservations $ValidationExperience $ctx
        $evaluation=if ($EvaluationExperience.Count -gt 0) {Get-PhonemizerObservations $EvaluationExperience $ctx} else {$ctx.LearningValidation}
        $signature=[Text.StringBuilder]::new()
        foreach ($row in @($construction)+@($ctx.LearningValidation)) {
            foreach ($text in @($row.SpecimenName,$row.Word,$row.Sentence,$row.ExpectedKey)+@($ctx.Gold[$row.Word].Values | Sort-Object -CaseSensitive)) { [void]$signature.Append($text.Length.ToString()+':'+$text) }
        }
        [void]$signature.Append((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash)
        [void]$signature.Append($MinimumNetFixes.ToString()+':'+$MinimumTransferIdentities.ToString()+':'+$MaximumRegressionRate.ToString([Globalization.CultureInfo]::InvariantCulture))
        $ctx.LearningSignature=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($signature.ToString())))
        $ctx.LearningCurve=[Collections.Generic.List[object]]::new()
        $initial=if ($null -ne $ctx.RefinementStore) {$ctx.RefinementStore.Current.Representation} else {[Representation]::new([string[]]@())}
        $ctx.AdmissionBaseline=$null
        $score=Measure-PhonemizerRepresentation $evaluation $initial 'Corpus' $ctx -ValidationOnly
        $ctx.LearningCurve.Add((Get-PhonemizerCurvePoint 0 $score $null 0 @()))
        for ($iteration=1;$iteration -le $MaxLearningIterations;$iteration++) {
            $parentRep=if ($null -ne $ctx.RefinementStore) {$ctx.RefinementStore.Current.Representation} else {$initial}
            $before=Measure-PhonemizerRepresentation $construction $parentRep 'Construction' $ctx -ValidationOnly
            # Abduct selection effects from observed construction failures only.
            # Applicability stays in the existing observable percept language.
            $candidates=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            for ($case=0;$case -lt $construction.Count;$case++) {
                if ($before.ReplayHistory[$case].PredictionError -eq 0) { continue }
                foreach ($property in $construction[$case].CanonicalBefore.PSObject.Properties) {
                    if ($property.Name.Contains('|') -or $property.Value -ne 1) { continue }
                    [void]$candidates.Add($property.Name+'|'+$construction[$case].ExpectedKey)
                }
            }
            $ctx.SelectionCandidates=[string[]]@($candidates | Sort-Object -CaseSensitive)
            $construction=Get-PhonemizerObservations $Experience $ctx
            $ctx.LearningValidation=Get-PhonemizerObservations $ValidationExperience $ctx
            $evaluation=if ($EvaluationExperience.Count -gt 0) {Get-PhonemizerObservations $EvaluationExperience $ctx} else {$ctx.LearningValidation}
            $before=Measure-PhonemizerRepresentation $construction $parentRep 'Construction' $ctx -ValidationOnly
            $held=Measure-PhonemizerRepresentation $ctx.LearningValidation $parentRep 'Admission' $ctx -ValidationOnly
            # Cluster actual surprises by active relation structure and observable
            # property values. Lexical identities only measure support/transfer.
            $clusters=@($before.ReplayHistory | Where-Object PredictionError -gt 0 | Group-Object {
                $i=[array]::IndexOf([object[]]@($before.ReplayHistory),$_)
                $record=$construction[$i]
                $attribution=Get-SurpriseAttribution (Measure-PerceptSurprise (New-PerceptExpectation -Specimen $record.SpecimenName -RepresentationId 'cluster' -PredictedOutcome ([string]$_.PredictedDelta) -ActiveAssumptions $record.ActiveAssumptions -Justifications $record.Justifications) ([string]$record.ActualDelta))
                (($attribution.Pattern | ForEach-Object {$_.Relation+':'+$_.From+':'+$_.To} | Sort-Object) -join ';')+'|'+(($_.CanonicalBefore.PSObject.Properties | Sort-Object Name | ForEach-Object {$_.Name+'='+$_.Value}) -join ';')+'|'+$_.PredictedDelta+'>'+ $_.ActualDelta
            } | Sort-Object Count -Descending)
            $ranking=@(foreach ($property in $construction[0].CanonicalBefore.PSObject.Properties.Name) {
                if ($property -cnotin $ctx.SelectionCandidates) { continue }
                if ($property -in $parentRep.Features) { continue }
                $support=0;$population=0
                foreach ($row in $before.ReplayHistory) { if ($row.CanonicalBefore.$property -eq 1) { $population++;if ($row.PredictionError -gt 0) {$support++} } }
                $clusterRank=2147483647
                for ($index=0;$index -lt $clusters.Count;$index++) {
                    if ($clusters[$index].Group[0].CanonicalBefore.$property -eq 1) { $clusterRank=$index;break }
                }
                if ($support -gt 0) { [pscustomobject]@{Property=$property;Support=$support;Enrichment=($support/[double]$population);ClusterRank=$clusterRank} }
            })
            $ctx.ClusterPriority=[string[]]@($ranking | Sort-Object ClusterRank,@{Expression='Enrichment';Descending=$true},@{Expression='Support';Descending=$true} | ForEach-Object Property)
            $ctx.AdmissionBaseline=[pscustomobject]@{Construction=$before;Validation=$held}
            $judge={param($History,$Rep,$RepVersion) Measure-PhonemizerRepresentation -History $History -Rep $Rep -RepVersion $RepVersion -Context $ctx}.GetNewClosure()
            $ctx.RefinementResult=Invoke-PerceptRefine -Experience $construction -InitialRepresentation $parentRep -Store $ctx.RefinementStore -NeutralBudget 0 -MaxIterations 1 -MaxAdmissions 1 -GreedyBest -MeasureRepresentation $judge
            $ctx.RefinementStore=$ctx.RefinementResult.Store
            if ($ctx.RefinementResult.Admissions -eq 0) { $ctx.LearningTermination='NoAdmissibleCandidateInCurrentPerceptLanguage';break }
            $saved=$ctx.RefinementStore.Current
            try {
                $ctx.RefinementStore.Current=$saved.Parents[0]
                $removed=Measure-PhonemizerRepresentation $ctx.LearningValidation $saved.Parents[0].Representation 'Removed' $ctx -ValidationOnly
                if (($removed.PhoneCases.FullPhones -join '|') -cne ($held.PhoneCases.FullPhones -join '|')) { throw 'Percept removal failed exact phone restoration.' }
            } finally { $ctx.RefinementStore.Current=$saved }
            $next=Measure-PhonemizerRepresentation $evaluation $saved.Representation 'Corpus' $ctx -ValidationOnly
            $point=Get-PhonemizerCurvePoint $iteration $next $score $ctx.RefinementResult.CandidateEvaluations $saved.Proposal.Arguments
            $point | Add-Member -NotePropertyName Admission -NotePropertyValue $ctx.RefinementResult.FinalMeasure.Transfer
            $point | Add-Member -NotePropertyName StructuralClusters -NotePropertyValue $clusters.Count
            $ctx.LearningCurve.Add($point);$score=$next
        }
        if (-not $ctx.LearningTermination) { $ctx.LearningTermination='IterationBudgetExhausted' }
        $ctx.AdmissionBaseline=$null
        Sync-PhonemizerRuntime $ctx
        return $ctx
    }
    if ($Experience.Count -gt 0) {
        $observations=@(foreach ($row in $Experience) {
            $result=Get-SmaPhonemes -Text $row.Sentence -Context $ctx
            $decision=@($result.AmbiguousDecisions | Where-Object { $_.Word.ToLowerInvariant() -ceq $row.Word.ToLowerInvariant() })
            if ($decision.Count -ne 1) { throw 'Training requires one unambiguous target span.' }
            if ($row.ExpectedKey -cnotin @('DEFAULT','VERB')) { throw 'Context refinement supports default/verb observations.' }
            [pscustomobject]@{SpecimenName=$row.SpecimenName;Sentence=$row.Sentence;Word=$row.Word;ExpectedKey=$row.ExpectedKey;CanonicalBefore=$decision[0].CanonicalContext;Action='ChoosePronunciation';ActualDelta=$(if ($row.ExpectedKey -ceq 'VERB') {1} else {0});Justifications=$decision[0].Justifications;ActiveAssumptions=@('projection')}
        })
        $judge={param($History,$Rep,$RepVersion) Measure-PhonemizerRepresentation -History $History -Rep $Rep -RepVersion $RepVersion -Context $ctx}.GetNewClosure()
        $ctx.RefinementResult=Invoke-PerceptRefine -Experience $observations -Store $ctx.RefinementStore -NeutralBudget 0 -MaxIterations 3 -MeasureRepresentation $judge
        $ctx.RefinementStore=$ctx.RefinementResult.Store
    }
    Sync-PhonemizerRuntime $ctx
    $ctx
}

function Measure-PhonemizerRepresentation {
    param([array]$History,[object]$Rep,[string]$RepVersion,[PhonemizerContext]$Context,[switch]$ValidationOnly)
    $replay=[Collections.Generic.List[object]]::new();$errors=0
    $phones=[Collections.Generic.List[object]]::new()
    $previous=$Context.CandidateRepresentation
    try {
        $Context.CandidateRepresentation=$Rep
        foreach ($row in $History) {
            $result=Get-SmaPhonemes -Text $row.Sentence -Context $Context
            $decision=Get-PhonemizerTarget $result $row
            $expected=$Context.Gold[$row.Word][$row.ExpectedKey]
            $wrong=[int]($decision.Pronunciation -cne $expected);$errors+=$wrong
            $represented=$Rep.GetRepresentedState($row.CanonicalBefore)
            $predicted=if ($Context.LearningValidation.Count -gt 0) {[array]::IndexOf($Context.OutcomeKeys,$decision.ChosenKey)} elseif ($decision.ChosenKey -ceq 'VERB') {1} else {0}
            $replay.Add((New-ObservationRecord -RepresentationVersion $RepVersion -CanonicalBefore $row.CanonicalBefore -RepresentedBefore $represented -Action $row.Action -PredictedDelta $predicted -ActualDelta $row.ActualDelta -PredictionError $wrong -ConditionKey (Get-ConditionKey $represented $row.Action)))
            $phones.Add([pscustomobject]@{Word=$row.Word;Phone=$decision.Pronunciation;FullPhones=$result.KokoroPhones;Correct=($wrong -eq 0)})
        }
    } finally { $Context.CandidateRepresentation=$previous }
    $measure=[pscustomobject]@{Contradictions=0;PredictionError=$errors;RepresentationComplexity=$Rep.Features.Count;ReplayHistory=$replay;PhoneCases=$phones.ToArray()}
    if (-not $ValidationOnly -and $null -ne $Context.AdmissionBaseline) {
        $held=Measure-PhonemizerRepresentation $Context.LearningValidation $Rep $RepVersion $Context -ValidationOnly
        $change=Get-PhonemizerCurvePoint 0 $held $Context.AdmissionBaseline.Validation 0 @()
        $constructionNet=$Context.AdmissionBaseline.Construction.PredictionError-$errors
        $allowed=($constructionNet -gt 0 -and $change.NetFixes -ge $Context.MinimumNetFixes -and $change.TransferredIdentities -ge $Context.MinimumTransferIdentities -and $change.Regressions/[double]$held.PhoneCases.Count -le $Context.MaximumRegressionRate)
        $measure | Add-Member -NotePropertyName AdmissionAllowed -NotePropertyValue $allowed
        $measure | Add-Member -NotePropertyName Transfer -NotePropertyValue $change
        $measure | Add-Member -NotePropertyName FeaturePriority -NotePropertyValue $Context.ClusterPriority
        $measure | Add-Member -NotePropertyName CandidateAttributes -NotePropertyValue $Context.SelectionCandidates
        $measure | Add-Member -NotePropertyName AllowedMutationVerbs -NotePropertyValue @('AddFeature')
        $identity=Get-RefinementEvidenceIdentity $History $Rep
        $measure | Add-Member -NotePropertyName EvidenceIdentity -NotePropertyValue ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity+$Context.LearningSignature))))
    }
    $measure
}

function Get-PhonemizerTarget($Result,$Row) {
    $targets=@($Result.AmbiguousDecisions | Where-Object { $_.Word.ToLowerInvariant() -ceq $Row.Word.ToLowerInvariant() })
    if ($null -ne $Row.PSObject.Properties['TargetStart']) { $targets=@($targets | Sort-Object @{Expression={[math]::Abs($_.SourceStart-[int]$Row.TargetStart)}}) }
    elseif ($targets.Count -ne 1) { throw 'Observation requires a unique target span.' }
    if ($targets.Count -eq 0) { throw 'Missing observation target.' }
    $targets[0]
}

function Get-PhonemizerObservations($Rows,$Context) {
    @(foreach ($row in $Rows) {
        if (-not $Context.Gold[$row.Word].ContainsKey($row.ExpectedKey)) { throw 'Reference key is unavailable.' }
        $decision=Get-PhonemizerTarget (Get-SmaPhonemes $row.Sentence -Context $Context) $row
        # Derived representation coordinates belong to learning observations;
        # normal runtime selection executes the installed program instead.
        if ($null -ne $Context.RefinementStore) {
            foreach ($field in $Context.RefinementStore.Current.Representation.Features) {
                $parts=$field.Split('|')
                if ($parts.Count -eq 2 -and $null -eq $decision.CanonicalContext.PSObject.Properties[$field]) {
                    $decision.CanonicalContext | Add-Member -NotePropertyName $field -NotePropertyValue ([int]($decision.CanonicalContext.($parts[0]) -eq 1 -and $Context.Gold[$row.Word].ContainsKey($parts[1])))
                }
            }
        }
        $observation=[pscustomobject]@{SpecimenName=$row.SpecimenName;Sentence=$row.Sentence;Word=$row.Word;ExpectedKey=$row.ExpectedKey;CanonicalBefore=$decision.CanonicalContext;Action='ChoosePronunciation';ActualDelta=[array]::IndexOf($Context.OutcomeKeys,$row.ExpectedKey);Justifications=$decision.Justifications;ActiveAssumptions=@('projection')}
        if ($null -ne $row.PSObject.Properties['TargetStart']) { $observation | Add-Member TargetStart $row.TargetStart }
        $observation
    })
}

function Get-PhonemizerCurvePoint($Iteration,$Score,$Before,$Evaluations,$Percept) {
    $fixes=0;$regressions=0;$identities=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $Before) {
        for ($i=0;$i -lt $Score.PhoneCases.Count;$i++) {
            if (-not $Before.PhoneCases[$i].Correct -and $Score.PhoneCases[$i].Correct) { $fixes++;[void]$identities.Add($Score.PhoneCases[$i].Word) }
            if ($Before.PhoneCases[$i].Correct -and -not $Score.PhoneCases[$i].Correct) { $regressions++ }
        }
    }
    $macro=@($Score.PhoneCases | Group-Object Word | ForEach-Object {100*@($_.Group | Where-Object Correct).Count/$_.Count})
    [pscustomobject]@{Iteration=$Iteration;Micro=(100*($Score.PhoneCases.Count-$Score.PredictionError)/$Score.PhoneCases.Count);Macro=($macro | Measure-Object -Average).Average;Fixes=$fixes;Regressions=$regressions;NetFixes=($fixes-$regressions);UnexpectedOutputsReduction=($fixes-$regressions);SurprisalBits='NotMeasured';TransferredIdentities=$identities.Count;CandidateEvaluations=$Evaluations;Percept=@($Percept);Complexity=$Score.RepresentationComplexity}
}

function Get-SmaPhonemes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Text,

        [PhonemizerContext]$Context = $script:GlobalContext,
        [switch]$Sma,
        [object]$SmaContext = $null
    )

    if ($Sma -or $null -eq $Context) {
        return Invoke-EnglishPhonemizer -Text $Text -Context $SmaContext
    }
    if ($null -eq $Context.CandidateRepresentation) {Sync-PhonemizerRuntime $Context}

    $swTotal = [System.Diagnostics.Stopwatch]::StartNew()

    # Step 1: Reversible Projection
    $swProj = [System.Diagnostics.Stopwatch]::StartNew()
    $proj = ConvertTo-Stage0 $Text
    $swProj.Stop()

    # Step 2: SMA Parse / Bind
    $swParse = [System.Diagnostics.Stopwatch]::StartNew()
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($proj.Text, [ref]$tokens, [ref]$errors)
    $swParse.Stop()

    # Step 3: Extract projected words
    $legacy=$Context.TokenizationPolicy -ceq 'ProjectedWhitespace'
    $contextWords=Get-ProjectedWords $proj
    $projWords = if ($legacy) {$contextWords} else {Get-PhonemizerSourceWords $Text $proj $Context}

    $result = [PhonemeResult]::new()
    $result.OriginalText = $Text
    $result.ProjectedText = $proj.Text
    $result.Reversible = $proj.Reversible

    $emittedPhones = [System.Collections.Generic.List[string]]::new()
    $emissionCursor=0

    # Step 4: Token-by-token pronunciation decision & assembly
    for ($i = 0; $i -lt $projWords.Count; $i++) {
        $pw = $projWords[$i]
        if (-not $legacy -and $pw.Kind -ceq 'Boundary') {
            $phone=if ($pw.Text -cin @(';',':',',','.','!','?','—','…','"','(',')')) {$pw.Text} else {$null}
            $status=if ($null -ne $phone) {'Punctuation'} elseif ($pw.Text.Length -eq 1 -and [int]$pw.Text[0] -in @(45,47,39,0x2019,0x201C,0x201D,0xAB,0xBB)) {'Boundary'} else {'UnresolvedSymbol'}
            $record=[pscustomobject]@{Word=$pw.Text;Pron=$phone;Status=$status;SourceDict='none';SourceStart=$pw.SourceStart;SourceEnd=$pw.SourceEnd;ProjStart=$pw.Start;ProjEnd=$pw.End;IsAmbiguous=$false;EmissionStart=$null;EmissionEnd=$null}
            $result.Tokens.Add($record)
            if ($status -ceq 'UnresolvedSymbol') {$result.UnresolvedSpans.Add($record)}
            if ($null -ne $phone) {
                if ($emittedPhones.Count -gt 0) {$emissionCursor++}
                $record.EmissionStart=$emissionCursor;$emissionCursor+=$phone.Length;$record.EmissionEnd=$emissionCursor
                $emittedPhones.Add($phone)
            }
            continue
        }
        $cleanWord = if ($legacy) {$pw.Text.Trim("',-._/;:!?«»‐—…`"“”()")} else {$pw.Text}
        if ($cleanWord.Length -eq 0) {
            # Pure punctuation token
            continue
        }

        $lowWord = $cleanWord.ToLowerInvariant()
        $sourceStart = if ($pw.Start -lt $proj.Map.Length) { $proj.Map[$pw.Start] } else { -1 }
        $sourceEnd = if ($pw.End -le $proj.Map.Length -and $pw.End -gt 0) { $proj.Map[$pw.End - 1] + 1 } else { -1 }

        # Lookup in gold first, then silver
        $entry = $null
        $sourceDict = 'none'
        if ($Context.Gold -and $Context.Gold.ContainsKey($lowWord)) {
            $entry = $Context.Gold[$lowWord]
            $sourceDict = 'gold'
        } elseif ($Context.Gold -and $Context.Gold.ContainsKey($cleanWord)) {
            $entry = $Context.Gold[$cleanWord]
            $sourceDict = 'gold'
        } elseif ($Context.Silver -and $Context.Silver.ContainsKey($lowWord)) {
            $entry = $Context.Silver[$lowWord]
            $sourceDict = 'silver'
        } elseif ($Context.Silver -and $Context.Silver.ContainsKey($cleanWord)) {
            $entry = $Context.Silver[$cleanWord]
            $sourceDict = 'silver'
        }

        if ($null -eq $entry) {
            # OOV word
            $oovItem = [pscustomobject]@{
                Word        = $cleanWord
                SourceStart = $sourceStart
                SourceEnd   = $sourceEnd
                ProjStart   = $pw.Start
                ProjEnd     = $pw.End
                Reason      = 'NotInLexicon'
            }
            $result.OovSpans.Add($oovItem)
            $result.UnresolvedSpans.Add($oovItem)
            $result.Tokens.Add([pscustomobject]@{
                Word       = $cleanWord
                Pron       = $null
                Status     = 'OOV'
                SourceDict = 'none'
                SourceStart = $sourceStart
                SourceEnd = $sourceEnd
                ProjStart = $pw.Start
                ProjEnd = $pw.End
                EmissionStart = $null
                EmissionEnd = $null
            })
            continue
        }

        # Check if ambiguous
        $selectedPron = $null
        $decisionRecord = $null

        if ($entry -is [System.Collections.IDictionary]) {
            # Ambiguous homograph: decide pronunciation
            $keys = @($entry.Keys)
            
            # Context-sensitive decision: check decision models or AST features
            $decisionModel = if ($Context.DecisionModels) { $Context.DecisionModels[$lowWord] } else { $null }

            $chosenKey = 'DEFAULT'
            $ruleFired = 'DefaultFallback'
            $firedDelta = 'BaseLexicon'

            # AST feature extraction for the target token
            $smaFeatureList = [System.Collections.Generic.List[string]]::new()
            $deepest = $null
            foreach ($n in $ast.FindAll({ param($node) $node.Extent.StartOffset -le $pw.Start -and $node.Extent.EndOffset -gt $pw.Start }, $true)) {
                $deepest = $n
            }
            if ($deepest) {
                $parent = $deepest.Parent
                $gp = if ($parent) { $parent.Parent } else { $null }
                $smaFeatureList.Add("Node=" + $deepest.GetType().Name)
                $smaFeatureList.Add("Parent=" + $(if ($parent) { $parent.GetType().Name } else { '-' }))
                $smaFeatureList.Add("Grand=" + $(if ($gp) { $gp.GetType().Name } else { '-' }))
                if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                    $els = @($parent.CommandElements)
                    $idx = [array]::IndexOf($els, $deepest)
                    $smaFeatureList.Add("ElemIdx=" + [math]::Min($idx, 6))
                    $smaFeatureList.Add("PrevNode=" + $(if ($idx -gt 0) { $els[$idx - 1].GetType().Name } else { '-' }))
                    $smaFeatureList.Add("NextNode=" + $(if ($idx -ge 0 -and $idx + 1 -lt $els.Count) { $els[$idx + 1].GetType().Name } else { '-' }))
                }
            }

            # Left/Right lexical neighbors
            $contextIndex=if ($legacy) {$i} else {$pw.GroupIndex}
            $prevWord = if ($contextIndex -gt 0) { $contextWords[$contextIndex - 1].Text.Trim("',-._/;:!?«»‐—…`"“”()").ToLowerInvariant() } else { '<S>' }
            $nextWord = if ($contextIndex + 1 -lt $contextWords.Count) { $contextWords[$contextIndex + 1].Text.Trim("',-._/;:!?«»‐—…`"“”()").ToLowerInvariant() } else { '<E>' }
            # A component boundary is not evidence of adjacent sentence syntax.
            if (-not $legacy -and $pw.IsComponent) {$prevWord='<Boundary>';$nextWord='<Boundary>'}

            $canonicalContext=[pscustomobject]@{
                AstArrayMembership=[int]($parent -is [System.Management.Automation.Language.ArrayLiteralAst])
                DeterminerContext=[int]($prevWord -cin @('a','an','the'))
                InfinitivalVerbContext=[int]($prevWord -ceq 'to' -and $entry.ContainsKey('VERB'))
            }
            $active=$Context.CandidateRepresentation
            $selectionFields=@($Context.SelectionCandidates)
            if ($null -ne $active) { $selectionFields+=@($active.Features) }
            foreach ($field in @($selectionFields | Sort-Object -Unique -CaseSensitive)) {
                $parts=$field.Split('|')
                if ($parts.Count -ne 2) { continue }
                $property=$canonicalContext.PSObject.Properties[$parts[0]]
                if ($null -eq $property) { throw 'Unknown selection applicability property.' }
                $canonicalContext | Add-Member -NotePropertyName $field -NotePropertyValue ([int]($property.Value -eq 1 -and $entry.ContainsKey($parts[1])))
            }
            $justifications=@(
                [pscustomobject]@{Id='projection';DependsOn=@('predecessor');Relation='Contains';From='ProjectedCommand';To='TargetToken'},
                [pscustomobject]@{Id='predecessor';DependsOn=@('context');Relation='PrecededBy';From='TargetToken';To='PreviousToken'},
                [pscustomobject]@{Id='context';DependsOn=@();Relation='TestsApplicability';From='PreviousToken';To='InfinitivalVerbContext'}
            )
            # If an active refinement / decision model exists, apply it
            if ($decisionModel) {
                $matched = $false
                foreach ($rule in $decisionModel.Rules) {
                    if ($rule.Matches($smaFeatureList, $prevWord, $nextWord, $deepest)) {
                        $chosenKey = $rule.TargetKey
                        $ruleFired = $rule.PredicateName
                        $firedDelta = $rule.DeltaId
                        $matched = $true
                        break
                    }
                }
                if (-not $matched -and $decisionModel.DefaultKey) {
                    $chosenKey = $decisionModel.DefaultKey
                    $ruleFired = 'ModelMajorKey'
                }
            } else {
                # Heuristic fallback: if DEFAULT exists, use it
                if ($entry.ContainsKey('DEFAULT')) {
                    $chosenKey = 'DEFAULT'
                } elseif ($entry.Count -gt 0) {
                    $chosenKey = @($entry.Keys)[0]
                }
            }

            $active=$Context.CandidateRepresentation
            if ($null -ne $active) {
                foreach ($feature in $active.Features) {
                    $property=$canonicalContext.PSObject.Properties[$feature]
                    $parts=$feature.Split('|')
                    $outcome=if ($parts.Count -eq 2) {$parts[1]} else {'VERB'}
                    if ($null -ne $property -and $property.Value -eq 1 -and $entry.ContainsKey($outcome)) {
                        $justifications[2].To=$feature
                        $chosenKey=$outcome;$ruleFired=$feature;$firedDelta='RetainedPercept';break
                    }
                }
            } else {
                if ($null -ne $Context.PSObject.Methods['ChoosePercept']) {
                    $selection=$Context.ChoosePercept($canonicalContext,$entry)
                    if ($null -ne $selection) {
                        $justifications[2].To=$selection.Feature
                        $chosenKey=$selection.Key;$ruleFired=$selection.Feature;$firedDelta='ExecutableRetainedPercept'
                    }
                }
            }
            $selectedPron = if ($entry.ContainsKey($chosenKey)) { $entry[$chosenKey] } else { $entry['DEFAULT'] }

            $decisionRecord = [pscustomobject]@{
                Word           = $cleanWord
                ChosenKey      = $chosenKey
                Pronunciation  = $selectedPron
                PredicateFired = $ruleFired
                DeltaId        = $firedDelta
                CandidateKeys  = @($entry.Keys)
                SmaFeatures    = $smaFeatureList.ToArray()
                PrevWord       = $prevWord
                NextWord       = $nextWord
                SourceStart    = $sourceStart
                SourceEnd      = $sourceEnd
                CanonicalContext = $canonicalContext
                Justifications = $justifications
            }
            $result.AmbiguousDecisions.Add($decisionRecord)
            $result.Provenance.Add("Word '$cleanWord' resolved to key '$chosenKey' via predicate '$ruleFired' (Delta: $firedDelta).")
        } else {
            # Unambiguous string pronunciation
            $selectedPron = [string]$entry
        }

        # Validate phonemes against Kokoro inventory
        $validPhones = -not [string]::IsNullOrEmpty($selectedPron)
        foreach ($ch in ([string]$selectedPron).ToCharArray()) {
            if (-not $Context.KokoroVocab.Contains($ch)) {
                $validPhones = $false
                break
            }
        }

        $tokenRecord=[pscustomobject]@{
            Word        = $cleanWord
            Pron        = $selectedPron
            Status      = if ($validPhones) { 'Valid' } else { 'InvalidPhone' }
            SourceDict  = $sourceDict
            IsAmbiguous = ($null -ne $decisionRecord)
            SourceStart = $sourceStart
            SourceEnd = $sourceEnd
            ProjStart = $pw.Start
            ProjEnd = $pw.End
            EmissionStart = $null
            EmissionEnd = $null
        }
        $result.Tokens.Add($tokenRecord)

        if (-not $validPhones) {$result.UnresolvedSpans.Add([pscustomobject]@{Word=$cleanWord;SourceStart=$sourceStart;SourceEnd=$sourceEnd;Reason='InvalidOrEmptyPronunciation'})}
        if ($selectedPron -and ($legacy -or $validPhones)) {
            if ($emittedPhones.Count -gt 0) {$emissionCursor++}
            $tokenRecord.EmissionStart=$emissionCursor;$emissionCursor+=$selectedPron.Length;$tokenRecord.EmissionEnd=$emissionCursor
            $emittedPhones.Add($selectedPron)
        }
    }

    $result.KokoroPhones = ($emittedPhones -join ' ')
    $result.Complete = $result.UnresolvedSpans.Count -eq 0
    $swTotal.Stop()

    $result.Timing = [pscustomobject]@{
        TotalMs      = $swTotal.Elapsed.TotalMilliseconds
        ProjectionMs = $swProj.Elapsed.TotalMilliseconds
        ParseMs      = $swParse.Elapsed.TotalMilliseconds
    }

    return $result
}

# Narrow compatibility import. The directly launchable script owns the native
# product; explicitly initialized refinement contexts retain their frozen path.
if ($null -eq (Get-Command Invoke-EnglishPhonemizer -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Dev.MansfieldPlumbing.English.Phonemizer.ps1') -Import
}
