class RepresentationMutation {
    [string]$Verb
    [string[]]$Arguments
    [object[]]$Pattern = @()
    [string[]]$Evidence = @()
    [string]$EvidenceIdentity = ''
    [bool]$ReusableRejection = $false

    RepresentationMutation([string]$verb, [string[]]$arguments) {
        $this.Verb = $verb
        $this.Arguments = [string[]]$arguments.Clone()
    }

    [string] ToString() {
        return "$($this.Verb) $($this.Arguments -join ' ')"
    }
}

function Copy-RepresentationMutation {
    param([Parameter(Mandatory)][RepresentationMutation]$Mutation)
    $copy = [RepresentationMutation]::new($Mutation.Verb, $Mutation.Arguments)
    if ($Mutation.Pattern.Count -gt 8 -or $Mutation.Evidence.Count -gt 256) {
        throw 'Mutation explanation exceeds bounds.'
    }
    $pattern = [System.Collections.Generic.List[object]]::new()
    foreach ($edge in $Mutation.Pattern) {
        foreach ($field in @('Relation', 'From', 'To')) {
            if ($edge.$field -isnot [string] -or $edge.$field.Length -eq 0 -or $edge.$field.Length -gt 256) {
                throw 'Invalid mutation relation pattern.'
            }
        }
        $pattern.Add([pscustomobject]@{ Relation = $edge.Relation; From = $edge.From; To = $edge.To })
    }
    foreach ($id in $Mutation.Evidence) {
        if (-not $id -or $id.Length -gt 1024) { throw 'Invalid mutation evidence identity.' }
    }
    $copy.Pattern = $pattern.ToArray()
    $copy.Evidence = [string[]]$Mutation.Evidence.Clone()
    $copy.EvidenceIdentity = $Mutation.EvidenceIdentity
    $copy.ReusableRejection = $Mutation.ReusableRejection
    return $copy
}

function ConvertTo-RepresentationMutation {
    param([Parameter(Mandatory)]$InputObject)

    if ($InputObject -is [RepresentationMutation]) {
        return $InputObject
    }

    if ($InputObject -is [hashtable] -or $InputObject -is [pscustomobject]) {
        $verb = $InputObject.Verb
        $args = @($InputObject.Arguments)
        return [RepresentationMutation]::new($verb, $args)
    }

    if ($InputObject -is [string]) {
        $lines = $InputObject.Split("`n")
        foreach ($line in $lines) {
            $trimmed = $line.Trim().Trim("`r")
            if ($trimmed.StartsWith('```') -or $trimmed.Length -eq 0) { continue }
            $tokens = $trimmed.Split([char[]]@(' ', "`t"), [System.StringSplitOptions]::RemoveEmptyEntries)
            if ($tokens.Length -ge 2 -and $tokens[0] -in @('AddFeature', 'RemoveFeature', 'Combine')) {
                $verb = $tokens[0]
                $argParts = [string[]]@($tokens[1..($tokens.Length - 1)])
                return [RepresentationMutation]::new($verb, $argParts)
            }
        }
        throw "Could not parse representation mutation from text: '$InputObject'"
    }

    throw "Unsupported mutation format: $($InputObject.GetType().FullName)"
}

function Invoke-ApplyMutation {
    param(
        [Parameter(Mandatory)][Representation]$Representation,
        [Parameter(Mandatory)][RepresentationMutation]$Mutation
    )

    $currentList = [System.Collections.Generic.List[string]]::new([string[]]$Representation.Features)

    switch ($Mutation.Verb) {
        'AddFeature' {
            foreach ($arg in $Mutation.Arguments) {
                if (-not $currentList.Contains($arg)) {
                    $currentList.Add($arg)
                }
            }
        }
        'RemoveFeature' {
            foreach ($arg in $Mutation.Arguments) {
                [void]$currentList.Remove($arg)
            }
        }
        'Combine' {
            $combined = ($Mutation.Arguments | Sort-Object) -join '+'
            if (-not $currentList.Contains($combined)) {
                $currentList.Add($combined)
            }
        }
        Default {
            throw "Unknown mutation verb '$($Mutation.Verb)'."
        }
    }

    return [Representation]::new($currentList.ToArray())
}

function Get-Residuals {
    param([Parameter(Mandatory)][pscustomobject]$MeasureResult)

    $hasStructural = ($MeasureResult.Contradictions -gt 0)
    [pscustomobject]@{
        ContradictionCount = $MeasureResult.Contradictions
        ContradictoryKeys = @($MeasureResult.ContradictoryKeys)
        ContradictionDetails = $MeasureResult.ContradictionDetails
        PredictionError = $MeasureResult.PredictionError
        HasStructuralResidual = $hasStructural
    }
}

function Format-ProposalPrompt {
    param(
        [Parameter(Mandatory)][Representation]$CurrentRepresentation,
        [Parameter(Mandatory)][pscustomobject]$Residuals,
        [string[]]$AvailableDomainFeatures = @()
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("TASK: Propose a representation mutation to resolve structural residuals.")
    [void]$sb.AppendLine("CURRENT_REPRESENTATION: $($CurrentRepresentation.ToString())")
    [void]$sb.AppendLine("CONTRADICTIONS: $($Residuals.ContradictionCount)")
    [void]$sb.AppendLine("PREDICTION_ERROR: $($Residuals.PredictionError)")
    if ($Residuals.ContradictoryKeys.Count -gt 0) {
        [void]$sb.AppendLine("INCOMPATIBLE_OBSERVATIONS:")
        foreach ($k in $Residuals.ContradictoryKeys) {
            $deltas = $Residuals.ContradictionDetails[$k] -join ', '
            [void]$sb.AppendLine("  RepresentedCondition: [$k] => MultipleObservedDeltas: [$deltas]")
        }
    }
    if ($AvailableDomainFeatures.Length -gt 0) {
        [void]$sb.AppendLine("AVAILABLE_DOMAIN_FEATURES: $($AvailableDomainFeatures -join ', ')")
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("COMMAND_LANGUAGE:")
    [void]$sb.AppendLine("  AddFeature <name>")
    [void]$sb.AppendLine("  RemoveFeature <name>")
    [void]$sb.AppendLine("  Combine <names...>")
    [void]$sb.AppendLine("Respond ONLY with a single mutation command.")

    return $sb.ToString()
}

function Invoke-RepresentationProposal {
    param(
        [Parameter(Mandatory)][Representation]$CurrentRepresentation,
        [Parameter(Mandatory)][array]$Experience,
        [Parameter(Mandatory)][pscustomobject]$Residuals,
        [Parameter(Mandatory)][scriptblock]$ProposalProvider
    )

    $raw = & $ProposalProvider $CurrentRepresentation $Experience $Residuals
    return ConvertTo-RepresentationMutation $raw
}

function Test-RepresentationProposal {
    param(
        [Parameter(Mandatory)][Representation]$CurrentRepresentation,
        [Parameter(Mandatory)][array]$Experience,
        [Parameter(Mandatory)][scriptblock]$ProposalProvider,
        [string]$RepVersion = "V_Candidate"
    )

    # 1. Measure under current representation
    $currentMeasure = Measure-Representation -History $Experience -Rep $CurrentRepresentation -RepVersion "V_Current"
    $residualsBefore = Get-Residuals -MeasureResult $currentMeasure

    # 2. Invoke proposal provider across the boundary
    $mutation = Invoke-RepresentationProposal `
        -CurrentRepresentation $CurrentRepresentation `
        -Experience $Experience `
        -Residuals $residualsBefore `
        -ProposalProvider $ProposalProvider

    # 3. Apply mutation candidate
    $candidateRep = Invoke-ApplyMutation -Representation $CurrentRepresentation -Mutation $mutation

    # 4. Replay complete ledger
    $candidateMeasure = Measure-Representation -History $Experience -Rep $candidateRep -RepVersion $RepVersion
    $residualsAfter = Get-Residuals -MeasureResult $candidateMeasure

    # 5. Measure and decide strictly by evidence (lexicographic ordering)
    $isBetter = $false
    if ($candidateMeasure.Contradictions -lt $currentMeasure.Contradictions) {
        $isBetter = $true
    } elseif ($candidateMeasure.Contradictions -eq $currentMeasure.Contradictions) {
        if ($candidateMeasure.PredictionError -lt $currentMeasure.PredictionError) {
            $isBetter = $true
        } elseif ($candidateMeasure.PredictionError -eq $currentMeasure.PredictionError) {
            # Complexity reduction only counts as improvement if the representation is predictive (no unresolved contradictions)
            if ($candidateMeasure.Contradictions -eq 0 -and $candidateMeasure.RepresentationComplexity -lt $currentMeasure.RepresentationComplexity) {
                $isBetter = $true
            }
        }
    }

    $reason = if ($isBetter) {
        "ACCEPTED: Strict improvement in evidence (Contradictions: $($currentMeasure.Contradictions)->$($candidateMeasure.Contradictions), Error: $($currentMeasure.PredictionError)->$($candidateMeasure.PredictionError), Complexity: $($currentMeasure.RepresentationComplexity)->$($candidateMeasure.RepresentationComplexity))."
    } else {
        "REJECTED: No strict improvement in evidence (Contradictions: $($currentMeasure.Contradictions)->$($candidateMeasure.Contradictions), Error: $($currentMeasure.PredictionError)->$($candidateMeasure.PredictionError), Complexity: $($currentMeasure.RepresentationComplexity)->$($candidateMeasure.RepresentationComplexity))."
    }

    return [pscustomobject]@{
        CurrentRepresentation = $CurrentRepresentation
        ProposedMutation = $mutation
        CandidateRepresentation = $candidateRep
        CurrentMeasure = $currentMeasure
        CandidateMeasure = $candidateMeasure
        ResidualsBefore = $residualsBefore
        ResidualsAfter = $residualsAfter
        Accepted = $isBetter
        Reason = $reason
    }
}
