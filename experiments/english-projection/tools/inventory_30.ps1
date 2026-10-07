# Inventory 30 deterministic sentences:
# 1. PowerShell-reserved-word collisions
# 2. Punctuation -> AST-shape mappings
# 3. Places SMA boundary != spaCy boundary

$baseDir = "C:\temp\sma-english-projection"
$trainPath = [System.IO.Path]::Combine($baseDir, "inputs", "train_500.tsv")
$spacyPath = [System.IO.Path]::Combine($baseDir, "inputs", "spacy_train_500.tsv")

$trainLines = [System.IO.File]::ReadAllLines($trainPath)
$spacyLines = [System.IO.File]::ReadAllLines($spacyPath)

# Load spaCy tokens for sentences 0..29
class SpacyToken {
    [int]$SentenceId
    [int]$TokenIdx
    [int]$Start
    [int]$End
    [string]$Text
    [string]$Pos
    [string]$Dep
}

$spacyTokensBySentence = [System.Collections.Generic.Dictionary[int, System.Collections.Generic.List[SpacyToken]]]::new()

for ($i = 1; $i -lt $spacyLines.Length; $i++) {
    $line = $spacyLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $cols = $line.Split([char]9)
    $sId = [int]::Parse($cols[0])
    if ($sId -ge 30) { break }
    if (-not $spacyTokensBySentence.ContainsKey($sId)) {
        $spacyTokensBySentence[$sId] = [System.Collections.Generic.List[SpacyToken]]::new()
    }
    $tok = [SpacyToken]::new()
    $tok.SentenceId = $sId
    $tok.TokenIdx = [int]::Parse($cols[1])
    $tok.Start = [int]::Parse($cols[2])
    $tok.End = [int]::Parse($cols[3])
    $tok.Text = $cols[4]
    $tok.Pos = $cols[5]
    $tok.Dep = $cols[6]
    $spacyTokensBySentence[$sId].Add($tok)
}

# Data structures for the 3 inventories
$collisionRows = [System.Collections.Generic.List[string]]::new()
$collisionRows.Add("sentence_id`ttoken_text`tsma_kind`tspan`tspacy_pos`tspacy_dep`tast_parent_type")

$punctShapeRows = [System.Collections.Generic.List[string]]::new()
$punctShapeRows.Add("sentence_id`tpunct_char`tsma_token_kind`tspan`tast_parent_type`tast_node_type`tnode_snippet")

$boundaryDiffRows = [System.Collections.Generic.List[string]]::new()
$boundaryDiffRows.Add("sentence_id`tspacy_text`tspacy_span`tspacy_pos`tsma_span`tsma_text`tsma_kind`tdiff_category")

# Helper to check if text is a plain word (all ASCII letters)
function IsAlphaWord([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    for ($c = 0; $c -lt $text.Length; $c++) {
        $ch = [int]$text[$c]
        $isUpper = ($ch -ge 65 -and $ch -le 90)
        $isLower = ($ch -ge 97 -and $ch -le 122)
        if (-not ($isUpper -or $isLower)) { return $false }
    }
    return $true
}

$punctChars = @(
    [char]46,  # .
    [char]44,  # ,
    [char]59,  # ;
    [char]58,  # :
    [char]33,  # !
    [char]63,  # ?
    [char]39,  # '
    [char]34,  # "
    [char]40,  # (
    [char]41,  # )
    [char]91,  # [
    [char]93,  # ]
    [char]123, # {
    [char]125, # }
    [char]45,  # -
    [char]47,  # /
    [char]36,  # $
    [char]35,  # #
    [char]38,  # &
    [char]124  # |
)

$summaryLines = [System.Collections.Generic.List[string]]::new()
$totalErrors = 0
$sentencesWithErrors = 0

for ($s = 0; $s -lt 30; $s++) {
    $lineIdx = $s + 1
    $line = $trainLines[$lineIdx]
    $parts = $line.Split([char]9)
    $sId = [int]::Parse($parts[0])
    $sent = $parts[5]

    $errors = [System.Management.Automation.Language.ParseError[]]@()
    $tokens = [System.Management.Automation.Language.Token[]]@()
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($sent, [ref]$tokens, [ref]$errors)

    if ($errors.Length -gt 0) {
        $sentencesWithErrors++
        $totalErrors += $errors.Length
    }

    # Find AST node for an offset span
    function FindAstNodeAt([System.Management.Automation.Language.Ast]$root, [int]$start, [int]$end) {
        $best = $root
        foreach ($node in $root.FindAll({ $true }, $true)) {
            if ($node.Extent.StartOffset -le $start -and $node.Extent.EndOffset -ge $end) {
                # Find narrowest enclosing
                if ($node.Extent.EndOffset - $node.Extent.StartOffset -lt $best.Extent.EndOffset - $best.Extent.StartOffset) {
                    $best = $node
                }
            }
        }
        return $best
    }

    # 1. Reserved-word collisions
    foreach ($tok in $tokens) {
        if ($tok.Kind -eq "EndOfInput") { continue }
        $tokText = $tok.Text
        $kindStr = $tok.Kind.ToString()
        if ($kindStr -ne "Identifier" -and $kindStr -ne "Generic" -and $kindStr -ne "StringExpandable" -and $kindStr -ne "StringLiteral") {
            if (IsAlphaWord $tokText) {
                # Find matching spaCy token
                $sPos = "?"
                $sDep = "?"
                if ($spacyTokensBySentence.ContainsKey($sId)) {
                    foreach ($st in $spacyTokensBySentence[$sId]) {
                        if ($st.Start -le $tok.Extent.StartOffset -and $st.End -ge $tok.Extent.EndOffset) {
                            $sPos = $st.Pos
                            $sDep = $st.Dep
                            break
                        }
                    }
                }
                $node = FindAstNodeAt $ast $tok.Extent.StartOffset $tok.Extent.EndOffset
                $pType = if ($node.Parent) { $node.Parent.GetType().Name } else { "None" }
                $span = "$($tok.Extent.StartOffset)..$($tok.Extent.EndOffset)"
                $collisionRows.Add("${sId}`t${tokText}`t${kindStr}`t${span}`t${sPos}`t${sDep}`t${pType}")
            }
        }
    }

    # 2. Punctuation -> AST shape mappings
    # Find all punctuation occurrences in source
    for ($c = 0; $c -lt $sent.Length; $c++) {
        $ch = $sent[$c]
        if ($punctChars.Contains($ch)) {
            # Find which SMA token covers this offset
            $coveringTok = $null
            foreach ($t in $tokens) {
                if ($t.Kind -eq "EndOfInput") { continue }
                if ($t.Extent.StartOffset -le $c -and $t.Extent.EndOffset -gt $c) {
                    $coveringTok = $t
                    break
                }
            }
            $tKind = if ($coveringTok) { $coveringTok.Kind.ToString() } else { "None" }
            $tSpan = if ($coveringTok) { "$($coveringTok.Extent.StartOffset)..$($coveringTok.Extent.EndOffset)" } else { "$c..$($c+1)" }
            $node = FindAstNodeAt $ast $c ($c + 1)
            $pType = if ($node.Parent) { $node.Parent.GetType().Name } else { "None" }
            $nType = $node.GetType().Name
            $snip = $node.Extent.Text.Replace("`r", " ").Replace("`n", " ").Replace("`t", " ")
            if ($snip.Length -gt 35) { $snip = $snip.Substring(0, 32) + "..." }
            $punctShapeRows.Add("${sId}`t${ch}`t${tKind}`t${tSpan}`t${pType}`t${nType}`t${snip}")
        }
    }

    # 3. SMA boundary != spaCy boundary
    if ($spacyTokensBySentence.ContainsKey($sId)) {
        foreach ($st in $spacyTokensBySentence[$sId]) {
            # Check if an SMA token matches exact boundaries [st.Start, st.End]
            $exactMatch = $false
            $coveringSma = $null
            foreach ($t in $tokens) {
                if ($t.Kind -eq "EndOfInput") { continue }
                if ($t.Extent.StartOffset -eq $st.Start -and $t.Extent.EndOffset -eq $st.End) {
                    $exactMatch = $true
                    break
                }
                if ($t.Extent.StartOffset -le $st.Start -and $t.Extent.EndOffset -ge $st.End) {
                    $coveringSma = $t
                }
            }
            if (-not $exactMatch) {
                $smaSpan = if ($coveringSma) { "$($coveringSma.Extent.StartOffset)..$($coveringSma.Extent.EndOffset)" } else { "None" }
                $smaText = if ($coveringSma) { $coveringSma.Text.Replace("`r", " ").Replace("`n", " ") } else { "None" }
                $smaKind = if ($coveringSma) { $coveringSma.Kind.ToString() } else { "None" }
                
                # Classify disagreement category
                $cat = "Other"
                if ($coveringSma) {
                    if ($st.End -eq $sent.Length -or $coveringSma.Extent.EndOffset -eq $sent.Length) {
                        $cat = "TerminalPunctuationGlued"
                    } elseif ($coveringSma.Text.Contains([string]"'")) {
                        $cat = "ApostropheQuoteAbsorption"
                    } elseif ($coveringSma.Text.Contains([string]",")) {
                        $cat = "CommaAbsorption"
                    } elseif ($st.Pos -eq "PUNCT") {
                        $cat = "PunctuationAbsorbedIntoWord"
                    } elseif ($coveringSma.Extent.EndOffset - $coveringSma.Extent.StartOffset -gt $st.End - $st.Start) {
                        $cat = "WordFusedWithNeighbor"
                    }
                }
                $spSpan = "$($st.Start)..$($st.End)"
                $boundaryDiffRows.Add("${sId}`t$($st.Text)`t${spSpan}`t$($st.Pos)`t${smaSpan}`t${smaText}`t${smaKind}`t${cat}")
            }
        }
    }
}

# Write inventory files
$collisionPath = [System.IO.Path]::Combine($baseDir, "results", "inventory_reserved_collisions_30.tsv")
$punctShapePath = [System.IO.Path]::Combine($baseDir, "results", "inventory_punctuation_ast_shapes_30.tsv")
$boundaryDiffPath = [System.IO.Path]::Combine($baseDir, "results", "inventory_boundary_disagreements_30.tsv")
$summaryPath = [System.IO.Path]::Combine($baseDir, "results", "inventory_summary_30.txt")

[System.IO.File]::WriteAllLines($collisionPath, $collisionRows)
[System.IO.File]::WriteAllLines($punctShapePath, $punctShapeRows)
[System.IO.File]::WriteAllLines($boundaryDiffPath, $boundaryDiffRows)

# Generate Summary Report
$summary = [System.Collections.Generic.List[string]]::new()
$summary.Add("=== INVENTORY SUMMARY (SENTENCES 0..29) ===")
$summary.Add("Total Sentences: 30")
$summary.Add("Sentences with Parse Errors: ${sentencesWithErrors} / 30")
$summary.Add("Total Parse Errors: ${totalErrors}")
$summary.Add("Reserved-Word Collision Count: " + ($collisionRows.Count - 1))
$summary.Add("Punctuation Occurrences: " + ($punctShapeRows.Count - 1))
$summary.Add("Boundary Disagreements vs spaCy: " + ($boundaryDiffRows.Count - 1))
$summary.Add("")
$summary.Add("Unique Reserved Collisions:")
$uniqueCollisions = [System.Collections.Generic.HashSet[string]]::new()
for ($i = 1; $i -lt $collisionRows.Count; $i++) {
    $parts = $collisionRows[$i].Split([char]9)
    [void]$uniqueCollisions.Add("Word='$($parts[1])' -> Kind=$($parts[2]) (spaCy POS=$($parts[4]), Dep=$($parts[5]))")
}
foreach ($uc in $uniqueCollisions) {
    $summary.Add("  $uc")
}

$summary.Add("")
$summary.Add("Punctuation -> AST Node Types:")
$punctToAst = [System.Collections.Generic.Dictionary[string, [System.Collections.Generic.HashSet[string]]]]::new()
for ($i = 1; $i -lt $punctShapeRows.Count; $i++) {
    $parts = $punctShapeRows[$i].Split([char]9)
    $ch = $parts[1]
    $nType = $parts[5]
    $pType = $parts[4]
    if (-not $punctToAst.ContainsKey($ch)) {
        $punctToAst[$ch] = [System.Collections.Generic.HashSet[string]]::new()
    }
    [void]$punctToAst[$ch].Add("$nType (parent: $pType)")
}
foreach ($k in $punctToAst.Keys) {
    $summary.Add("  Punct '${k}':")
    foreach ($v in $punctToAst[$k]) {
        $summary.Add("    -> $v")
    }
}

$summary.Add("")
$summary.Add("Boundary Disagreement Categories:")
$catCounts = [System.Collections.Generic.Dictionary[string, int]]::new()
for ($i = 1; $i -lt $boundaryDiffRows.Count; $i++) {
    $parts = $boundaryDiffRows[$i].Split([char]9)
    $cat = $parts[7]
    if (-not $catCounts.ContainsKey($cat)) { $catCounts[$cat] = 0 }
    $catCounts[$cat]++
}
foreach ($k in $catCounts.Keys) {
    $summary.Add("  ${k}: $($catCounts[$k])")
}

[System.IO.File]::WriteAllLines($summaryPath, $summary)
Write-Output "Inventories complete. Summary written to $summaryPath"
