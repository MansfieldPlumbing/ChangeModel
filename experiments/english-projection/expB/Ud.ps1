#requires -Version 7.4
# UD CoNLL-U reader and gold relations for Experiment B. No regex.
# Gold is a judge only: nothing here is visible to a projector.

class UdToken {
    [int]$Id; [string]$Form; [string]$Lemma; [string]$Upos; [int]$Head; [string]$Deprel
    [int]$Start; [int]$End          # character offsets in the sentence text (End exclusive)
}

class UdSentence {
    [string]$SentId; [string]$Text
    [UdToken[]]$Tokens
    [int]$Root = 0; [int]$Subject = 0; [int]$Object = 0
    [object[]]$Preps                # @{ Prep = id; Obj = id; Gov = id }
}

function Read-UdSentences([string[]]$Lines) {
    $out = [Collections.Generic.List[UdSentence]]::new()
    $sid = $null; $text = $null; $toks = [Collections.Generic.List[UdToken]]::new(); $bad = $false
    foreach ($line in $Lines + @('')) {
        if ($line.Length -eq 0) {
            if ($null -ne $text -and $toks.Count -gt 0 -and -not $bad) {
                $s = [UdSentence]::new(); $s.SentId = $sid; $s.Text = $text; $s.Tokens = $toks.ToArray()
                $cursor = 0; $ok = $true
                foreach ($t in $s.Tokens) {
                    $i = $text.IndexOf($t.Form, $cursor, [StringComparison]::Ordinal)
                    if ($i -lt 0) { $ok = $false; break }
                    $t.Start = $i; $t.End = $i + $t.Form.Length; $cursor = $t.End
                }
                if ($ok) { $out.Add($s) }
            }
            $sid = $null; $text = $null; $toks = [Collections.Generic.List[UdToken]]::new(); $bad = $false
            continue
        }
        if ($line.StartsWith('# sent_id = ', [StringComparison]::Ordinal)) { $sid = $line.Substring(12); continue }
        if ($line.StartsWith('# text = ', [StringComparison]::Ordinal)) { $text = $line.Substring(9); continue }
        if ($line.StartsWith('#', [StringComparison]::Ordinal)) { continue }
        $f = $line.Split("`t")
        if ($f.Count -lt 8) { $bad = $true; continue }
        if ($f[0].Contains('-') -or $f[0].Contains('.')) { $bad = $true; continue }   # multiword tokens and empty nodes are out of scope
        $t = [UdToken]::new(); $t.Id = [int]$f[0]; $t.Form = $f[1]; $t.Lemma = $f[2]; $t.Upos = $f[3]
        $t.Head = [int]$f[6]; $t.Deprel = $f[7]
        $toks.Add($t)
    }
    $out
}

# Ordinary finite clauses: verbal root with a nominal subject, 5..25 tokens.
function Set-UdGold([UdSentence]$S) {
    foreach ($t in $S.Tokens) { if ($t.Head -eq 0) { $S.Root = $t.Id } }
    $preps = [Collections.Generic.List[object]]::new()
    foreach ($t in $S.Tokens) {
        $base = $t.Deprel.Split(':')[0]
        if ($t.Head -eq $S.Root -and $base -eq 'nsubj' -and $S.Subject -eq 0) { $S.Subject = $t.Id }
        if ($t.Head -eq $S.Root -and $base -eq 'obj' -and $S.Object -eq 0) { $S.Object = $t.Id }
        if ($base -eq 'case' -and $t.Upos -eq 'ADP') {
            $obj = $S.Tokens[$t.Head - 1]
            $ob = $obj.Deprel.Split(':')[0]
            if ($ob -eq 'obl' -or $ob -eq 'nmod') { $preps.Add(@{ Prep = $t.Id; Obj = $obj.Id; Gov = $obj.Head }) }
        }
    }
    $S.Preps = $preps.ToArray()
}

function Test-FiniteClause([UdSentence]$S) {
    if ($S.Tokens.Count -lt 5 -or $S.Tokens.Count -gt 25 -or $S.Root -eq 0 -or $S.Subject -eq 0) { return $false }
    $S.Tokens[$S.Root - 1].Upos -eq 'VERB'
}
