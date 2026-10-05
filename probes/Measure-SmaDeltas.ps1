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

function Get-ExpressionStructureString ($res) {
    $flags = [Reflection.BindingFlags]'Instance,NonPublic,Public'
    $pending = [Collections.Generic.Stack[object]]::new()
    $visited = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $pending.Push($res.Lambda)
    $tokens = [Collections.Generic.List[string]]::new()

    while ($pending.Count) {
        $node = $pending.Pop()
        if (-not $visited.Add($node)) { continue }

        if ($node -is [Linq.Expressions.ConstantExpression]) {
            [void]$tokens.Add("Const:$($node.Value)")
        } elseif ($node -is [Linq.Expressions.DynamicExpression]) {
            $b = $node.Binder
            $bStr = "Dyn:$($b.GetType().Name)"
            $opProp = $b.GetType().GetProperty('Operation', $flags)
            if ($opProp) { $bStr += ":$($opProp.GetValue($b))" }
            [void]$tokens.Add($bStr)
        } elseif ($node -is [Linq.Expressions.BinaryExpression]) {
            [void]$tokens.Add("Bin:$($node.NodeType)")
        } elseif ($node -is [Linq.Expressions.MethodCallExpression]) {
            [void]$tokens.Add("Call:$($node.Method.Name)")
        }

        foreach ($property in $node.GetType().GetProperties([Reflection.BindingFlags]'Public,Instance')) {
            if ($property.GetIndexParameters().Count -or $property.Name -in 'Type','NodeType','CanReduce') { continue }
            $val = $property.GetValue($node)
            if ($val -is [Linq.Expressions.Expression]) { $pending.Push($val) }
            elseif ($val -is [Collections.IEnumerable] -and $val -isnot [string]) {
                foreach ($item in $val) { if ($item -is [Linq.Expressions.Expression]) { $pending.Push($item) } }
            }
        }
    }
    return $tokens -join ';'
}

function Get-ExpressionDelta ($resA, $resB) {
    $strA = Get-ExpressionStructureString $resA
    $strB = Get-ExpressionStructureString $resB
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
