Set-StrictMode -Version Latest

function New-PerceptExpectation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Specimen,
        [Parameter(Mandatory)][string]$RepresentationId,
        [Parameter(Mandatory)][string]$PredictedOutcome,
        [string[]]$ActiveAssumptions = @(),
        [object[]]$Justifications = @(),
        [hashtable]$OutcomeSupport = $null
    )
    if ($Specimen.Length -gt 1024 -or $RepresentationId.Length -gt 1024 -or $PredictedOutcome.Length -gt 4096) { throw 'Expectation identity exceeds bounds.' }
    if ($Justifications.Count -gt 256 -or $ActiveAssumptions.Count -gt 256) { throw 'Justification graph exceeds bounds.' }
    $claims = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($claim in $Justifications) {
        if ($claim.Id -isnot [string] -or -not $claim.Id -or $claim.Id.Length -gt 1024 -or $claims.ContainsKey($claim.Id)) { throw 'Invalid or duplicate justification identity.' }
        foreach ($dependency in $claim.DependsOn) {
            if ($dependency -isnot [string] -or $dependency.Length -eq 0 -or $dependency.Length -gt 1024) { throw 'Invalid justification dependency.' }
        }
        if ($null -ne $claim.Relation) {
            foreach ($value in @($claim.Relation,$claim.From,$claim.To)) {
                if ($value -isnot [string] -or $value.Length -eq 0 -or $value.Length -gt 256) { throw 'Invalid relational justification.' }
            }
        } elseif ($null -ne $claim.From -or $null -ne $claim.To) { throw 'Roles require a relation.' }
        $dependencies = [string[]]@($claim.DependsOn)
        if ($dependencies.Count -gt 256) { throw 'Too many justification dependencies.' }
        $claims.Add($claim.Id,[pscustomobject]@{Id=[string]$claim.Id;DependsOn=$dependencies.Clone();Relation=$claim.Relation;From=$claim.From;To=$claim.To})
    }
    foreach ($claim in $claims.Values) { foreach ($id in $claim.DependsOn) { if (-not $claims.ContainsKey($id)) { throw 'Justification dependency is missing.' } } }
    foreach ($id in $ActiveAssumptions) { if (-not $claims.ContainsKey($id)) { throw 'Active assumption is missing.' } }
    # Reject cycles before accepting a predictive justification.
    $remaining = [Collections.Generic.HashSet[string]]::new([string[]]@($claims.Keys),[StringComparer]::Ordinal)
    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object { $id=$_; @($claims[$id].DependsOn | Where-Object { $remaining.Contains($_) }).Count -eq 0 })
        if ($ready.Count -eq 0) { throw 'Justification graph contains a cycle.' }
        foreach ($id in $ready) { [void]$remaining.Remove($id) }
    }
    $support = $null
    if ($null -ne $OutcomeSupport) {
        if ($OutcomeSupport.Count -eq 0 -or $OutcomeSupport.Count -gt 256) { throw 'Outcome support exceeds bounds.' }
        $support=[Collections.Generic.Dictionary[string,double]]::new([StringComparer]::Ordinal)
        $sum=0.0
        foreach ($key in $OutcomeSupport.Keys) {
            if ($key -isnot [string] -or $key.Length -gt 4096) { throw 'Invalid outcome identity.' }
            $value=$OutcomeSupport[$key]
            if ($value -isnot [double] -and $value -isnot [int] -and $value -isnot [decimal]) { throw 'Outcome support must be numeric.' }
            $probability=[double]$value
            if ([double]::IsNaN($probability) -or [double]::IsInfinity($probability) -or $probability -lt 0 -or $probability -gt 1) { throw 'Invalid outcome probability.' }
            $support.Add($key,$probability);$sum+=$probability
        }
        if ([math]::Abs($sum-1.0) -gt 1e-9 -or -not $support.ContainsKey($PredictedOutcome)) { throw 'Outcome support must sum to one and include the prediction.' }
    }
    [pscustomobject]@{
        Specimen=$Specimen;RepresentationId=$RepresentationId;PredictedOutcome=$PredictedOutcome
        ActiveAssumptions=[string[]]$ActiveAssumptions.Clone();Justifications=$claims
        OutcomeSupport=$support
    }
}

function Measure-PerceptSurprise {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Expectation,[Parameter(Mandatory)][string]$ObservedOutcome)
    $mismatch=-not [StringComparer]::Ordinal.Equals($Expectation.PredictedOutcome,$ObservedOutcome)
    $probability=$null;$bits=$null;$supportStatus='NotProvided'
    if ($null -ne $Expectation.OutcomeSupport) {
        if ($Expectation.OutcomeSupport.ContainsKey($ObservedOutcome)) {
            $probability=$Expectation.OutcomeSupport[$ObservedOutcome]
            $bits=if ($probability -eq 0) { [double]::PositiveInfinity } else { -[math]::Log2($probability) }
            $supportStatus='Provided'
        } else { $supportStatus='OutcomeOutsideDeclaredSupport' }
    }
    [pscustomobject]@{
        Expectation=$Expectation;ObservedOutcome=$ObservedOutcome;Mismatch=$mismatch
        Probability=$probability;SurprisalBits=$bits;SupportStatus=$supportStatus
        BeliefChange='NotMeasured'
    }
}

function Get-SurpriseAttribution {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Surprise)
    $implicated=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pattern=[Collections.Generic.List[object]]::new()
    if ($Surprise.Mismatch) {
        $pending=[Collections.Generic.Stack[string]]::new()
        foreach ($id in $Surprise.Expectation.ActiveAssumptions) { $pending.Push($id) }
        while ($pending.Count -gt 0) {
            $id=$pending.Pop()
            if (-not $implicated.Add($id)) { continue }
            $claim=$Surprise.Expectation.Justifications[$id]
            foreach ($dependency in $claim.DependsOn) { $pending.Push($dependency) }
            if ($claim.Relation) {
                if (-not $claim.From -or -not $claim.To) { throw 'Relational justification has missing roles.' }
                $pattern.Add([pscustomobject]@{Relation=[string]$claim.Relation;From=[string]$claim.From;To=[string]$claim.To})
            }
        }
    }
    [pscustomobject]@{
        Surprise=$Surprise;ImplicatedAssumptions=[string[]]@($implicated | Sort-Object)
        Pattern=$pattern.ToArray();AttributionKind='ActiveJustificationClosure'
        CausalResponsibility='Unproved'
    }
}
