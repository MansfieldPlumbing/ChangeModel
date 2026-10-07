#requires -Version 7.4
# Dev.MansfieldPlumbing.PowerShell.Perception - Frontend Phonemizer
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\experiments\english-projection\expB\Projection.ps1')
. (Join-Path $PSScriptRoot 'Refine.ps1')

class PhonemeResult {
    [string]$OriginalText
    [string]$ProjectedText
    [bool]$Reversible
    [System.Collections.Generic.List[object]]$Tokens
    [string]$KokoroPhones
    [System.Collections.Generic.List[object]]$AmbiguousDecisions
    [System.Collections.Generic.List[object]]$OovSpans
    [System.Collections.Generic.List[string]]$Provenance
    [pscustomobject]$Timing

    PhonemeResult() {
        $this.Tokens = [System.Collections.Generic.List[object]]::new()
        $this.AmbiguousDecisions = [System.Collections.Generic.List[object]]::new()
        $this.OovSpans = [System.Collections.Generic.List[object]]::new()
        $this.Provenance = [System.Collections.Generic.List[string]]::new()
    }
}

class PhonemizerContext {
    [hashtable]$Gold
    [hashtable]$Silver
    [hashtable]$DecisionModels  # Homograph decision models
    [object]$RefinementStore
    [object]$CandidateRepresentation
    [object]$RefinementResult
    [System.Collections.Generic.HashSet[char]]$KokoroVocab
    [System.Collections.Generic.HashSet[string]]$MultiWords

    PhonemizerContext() {
        $this.KokoroVocab = [System.Collections.Generic.HashSet[char]]::new()
        # Pinned Kokoro US vocabulary: US_VOCAB + special punctuation
        foreach ($c in 'AIOWYbdfhijklmnpstuvwzæðŋɑɔəɛɜɡɪɹɾʃʊʌʒʤʧˈˌθᵊᵻʔɐ'.ToCharArray()) {
            [void]$this.KokoroVocab.Add($c)
        }
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

function Initialize-Phonemizer {
    param(
        [string]$GoldPath = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_gold.json'),
        [string]$SilverPath = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_silver.json'),
        [object[]]$Experience = @(),
        [PhonemizerContext]$Context = $null
    )

    $ctx = if ($null -ne $Context) {$Context} else {[PhonemizerContext]::new()}
    if ($null -eq $Context) { $ctx.LoadLexicons($GoldPath, $SilverPath) }
    $script:GlobalContext = $ctx
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
    $ctx
}

function Measure-PhonemizerRepresentation {
    param([array]$History,[object]$Rep,[string]$RepVersion,[PhonemizerContext]$Context)
    $replay=[Collections.Generic.List[object]]::new();$errors=0
    $previous=$Context.CandidateRepresentation
    try {
        $Context.CandidateRepresentation=$Rep
        foreach ($row in $History) {
            $result=Get-SmaPhonemes -Text $row.Sentence -Context $Context
            $decision=@($result.AmbiguousDecisions | Where-Object { $_.Word.ToLowerInvariant() -ceq $row.Word.ToLowerInvariant() })[0]
            $expected=$Context.Gold[$row.Word][$row.ExpectedKey]
            $wrong=[int]($decision.Pronunciation -cne $expected);$errors+=$wrong
            $represented=$Rep.GetRepresentedState($row.CanonicalBefore)
            $replay.Add((New-ObservationRecord -RepresentationVersion $RepVersion -CanonicalBefore $row.CanonicalBefore -RepresentedBefore $represented -Action $row.Action -PredictedDelta $(if ($decision.ChosenKey -ceq 'VERB') {1} else {0}) -ActualDelta $row.ActualDelta -PredictionError $wrong -ConditionKey (Get-ConditionKey $represented $row.Action)))
        }
    } finally { $Context.CandidateRepresentation=$previous }
    [pscustomobject]@{Contradictions=0;PredictionError=$errors;RepresentationComplexity=$Rep.Features.Count;ReplayHistory=$replay}
}

function Get-SmaPhonemes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Text,

        [PhonemizerContext]$Context = $script:GlobalContext
    )

    if ($null -eq $Context) {
        $Context = Initialize-Phonemizer
    }

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
    $projWords = Get-ProjectedWords $proj

    $result = [PhonemeResult]::new()
    $result.OriginalText = $Text
    $result.ProjectedText = $proj.Text
    $result.Reversible = $proj.Reversible

    $emittedPhones = [System.Collections.Generic.List[string]]::new()

    # Step 4: Token-by-token pronunciation decision & assembly
    for ($i = 0; $i -lt $projWords.Count; $i++) {
        $pw = $projWords[$i]
        $cleanWord = $pw.Text.Trim("',-._/;:!?«»‐—…`"“”()")
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
            $result.Tokens.Add([pscustomobject]@{
                Word       = $cleanWord
                Pron       = $null
                Status     = 'OOV'
                SourceDict = 'none'
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
            $prevWord = if ($i -gt 0) { $projWords[$i - 1].Text.Trim("',-._/;:!?«»‐—…`"“”()").ToLowerInvariant() } else { '<S>' }
            $nextWord = if ($i + 1 -lt $projWords.Count) { $projWords[$i + 1].Text.Trim("',-._/;:!?«»‐—…`"“”()").ToLowerInvariant() } else { '<E>' }

            $canonicalContext=[pscustomobject]@{
                AstArrayMembership=[int]($parent -is [System.Management.Automation.Language.ArrayLiteralAst])
                DeterminerContext=[int]($prevWord -cin @('a','an','the'))
                InfinitivalVerbContext=[int]($prevWord -ceq 'to' -and $entry.ContainsKey('VERB'))
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
            if ($null -eq $active -and $null -ne $Context.RefinementStore) { $active=$Context.RefinementStore.Current.Representation }
            if ($null -ne $active) {
                foreach ($feature in $active.Features) {
                    $property=$canonicalContext.PSObject.Properties[$feature]
                    if ($null -ne $property -and $property.Value -eq 1 -and $entry.ContainsKey('VERB')) {
                        $chosenKey='VERB';$ruleFired=$feature;$firedDelta='RetainedPercept';break
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
        $validPhones = $true
        foreach ($ch in $selectedPron.ToCharArray()) {
            if (-not $Context.KokoroVocab.Contains($ch)) {
                $validPhones = $false
                break
            }
        }

        $result.Tokens.Add([pscustomobject]@{
            Word        = $cleanWord
            Pron        = $selectedPron
            Status      = if ($validPhones) { 'Valid' } else { 'InvalidPhone' }
            SourceDict  = $sourceDict
            IsAmbiguous = ($null -ne $decisionRecord)
        })

        if ($selectedPron) {
            $emittedPhones.Add($selectedPron)
        }
    }

    $result.KokoroPhones = ($emittedPhones -join ' ')
    $swTotal.Stop()

    $result.Timing = [pscustomobject]@{
        TotalMs      = $swTotal.Elapsed.TotalMilliseconds
        ProjectionMs = $swProj.Elapsed.TotalMilliseconds
        ParseMs      = $swParse.Elapsed.TotalMilliseconds
    }

    return $result
}
