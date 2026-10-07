#requires -Version 7.4
# Experiment B: does a relational projection (pipe before a predicate cue, "-" before parameter
# words) make SMA's tree match UD English EWT relations? Greedy hill climb on train, scored
# once on dev after freezing. Gold is revealed only to the scorer. Parse only; nothing executes.
param(
    [string] $UdDir = (Join-Path $PSScriptRoot '..\inputs\ud-ewt-r2.18'),
    [string] $UdCommit = 'b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c',      # tag r2.18; files fetched at this commit
    [ValidateRange(50, 5000)][int] $TrainCount = 600,
    [ValidateRange(50, 2000)][int] $DevCount = 300,
    [ValidateRange(10, 400)][int] $CandidateWords = 120,
    [ValidateRange(1, 20000)][int] $MaxEvaluations = 3000,
    [ValidateRange(1, 200)][int] $MaxRules = 40,
    [ValidateRange(0, 20)][int] $MaxNeutralMoves = 5,
    [ValidateRange(1, 600)][int] $MaxMinutes = 60,
    [string] $OutDir = (Join-Path $PSScriptRoot 'results')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ud.ps1'); . (Join-Path $PSScriptRoot 'Projection.ps1'); . (Join-Path $PSScriptRoot 'Extract.ps1')
. (Join-Path $PSScriptRoot '..\tools\EvaluationEngine.ps1')
[void][IO.Directory]::CreateDirectory($OutDir)
$stopFile = Join-Path $OutDir 'STOP'
$clock = [Diagnostics.Stopwatch]::StartNew()
$log = [Collections.Generic.List[string]]::new()
$say = { param($m) $line = '[{0,6:F1}s] {1}' -f $clock.Elapsed.TotalSeconds, $m; $log.Add($line); $line }

# Data: pinned release, ordinary finite clauses, deterministic order.
$pinned = @{ 'en_ewt-ud-train.conllu' = 'D68E06122A702464C613076523D56740F047E5BBE89DD90EC32737E04D952143'
             'en_ewt-ud-dev.conllu'   = '39239E0A60DB3AE68F4B7036189F11B6692741D10FF8240DD91F74F2760D90F8' }
$load = { param($name, $count)
    $path = Join-Path $UdDir $name
    if ((Get-FileHash $path).Hash -ne $pinned[$name]) { throw "$name does not match its pinned SHA-256" }
    $lines = [IO.File]::ReadAllLines($path)
    $all = @(Read-UdSentences $lines); foreach ($s in $all) { Set-UdGold $s }
    @($all | Where-Object { Test-FiniteClause $_ } | Select-Object -First $count)
}
$train = & $load 'en_ewt-ud-train.conllu' $TrainCount
$dev = & $load 'en_ewt-ud-dev.conllu' $DevCount
& $say "UD EWT r2.18 ${UdCommit}: train $($train.Count), dev $($dev.Count) finite clauses"

# Stage 0 must equal the lab's frozen ProjectSentence, and invert exactly.
$cfg = [ProjectionConfig]::new(); $cfg.Prefix = 'slash'; $cfg.Apostrophe = 'modifier'; $cfg.Hash = 'fullwidth'
$cfg.Semicolon = 'fullwidth'; $cfg.TermPunct = 'space'; $cfg.Hyphen = 'unicode'; $cfg.Quote = 'guillemets'
$stage0 = @{}; $equivFail = 0; $invFail = 0; $collisions = 0
foreach ($s in $train + $dev) {
    $p = ConvertTo-Stage0 $s.Text; $stage0[$s.SentId] = $p
    if ($p.Text -cne (ProjectSentence $s.Text $cfg)) { $equivFail++ }
    if (-not $p.Reversible) { $collisions++ } elseif ((ConvertFrom-Projected $p) -cne $s.Text) { $invFail++ }
}
& $say "Stage 0: equivalence failures $equivFail, inverse failures $invFail, source collisions $collisions"
if ($equivFail -or $invFail) { throw 'Stage 0 is not the frozen projection or does not invert exactly' }

$cache = @{}
$fields = @('ParseErrors', 'RevFail', 'Root', 'Subject', 'Object', 'PrepMissed', 'PrepFalse', 'PrepTotal')
$scoreOne = { param([RelationRules]$R, $s)
    $p0 = $stage0[$s.SentId]
    $p = ConvertTo-Relational $p0 $R
    $row = @{ RevFail = 0 }
    if ($p0.Reversible -and (ConvertFrom-Projected $p) -cne $s.Text) { $row.RevFail = 1 }
    $key = $s.SentId + "`n" + $p.Text
    $pr = $cache[$key]
    if ($null -eq $pr) { $pr = Get-Prediction $p $s.Tokens; $cache[$key] = $pr }
    $m = Measure-Prediction $pr $s
    $row.ParseErrors = $pr.Errors
    foreach ($k in 'Root', 'Subject', 'Object', 'PrepMissed', 'PrepFalse', 'PrepTotal') { $row[$k] = $m[$k] }
    $row
}
$evaluate = { param([RelationRules]$R, [object[]]$Set)
    $v = [ordered]@{ ParseErrors = 0; RevFail = 0; Relation = 0; Root = 0; Subject = 0; Object = 0; PrepMissed = 0; PrepFalse = 0; PrepTotal = 0; Rules = $R.Count() }
    foreach ($s in $Set) { $row = & $scoreOne $R $s; foreach ($k in $fields) { $v[$k] += $row[$k] } }
    $v.Relation = $v.Root + $v.Subject + $v.Object + $v.PrepMissed + $v.PrepFalse
    $v
}
# Strict order: parse errors, reversibility, relation errors, rule count.
$better = { param($a, $b)
    foreach ($k in 'ParseErrors', 'RevFail', 'Relation', 'Rules') { if ($a[$k] -lt $b[$k]) { return 1 }; if ($a[$k] -gt $b[$k]) { return -1 } }
    0
}
$fmt = { param($v) 'parse={0} rev={1} rel={2} [root={3} subj={4} obj={5} prepMiss={6}/{7} prepFalse={8}] rules={9}' -f $v.ParseErrors, $v.RevFail, $v.Relation, $v.Root, $v.Subject, $v.Object, $v.PrepMissed, $v.PrepTotal, $v.PrepFalse, $v.Rules }

# Candidate vocabulary from train surface text only (no gold).
$freq = @{}
foreach ($s in $train) { foreach ($w in $s.Text.Split(' ')) { if (Test-PlainWord $w) { $l = $w.ToLowerInvariant(); $freq[$l] = 1 + [int]$freq[$l] } } }
$vocab = @($freq.GetEnumerator() | Sort-Object @{ e = { $_.Value }; Descending = $true }, @{ e = { $_.Key } } | Select-Object -First $CandidateWords | ForEach-Object Key)
$suffixes = @('s', 'es', 'ed', 'ing', 'ize', 'ate', 'en')

# Incremental scoring: a move on word w (or suffix x) only changes sentences containing it.
$byWord = @{}
foreach ($s in $train) {
    foreach ($w in (Get-ProjectedWords $stage0[$s.SentId])) {
        if (Test-PlainWord $w.Text) { $l = $w.Text.ToLowerInvariant(); if (-not $byWord[$l]) { $byWord[$l] = [Collections.Generic.HashSet[string]]::new() }; [void]$byWord[$l].Add($s.SentId) }
    }
}
$trainById = @{}; foreach ($s in $train) { $trainById[$s.SentId] = $s }
$affected = { param([string]$Kind, [string]$Token)
    if ($Kind -ne 'S') { if ($byWord[$Token]) { return @($byWord[$Token]) } else { return @() } }
    $set = [Collections.Generic.HashSet[string]]::new()
    foreach ($e in $byWord.GetEnumerator()) { if ($e.Key.Length -gt $Token.Length + 2 -and $e.Key.EndsWith($Token, [StringComparison]::Ordinal)) { foreach ($id in $e.Value) { [void]$set.Add($id) } } }
    @($set)
}
$rules = [RelationRules]::new()
$per = @{}; foreach ($s in $train) { $per[$s.SentId] = & $scoreOne $rules $s }
$score = & $evaluate $rules $train; $evals = 1
$scoreMove = { param([RelationRules]$Cand, [string]$Kind, [string]$Token)
    $v = [ordered]@{}; foreach ($k in $score.Keys) { $v[$k] = $score[$k] }
    $pending = @{}
    foreach ($id in (& $affected $Kind $Token)) {
        $old = $per[$id]; $new = & $scoreOne $Cand $trainById[$id]; $pending[$id] = $new
        foreach ($k in $fields) { $v[$k] += $new[$k] - $old[$k] }
    }
    $v.Rules = $Cand.Count(); $v.Relation = $v.Root + $v.Subject + $v.Object + $v.PrepMissed + $v.PrepFalse
    @($v, $pending)
}
$baseDev = & $evaluate $rules $dev
& $say ("Baseline train: " + (& $fmt $score))
$moves = [Collections.Generic.List[string]]::new(); $moves.Add("step`tmove`toutcome`tparse`trev`trelation`trules")
$visited = [Collections.Generic.HashSet[string]]::new(); [void]$visited.Add($rules.Key())
$neutral = 0; $step = 0; $stopReason = 'no improving move'
while ($true) {
    $step++
    $neighbors = [Collections.Generic.List[object]]::new()
    if ($rules.Count() -lt $MaxRules) {
        foreach ($w in $vocab) {
            if (-not $rules.VerbCues.Contains($w)) { $neighbors.Add(@("+V:$w", { param($r) [void]$r.VerbCues.Add($args[0]) }, $w)) }
            if (-not $rules.Params.Contains($w)) { $neighbors.Add(@("+P:$w", { param($r) [void]$r.Params.Add($args[0]) }, $w)) }
        }
        foreach ($x in $suffixes) { if (-not $rules.Suffixes.Contains($x)) { $neighbors.Add(@("+S:$x", { param($r) [void]$r.Suffixes.Add($args[0]) }, $x)) } }
    }
    foreach ($w in @($rules.VerbCues)) { $neighbors.Add(@("-V:$w", { param($r) [void]$r.VerbCues.Remove($args[0]) }, $w)) }
    foreach ($w in @($rules.Params)) { $neighbors.Add(@("-P:$w", { param($r) [void]$r.Params.Remove($args[0]) }, $w)) }
    foreach ($x in @($rules.Suffixes)) { $neighbors.Add(@("-S:$x", { param($r) [void]$r.Suffixes.Remove($args[0]) }, $x)) }

    $best = $null; $bestScore = $null; $bestName = $null; $bestNeutral = $null; $bestNeutralName = $null; $bestNeutralScore = $null
    foreach ($n in $neighbors) {
        if ($evals -ge $MaxEvaluations) { $stopReason = 'evaluation budget'; break }
        if ($clock.Elapsed.TotalMinutes -ge $MaxMinutes) { $stopReason = 'time limit'; break }
        if (Test-Path $stopFile) { $stopReason = 'stop file'; break }
        $cand = $rules.Clone(); & $n[1] $cand $n[2]
        if ($visited.Contains($cand.Key())) { continue }
        $sm = & $scoreMove $cand $n[0].Substring(1, 1) $n[2]; $v = $sm[0]; $evals++
        $c = & $better $v $score
        $moves.Add("$step`t$($n[0])`t" + $(if ($c -gt 0) { 'improves' } elseif ($c -eq 0) { 'neutral' } else { 'worse' }) + "`t$($v.ParseErrors)`t$($v.RevFail)`t$($v.Relation)`t$($v.Rules)")
        if ($c -gt 0 -and ($null -eq $bestScore -or (& $better $v $bestScore) -gt 0)) { $best = $cand; $bestScore = $v; $bestName = $n[0]; $bestPending = $sm[1] }
        if ($c -eq 0 -and $null -eq $bestNeutral) { $bestNeutral = $cand; $bestNeutralName = $n[0]; $bestNeutralScore = $v; $bestNeutralPending = $sm[1] }
    }
    if ($null -ne $best) {
        foreach ($e in $bestPending.GetEnumerator()) { $per[$e.Key] = $e.Value }
        $rules = $best; $score = $bestScore; [void]$visited.Add($rules.Key())
        $moves.Add("$step`t$bestName`tKEPT`t$($score.ParseErrors)`t$($score.RevFail)`t$($score.Relation)`t$($score.Rules)")
        & $say "step $step keep $bestName -> $(& $fmt $score)  (evals $evals)"
    } elseif ($null -ne $bestNeutral -and $neutral -lt $MaxNeutralMoves -and $stopReason -eq 'no improving move') {
        foreach ($e in $bestNeutralPending.GetEnumerator()) { $per[$e.Key] = $e.Value }
        $neutral++; $rules = $bestNeutral; $score = $bestNeutralScore; [void]$visited.Add($rules.Key())
        $moves.Add("$step`t$bestNeutralName`tKEPT-NEUTRAL`t$($score.ParseErrors)`t$($score.RevFail)`t$($score.Relation)`t$($score.Rules)")
        & $say "step $step neutral $bestNeutralName ($neutral/$MaxNeutralMoves)"
    } else { break }
    if ($stopReason -ne 'no improving move') { break }
}
& $say "Stopped: $stopReason after $evals evaluations"
$full = & $evaluate $rules $train
foreach ($k in $fields + 'Relation') { if ($full[$k] -ne $score[$k]) { throw "Incremental score differs from full rescore on $k ($($score[$k]) vs $($full[$k]))" } }
& $say 'Incremental score equals full rescore'
& $say ("Frozen train: " + (& $fmt $score))
& $say ("Frozen rules: " + $rules.Key())
$frozenDev = & $evaluate $rules $dev
& $say ("Dev baseline: " + (& $fmt $baseDev))
& $say ("Dev frozen:   " + (& $fmt $frozenDev))
[IO.File]::WriteAllLines((Join-Path $OutDir 'moves.tsv'), $moves)
[IO.File]::WriteAllLines((Join-Path $OutDir 'summary.txt'), $log)
