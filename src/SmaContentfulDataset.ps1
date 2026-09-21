. $PSScriptRoot\ExpressionFeatures.ps1

function Get-SmaContentfulSpecimenPairs {
    return @(
        [pscustomobject]@{
            Name = 'Preserving_Whitespace'
            SourceA = 'param([double]$a, [double]$b) $a + $b'
            SourceB = 'param([double]$a, [double]$b)  $a  +  $b'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'Preserving_Grouping'
            SourceA = 'param([double]$a, [double]$b) $a + $b'
            SourceB = 'param([double]$a, [double]$b) ($a + $b)'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'Preserving_CommutativeAddition'
            SourceA = 'param([double]$a, [double]$b) $a + $b'
            SourceB = 'param([double]$a, [double]$b) $b + $a'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'Preserving_Identical'
            SourceA = 'param([double]$a, [double]$b) $a + $b'
            SourceB = 'param([double]$a, [double]$b) $a + $b'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'Breaking_Operator_Add_Sub'
            SourceA = 'param([double]$a, [double]$b) $a + $b'
            SourceB = 'param([double]$a, [double]$b) $a - $b'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'Breaking_Constant_Number'
            SourceA = 'param([double]$a) $a + 1.0'
            SourceB = 'param([double]$a) $a + 2.0'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'Breaking_Compare_Lt_Gt'
            SourceA = 'param([double]$a, [double]$b) $a -lt $b'
            SourceB = 'param([double]$a, [double]$b) $a -gt $b'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'Breaking_Both_Op_And_Const'
            SourceA = 'param([double]$a) $a + 1.0'
            SourceB = 'param([double]$a) $a - 5.0'
            Domain = 'NumericDouble'
        }
    )
}

function Get-SmaContentfulHeldOutPairs {
    return @(
        [pscustomobject]@{
            Name = 'HeldOut_Preserving_CommutativeMult'
            SourceA = 'param([double]$a, [double]$b) $a * $b'
            SourceB = 'param([double]$a, [double]$b) $b * $a'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'HeldOut_Breaking_DivisionVersusMult'
            SourceA = 'param([double]$a, [double]$b) $a * $b'
            SourceB = 'param([double]$a, [double]$b) $a / $b'
            Domain = 'NumericDouble'
        },
        [pscustomobject]@{
            Name = 'HeldOut_Breaking_ScaleConstant'
            SourceA = 'param([double]$a) $a * 3.0'
            SourceB = 'param([double]$a) $a * 7.0'
            Domain = 'NumericDouble'
        }
    )
}

function New-SmaContentfulDataset {
    param(
        [array]$SpecimenPairs = (Get-SmaContentfulSpecimenPairs),
        [string]$LoweringProbePath = "$PSScriptRoot\..\probes\Observe-SmaLowering.ps1",
        [string]$DeltasProbePath = "$PSScriptRoot\..\probes\Measure-SmaDeltas.ps1"
    )

    $dataset = [System.Collections.Generic.List[object]]::new()

    foreach ($pair in $SpecimenPairs) {
        # 1. Authentic compiler lowering observation
        $loweredA = & $LoweringProbePath -Source $pair.SourceA -PassThru
        $loweredB = & $LoweringProbePath -Source $pair.SourceB -PassThru

        # 2. Authentic expression subfeatures
        $features = Get-ContentfulDeltaFeatures -LoweredResultA $loweredA -LoweredResultB $loweredB

        # 3. Authentic behavior measurement
        $deltaMeasurement = & $DeltasProbePath -SourceA $pair.SourceA -SourceB $pair.SourceB
        $actualBehaviorDelta = if ($deltaMeasurement.DeltaBehavior) { 1 } else { 0 }

        # Canonical evidence preserving both sides and all contentful features
        $canonical = [pscustomobject]@{
            CoarseDeltaExpression  = $features.CoarseDeltaExpression
            BinderOperationChanged = $features.BinderOperationChanged
            ConstantValueChanged   = $features.ConstantValueChanged
            OperandOrderChanged    = $features.OperandOrderChanged
            NodeTypeChanged        = $features.NodeTypeChanged
            CallTargetChanged      = $features.CallTargetChanged
            ExpressionBeforeFingerprint = $features.ExpressionBeforeFingerprint
            ExpressionAfterFingerprint  = $features.ExpressionAfterFingerprint
        }

        $dataset.Add([pscustomobject]@{
            SpecimenName = $pair.Name
            Domain       = $pair.Domain
            SourceA      = $pair.SourceA
            SourceB      = $pair.SourceB
            CanonicalBefore = $canonical
            Action       = 'PredictBehavior'
            ActualDelta  = $actualBehaviorDelta
            Features     = $features
            Measurement  = $deltaMeasurement
        })
    }

    return $dataset.ToArray()
}
