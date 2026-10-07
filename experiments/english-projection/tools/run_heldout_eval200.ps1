# Single-Pass Evaluation of Frozen Model on Held-Out 200 Sentences
# STRICT RULE: Executed EXACTLY ONCE after search is frozen.
# Evaluates baseline vs frozen projection.
# Verifies 100% bit-for-bit lossless reversibility.
# Categorizes all remaining failures and maps to PowerShell source locations.

$baseDir = "C:\temp\sma-english-projection"
. "$baseDir\tools\EvaluationEngine.ps1"

$evalPath = "$baseDir\inputs\eval_200.tsv"
$evalLines = [System.IO.File]::ReadAllLines($evalPath)

$sentences = [string[]]::new(200)
for ($i = 0; $i -lt 200; $i++) {
    $sentences[$i] = $evalLines[$i + 1].Split([char]9)[5]
}

# 1. Baseline Evaluation on Eval 200 (all none)
$baseCfg = [ProjectionConfig]::new()
$baseRes = EvaluateDataset $sentences $null $baseCfg

# 2. Frozen Best Configuration
$frozenCfg = [ProjectionConfig]::new()
$frozenCfg.Prefix = "slash"
$frozenCfg.Apostrophe = "modifier"
$frozenCfg.Hash = "fullwidth"
$frozenCfg.Semicolon = "fullwidth"
$frozenCfg.TermPunct = "space"
$frozenCfg.Hyphen = "unicode"
$frozenCfg.Quote = "guillemets"

$frozenRes = EvaluateDataset $sentences $null $frozenCfg

# 3. Detailed Failure Accounting on Frozen Projection
$failureRows = [System.Collections.Generic.List[string]]::new()
$failureRows.Add("eval_id`terror_count`terror_ids`terror_messages`textents`tcontext_snippet`tsentence_text")

$errorCategoryCounts = [System.Collections.Generic.Dictionary[string, int]]::new()
$allPassedReversibility = $true

for ($i = 0; $i -lt 200; $i++) {
    $raw = $sentences[$i]
    $proj = ProjectSentence $raw $frozenCfg

    # Check reversibility
    $rev = ReverseProjectSentence $proj $frozenCfg
    if ($rev -ne $raw) {
        $allPassedReversibility = $false
    }

    $errors = [System.Management.Automation.Language.ParseError[]]@()
    $tokens = [System.Management.Automation.Language.Token[]]@()
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($proj, [ref]$tokens, [ref]$errors)

    if ($errors.Length -gt 0) {
        $errIds = ($errors | ForEach-Object { $_.ErrorId }) -join ","
        $errMsgs = ($errors | ForEach-Object { $_.Message.Replace("`t", " ") }) -join " | "
        $extents = ($errors | ForEach-Object { "$($_.Extent.StartOffset)..$($_.Extent.EndOffset)" }) -join ","
        $firstErr = $errors[0]
        $snipStart = [Math]::Max(0, $firstErr.Extent.StartOffset - 10)
        $snipLen = [Math]::Min(30, $proj.Length - $snipStart)
        $snip = $proj.Substring($snipStart, $snipLen).Replace("`t", " ")

        $failureRows.Add("${i}`t$($errors.Length)`t${errIds}`t${errMsgs}`t${extents}`t${snip}`t${raw}")

        foreach ($e in $errors) {
            $eid = $e.ErrorId
            if (-not $errorCategoryCounts.ContainsKey($eid)) { $errorCategoryCounts[$eid] = 0 }
            $errorCategoryCounts[$eid]++
        }
    }
}

# 4. Write Results
$outTsv = "$baseDir\results\heldout_eval200_failures.tsv"
[System.IO.File]::WriteAllLines($outTsv, $failureRows)

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add("=== HELD-OUT EVAL 200 SINGLE-PASS VERIFICATION ===")
$summaryLines.Add("Total Sentences: 200")
$summaryLines.Add("Lossless Reversibility Verified: $allPassedReversibility (100% bit-for-bit)")
$summaryLines.Add("")
$summaryLines.Add("BASELINE EVAL 200:")
$summaryLines.Add("  Errors: $($baseRes.TotalErrors)")
$summaryLines.Add("  Failing Sentences: $($baseRes.FailingSentences) / 200 (Pass rate: $( [Math]::Round((200 - $baseRes.FailingSentences)/2.0, 1) )%)")
$summaryLines.Add("  Useful AST Score: $($baseRes.UsefulAstScore)")
$summaryLines.Add("")
$summaryLines.Add("FROZEN PROJECTION EVAL 200:")
$summaryLines.Add("  Config: $($frozenCfg.GetKey())")
$summaryLines.Add("  Errors: $($frozenRes.TotalErrors)")
$summaryLines.Add("  Failing Sentences: $($frozenRes.FailingSentences) / 200 (Pass rate: $( [Math]::Round((200 - $frozenRes.FailingSentences)/2.0, 1) )%)")
$summaryLines.Add("  Useful AST Score: $($frozenRes.UsefulAstScore)")
$summaryLines.Add("")
$summaryLines.Add("ERROR REDUCTION: $($baseRes.TotalErrors) errors -> $($frozenRes.TotalErrors) errors")
$summaryLines.Add("FAILURE REDUCTION: $($baseRes.FailingSentences) failing -> $($frozenRes.FailingSentences) failing")
$summaryLines.Add("")
$summaryLines.Add("REMAINING ERROR BREAKDOWN:")
foreach ($k in $errorCategoryCounts.Keys) {
    $summaryLines.Add("  ${k}: $($errorCategoryCounts[$k])")
}

$outSummary = "$baseDir\results\heldout_eval200_summary.txt"
[System.IO.File]::WriteAllLines($outSummary, $summaryLines)

Write-Output "Held-out evaluation complete."
Write-Output "Baseline: $($baseRes.TotalErrors) errors ($($baseRes.FailingSentences) failing)"
Write-Output "Frozen  : $($frozenRes.TotalErrors) errors ($($frozenRes.FailingSentences) failing)"
Write-Output "Pass rate: $( [Math]::Round((200 - $frozenRes.FailingSentences)/2.0, 1) )%"
Write-Output "Reversibility: $allPassedReversibility"
