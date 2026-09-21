function Get-AuthenticExpressionFingerprint {
    param([Parameter(Mandatory)]$LoweredResult)

    $flags = [Reflection.BindingFlags]'Instance,NonPublic,Public'
    $pending = [Collections.Generic.Stack[object]]::new()
    $visited = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $pending.Push($LoweredResult.Lambda)

    $binderOps = [Collections.Generic.List[string]]::new()
    $constantValues = [Collections.Generic.List[string]]::new()
    $nodeTypes = [Collections.Generic.List[string]]::new()
    $calls = [Collections.Generic.List[string]]::new()
    $operandOrder = [Collections.Generic.List[string]]::new()
    $fullTokens = [Collections.Generic.List[string]]::new()

    while ($pending.Count) {
        $node = $pending.Pop()
        if (-not $visited.Add($node)) { continue }

        if ($node -is [Linq.Expressions.Expression]) {
            [void]$nodeTypes.Add($node.NodeType.ToString())
        }

        if ($node -is [Linq.Expressions.ConstantExpression]) {
            $cStr = "{0}:{1}" -f $node.Type.Name, $node.Value
            [void]$constantValues.Add($cStr)
            [void]$fullTokens.Add("Const:$cStr")
        } elseif ($node -is [Linq.Expressions.DynamicExpression]) {
            $b = $node.Binder
            $bName = $b.GetType().Name
            $opProp = $b.GetType().GetProperty('Operation', $flags)
            $opVal = if ($opProp) { [string]$opProp.GetValue($b) } else { '' }
            if ($opVal) { [void]$binderOps.Add($opVal) } else { [void]$binderOps.Add($bName) }

            $argsList = ($node.Arguments | ForEach-Object { [string]$_ }) -join ','
            [void]$operandOrder.Add($argsList)
            [void]$fullTokens.Add("Dyn:$($bName):$($opVal)($argsList)")
        } elseif ($node -is [Linq.Expressions.BinaryExpression]) {
            [void]$binderOps.Add($node.NodeType.ToString())
            $argsList = "{0},{1}" -f $node.Left, $node.Right
            [void]$operandOrder.Add($argsList)
            [void]$fullTokens.Add("Bin:$($node.NodeType)($argsList)")
        } elseif ($node -is [Linq.Expressions.MethodCallExpression]) {
            [void]$calls.Add($node.Method.Name)
            [void]$fullTokens.Add("Call:$($node.Method.Name)")
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

    return [pscustomobject]@{
        BinderOperations = @($binderOps | Sort-Object)
        ConstantValues = @($constantValues | Sort-Object)
        NodeTypes = @($nodeTypes | Sort-Object)
        Calls = @($calls | Sort-Object)
        OperandOrder = @($operandOrder)
        FullFingerprint = $fullTokens -join ';'
    }
}

function Get-ContentfulDeltaFeatures {
    param(
        [Parameter(Mandatory)]$LoweredResultA,
        [Parameter(Mandatory)]$LoweredResultB
    )

    $fpA = Get-AuthenticExpressionFingerprint $LoweredResultA
    $fpB = Get-AuthenticExpressionFingerprint $LoweredResultB

    $coarseDeltaExpr = if ($fpA.FullFingerprint -ne $fpB.FullFingerprint) { 1 } else { 0 }
    $binderOpChanged = if (($fpA.BinderOperations -join ';') -ne ($fpB.BinderOperations -join ';')) { 1 } else { 0 }
    $constantValChanged = if (($fpA.ConstantValues -join ';') -ne ($fpB.ConstantValues -join ';')) { 1 } else { 0 }
    $operandOrderChanged = if (($fpA.OperandOrder -join ';') -ne ($fpB.OperandOrder -join ';')) { 1 } else { 0 }
    $nodeTypeChanged = if (($fpA.NodeTypes -join ';') -ne ($fpB.NodeTypes -join ';')) { 1 } else { 0 }
    $callTargetChanged = if (($fpA.Calls -join ';') -ne ($fpB.Calls -join ';')) { 1 } else { 0 }

    return [pscustomobject]@{
        CoarseDeltaExpression = $coarseDeltaExpr
        BinderOperationChanged = $binderOpChanged
        ConstantValueChanged = $constantValChanged
        OperandOrderChanged = $operandOrderChanged
        NodeTypeChanged = $nodeTypeChanged
        CallTargetChanged = $callTargetChanged
        ExpressionBeforeFingerprint = $fpA
        ExpressionAfterFingerprint = $fpB
    }
}
