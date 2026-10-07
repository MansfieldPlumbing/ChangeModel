# Exhaustive vs Greedy Comparison on 30-sentence Training Subset
# Governed by NIST SP 800-218 and prompt specifications:
# 1. Evaluate all 768 configurations exhaustively.
# 2. Run greedy hill-climb on the same vocabulary.
# 3. Report whether greedy reaches the exhaustive optimum.
# 4. Save plain-text / TSV receipts.

$baseDir = "C:\temp\sma-english-projection"
. "$baseDir\tools\EvaluationEngine.ps1"

$trainPath = "$baseDir\inputs\train_500.tsv"
$spacyPath = "$baseDir\inputs\spacy_train_500.tsv"
$trainLines = [System.IO.File]::ReadAllLines($trainPath)
$spacyLines = [System.IO.File]::ReadAllLines($spacyPath)

# Collect first 30 sentences
$sentences = [string[]]::new(30)
for ($i = 0; $i -lt 30; $i++) {
    $sentences[$i] = $trainLines[$i + 1].Split([char]9)[5]
}

# Collect spaCy tokens for first 30 sentences
$spacyMap = [System.Collections.Generic.Dictionary[int, object]]::new()
for ($i = 1; $i -lt $spacyLines.Length; $i++) {
    $line = $spacyLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $cols = $line.Split([char]9)
    $sId = [int]::Parse($cols[0])
    if ($sId -ge 30) { break }
    if (-not $spacyMap.ContainsKey($sId)) {
        $spacyMap[$sId] = [System.Collections.Generic.List[object]]::new()
    }
    $spacyMap[$sId].Add([PSCustomObject]@{
        SentenceId = $sId
        TokenIdx   = [int]::Parse($cols[1])
        Start      = [int]::Parse($cols[2])
        End        = [int]::Parse($cols[3])
        Text       = $cols[4]
        Pos        = $cols[5]
        Dep        = $cols[6]
    })
}

# Define mutation vocabulary slots
$slotPrefix = @("none", "qmark", "slash", "spade")
$slotApos   = @("none", "escaped", "modifier", "backtick")
$slotHash   = @("none", "fullwidth")
$slotSemi   = @("none", "fullwidth")
$slotTerm   = @("none", "space", "nbsp")
$slotHyph   = @("none", "unicode")
$slotQuot   = @("none", "guillemets")

Write-Output "=== PHASE 1: EXHAUSTIVE EVALUATION (768 COMBINATIONS) ==="

$allResults = [System.Collections.Generic.List[EvalResult]]::new()
$exhaustiveReceipts = [System.Collections.Generic.List[string]]::new()
$exhaustiveReceipts.Add("config_key`terrors`tfailing_sent`tuseful_ast`tboundary_diff`tmut_count`tfidelity_passed")

$evalCount = 0
$bestExhaustive = $null

foreach ($p in $slotPrefix) {
    foreach ($a in $slotApos) {
        foreach ($h in $slotHash) {
            foreach ($s in $slotSemi) {
                foreach ($t in $slotTerm) {
                    foreach ($hy in $slotHyph) {
                        foreach ($q in $slotQuot) {
                            $cfg = [ProjectionConfig]::new()
                            $cfg.Prefix = $p
                            $cfg.Apostrophe = $a
                            $cfg.Hash = $h
                            $cfg.Semicolon = $s
                            $cfg.TermPunct = $t
                            $cfg.Hyphen = $hy
                            $cfg.Quote = $q

                            $res = EvaluateDataset $sentences $spacyMap $cfg
                            $evalCount++
                            $allResults.Add($res)

                            $exhaustiveReceipts.Add("$($res.ConfigKey)`t$($res.TotalErrors)`t$($res.FailingSentences)`t$($res.UsefulAstScore)`t$($res.BoundaryDisagreements)`t$($res.MutationCount)`t$($res.FidelityPassed)")

                            if ($bestExhaustive -eq $null) {
                                $bestExhaustive = $res
                            } else {
                                $cmp = CompareResults $res $bestExhaustive
                                if ($cmp -gt 0) {
                                    $bestExhaustive = $res
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

Write-Output "Exhaustive evaluations completed: $evalCount"
Write-Output "Best Exhaustive Score: $($bestExhaustive.FormatScore())"
Write-Output "Best Exhaustive Config: $($bestExhaustive.ConfigKey)"

# Save exhaustive receipts
$exhPath = "$baseDir\receipts\exhaustive_30_receipts.tsv"
[System.IO.File]::WriteAllLines($exhPath, $exhaustiveReceipts)
Write-Output "Saved exhaustive receipts to $exhPath"

Write-Output ""
Write-Output "=== PHASE 2: GREEDY HILL-CLIMB ON 30 SENTENCES ==="

$currentCfg = [ProjectionConfig]::new() # start at baseline
$currentRes = EvaluateDataset $sentences $spacyMap $currentCfg

$greedyReceipts = [System.Collections.Generic.List[string]]::new()
$greedyReceipts.Add("step`tmutation_tested`tscore_before`tscore_after`tstatus`tconfig_key")

Write-Output "Greedy Start (Baseline): $($currentRes.FormatScore())"
$greedyReceipts.Add("0`tbaseline`tN/A`t$($currentRes.FormatScore())`taccepted`t$($currentCfg.GetKey())")

$neutralMovesLeft = 5
$step = 0
$greedyEvaluations = 0

while ($true) {
    $step++
    $bestCandidate = $null
    $bestCandidateCfg = $null
    $bestCandidateName = ""
    $bestCandidateCmp = -999

    # Generate all single-mutation neighbors from current config
    $candidateList = [System.Collections.Generic.List[object]]::new()

    # Slot 1: Prefix
    foreach ($v in $slotPrefix) {
        if ($v -ne $currentCfg.Prefix) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $v; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $candidateList.Add([PSCustomObject]@{ Name = "Prefix=$v"; Cfg = $c })
        }
    }
    # Slot 2: Apostrophe
    foreach ($v in $slotApos) {
        if ($v -ne $currentCfg.Apostrophe) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $v; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $candidateList.Add([PSCustomObject]@{ Name = "Apos=$v"; Cfg = $c })
        }
    }
    # Slot 3: Hash
    foreach ($v in $slotHash) {
        if ($v -ne $currentCfg.Hash) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $v; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $candidateList.Add([PSCustomObject]@{ Name = "Hash=$v"; Cfg = $c })
        }
    }
    # Slot 4: Semicolon
    foreach ($v in $slotSemi) {
        if ($v -ne $currentCfg.Semicolon) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $v; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $candidateList.Add([PSCustomObject]@{ Name = "Semi=$v"; Cfg = $c })
        }
    }
    # Slot 5: TermPunct
    foreach ($v in $slotTerm) {
        if ($v -ne $currentCfg.TermPunct) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $v; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $candidateList.Add([PSCustomObject]@{ Name = "Term=$v"; Cfg = $c })
        }
    }
    # Slot 6: Hyphen
    foreach ($v in $slotHyph) {
        if ($v -ne $currentCfg.Hyphen) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $v; $c.Quote = $currentCfg.Quote
            $candidateList.Add([PSCustomObject]@{ Name = "Hyphen=$v"; Cfg = $c })
        }
    }
    # Slot 7: Quote
    foreach ($v in $slotQuot) {
        if ($v -ne $currentCfg.Quote) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $v
            $candidateList.Add([PSCustomObject]@{ Name = "Quote=$v"; Cfg = $c })
        }
    }

    # Evaluate all candidates
    foreach ($cand in $candidateList) {
        $greedyEvaluations++
        $res = EvaluateDataset $sentences $spacyMap $cand.Cfg
        $cmp = CompareResults $res $currentRes

        # Check if this candidate is better than our best seen this step
        if ($bestCandidate -eq $null) {
            $bestCandidate = $res
            $bestCandidateCfg = $cand.Cfg
            $bestCandidateName = $cand.Name
            $bestCandidateCmp = $cmp
        } else {
            $candCmpBest = CompareResults $res $bestCandidate
            if ($candCmpBest -gt 0) {
                $bestCandidate = $res
                $bestCandidateCfg = $cand.Cfg
                $bestCandidateName = $cand.Name
                $bestCandidateCmp = $cmp
            }
        }
    }

    # Decide whether to step
    if ($bestCandidateCmp -gt 0) {
        # Strict improvement
        $greedyReceipts.Add("${step}`t${bestCandidateName}`t$($currentRes.FormatScore())`t$($bestCandidate.FormatScore())`taccepted`t$($bestCandidateCfg.GetKey())")
        Write-Output "Step ${step}: ACCEPTED ${bestCandidateName} -> $($bestCandidate.FormatScore())"
        $currentCfg = $bestCandidateCfg
        $currentRes = $bestCandidate
    } elseif ($bestCandidateCmp -eq 0 -and $neutralMovesLeft -gt 0) {
        # Neutral move
        $neutralMovesLeft--
        $greedyReceipts.Add("${step}`t${bestCandidateName}`t$($currentRes.FormatScore())`t$($bestCandidate.FormatScore())`tneutral`t$($bestCandidateCfg.GetKey())")
        Write-Output "Step ${step}: NEUTRAL ${bestCandidateName} (Neutral moves left: $neutralMovesLeft) -> $($bestCandidate.FormatScore())"
        $currentCfg = $bestCandidateCfg
        $currentRes = $bestCandidate
    } else {
        # Stagnation / no improvement
        Write-Output "Greedy search converged at step ${step}. No further improvements."
        break
    }

    if ($step -ge 20) { break }
}

$greedyPath = "$baseDir\receipts\greedy_30_receipts.tsv"
[System.IO.File]::WriteAllLines($greedyPath, $greedyReceipts)
Write-Output "Saved greedy receipts to $greedyPath"

Write-Output ""
Write-Output "=== PHASE 3: COMPARISON (GREEDY VS EXHAUSTIVE OPTIMUM) ==="
Write-Output "Exhaustive Best: $($bestExhaustive.FormatScore()) [$($bestExhaustive.ConfigKey)]"
Write-Output "Greedy Final   : $($currentRes.FormatScore()) [$($currentCfg.GetKey())]"

$cmpFinal = CompareResults $currentRes $bestExhaustive
if ($cmpFinal -eq 0) {
    Write-Output "RESULT: Greedy REACHED the Exhaustive Optimum! (Exact match)"
} elseif ($cmpFinal -gt 0) {
    Write-Output "RESULT: Greedy EXCEEDED prior recorded best!"
} else {
    Write-Output "RESULT: Greedy stopped short of Exhaustive Optimum."
}
