#requires -Version 7.4
# Experiment B projection: frozen stage 0 (same semantics as tools/EvaluationEngine.ps1
# ProjectSentence with the frozen config) plus a relational layer, both carrying a map from
# every projected character to its source index (-1 = inserted). No regex.

$script:Stage0Targets = [char[]]@(0x00AB, 0x00BB, 0x2010, 0xFF1B, 0xFF03, 0x02BC)

class Projected {
    [string]$Text
    [int[]]$Map
    [bool]$Reversible = $true
}

function ConvertTo-Stage0([string]$Source) {
    $p = [Projected]::new()
    foreach ($c in $script:Stage0Targets) { if ($Source.IndexOf($c) -ge 0) { $p.Reversible = $false } }
    $chars = [Collections.Generic.List[char]]::new(); $map = [Collections.Generic.List[int]]::new()
    foreach ($c in '// '.ToCharArray()) { $chars.Add($c); $map.Add(-1) }
    $inQuote = $false
    $last = $Source.Length - 1
    $term = $Source.Length -gt 0 -and ($Source[$last] -eq '.' -or $Source[$last] -eq '?' -or $Source[$last] -eq '!')
    for ($i = 0; $i -lt $Source.Length; $i++) {
        $c = $Source[$i]
        if ($term -and $i -eq $last) { $chars.Add(' '); $map.Add(-1) }
        switch ([int]$c) {
            34     { $c = if ($inQuote) { [char]0x00BB } else { [char]0x00AB }; $inQuote = -not $inQuote }
            0x2D   { $c = [char]0x2010 }
            0x3B   { $c = [char]0xFF1B }
            0x23   { $c = [char]0xFF03 }
            0x27   { $c = [char]0x02BC }
        }
        $chars.Add($c); $map.Add($i)
    }
    $p.Text = [string]::new($chars.ToArray()); $p.Map = $map.ToArray()
    $p
}

# Inverse: drop inserted characters, undo the 1:1 substitutions.
function ConvertFrom-Projected([Projected]$P) {
    $sb = [Text.StringBuilder]::new()
    for ($i = 0; $i -lt $P.Text.Length; $i++) {
        if ($P.Map[$i] -lt 0) { continue }
        $c = $P.Text[$i]
        switch ([int]$c) {
            0x00AB { $c = [char]34 } 0x00BB { $c = [char]34 } 0x2010 { $c = [char]0x2D }
            0xFF1B { $c = [char]0x3B } 0xFF03 { $c = [char]0x23 } 0x02BC { $c = [char]0x27 }
        }
        [void]$sb.Append($c)
    }
    $sb.ToString()
}

# Whitespace-delimited words of a projected text (after the "// " sentinel), with offsets.
function Get-ProjectedWords([Projected]$P) {
    $words = [Collections.Generic.List[object]]::new()
    $t = $P.Text; $i = 3
    while ($i -lt $t.Length) {
        while ($i -lt $t.Length -and [char]::IsWhiteSpace($t[$i])) { $i++ }
        if ($i -ge $t.Length) { break }
        $s = $i
        while ($i -lt $t.Length -and -not [char]::IsWhiteSpace($t[$i])) { $i++ }
        $words.Add([pscustomobject]@{ Start = $s; End = $i; Text = $t.Substring($s, $i - $s) })
    }
    $words
}

function Test-PlainWord([string]$W) {
    if ($W.Length -eq 0) { return $false }
    foreach ($c in $W.ToCharArray()) { if (-not [char]::IsAsciiLetter($c)) { return $false } }
    $true
}

# Relational rules: the only thing the search changes. A projector sees source text only.
class RelationRules {
    [Collections.Generic.HashSet[string]]$VerbCues = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [Collections.Generic.HashSet[string]]$Suffixes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [Collections.Generic.HashSet[string]]$Params   = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [int] Count() { return $this.VerbCues.Count + $this.Suffixes.Count + $this.Params.Count }
    [string] Key() {
        return 'V:' + (($this.VerbCues | Sort-Object) -join ',') + '|S:' + (($this.Suffixes | Sort-Object) -join ',') + '|P:' + (($this.Params | Sort-Object) -join ',')
    }
    [RelationRules] Clone() {
        $r = [RelationRules]::new()
        foreach ($x in $this.VerbCues) { [void]$r.VerbCues.Add($x) }
        foreach ($x in $this.Suffixes) { [void]$r.Suffixes.Add($x) }
        foreach ($x in $this.Params) { [void]$r.Params.Add($x) }
        return $r
    }
}

function Test-VerbCue([string]$Lower, [RelationRules]$R) {
    if ($R.VerbCues.Contains($Lower)) { return $true }
    foreach ($s in $R.Suffixes) { if ($Lower.Length -gt $s.Length + 2 -and $Lower.EndsWith($s, [StringComparison]::Ordinal)) { return $true } }
    $false
}

# Insert "| " before the first verb-cue word after the first word, and "-" before parameter
# words that follow it. Inserted characters map to -1, so the inverse is exact.
function ConvertTo-Relational([Projected]$P0, [RelationRules]$R) {
    $words = @(Get-ProjectedWords $P0)
    $inserts = @{}
    $pipeAt = -1
    for ($k = 1; $k -lt $words.Count; $k++) {
        $w = $words[$k].Text
        if ((Test-PlainWord $w) -and (Test-VerbCue $w.ToLowerInvariant() $R)) { $pipeAt = $k; $inserts[$words[$k].Start] = '| '; break }
    }
    $from = if ($pipeAt -ge 0) { $pipeAt + 1 } else { 1 }
    for ($k = $from; $k -lt $words.Count; $k++) {
        $w = $words[$k].Text
        if ((Test-PlainWord $w) -and $R.Params.Contains($w.ToLowerInvariant())) { $inserts[$words[$k].Start] = '-' }
    }
    $p = [Projected]::new(); $p.Reversible = $P0.Reversible
    $chars = [Collections.Generic.List[char]]::new(); $map = [Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $P0.Text.Length; $i++) {
        if ($inserts.ContainsKey($i)) { foreach ($c in ([string]$inserts[$i]).ToCharArray()) { $chars.Add($c); $map.Add(-1) } }
        $chars.Add($P0.Text[$i]); $map.Add($P0.Map[$i])
    }
    $p.Text = [string]::new($chars.ToArray()); $p.Map = $map.ToArray()
    $p
}
