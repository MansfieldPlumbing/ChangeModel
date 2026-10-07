# Analyze homograph AST correlation findings
$baseDir = "C:\temp\sma-english-projection"
$tsvPath = "$baseDir\results\homograph_ast_experiment.tsv"
$lines = [System.IO.File]::ReadAllLines($tsvPath)

$verbCount = 0
$nounCount = 0

$prevWordsVerb = [System.Collections.Generic.Dictionary[string, int]]::new()
$prevWordsNoun = [System.Collections.Generic.Dictionary[string, int]]::new()

$nextWordsVerb = [System.Collections.Generic.Dictionary[string, int]]::new()
$nextWordsNoun = [System.Collections.Generic.Dictionary[string, int]]::new()

$astParentVerb = [System.Collections.Generic.Dictionary[string, int]]::new()
$astParentNoun = [System.Collections.Generic.Dictionary[string, int]]::new()

for ($i = 1; $i -lt $lines.Length; $i++) {
    $cols = $lines[$i].Split([char]9)
    $isVerb = [int]::Parse($cols[3])
    $prev = $cols[5].ToLowerInvariant()
    $next = $cols[7].ToLowerInvariant()
    $pType = $cols[9]

    if ($isVerb -eq 1) {
        $verbCount++
        if (-not $prevWordsVerb.ContainsKey($prev)) { $prevWordsVerb[$prev] = 0 }
        $prevWordsVerb[$prev]++
        if (-not $nextWordsVerb.ContainsKey($next)) { $nextWordsVerb[$next] = 0 }
        $nextWordsVerb[$next]++
        if (-not $astParentVerb.ContainsKey($pType)) { $astParentVerb[$pType] = 0 }
        $astParentVerb[$pType]++
    } else {
        $nounCount++
        if (-not $prevWordsNoun.ContainsKey($prev)) { $prevWordsNoun[$prev] = 0 }
        $prevWordsNoun[$prev]++
        if (-not $nextWordsNoun.ContainsKey($next)) { $nextWordsNoun[$next] = 0 }
        $nextWordsNoun[$next]++
        if (-not $astParentNoun.ContainsKey($pType)) { $astParentNoun[$pType] = 0 }
        $astParentNoun[$pType]++
    }
}

Write-Output "=== HOMOGRAPH AST ANALYSIS (261 INSTANCES) ==="
Write-Output "Total Nouns: $nounCount | Total Verbs: $verbCount"
Write-Output ""

Write-Output "--- TOP PRECEDING TOKENS FOR VERBS ---"
foreach ($k in $prevWordsVerb.Keys | Sort-Object { -$prevWordsVerb[$_] } | Select-Object -First 10) {
    Write-Output "  '${k}': $($prevWordsVerb[$k]) times"
}

Write-Output ""
Write-Output "--- TOP PRECEDING TOKENS FOR NOUNS ---"
foreach ($k in $prevWordsNoun.Keys | Sort-Object { -$prevWordsNoun[$_] } | Select-Object -First 10) {
    Write-Output "  '${k}': $($prevWordsNoun[$k]) times"
}

Write-Output ""
Write-Output "--- TOP FOLLOWING TOKENS FOR VERBS ---"
foreach ($k in $nextWordsVerb.Keys | Sort-Object { -$nextWordsVerb[$_] } | Select-Object -First 10) {
    Write-Output "  '${k}': $($nextWordsVerb[$k]) times"
}

Write-Output ""
Write-Output "--- TOP FOLLOWING TOKENS FOR NOUNS ---"
foreach ($k in $nextWordsNoun.Keys | Sort-Object { -$nextWordsNoun[$_] } | Select-Object -First 10) {
    Write-Output "  '${k}': $($nextWordsNoun[$k]) times"
}

Write-Output ""
Write-Output "--- AST PARENT TYPE FOR NOUNS VS VERBS ---"
Write-Output "Nouns in ArrayLiteralAst: $( if ($astParentNoun.ContainsKey('ArrayLiteralAst')) { $astParentNoun['ArrayLiteralAst'] } else { 0 } )"
Write-Output "Verbs in ArrayLiteralAst: $( if ($astParentVerb.ContainsKey('ArrayLiteralAst')) { $astParentVerb['ArrayLiteralAst'] } else { 0 } )"
