# Test evaluation on 30 sentences using EvaluationEngine.ps1
$baseDir = "C:\temp\sma-english-projection"
. "$baseDir\tools\EvaluationEngine.ps1"

$trainPath = "$baseDir\inputs\train_500.tsv"
$spacyPath = "$baseDir\inputs\spacy_train_500.tsv"

$trainLines = [System.IO.File]::ReadAllLines($trainPath)
$spacyLines = [System.IO.File]::ReadAllLines($spacyPath)

# Collect first 30 sentences
$sentences = [string[]]::new(30)
for ($i = 0; $i -lt 30; $i++) {
    $sentences[$i] = $trainLines[$i + 1].Split([char]9)[5]
}

# Collect spaCy tokens for first 30 sentences
$spacyMap = [System.Collections.Generic.Dictionary[int, object]]::new()
for ($i = 1; $i -lt $spacyLines.Length; $i++) {
    $line = $spacyLines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $cols = $line.Split([char]9)
    $sId = [int]::Parse($cols[0])
    if ($sId -ge 30) { break }
    if (-not $spacyMap.ContainsKey($sId)) {
        $spacyMap[$sId] = [System.Collections.Generic.List[object]]::new()
    }
    $spacyMap[$sId].Add([PSCustomObject]@{
        SentenceId = $sId
        TokenIdx   = [int]::Parse($cols[1])
        Start      = [int]::Parse($cols[2])
        End        = [int]::Parse($cols[3])
        Text       = $cols[4]
        Pos        = $cols[5]
        Dep        = $cols[6]
    })
}

# Test 1: Baseline config (all none)
$baseCfg = [ProjectionConfig]::new()
$baseRes = EvaluateDataset $sentences $spacyMap $baseCfg
Write-Output "BASELINE: $($baseRes.FormatScore())"

# Test 2: Proposed config (qmark + apos_modifier + hash + semi + term_space)
$propCfg = [ProjectionConfig]::new()
$propCfg.Prefix = "qmark"
$propCfg.Apostrophe = "modifier"
$propCfg.Hash = "fullwidth"
$propCfg.Semicolon = "fullwidth"
$propCfg.TermPunct = "space"

$propRes = EvaluateDataset $sentences $spacyMap $propCfg
Write-Output "PROPOSED: $($propRes.FormatScore())"

$cmp = CompareResults $propRes $baseRes
Write-Output "COMPARISON: Proposed vs Baseline = $cmp (1=better, -1=worse, 0=neutral)"
