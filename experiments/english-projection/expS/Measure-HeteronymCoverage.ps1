#requires -Version 7.4
# Count occurrences of misaki's multi-pronunciation words (us_gold, fba12365) in the Gutenberg
# snapshot, as whole words, case-insensitive. No regex.
param(
    [string] $Books = (Join-Path $PSScriptRoot '..\inputs\gutenberg'),
    [string] $MisakiRepo = 'C:\Dev\.vendor\misaki',
    [string] $MisakiCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3',
    [string] $OutDir = (Join-Path $PSScriptRoot 'results')
)
$ErrorActionPreference = 'Stop'
[void][IO.Directory]::CreateDirectory($OutDir)
$gold = (git -C $MisakiRepo show "${MisakiCommit}:misaki/data/us_gold.json") -join "`n" | ConvertFrom-Json -AsHashtable
$multi = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($k in $gold.Keys) {
    $v = $gold[$k]
    if ($v -is [Collections.IDictionary] -and @($v.Values | Where-Object { $_ -is [string] -and $_.Length } | Sort-Object -Unique -CaseSensitive).Count -gt 1) { [void]$multi.Add($k.ToLowerInvariant()) }
}
$counts = @{}; foreach ($w in $multi) { $counts[$w] = 0 }
$total = 0
foreach ($f in (Get-ChildItem $Books -Filter 'pg*.txt' | Where-Object { -not $_.Name.Contains('.raw.') })) {
    $t = [IO.File]::ReadAllText($f.FullName); $i = 0
    while ($i -lt $t.Length) {
        while ($i -lt $t.Length -and -not [char]::IsLetter($t[$i])) { $i++ }
        $a = $i; while ($i -lt $t.Length -and ([char]::IsLetter($t[$i]))) { $i++ }
        if ($i -gt $a) { $total++; $w = $t.Substring($a, $i - $a).ToLowerInvariant(); if ($multi.Contains($w)) { $counts[$w]++ } }
    }
}
$rows = @($counts.GetEnumerator() | Sort-Object Value -Descending)
[IO.File]::WriteAllLines((Join-Path $OutDir 'coverage.tsv'), @("word`tcount") + ($rows | ForEach-Object { "$($_.Key)`t$($_.Value)" }))
"words in snapshot: $total; multi-pronunciation words: $($multi.Count)"
foreach ($t in 0, 1, 10, 50, 200, 1000) { "  with >= $t occurrences: $(@($rows | Where-Object Value -ge $t).Count)" }
"  never seen: $(@($rows | Where-Object Value -eq 0).Count)"
"  top: " + (($rows | Select-Object -First 12 | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
