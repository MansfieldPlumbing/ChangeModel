[CmdletBinding()]
param(
    [string]$SourceA = 'param($a, $b) [void]($a + $b)',
    [string]$SourceB = 'param($a, $b) [void]( $a + $b )'
)

$probe = "$PSScriptRoot\Observe-SmaLowering.ps1"

$resA = & $probe -Source $SourceA -PassThru
$resB = & $probe -Source $SourceB -PassThru

function Get-AstStructureString ($ast) {
    $sb = [System.Text.StringBuilder]::new()
    $nodes = $ast.FindAll({ $true }, $true)
    foreach ($node in $nodes) {
        $nodeType = $node.GetType().Name
        $details = switch ($nodeType) {
            'VariableExpressionAst' { $node.VariablePath.UserPath }
            'BinaryExpressionAst' { $node.Operator.ToString() }
            'ConstantExpressionAst' { [string]$node.Value }
            'TypeExpressionAst' { $node.TypeName.FullName }
            'ParameterAst' { $node.Name.VariablePath.UserPath }
            Default { '' }
        }
        [void]$sb.Append("$($nodeType):$($details);")
    }
    return $sb.ToString()
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

function Get-BehaviorDelta ($resA, $resB, [array]$TestInputs = @(@(2, 3), @(-1, 5), @(0, 0))) {
    foreach ($inputs in $TestInputs) {
        $outA = $null; $errA = $null
        $outB = $null; $errB = $null

        try {
            $outA = & $resA.ScriptBlock @inputs
        } catch {
            $errA = $_.Exception.Message
        }

        try {
            $outB = & $resB.ScriptBlock @inputs
        } catch {
            $errB = $_.Exception.Message
        }

        if ($errA -ne $errB) { return $true }
        if ([string]$outA -ne [string]$outB) { return $true }
    }
    return $false
}

$deltaSource = $SourceA -ne $SourceB
$deltaTokens = Get-TokensDelta $SourceA $SourceB
$deltaAstExtent = $resA.Ast.ToString() -ne $resB.Ast.ToString()
$deltaAstStructure = (Get-AstStructureString $resA.Ast) -ne (Get-AstStructureString $resB.Ast)
$deltaExpression = Get-ExpressionDelta $resA $resB
$deltaBehavior = Get-BehaviorDelta $resA $resB

[pscustomobject]@{
    SourceA = $SourceA
    SourceB = $SourceB
    DeltaSource = $deltaSource
    DeltaTokens = $deltaTokens
    DeltaAstExtent = $deltaAstExtent
    DeltaAstStructure = $deltaAstStructure
    DeltaExpression = $deltaExpression
    DeltaBehavior = $deltaBehavior
    IsSemanticsPreserving = ($deltaSource -and -not $deltaBehavior)
}
