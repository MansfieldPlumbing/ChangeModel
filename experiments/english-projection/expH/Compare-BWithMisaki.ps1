#requires -Version 7.4
# Paired bootstrap over homographs: system B (word-context decision lists) minus misaki.
$r = Join-Path $PSScriptRoot 'results'
$b = @{}; foreach ($l in ([IO.File]::ReadAllLines("$r\per-homograph.tsv") | Select-Object -Skip 1)) { $f = $l.Split("`t"); $b[$f[0]] = [double]$f[4] / [double]$f[2] }
$m = @{}; foreach ($l in ([IO.File]::ReadAllLines("$r\misaki-per-homograph.tsv") | Select-Object -Skip 1)) { $f = $l.Split("`t"); $m[$f[0]] = [double]$f[2] / [double]$f[1] }
$hs = @($b.Keys | Where-Object { $m.ContainsKey($_) } | Sort-Object)
$mean = { param($keys, $t) $s = 0.0; foreach ($h in $keys) { $s += $t[$h] }; $s / $keys.Count }
$rng = [Random]::new(20261007); $n = 2000; $d = [double[]]::new($n)
for ($i = 0; $i -lt $n; $i++) { $s = 0.0; for ($k = 0; $k -lt $hs.Count; $k++) { $h = $hs[$rng.Next($hs.Count)]; $s += $b[$h] - $m[$h] }; $d[$i] = $s / $hs.Count }
[Array]::Sort($d)
'homographs {0}  B {1:P2}  misaki {2:P2}  B - misaki {3:P2}  95% CI [{4:P2}, {5:P2}]' -f $hs.Count, (& $mean $hs $b), (& $mean $hs $m), ((& $mean $hs $b) - (& $mean $hs $m)), $d[[int](0.025 * $n)], $d[[int](0.975 * $n) - 1]
$wins = @($hs | Where-Object { $b[$_] -gt $m[$_] }).Count; $losses = @($hs | Where-Object { $b[$_] -lt $m[$_] }).Count
"B better on $wins homographs, misaki better on $losses, tied on $($hs.Count - $wins - $losses)"
