#requires -Version 7.4
# Dev.MansfieldPlumbing.PowerShell.Perception - Frontend Phonemizer
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\experiments\english-projection\expB\Projection.ps1')

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
        [string]$SilverPath = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\misaki\us_silver.json')
    )

    $ctx = [PhonemizerContext]::new()
    $ctx.LoadLexicons($GoldPath, $SilverPath)
    $script:GlobalContext = $ctx
    $ctx
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
