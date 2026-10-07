# Comprehensive inventory generator:
# 1. PowerShell-reserved-word collisions across 500 sentences
# 2. Punctuation -> AST shape mappings
# 3. Boundary disagreements (SMA vs spaCy) on 30 sentences

$baseDir = "C:\temp\sma-english-projection"
$trainPath = [System.IO.Path]::Combine($baseDir, "inputs", "train_500.tsv")
$spacyPath = [System.IO.Path]::Combine($baseDir, "inputs", "spacy_train_500.tsv")

$trainLines = [System.IO.File]::ReadAllLines($trainPath)
$spacyLines = [System.IO.File]::ReadAllLines($spacyPath)

# Build spaCy lookup for 500 sentences
class SpacyTok {
    [int]$SentenceId
    [int]$TokenIdx
    [int]$Start
    [int]$End
    [string]$Text
    [string]$Pos
    [string]$Dep
}

$spacyMap = [System.Collections.Generic.Dictionary[int, System.Collections.Generic.List[SpacyTok]]]::new()
for ($i = 1; $i -lt $spacyLines.Length; $i++) {
    $line = $spacyLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $cols = $line.Split([char]9)
    $sId = [int]::Parse($cols[0])
    if (-not $spacyMap.ContainsKey($sId)) {
        $spacyMap[$sId] = [System.Collections.Generic.List[SpacyTok]]::new()
    }
    $tok = [SpacyTok]::new()
    $tok.SentenceId = $sId
    $tok.TokenIdx = [int]::Parse($cols[1])
    $tok.Start = [int]::Parse($cols[2])
    $tok.End = [int]::Parse($cols[3])
    $tok.Text = $cols[4]
    $tok.Pos = $cols[5]
    $tok.Dep = $cols[6]
    $spacyMap[$sId].Add($tok)
}

function IsAlpha([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    for ($c = 0; $c -lt $text.Length; $c++) {
        $ch = [int]$text[$c]
        if (-not (($ch -ge 65 -and $ch -le 90) -or ($ch -ge 97 -and $ch -le 122))) { return $false }
    }
    return $true
}

function FindNarrowestAstNode([System.Management.Automation.Language.Ast]$root, [int]$start, [int]$end) {
    $best = $root
    foreach ($node in $root.FindAll({ $true }, $true)) {
        if ($node.Extent.StartOffset -le $start -and $node.Extent.EndOffset -ge $end) {
            if ($node.Extent.EndOffset - $node.Extent.StartOffset -lt $best.Extent.EndOffset - $best.Extent.StartOffset) {
                $best = $node
            }
        }
    }
    return $best
}

$punctChars = @(
    [char]46, [char]44, [char]59, [char]58, [char]33, [char]63, [char]39,
    [char]34, [char]40, [char]41, [char]91, [char]93, [char]123, [char]125,
    [char]45, [char]47, [char]36, [char]35, [char]38, [char]124
)

# 1. Reserved-Word collisions across all 500 sentences
$collisionList = [System.Collections.Generic.List[string]]::new()
$collisionList.Add("sentence_id`ttoken_text`tsma_kind`tspan`tspacy_pos`tspacy_dep`tast_parent_type")

$punctShapeList = [System.Collections.Generic.List[string]]::new()
$punctShapeList.Add("sentence_id`tpunct_char`tsma_token_kind`tspan`tast_parent_type`tast_node_type`tnode_snippet")

$boundaryDiffList = [System.Collections.Generic.List[string]]::new()
$boundaryDiffList.Add("sentence_id`tspacy_text`tspacy_span`tspacy_pos`tsma_span`tsma_text`tsma_kind`tdiff_category")

for ($s = 0; $s -lt 500; $s++) {
    $lineIdx = $s + 1
    if ($lineIdx -ge $trainLines.Length) { break }
    $line = $trainLines[$lineIdx]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line.Split([char]9)
    $sId = [int]::Parse($parts[0])
    $sent = $parts[5]

    $errors = [System.Management.Automation.Language.ParseError[]]@()
    $tokens = [System.Management.Automation.Language.Token[]]@()
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($sent, [ref]$tokens, [ref]$errors)

    # Check reserved collisions across all 500
    foreach ($tok in $tokens) {
        if ($tok.Kind -eq "EndOfInput") { continue }
        $tKind = $tok.Kind.ToString()
        if ($tKind -ne "Identifier" -and $tKind -ne "Generic" -and $tKind -ne "StringExpandable" -and $tKind -ne "StringLiteral" -and $tKind -ne "Comment") {
            if (IsAlpha $tok.Text) {
                $spPos = "?"
                $spDep = "?"
                if ($spacyMap.ContainsKey($sId)) {
                    foreach ($st in $spacyMap[$sId]) {
                        if ($st.Start -le $tok.Extent.StartOffset -and $st.End -ge $tok.Extent.EndOffset) {
                            $spPos = $st.Pos
                            $spDep = $st.Dep
                            break
                        }
                    }
                }
                $node = FindNarrowestAstNode $ast $tok.Extent.StartOffset $tok.Extent.EndOffset
                $pType = if ($node.Parent) { $node.Parent.GetType().Name } else { "None" }
                $collisionList.Add("${sId}`t$($tok.Text)`t${tKind}`t$($tok.Extent.StartOffset)..$($tok.Extent.EndOffset)`t${spPos}`t${spDep}`t${pType}")
            }
        }
    }

    # For sentences 0..29: collect punctuation shapes and boundary disagreements
    if ($s -lt 30) {
        # Punctuation shapes
        for ($c = 0; $c -lt $sent.Length; $c++) {
            $ch = $sent[$c]
            if ($punctChars.Contains($ch)) {
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
                $node = FindNarrowestAstNode $ast $c ($c + 1)
                $pType = if ($node.Parent) { $node.Parent.GetType().Name } else { "None" }
                $nType = $node.GetType().Name
                $snip = $node.Extent.Text.Replace("`r", " ").Replace("`n", " ").Replace("`t", " ")
                if ($snip.Length -gt 35) { $snip = $snip.Substring(0, 32) + "..." }
                $punctShapeList.Add("${sId}`t${ch}`t${tKind}`t${tSpan}`t${pType}`t${nType}`t${snip}")
            }
        }

        # Boundary differences
        if ($spacyMap.ContainsKey($sId)) {
            foreach ($st in $spacyMap[$sId]) {
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
                    $boundaryDiffList.Add("${sId}`t$($st.Text)`t$($st.Start)..$($st.End)`t$($st.Pos)`t${smaSpan}`t${smaText}`t${smaKind}`t${cat}")
                }
            }
        }
    }
}

# Write inventory files
$collisionPath = [System.IO.Path]::Combine($baseDir, "results", "inventory_reserved_collisions_500.tsv")
$punctShapePath = [System.IO.Path]::Combine($baseDir, "results", "inventory_punctuation_ast_shapes_30.tsv")
$boundaryDiffPath = [System.IO.Path]::Combine($baseDir, "results", "inventory_boundary_disagreements_30.tsv")

[System.IO.File]::WriteAllLines($collisionPath, $collisionList)
[System.IO.File]::WriteAllLines($punctShapePath, $punctShapeList)
[System.IO.File]::WriteAllLines($boundaryDiffPath, $boundaryDiffList)

Write-Output "Generated inventories:"
Write-Output "  Reserved collisions across 500: $( $collisionList.Count - 1 )"
Write-Output "  Punctuation shapes (30 sent): $( $punctShapeList.Count - 1 )"
Write-Output "  Boundary disagreements (30 sent): $( $boundaryDiffList.Count - 1 )"
