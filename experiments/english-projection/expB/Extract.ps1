#requires -Version 7.4
# Deterministic relation extraction from SMA's parse of a projected sentence, and scoring
# against hidden UD gold. Parse only; nothing is executed. The extraction rules are fixed
# here (not searched): predicate = command name of the stage after the first pipe (else the
# first word); subject = last word of the stage before the pipe; object = last word of the
# run between the predicate and the first parameter; a parameter's object = last word before
# the next parameter; every parameter is governed by the predicate.

class Prediction {
    [int]$Errors; [int]$Predicate; [int]$Subject; [int]$Object
    [object[]]$Preps    # @{ Prep; Obj; Gov }
}

function Test-PunctText([string]$T) {
    foreach ($c in $T.ToCharArray()) { if ([char]::IsLetterOrDigit($c)) { return $false } }
    $true
}

# Source token id (1-based) covering projected offset range [a,b), via the character map.
function Get-TokenAt([int]$A, [int]$B, [int[]]$Map, [object[]]$Tokens) {
    for ($i = $B - 1; $i -ge $A; $i--) {
        $src = $Map[$i]
        if ($src -lt 0) { continue }
        foreach ($t in $Tokens) { if ($src -ge $t.Start -and $src -lt $t.End) { return $t.Id } }
    }
    0
}

function Get-Prediction([Projected]$P, [object[]]$Tokens) {
    $pred = [Prediction]::new(); $pred.Preps = @()
    $tk = $null; $er = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($P.Text, [ref]$tk, [ref]$er)
    $pred.Errors = $er.Count
    $stmt = if ($ast.EndBlock -and $ast.EndBlock.Statements.Count) { $ast.EndBlock.Statements[0] } else { $null }
    if ($stmt -isnot [Management.Automation.Language.PipelineAst]) { return $pred }
    $stages = @($stmt.PipelineElements | Where-Object { $_ -is [Management.Automation.Language.CommandAst] })
    if ($stages.Count -eq 0) { return $pred }
    $words = { param($els) @($els | Where-Object { $_ -isnot [Management.Automation.Language.CommandParameterAst] -and -not (Test-PunctText $_.Extent.Text) }) }
    if ($stages.Count -ge 2) {
        $subjEls = & $words @($stages[0].CommandElements | Select-Object -Skip 1)
        if ($subjEls.Count) { $e = $subjEls[-1].Extent; $pred.Subject = Get-TokenAt $e.StartOffset $e.EndOffset $P.Map $Tokens }
        $body = @($stages[1].CommandElements)
    } else {
        $body = @($stages[0].CommandElements | Select-Object -Skip 1)     # drop the "//" sentinel
    }
    if ($body.Count -eq 0) { return $pred }
    $e = $body[0].Extent; $pred.Predicate = Get-TokenAt $e.StartOffset $e.EndOffset $P.Map $Tokens
    $run = [Collections.Generic.List[object]]::new(); $preps = [Collections.Generic.List[object]]::new()
    $current = $null
    $flush = {
        $ws = & $words $run.ToArray()
        $last = if ($ws.Count) { $x = $ws[-1].Extent; Get-TokenAt $x.StartOffset $x.EndOffset $P.Map $Tokens } else { 0 }
        if ($null -eq $current) { $pred.Object = $last } else { $preps.Add(@{ Prep = $current; Obj = $last; Gov = $pred.Predicate }) }
        $run.Clear()
    }
    foreach ($el in ($body | Select-Object -Skip 1)) {
        if ($el -is [Management.Automation.Language.CommandParameterAst]) {
            & $flush
            $x = $el.Extent; $current = Get-TokenAt $x.StartOffset $x.EndOffset $P.Map $Tokens
            if ($el.Argument) { $run.Add($el.Argument) }
        } else { $run.Add($el) }
    }
    & $flush
    $pred.Preps = $preps.ToArray()
    $pred
}

# Error counts against gold; each field is one judge dimension.
function Measure-Prediction([Prediction]$Pr, [object]$Gold) {
    $r = [ordered]@{ Root = 0; Subject = 0; Object = 0; PrepMissed = 0; PrepFalse = 0; PrepTotal = $Gold.Preps.Count }
    if ($Pr.Predicate -ne $Gold.Root) { $r.Root = 1 }
    if ($Pr.Subject -ne $Gold.Subject) { $r.Subject = 1 }
    if ($Pr.Object -ne $Gold.Object) { $r.Object = 1 }
    foreach ($g in $Gold.Preps) {
        $hit = $false
        foreach ($p in $Pr.Preps) { if ($p.Prep -eq $g.Prep -and $p.Obj -eq $g.Obj -and $p.Gov -eq $g.Gov) { $hit = $true } }
        if (-not $hit) { $r.PrepMissed++ }
    }
    foreach ($p in $Pr.Preps) {
        $hit = $false
        foreach ($g in $Gold.Preps) { if ($p.Prep -eq $g.Prep -and $p.Obj -eq $g.Obj -and $p.Gov -eq $g.Gov) { $hit = $true } }
        if (-not $hit) { $r.PrepFalse++ }
    }
    $r
}
