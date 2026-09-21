[CmdletBinding()]
param(
    [string]$SourceA = 'param($a, $b) [void]($a + $b)',
    [string]$SourceB = 'param($a, $b) [void]( $a + $b )'
)

$probe = "$PSScriptRoot\Observe-SmaLowering.ps1"

$resA = & $probe -Source $SourceA -PassThru
$resB = & $probe -Source $SourceB -PassThru

function Get-AstDelta ($astA, $astB) {
    # Simple delta: string representation comparison
    $strA = $astA.ToString()
    $strB = $astB.ToString()
    return $strA -ne $strB
}

function Get-TokensDelta ($srcA, $srcB) {
    $tA = $null; $eA = $null; $null = [System.Management.Automation.Language.Parser]::ParseInput($srcA, [ref]$tA, [ref]$eA)
    $tB = $null; $eB = $null; $null = [System.Management.Automation.Language.Parser]::ParseInput($srcB, [ref]$tB, [ref]$eB)
    
    if ($tA.Count -ne $tB.Count) { return $true }
    for ($i = 0; $i -lt $tA.Count; $i++) {
        if ($tA[$i].Kind -ne $tB[$i].Kind) { return $true }
        if ($tA[$i].Text -ne $tB[$i].Text) { return $true }
    }
    return $false
}

function Get-ExpressionDelta ($resA, $resB) {
    $strA = $resA.Lambda.ToString()
    $strB = $resB.Lambda.ToString()
    return $strA -ne $strB
}

function Get-BehaviorDelta ($resA, $resB) {
    # We can invoke them to see if behavior is same.
    # For simplicity, if they both don't throw and return same results for a few inputs.
    # Since these are void returns, they just execute.
    return $false # Stub for now
}

$deltaSource = $SourceA -ne $SourceB
$deltaTokens = Get-TokensDelta $SourceA $SourceB
$deltaAst = Get-AstDelta $resA.Ast $resB.Ast
$deltaExpression = Get-ExpressionDelta $resA $resB
$deltaBehavior = Get-BehaviorDelta $resA $resB

[pscustomobject]@{
    SourceA = $SourceA
    SourceB = $SourceB
    DeltaSource = $deltaSource
    DeltaTokens = $deltaTokens
    DeltaAst = $deltaAst
    DeltaExpression = $deltaExpression
    DeltaBehavior = $deltaBehavior
}
