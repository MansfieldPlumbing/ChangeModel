# Measure baseline on full 500 training sentences
$baseDir = "C:\temp\sma-english-projection"
$trainPath = [System.IO.Path]::Combine($baseDir, "inputs", "train_500.tsv")
$trainLines = [System.IO.File]::ReadAllLines($trainPath)

$errorIdCounts = [System.Collections.Generic.Dictionary[string, int]]::new()
$failingSentences = [System.Collections.Generic.List[string]]::new()
$totalErrors = 0
$failingCount = 0

for ($i = 1; $i -lt $trainLines.Length; $i++) {
    $line = $trainLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line.Split([char]9)
    $sId = [int]::Parse($parts[0])
    $sent = $parts[5]

    $errors = [System.Management.Automation.Language.ParseError[]]@()
    $tokens = [System.Management.Automation.Language.Token[]]@()
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($sent, [ref]$tokens, [ref]$errors)

    if ($errors.Length -gt 0) {
        $failingCount++
        $totalErrors += $errors.Length
        $errSummary = ($errors | ForEach-Object { $_.ErrorId }) -join ","
        $failingSentences.Add("${sId}`t$($errors.Length)`t${errSummary}`t${sent}")
        foreach ($e in $errors) {
            $eid = $e.ErrorId
            if (-not $errorIdCounts.ContainsKey($eid)) { $errorIdCounts[$eid] = 0 }
            $errorIdCounts[$eid]++
        }
    }
}

$summary = [System.Collections.Generic.List[string]]::new()
$summary.Add("=== TRAIN 500 BASELINE MEASUREMENT ===")
$summary.Add("Total Sentences: 500")
$summary.Add("Passing Sentences (0 errors): $(500 - $failingCount)")
$summary.Add("Failing Sentences (>=1 error): ${failingCount}")
$summary.Add("Total Parse Errors: ${totalErrors}")
$summary.Add("")
$summary.Add("ErrorId Breakdown:")
foreach ($k in $errorIdCounts.Keys) {
    $summary.Add("  ${k}: $($errorIdCounts[$k])")
}

$reportPath = [System.IO.Path]::Combine($baseDir, "results", "train500_baseline_summary.txt")
$failuresPath = [System.IO.Path]::Combine($baseDir, "results", "train500_baseline_failures.tsv")

[System.IO.File]::WriteAllLines($reportPath, $summary)
[System.IO.File]::WriteAllLines($failuresPath, $failingSentences)

Write-Output "Measured 500 sentences. Failing: ${failingCount}/500. Total errors: ${totalErrors}. Written to $reportPath"
