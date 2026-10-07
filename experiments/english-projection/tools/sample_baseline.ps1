# Sample baseline inspection on first 5 sentences
$baseDir = "C:\temp\sma-english-projection"
$trainPath = [System.IO.Path]::Combine($baseDir, "inputs", "train_500.tsv")
$spacyPath = [System.IO.Path]::Combine($baseDir, "inputs", "spacy_train_500.tsv")
$outPath = [System.IO.Path]::Combine($baseDir, "results", "baseline_sample_5.txt")

$trainLines = [System.IO.File]::ReadAllLines($trainPath)
$spacyLines = [System.IO.File]::ReadAllLines($spacyPath)

# Read spaCy tokens for sentences 0..4
$spacyMap = [System.Collections.Generic.Dictionary[int, System.Collections.Generic.List[string]]]::new()
for ($i = 1; $i -lt $spacyLines.Length; $i++) {
    $line = $spacyLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $cols = $line.Split([char]9)
    $sId = [int]::Parse($cols[0])
    if ($sId -ge 5) { break }
    if (-not $spacyMap.ContainsKey($sId)) {
        $spacyMap[$sId] = [System.Collections.Generic.List[string]]::new()
    }
    # cols: sentence_id, token_idx, start, end, text, pos, dep
    $spacyMap[$sId].Add("$($cols[1])`t$($cols[2])..$($cols[3])`t$($cols[4])`t$($cols[5])`t$($cols[6])")
}

$report = [System.Collections.Generic.List[string]]::new()

function DumpAstNode([System.Management.Automation.Language.Ast]$ast, [int]$depth, [System.Collections.Generic.List[string]]$outList) {
    $indent = [string]::new([char]32, $depth * 2)
    $typeStr = $ast.GetType().Name
    $extentStr = "$($ast.Extent.StartOffset)..$($ast.Extent.EndOffset)"
    $nodeText = $ast.Extent.Text
    if ($nodeText.Length -gt 40) {
        $nodeText = $nodeText.Substring(0, 37) + "..."
    }
    # Clean newlines in text
    $nodeText = $nodeText.Replace("`r", " ").Replace("`n", " ")
    $outList.Add("$indent|- $typeStr [$extentStr]: '$nodeText'")
    foreach ($child in $ast.FindAll({ $true }, $false)) {
        if ($child -ne $ast -and $child.Parent -eq $ast) {
            DumpAstNode $child ($depth + 1) $outList
        }
    }
}

for ($i = 1; $i -le 5; $i++) {
    $line = $trainLines[$i]
    $parts = $line.Split([char]9)
    $sId = [int]::Parse($parts[0])
    $sent = $parts[5]

    $report.Add("================================================================================")
    $report.Add("SENTENCE ${sId}: $sent")
    $report.Add("LENGTH: $($sent.Length)")
    $report.Add("--- spaCy REFERENCE TOKENS ---")
    if ($spacyMap.ContainsKey($sId)) {
        foreach ($st in $spacyMap[$sId]) {
            $report.Add("  spaCy: $st")
        }
    }

    $errors = [System.Management.Automation.Language.ParseError[]]@()
    $tokens = [System.Management.Automation.Language.Token[]]@()
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($sent, [ref]$tokens, [ref]$errors)

    $report.Add("--- SMA PARSE ERRORS: $($errors.Length) ---")
    foreach ($err in $errors) {
        $report.Add("  ERROR [$($err.Extent.StartOffset)..$($err.Extent.EndOffset)]: $($err.ErrorId) | $($err.Message)")
    }

    $report.Add("--- SMA TOKENS: $($tokens.Length) ---")
    foreach ($t in $tokens) {
        $cleanText = $t.Text.Replace("`r", " ").Replace("`n", " ")
        $report.Add("  SMA Token: [$($t.Extent.StartOffset)..$($t.Extent.EndOffset)] Kind=$($t.Kind) Text='$cleanText'")
    }

    $report.Add("--- SMA AST HIERARCHY ---")
    DumpAstNode $ast 0 $report
    $report.Add("")
}

[System.IO.File]::WriteAllLines($outPath, $report)
Write-Output "Baseline sample analysis written to $outPath"
