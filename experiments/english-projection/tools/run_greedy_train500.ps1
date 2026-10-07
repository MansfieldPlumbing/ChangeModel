# Greedy Hill-Climb on Full 500 Training Sentences
# Governed by NIST SP 800-218 and prompt specifications:
# - Single-variable mutation steps.
# - Primary ordering:
#   1. Fewer parse errors
#   2. 100% source-coordinate fidelity
#   3. Higher useful AST-structure score
#   4. Fewer token-boundary disagreements against spaCy
#   5. Smaller mutation set
# - Retain strict improvements, at most 5 explicitly recorded neutral moves.
# - Max 2,000 candidate evaluations.
# - Output full receipts to receipts/greedy_train500_receipts.tsv.

$baseDir = "C:\temp\sma-english-projection"
. "$baseDir\tools\EvaluationEngine.ps1"

$trainPath = "$baseDir\inputs\train_500.tsv"
$spacyPath = "$baseDir\inputs\spacy_train_500.tsv"
$trainLines = [System.IO.File]::ReadAllLines($trainPath)
$spacyLines = [System.IO.File]::ReadAllLines($spacyPath)

# Collect all 500 sentences
$sentences = [string[]]::new(500)
for ($i = 0; $i -lt 500; $i++) {
    $sentences[$i] = $trainLines[$i + 1].Split([char]9)[5]
}

# Collect spaCy tokens for all 500 sentences
$spacyMap = [System.Collections.Generic.Dictionary[int, object]]::new()
for ($i = 1; $i -lt $spacyLines.Length; $i++) {
    $line = $spacyLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $cols = $line.Split([char]9)
    $sId = [int]::Parse($cols[0])
    if ($sId -ge 500) { break }
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

# Define frozen mutation vocabulary slots
$slotPrefix = @("none", "qmark", "slash", "spade")
$slotApos   = @("none", "escaped", "modifier", "backtick")
$slotHash   = @("none", "fullwidth")
$slotSemi   = @("none", "fullwidth")
$slotTerm   = @("none", "space", "nbsp")
$slotHyph   = @("none", "unicode")
$slotQuot   = @("none", "guillemets")

$receipts = [System.Collections.Generic.List[string]]::new()
$receipts.Add("eval_id`tstep`tmutation_tested`tscore_before`tscore_after`tstatus`taffected_sentences`tconfig_key")

$currentCfg = [ProjectionConfig]::new() # baseline
$currentRes = EvaluateDataset $sentences $spacyMap $currentCfg

Write-Output "=== GREEDY HILL-CLIMB ON 500 TRAINING SENTENCES ==="
Write-Output "Initial Baseline Score: $($currentRes.FormatScore())"
$receipts.Add("0`t0`tbaseline`tN/A`t$($currentRes.FormatScore())`taccepted`t0`t$($currentCfg.GetKey())")

$neutralMovesLeft = 5
$step = 0
$totalEvals = 0

while ($totalEvals -lt 2000) {
    $step++
    $bestStepCandidate = $null
    $bestStepCfg = $null
    $bestStepName = ""
    $bestStepCmp = -999
    $bestStepAffected = 0

    # Generate all 1-mutation neighbors
    $neighbors = [System.Collections.Generic.List[object]]::new()

    # Slot 1: Prefix
    foreach ($v in $slotPrefix) {
        if ($v -ne $currentCfg.Prefix) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $v; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $neighbors.Add([PSCustomObject]@{ Name = "Prefix=$v"; Cfg = $c })
        }
    }
    # Slot 2: Apostrophe
    foreach ($v in $slotApos) {
        if ($v -ne $currentCfg.Apostrophe) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $v; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $neighbors.Add([PSCustomObject]@{ Name = "Apos=$v"; Cfg = $c })
        }
    }
    # Slot 3: Hash
    foreach ($v in $slotHash) {
        if ($v -ne $currentCfg.Hash) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $v; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $neighbors.Add([PSCustomObject]@{ Name = "Hash=$v"; Cfg = $c })
        }
    }
    # Slot 4: Semicolon
    foreach ($v in $slotSemi) {
        if ($v -ne $currentCfg.Semicolon) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $v; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $neighbors.Add([PSCustomObject]@{ Name = "Semi=$v"; Cfg = $c })
        }
    }
    # Slot 5: TermPunct
    foreach ($v in $slotTerm) {
        if ($v -ne $currentCfg.TermPunct) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $v; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $currentCfg.Quote
            $neighbors.Add([PSCustomObject]@{ Name = "Term=$v"; Cfg = $c })
        }
    }
    # Slot 6: Hyphen
    foreach ($v in $slotHyph) {
        if ($v -ne $currentCfg.Hyphen) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $v; $c.Quote = $currentCfg.Quote
            $neighbors.Add([PSCustomObject]@{ Name = "Hyphen=$v"; Cfg = $c })
        }
    }
    # Slot 7: Quote
    foreach ($v in $slotQuot) {
        if ($v -ne $currentCfg.Quote) {
            $c = [ProjectionConfig]::new()
            $c.Prefix = $currentCfg.Prefix; $c.Apostrophe = $currentCfg.Apostrophe; $c.Hash = $currentCfg.Hash; $c.Semicolon = $currentCfg.Semicolon; $c.TermPunct = $currentCfg.TermPunct; $c.Hyphen = $currentCfg.Hyphen; $c.Quote = $v
            $neighbors.Add([PSCustomObject]@{ Name = "Quote=$v"; Cfg = $c })
        }
    }

    # Evaluate each neighbor
    foreach ($neighbor in $neighbors) {
        $totalEvals++
        $res = EvaluateDataset $sentences $spacyMap $neighbor.Cfg
        $cmp = CompareResults $res $currentRes

        # Count affected sentences (sentences with error change)
        $affected = [Math]::Abs($res.FailingSentences - $currentRes.FailingSentences)
        if ($affected -eq 0 -and $res.TotalErrors -ne $currentRes.TotalErrors) {
            $affected = [Math]::Abs($res.TotalErrors - $currentRes.TotalErrors)
        }

        # Track best step candidate
        if ($bestStepCandidate -eq $null) {
            $bestStepCandidate = $res
            $bestStepCfg = $neighbor.Cfg
            $bestStepName = $neighbor.Name
            $bestStepCmp = $cmp
            $bestStepAffected = $affected
        } else {
            $candCmpBest = CompareResults $res $bestStepCandidate
            if ($candCmpBest -gt 0) {
                $bestStepCandidate = $res
                $bestStepCfg = $neighbor.Cfg
                $bestStepName = $neighbor.Name
                $bestStepCmp = $cmp
                $bestStepAffected = $affected
            }
        }
    }

    # Decide step outcome
    if ($bestStepCmp -gt 0) {
        $receipts.Add("${totalEvals}`t${step}`t${bestStepName}`t$($currentRes.FormatScore())`t$($bestStepCandidate.FormatScore())`taccepted`t${bestStepAffected}`t$($bestStepCfg.GetKey())")
        Write-Output "Step ${step} (Eval ${totalEvals}): ACCEPTED ${bestStepName} -> $($bestStepCandidate.FormatScore())"
        $currentCfg = $bestStepCfg
        $currentRes = $bestStepCandidate
    } elseif ($bestStepCmp -eq 0 -and $neutralMovesLeft -gt 0) {
        $neutralMovesLeft--
        $receipts.Add("${totalEvals}`t${step}`t${bestStepName}`t$($currentRes.FormatScore())`t$($bestStepCandidate.FormatScore())`tneutral`t${bestStepAffected}`t$($bestStepCfg.GetKey())")
        Write-Output "Step ${step} (Eval ${totalEvals}): NEUTRAL ${bestStepName} (Neutrals left: ${neutralMovesLeft}) -> $($bestStepCandidate.FormatScore())"
        $currentCfg = $bestStepCfg
        $currentRes = $bestStepCandidate
    } else {
        Write-Output "Greedy hill-climb converged at step ${step} after ${totalEvals} evaluations. No further improvement."
        break
    }
}

$receiptsPath = "$baseDir\receipts\greedy_train500_receipts.tsv"
[System.IO.File]::WriteAllLines($receiptsPath, $receipts)
Write-Output "Saved receipts to $receiptsPath"

Write-Output ""
Write-Output "=== HILL-CLIMB FINAL RESULT ==="
Write-Output "Final Config : $($currentCfg.GetKey())"
Write-Output "Final Score  : $($currentRes.FormatScore())"
Write-Output "Total Evals  : $totalEvals"

# Save winning configuration to a dedicated file
$winCfgPath = "$baseDir\results\frozen_best_config.tsv"
$winLines = @(
    "Slot`tValue",
    "Prefix`t$($currentCfg.Prefix)",
    "Apostrophe`t$($currentCfg.Apostrophe)",
    "Hash`t$($currentCfg.Hash)",
    "Semicolon`t$($currentCfg.Semicolon)",
    "TermPunct`t$($currentCfg.TermPunct)",
    "Hyphen`t$($currentCfg.Hyphen)",
    "Quote`t$($currentCfg.Quote)",
    "ConfigKey`t$($currentCfg.GetKey())",
    "Score`t$($currentRes.FormatScore())"
)
[System.IO.File]::WriteAllLines($winCfgPath, $winLines)
Write-Output "Saved frozen winning configuration to $winCfgPath"
