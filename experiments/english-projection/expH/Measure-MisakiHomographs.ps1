#requires -Version 7.4
# Score misaki's homograph choices against WikipediaHomographData eval labels.
# 1. Map each dataset WORDID to one of misaki's lexicon pronunciations for that word, by edit
#    distance after normalizing both transcription conventions (written to mapping.tsv for review).
# 2. misaki's choice for a sentence = its nearest lexicon pronunciation to the phonemes it output.
# 3. Correct when that choice maps to the gold WORDID. A WORDID with no misaki pronunciation is
#    unreachable for misaki. No regex.
param(
    [string] $Data = (Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\WikipediaHomographData\data'),
    [string] $MisakiOutput = (Join-Path $PSScriptRoot 'results\misaki-eval.tsv'),
    [string] $MisakiRepo = 'C:\Dev\.vendor\misaki',
    [string] $MisakiCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3',
    [string] $OutDir = (Join-Path $PSScriptRoot 'results')
)
$ErrorActionPreference = 'Stop'
$unquote = { param([string]$f) if ($f.Length -ge 2 -and $f[0] -eq '"' -and $f[-1] -eq '"') { $f.Substring(1, $f.Length - 2).Replace('""', '"') } else { $f } }

# One phone convention: misaki's capital-letter diphthongs and WHD's r-colored vowels expanded,
# stress and length dropped.
$normalize = { param([string]$p)
    $map = [ordered]@{ 'A' = 'eɪ'; 'I' = 'aɪ'; 'O' = 'oʊ'; 'W' = 'aʊ'; 'Y' = 'ɔɪ'; 'Q' = 'əʊ'; 'ʤ' = 'dʒ'; 'ʧ' = 'tʃ'; 'ɾ' = 't'; 'ᵻ' = 'ɪ'; 'ᵊ' = 'ə'
        'ɚ' = 'əɹ'; 'ɝ' = 'ɜɹ'; 'r' = 'ɹ'; 'ɡ' = 'g'; 'ɐ' = 'ə'; 'ɑː' = 'ɑ'; 'iː' = 'i'; 'uː' = 'u'; 'ɔː' = 'ɔ'; 'ɜː' = 'ɜ' }
    $sb = [Text.StringBuilder]::new($p)
    foreach ($e in $map.GetEnumerator()) { [void]$sb.Replace($e.Key, $e.Value) }
    [void]$sb.Replace("'", 'ˈ')                                   # WHD marks primary stress with an apostrophe
    foreach ($c in "ˌːˑ.- ".ToCharArray()) { [void]$sb.Replace([string]$c, '') }
    # Primary stress = index of the vowel nucleus after the mark (WHD marks the syllable, misaki the vowel).
    $vowels = 'aeiouæɑɔəɛɪʊʌɜɒ'
    $s = $sb.ToString(); $seg = [Text.StringBuilder]::new(); $nucleus = -1; $stressAt = -1; $pending = $false; $inVowel = $false
    foreach ($c in $s.ToCharArray()) {
        if ($c -eq [char]0x02C8) { $pending = $true; continue }
        $isV = $vowels.IndexOf($c) -ge 0
        if ($isV -and -not $inVowel) { $nucleus++; if ($pending) { $stressAt = $nucleus; $pending = $false } }
        $inVowel = $isV; [void]$seg.Append($c)
    }
    "$stressAt|" + $seg.ToString()
}
# Distance between normalized forms: segment edit distance plus 2 when primary stress differs.
$distance = { param([string]$x, [string]$y)
    $px = $x.Split('|', 2); $py = $y.Split('|', 2)
    (& $editDistance $px[1] $py[1]) + $(if ($px[0] -ne $py[0]) { 2 } else { 0 })
}
$editDistance = { param([string]$a, [string]$b)
    $d = [int[,]]::new($a.Length + 1, $b.Length + 1)
    for ($i = 0; $i -le $a.Length; $i++) { $d[$i, 0] = $i }; for ($j = 0; $j -le $b.Length; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $a.Length; $i++) { for ($j = 1; $j -le $b.Length; $j++) {
        $c = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
        $d[$i, $j] = [math]::Min([math]::Min($d[($i - 1), $j] + 1, $d[$i, ($j - 1)] + 1), $d[($i - 1), ($j - 1)] + $c) } }
    $d[$a.Length, $b.Length]
}

$gold = (git -C $MisakiRepo show "${MisakiCommit}:misaki/data/us_gold.json") -join "`n" | ConvertFrom-Json -AsHashtable
$silver = (git -C $MisakiRepo show "${MisakiCommit}:misaki/data/us_silver.json") -join "`n" | ConvertFrom-Json -AsHashtable
$senses = @{}
foreach ($l in ([IO.File]::ReadAllLines((Join-Path $Data 'wordids.tsv')) | Select-Object -Skip 1)) {
    $f = $l.Split("`t"); $h = & $unquote $f[0]
    if (-not $senses[$h]) { $senses[$h] = [Collections.Generic.List[object]]::new() }
    $senses[$h].Add([pscustomobject]@{ WordId = (& $unquote $f[1]); Label = (& $unquote $f[2]); Ipa = (& $unquote $f[3]); Type = (& $unquote $f[5]) })
}

# Mapping: each distinct misaki pronunciation -> nearest WORDID; ties and far matches flagged.
# Human review applied to the 13 flagged rows (6 collapsed words + 3 ties):
$reviewedOverrides = @{
    'abuses'    = @{ 'əbjˈuzᵻz' = 'abuses_vrb' }    # DEFAULT is verb with voiced z; WHD IPA typo had dropped final z
    'axes'      = @{ 'ˈæksᵻz' = 'axes_nou-vrb' }    # VERB is ax/axes (plural or 3rd sing); DEFAULT is axis
    'diagnoses' = @{ 'dˌIəɡnˈOsᵻz' = 'diagnoses_vrb' } # DEFAULT is verb (diagnose-s); NOUN is diagnoses (plural)
    'fragment'  = @{ 'fɹˈæɡmˌɛnt' = 'fragment_vrb' } # VERB has full vowel /ɛnt/; noun has schwa
    'moderate'  = @{ 'mˈɑdəɹˌAt' = 'moderate_vrb' }  # VERB has full vowel /eɪt/; adj/noun has schwa
    'ornament'  = @{ 'ˈɔɹnəmɛnt' = 'ornament_vrb' }  # VERB has full vowel /ɛnt/; noun has schwa
}

$mapping = @{}; $mapRows = [Collections.Generic.List[string]]::new()
$mapRows.Add("homograph`tmisaki_key`tmisaki_phonemes`twordid`twhd_ipa`tdistance`tflag")
foreach ($h in ($senses.Keys | Sort-Object)) {
    $entry = if ($gold.ContainsKey($h)) { $gold[$h] } elseif ($silver.ContainsKey($h)) { $silver[$h] } else { $null }
    $cands = [ordered]@{}
    if ($entry -is [Collections.IDictionary]) { foreach ($k in ($entry.Keys | Sort-Object)) { if ($entry[$k] -is [string] -and $entry[$k].Length) { $cands[$k] = $entry[$k] } } }
    elseif ($entry -is [string]) { $cands['ONLY'] = $entry }
    $mapping[$h] = @{}
    foreach ($k in $cands.Keys) {
        $ph = $cands[$k]
        if ($reviewedOverrides.ContainsKey($h) -and $reviewedOverrides[$h].ContainsKey($ph)) {
            $wid = $reviewedOverrides[$h][$ph]
            $s = ($senses[$h] | Where-Object { $_.WordId -eq $wid } | Select-Object -First 1)
            $mapping[$h][$ph] = $wid
            $mapRows.Add("$h`t$k`t$ph`t$wid`t$($s.Ipa)`t0`tREVIEWED")
            continue
        }
        $mp = & $normalize $ph
        $scored = foreach ($s in $senses[$h]) { [pscustomobject]@{ S = $s; D = (& $distance $mp (& $normalize $s.Ipa)) } }
        $scored = @($scored | Sort-Object D)
        $flag = if ($scored.Count -gt 1 -and $scored[0].D -eq $scored[1].D) { 'TIE-RESOLVED' } elseif ($scored[0].D -gt 3) { 'FAR' } else { '' }
        $mapping[$h][$ph] = $scored[0].S.WordId
        $mapRows.Add("$h`t$k`t$ph`t$($scored[0].S.WordId)`t$($scored[0].S.Ipa)`t$($scored[0].D)`t$flag")
    }
    $distinct = @($mapping[$h].Keys).Count; $targets = @($mapping[$h].Values | Sort-Object -Unique).Count
    if ($distinct -gt 1 -and $targets -lt [math]::Min($distinct, $senses[$h].Count)) { $mapRows.Add("$h`t*`t*`t*`t*`t*`tCOLLAPSE") }
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'misaki-mapping.tsv'), $mapRows)

# Score.
$perH = @{}
$lines = [IO.File]::ReadAllLines($MisakiOutput)
foreach ($l in ($lines | Select-Object -Skip 1)) {
    $f = $l.Split("`t"); $h = $f[2]; $wid = $f[3]; $ph = $f[8]
    if (-not $perH[$h]) { $perH[$h] = @{ N = 0; Ok = 0; Unmatched = 0 } }
    $perH[$h].N++
    $choice = $null
    if ($ph.Length -and $mapping[$h].Count) {
        $np = & $normalize $ph; $bestD = [int]::MaxValue
        foreach ($cand in $mapping[$h].Keys) { $d = & $distance $np (& $normalize $cand); if ($d -lt $bestD) { $bestD = $d; $choice = $mapping[$h][$cand] } }
    } else { $perH[$h].Unmatched++ }
    if ($choice -ceq $wid) { $perH[$h].Ok++ }
}
$hs = @($perH.Keys | Sort-Object)
$macro = 0.0; $ok = 0; $n = 0; $un = 0
foreach ($h in $hs) { $macro += $perH[$h].Ok / $perH[$h].N; $ok += $perH[$h].Ok; $n += $perH[$h].N; $un += $perH[$h].Unmatched }
$flags = @($mapRows | Select-Object -Skip 1 | Where-Object { $_.EndsWith("`tTIE") -or $_.EndsWith("`tFAR") -or $_.EndsWith("`tCOLLAPSE") }).Count
"misaki (lexicon mode) macro {0:P2}  micro {1:P2}  homographs {2}  sentences {3}  no-phoneme rows {4}  mapping rows flagged {5}" -f ($macro / $hs.Count), ($ok / $n), $hs.Count, $n, $un, $flags
[IO.File]::WriteAllLines((Join-Path $OutDir 'misaki-per-homograph.tsv'), @("homograph`tn`tcorrect") + ($hs | ForEach-Object { "$_`t$($perH[$_].N)`t$($perH[$_].Ok)" }))
