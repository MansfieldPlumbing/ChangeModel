function Get-SmaSpecimenPairs {
    return @(
        [pscustomobject]@{
            Name = 'Whitespace_Addition'
            SourceA = 'param($a, $b) [void]($a + $b)'
            SourceB = 'param($a, $b) [void]( $a + $b )'
        },
        [pscustomobject]@{
            Name = 'Whitespace_Loop'
            SourceA = 'for ([int]$i = 0; $i -lt 3; $i++) { [void]$i }'
            SourceB = 'for ([int]$i = 0;   $i -lt 3;   $i++) { [void]$i }'
        },
        [pscustomobject]@{
            Name = 'Parameter_Rename'
            SourceA = 'param($a, $b) [void]($a + $b)'
            SourceB = 'param($x, $y) [void]($x + $y)'
        },
        [pscustomobject]@{
            Name = 'Redundant_Grouping'
            SourceA = 'param($a, $b) [void]($a + $b)'
            SourceB = 'param($a, $b) [void](($a + $b))'
        },
        [pscustomobject]@{
            Name = 'Identical_Specimen'
            SourceA = 'param($a, $b) [void]($a + $b)'
            SourceB = 'param($a, $b) [void]($a + $b)'
        },
        [pscustomobject]@{
            Name = 'Operator_Inversion'
            SourceA = 'param($a, $b) $a + $b'
            SourceB = 'param($a, $b) $a - $b'
        },
        [pscustomobject]@{
            Name = 'Constant_Modification'
            SourceA = 'param($a) $a + 1.0'
            SourceB = 'param($a) $a + 2.0'
        },
        [pscustomobject]@{
            Name = 'Comparison_Inversion'
            SourceA = 'param([double]$a, [double]$b) $a -lt $b'
            SourceB = 'param([double]$a, [double]$b) $a -gt $b'
        }
    )
}

function New-SmaExperienceDataset {
    param(
        [string]$ProbePath = "$PSScriptRoot\..\probes\Measure-SmaDeltas.ps1",
        [array]$SpecimenPairs = (Get-SmaSpecimenPairs)
    )

    $dataset = [System.Collections.Generic.List[object]]::new()

    foreach ($pair in $SpecimenPairs) {
        $m = & $ProbePath -SourceA $pair.SourceA -SourceB $pair.SourceB

        $canonical = [pscustomobject]@{
            DeltaSource = if ($m.DeltaSource) { 1 } else { 0 }
            DeltaTokens = if ($m.DeltaTokens) { 1 } else { 0 }
            DeltaAstExtent = if ($m.DeltaAstExtent) { 1 } else { 0 }
            DeltaAstStructure = if ($m.DeltaAstStructure) { 1 } else { 0 }
            DeltaExpression = if ($m.DeltaExpression) { 1 } else { 0 }
        }

        $actualDelta = if ($m.DeltaBehavior) { 1 } else { 0 }

        $dataset.Add([pscustomobject]@{
            SpecimenName = $pair.Name
            CanonicalBefore = $canonical
            Action = 'PredictSemantics'
            ActualDelta = $actualDelta
            Measurement = $m
        })
    }

    return $dataset.ToArray()
}
