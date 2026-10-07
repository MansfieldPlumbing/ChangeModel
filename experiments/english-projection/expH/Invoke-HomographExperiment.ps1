#requires -Version 7.4
# Homograph experiment: does SMA tree structure add information to the classic per-homograph
# decision list over neighboring words? WikipediaHomographData (Apache-2.0), its own train/eval
# split. A = most frequent WORDID; B = decision list over lexical features; C = B plus SMA
# features of the projected (frozen stage 0) sentence. Parse only; nothing is executed. No regex.
param(
    [string] $Data = (Join-Path $PSScriptRoot '..\inputs\WikipediaHomographData\data'),
    [ValidateRange(1, 50)][int] $MinSupport = 3,
    [ValidateRange(100, 20000)][int] $BootstrapSamples = 2000,
    [string] $OutDir = (Join-Path $PSScriptRoot 'results')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\expB\Projection.ps1')
[void][IO.Directory]::CreateDirectory($OutDir)
$clock = [Diagnostics.Stopwatch]::StartNew()
$log = [Collections.Generic.List[string]]::new()
$say = { param($m) $line = '[{0,6:F1}s] {1}' -f $clock.Elapsed.TotalSeconds, $m; $log.Add($line); $line }

$unquote = { param([string]$f) if ($f.Length -ge 2 -and $f[0] -eq '"' -and $f[-1] -eq '"') { $f.Substring(1, $f.Length - 2).Replace('""', '"') } else { $f } }
$readSplit = { param($dir)
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($file in (Get-ChildItem (Join-Path $Data $dir) -Filter *.tsv | Sort-Object Name)) {
        $lines = [IO.File]::ReadAllLines($file.FullName)
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $f = $lines[$i].Split("`t"); if ($f.Count -lt 5) { continue }
            $rows.Add([pscustomobject]@{ Homograph = (& $unquote $f[0]); WordId = (& $unquote $f[1]); Sentence = (& $unquote $f[2]); Start = [int](& $unquote $f[3]); End = [int](& $unquote $f[4]) })
        }
    }
    $rows
}
$train = & $readSplit 'train'; $eval = & $readSplit 'eval'
$types = @{}
foreach ($l in ([IO.File]::ReadAllLines((Join-Path $Data 'wordids.tsv')) | Select-Object -Skip 1)) { $f = $l.Split("`t"); $types[(& $unquote $f[0])] = (& $unquote $f[5]) }
& $say "Train $($train.Count) sentences, eval $($eval.Count), homographs $(@($train.Homograph | Sort-Object -Unique).Count)"
# Some dataset offsets drift (they appear to count UTF-8 bytes); re-anchor to the nearest
# occurrence of the homograph text before the given start, or drop the row if none is near.
$spanFixed = 0; $spanDropped = 0
$fix = { param($rows)
    foreach ($r in $rows) {
        $len = $r.Homograph.Length
        if ($r.End -le $r.Sentence.Length -and $r.Sentence.Substring($r.Start, $r.End - $r.Start).Equals($r.Homograph, [StringComparison]::OrdinalIgnoreCase)) { $r; continue }
        $found = -1
        for ($d = 0; $d -le 12 -and $found -lt 0; $d++) {
            foreach ($c in @(($r.Start - $d), ($r.Start + $d))) {
                if ($c -ge 0 -and $c + $len -le $r.Sentence.Length -and $r.Sentence.Substring($c, $len).Equals($r.Homograph, [StringComparison]::OrdinalIgnoreCase)) { $found = $c; break }
            }
        }
        if ($found -ge 0) { $r.Start = $found; $r.End = $found + $len; $script:spanFixed++; $r } else { $script:spanDropped++ }
    }
}
$train = @(& $fix $train); $eval = @(& $fix $eval)
& $say "Target spans re-anchored: $spanFixed, dropped: $spanDropped"

# Lexical features: neighboring words around the target span, classic Gorman-style windows.
$norm = { param([string]$w)
    $a = 0; $b = $w.Length
    while ($a -lt $b -and -not [char]::IsLetterOrDigit($w[$a])) { $a++ }
    while ($b -gt $a -and -not [char]::IsLetterOrDigit($w[$b - 1])) { $b-- }
    $x = $w.Substring($a, $b - $a).ToLowerInvariant()
    if ($x.Length -eq 0) { return '<P>' }
    $digits = $true; foreach ($c in $x.ToCharArray()) { if (-not [char]::IsDigit($c)) { $digits = $false } }
    if ($digits) { '<NUM>' } else { $x }
}
$lexical = { param($r)
    $words = [Collections.Generic.List[object]]::new(); $s = $r.Sentence; $i = 0
    while ($i -lt $s.Length) {
        while ($i -lt $s.Length -and [char]::IsWhiteSpace($s[$i])) { $i++ }; if ($i -ge $s.Length) { break }
        $a = $i; while ($i -lt $s.Length -and -not [char]::IsWhiteSpace($s[$i])) { $i++ }
        $words.Add(@($a, $i))
    }
    $t = -1; for ($k = 0; $k -lt $words.Count; $k++) { if ($r.Start -ge $words[$k][0] -and $r.Start -lt $words[$k][1]) { $t = $k } }
    $w = { param($k) if ($k -lt 0) { '<S>' } elseif ($k -ge $words.Count) { '<E>' } else { & $norm $s.Substring($words[$k][0], $words[$k][1] - $words[$k][0]) } }
    $l1 = & $w ($t - 1); $l2 = & $w ($t - 2); $r1 = & $w ($t + 1); $r2 = & $w ($t + 2)
    $cap = if ([char]::IsUpper($s[$r.Start])) { 'C' } else { 'c' }
    @("L1=$l1", "L2=$l2", "R1=$r1", "R2=$r2", "L2L1=$l2 $l1", "R1R2=$r1 $r2", "L1R1=$l1 $r1", "Cap=$cap", "First=$($t -eq 0)")
}
# Wider context: unordered words at distance 3..6 on each side (probe for long-range signal).
$wide = { param($r)
    $s = $r.Sentence; $words = [Collections.Generic.List[object]]::new(); $i = 0
    while ($i -lt $s.Length) {
        while ($i -lt $s.Length -and [char]::IsWhiteSpace($s[$i])) { $i++ }; if ($i -ge $s.Length) { break }
        $a = $i; while ($i -lt $s.Length -and -not [char]::IsWhiteSpace($s[$i])) { $i++ }
        $words.Add(@($a, $i))
    }
    $t = -1; for ($k = 0; $k -lt $words.Count; $k++) { if ($r.Start -ge $words[$k][0] -and $r.Start -lt $words[$k][1]) { $t = $k } }
    $out = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($d in 3..6) {
        foreach ($k in @(($t - $d), ($t + $d))) {
            if ($k -ge 0 -and $k -lt $words.Count) { $w = & $norm $s.Substring($words[$k][0], $words[$k][1] - $words[$k][0]); if ($w -ne '<P>') { [void]$out.Add($(if ($k -lt $t) { "WL=$w" } else { "WR=$w" })) } }
        }
    }
    @($out)
}

# SMA features: node facts for the AST element covering the target in the stage-0 projection.
$smaFeatures = { param($r)
    $p = ConvertTo-Stage0 $r.Sentence
    $at = -1; for ($i = 0; $i -lt $p.Map.Count; $i++) { if ($p.Map[$i] -eq $r.Start) { $at = $i; break } }
    $tk = $null; $er = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($p.Text, [ref]$tk, [ref]$er)
    if ($at -lt 0) { return @('Sma=unmapped') }
    $deepest = $null
    foreach ($n in $ast.FindAll({ param($n) $n.Extent.StartOffset -le $at -and $n.Extent.EndOffset -gt $at }, $true)) { $deepest = $n }
    if ($null -eq $deepest) { return @('Sma=none') }
    $parent = $deepest.Parent; $gp = if ($parent) { $parent.Parent } else { $null }
    $f = [Collections.Generic.List[string]]::new()
    $f.Add('Node=' + $deepest.GetType().Name); $f.Add('Parent=' + $(if ($parent) { $parent.GetType().Name } else { '-' })); $f.Add('Grand=' + $(if ($gp) { $gp.GetType().Name } else { '-' }))
    $depth = 0; $q = $deepest; while ($q.Parent) { $depth++; $q = $q.Parent }; $f.Add("Depth=$depth")
    if ($parent -is [Management.Automation.Language.CommandAst]) {
        $els = @($parent.CommandElements); $idx = [array]::IndexOf($els, $deepest)
        $f.Add('ElemIdx=' + [math]::Min($idx, 6))
        $f.Add('PrevNode=' + $(if ($idx -gt 0) { $els[$idx - 1].GetType().Name } else { '-' }))
        $f.Add('NextNode=' + $(if ($idx -ge 0 -and $idx + 1 -lt $els.Count) { $els[$idx + 1].GetType().Name } else { '-' }))
    }
    $f.Add("Errors=$([math]::Min($er.Count, 1))")
    $f.ToArray()
}

& $say 'Extracting features'
foreach ($r in $train + $eval) {
    $r | Add-Member Lex (& $lexical $r)
    $r | Add-Member Wide (& $wide $r)
    $r | Add-Member Sma (& $smaFeatures $r)
}
& $say 'Features done'

# Decision list per homograph (Yarowsky-style): rules ranked by smoothed log-likelihood ratio.
$learn = { param($rows, [scriptblock]$feats)
    $byH = @{}
    foreach ($g in ($rows | Group-Object Homograph)) {
        $classes = @{}; foreach ($r in $g.Group) { $classes[$r.WordId] = 1 + [int]$classes[$r.WordId] }
        $major = ($classes.GetEnumerator() | Sort-Object @{ e = { $_.Value }; Descending = $true }, @{ e = { $_.Key } } | Select-Object -First 1).Key
        $counts = @{}
        foreach ($r in $g.Group) { foreach ($f in (& $feats $r)) { if (-not $counts[$f]) { $counts[$f] = @{} }; $counts[$f][$r.WordId] = 1 + [int]$counts[$f][$r.WordId] } }
        $rules = foreach ($e in $counts.GetEnumerator()) {
            $tot = 0; foreach ($v in $e.Value.Values) { $tot += $v }
            if ($tot -lt $MinSupport) { continue }
            $best = ($e.Value.GetEnumerator() | Sort-Object @{ e = { $_.Value }; Descending = $true }, @{ e = { $_.Key } } | Select-Object -First 1)
            $score = [math]::Log(($best.Value + 0.1) / ($tot - $best.Value + 0.1))
            [pscustomobject]@{ Feature = $e.Key; Class = $best.Key; Score = $score; Support = $tot }
        }
        $byH[$g.Name] = [pscustomobject]@{ Major = $major; Rules = @($rules | Sort-Object @{ e = { $_.Score }; Descending = $true }, @{ e = { $_.Feature } }) }
    }
    $byH
}
$classify = { param($model, $r, [scriptblock]$feats)
    $m = $model[$r.Homograph]; if (-not $m) { return $null }
    $fs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($x in @(& $feats $r)) { [void]$fs.Add([string]$x) }
    foreach ($rule in $m.Rules) { if ($fs.Contains($rule.Feature)) { return $rule.Class } }
    $m.Major
}
$systems = [ordered]@{
    A = { param($r) @() }
    B = { param($r) $r.Lex }
    C = { param($r) @($r.Lex) + @($r.Sma) }
    SmaOnly = { param($r) $r.Sma }
    BWide = { param($r) @($r.Lex) + @($r.Wide) }
}
$perH = @{}
foreach ($name in $systems.Keys) {
    $model = & $learn $train $systems[$name]
    foreach ($g in ($eval | Group-Object Homograph)) {
        $ok = 0; foreach ($r in $g.Group) { if ((& $classify $model $r $systems[$name]) -ceq $r.WordId) { $ok++ } }
        if (-not $perH[$g.Name]) { $perH[$g.Name] = @{ N = $g.Count; Type = $types[$g.Name] } }
        $perH[$g.Name][$name] = $ok
    }
    & $say "System $name done"
}
$hs = @($perH.Keys | Sort-Object)
$macro = { param($name, $keys) $s = 0.0; foreach ($h in $keys) { $s += $perH[$h][$name] / $perH[$h].N }; $s / $keys.Count }
foreach ($name in $systems.Keys) {
    $micro = 0; $n = 0; foreach ($h in $hs) { $micro += $perH[$h][$name]; $n += $perH[$h].N }
    & $say ('{0,-8} macro {1:P2}  micro {2:P2}' -f $name, (& $macro $name $hs), ($micro / $n))
}
# Paired bootstrap over homographs: C - B and SmaOnly - A.
$rng = [Random]::new(20261007)
foreach ($pair in @(@('C', 'B'), @('SmaOnly', 'A'), @('BWide', 'B'))) {
    $diffs = [double[]]::new($BootstrapSamples)
    for ($b = 0; $b -lt $BootstrapSamples; $b++) {
        $d = 0.0; for ($i = 0; $i -lt $hs.Count; $i++) { $h = $hs[$rng.Next($hs.Count)]; $d += ($perH[$h][$pair[0]] - $perH[$h][$pair[1]]) / $perH[$h].N }
        $diffs[$b] = $d / $hs.Count
    }
    [Array]::Sort($diffs)
    & $say ('{0} - {1}: macro difference {2:P2}, 95% CI [{3:P2}, {4:P2}]' -f $pair[0], $pair[1], ((& $macro $pair[0] $hs) - (& $macro $pair[1] $hs)), $diffs[[int](0.025 * $BootstrapSamples)], $diffs[[int](0.975 * $BootstrapSamples) - 1])
}
foreach ($t in ($hs | Group-Object { $perH[$_].Type } | Sort-Object Count -Descending)) {
    & $say ('type {0,-26} n={1,3}  A {2:P1}  B {3:P1}  C {4:P1}' -f $t.Name, $t.Count, (& $macro 'A' $t.Group), (& $macro 'B' $t.Group), (& $macro 'C' $t.Group))
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'summary.txt'), $log)
$rows = foreach ($h in $hs) { "$h`t$($perH[$h].Type)`t$($perH[$h].N)`t$($perH[$h].A)`t$($perH[$h].B)`t$($perH[$h].C)`t$($perH[$h].SmaOnly)`t$($perH[$h].BWide)" }
[IO.File]::WriteAllLines((Join-Path $OutDir 'per-homograph.tsv'), @("homograph`ttype`tn`tA`tB`tC`tSmaOnly`tBWide") + $rows)
