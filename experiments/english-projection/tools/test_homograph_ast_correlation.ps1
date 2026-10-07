# Experimental probe: Can SMA AST topology distinguish homograph wordids?
# Focus: abuse (nou vs vrb), abuses (nou vs vrb), advocate (nou vs vrb)
# Dataset: train_500.tsv

$baseDir = "C:\temp\sma-english-projection"
. "$baseDir\tools\EvaluationEngine.ps1"
$trainPath = "$baseDir\inputs\train_500.tsv"
$lines = [System.IO.File]::ReadAllLines($trainPath)

$cfg = [ProjectionConfig]::new()
$cfg.Prefix = "slash"
$cfg.Apostrophe = "modifier"
$cfg.Hash = "fullwidth"
$cfg.Semicolon = "fullwidth"
$cfg.TermPunct = "space"
$cfg.Hyphen = "unicode"
$cfg.Quote = "guillemets"

$records = [System.Collections.Generic.List[string]]::new()
$records.Add("id`thomograph`twordid`tis_verb`ttarget_word`tprev_tok_text`tprev_tok_kind`tnext_tok_text`tast_node_type`tast_parent_type`tcmd_elem_index`ttotal_cmd_elems")

for ($i = 1; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $cols = $line.Split([char]9)
    $sId = [int]::Parse($cols[0])
    $homo = $cols[3]
    $wid = $cols[4]
    $sent = $cols[5]

    if ($homo -ne "abuse" -and $homo -ne "abuses" -and $homo -ne "advocate") { continue }

    $isVerb = if ($wid.EndsWith("vrb") -or $wid -eq "affect") { 1 } else { 0 }

    # Parse under frozen projection
    $proj = ProjectSentence $sent $cfg
    $errs = [System.Management.Automation.Language.ParseError[]]@()
    $toks = [System.Management.Automation.Language.Token[]]@()
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($proj, [ref]$toks, [ref]$errs)

    # Locate the target homograph token
    $targetTokIdx = -1
    for ($t = 0; $t -lt $toks.Length; $t++) {
        $tok = $toks[$t]
        if ($tok.Kind -eq "EndOfInput") { continue }
        # Match word text
        $tText = $tok.Text.ToLowerInvariant()
        if ($tText -eq $homo -or $tText -eq ($homo + ".") -or $tText -eq ($homo + ",") -or $tText -eq ($homo + "；")) {
            $targetTokIdx = $t
            break
        }
    }

    if ($targetTokIdx -ge 0) {
        $targetTok = $toks[$targetTokIdx]
        $prevTok = if ($targetTokIdx -gt 0) { $toks[$targetTokIdx - 1] } else { $null }
        $nextTok = if ($targetTokIdx -lt $toks.Length - 1) { $toks[$targetTokIdx + 1] } else { $null }

        $prevText = if ($prevTok) { $prevTok.Text } else { "START" }
        $prevKind = if ($prevTok) { $prevTok.Kind.ToString() } else { "START" }
        $nextText = if ($nextTok) { $nextTok.Text } else { "END" }

        # Find narrowest AST node
        $node = $ast.FindAll({ $args[0].Extent.StartOffset -le $targetTok.Extent.StartOffset -and $args[0].Extent.EndOffset -ge $targetTok.Extent.EndOffset }, $true) |
            Sort-Object { $_.Extent.EndOffset - $_.Extent.StartOffset } | Select-Object -First 1

        $nType = if ($node) { $node.GetType().Name } else { "None" }
        $pType = if ($node -and $node.Parent) { $node.Parent.GetType().Name } else { "None" }

        # Find enclosing CommandAst
        $cmd = $node
        while ($cmd -and -not ($cmd -is [System.Management.Automation.Language.CommandAst])) {
            $cmd = $cmd.Parent
        }

        $cmdElemIdx = -1
        $totalCmdElems = 0
        if ($cmd) {
            $totalCmdElems = $cmd.CommandElements.Count
            for ($e = 0; $e -lt $cmd.CommandElements.Count; $e++) {
                if ($cmd.CommandElements[$e].Extent.StartOffset -le $targetTok.Extent.StartOffset -and $cmd.CommandElements[$e].Extent.EndOffset -ge $targetTok.Extent.EndOffset) {
                    $cmdElemIdx = $e
                    break
                }
            }
        }

        $records.Add("${sId}`t${homo}`t${wid}`t${isVerb}`t$($targetTok.Text)`t${prevText}`t${prevKind}`t${nextText}`t${nType}`t${pType}`t${cmdElemIdx}`t${totalCmdElems}")
    }
}

$outPath = "$baseDir\results\homograph_ast_experiment.tsv"
[System.IO.File]::WriteAllLines($outPath, $records)

Write-Output "Processed $($records.Count - 1) homograph instances. Saved to $outPath"
