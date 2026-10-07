Set-StrictMode -Version Latest

function Get-RefinementEvidenceIdentity {
    param([Parameter(Mandatory)][array]$Experience,[Parameter(Mandatory)][Representation]$Representation)
    # Cache only bounded primitive observations. Unsupported state disables reuse.
    if ($Experience.Count -gt 4096 -or $Representation.Features.Count -gt 64) { return '' }
    $text=[Text.StringBuilder]::new()
    [void]$text.Append('LexicographicAdmission-v1;')
    [void]$text.Append($PSVersionTable.PSVersion.ToString()+';')
    [void]$text.Append([Runtime.InteropServices.RuntimeInformation]::FrameworkDescription+';')
    [void]$text.Append([System.Management.Automation.PSObject].Assembly.ManifestModule.ModuleVersionId.ToString()+';')
    [void]$text.Append([object].Assembly.ManifestModule.ModuleVersionId.ToString()+';')
    [void]$text.Append([Globalization.CultureInfo]::CurrentCulture.Name+';')
    [void]$text.Append('features:'+ $Representation.Features.Count.ToString()+';')
    foreach ($feature in $Representation.Features) {
        if ($feature.Length -gt 4096) { return '' }
        [void]$text.Append($feature.Length.ToString()+':'+$feature)
    }
    [void]$text.Append('records:'+ $Experience.Count.ToString()+';')
    foreach ($record in $Experience) {
        $values=[Collections.Generic.List[object]]::new()
        foreach ($field in @('SpecimenName','Action','ActualDelta')) {
            $property=$record.PSObject.Properties[$field]
            $values.Add($field);$values.Add($(if ($null -ne $property) {$property.Value} else {$null}))
        }
        $properties=@($record.CanonicalBefore.PSObject.Properties | Sort-Object Name -CaseSensitive)
        if ($properties.Count -gt 64) { return '' }
        $values.Add('CanonicalBefore');$values.Add($properties.Count)
        foreach ($property in $properties) { $values.Add($property.Name);$values.Add($property.Value) }
        foreach ($value in $values) {
            $part=if ($null -eq $value) { 'null' }
                elseif ($value -is [string]) { 'string:'+ $value }
                elseif ($value -is [int]) { 'int:'+ $value.ToString([Globalization.CultureInfo]::InvariantCulture) }
                elseif ($value -is [long]) { 'long:'+ $value.ToString([Globalization.CultureInfo]::InvariantCulture) }
                elseif ($value -is [bool]) { 'bool:'+ $value.ToString() }
                else { return '' }
            if ($part.Length -gt 4096 -or $text.Length+$part.Length+16 -gt 1048576) { return '' }
            [void]$text.Append($part.Length.ToString()+':'+$part)
        }
        [void]$text.Append(';record;')
    }
    # Include the authored admission/predictor implementation in rejection scope.
    foreach ($name in @('Refine.ps1','Prediction.ps1','Representation.ps1','Proposal.ps1','ObservationRecord.ps1','Analogy.ps1')) {
        [void]$text.Append((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash)
    }
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text.ToString())))
}

function Get-PerceptProposalHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][RepresentationMutation]$Mutation,[Parameter(Mandatory)][PerceptionStore]$Store,[string]$EvidenceIdentity,[ValidateRange(1,4096)][int]$NodeBudget=256)
    $rejections=0;$inspected=0;$sources=[Collections.Generic.List[string]]::new()
    if (-not $EvidenceIdentity) { return [pscustomobject]@{ReusableRejections=0;NodesInspected=0;SourceNodes=@();Scope='Unavailable';Truncated=$false} }
    for ($i=$Store.AllNodes.Count-1;$i -ge 0 -and $inspected -lt $NodeBudget;$i--) {
        $inspected++;$node=$Store.AllNodes[$i]
        if ($node.Outcome -cne 'rejected' -or $node.Parents.Count -eq 0 -or $node.Parents[0].Id -cne $Store.Current.Id -or $node.Proposal -isnot [RepresentationMutation]) { continue }
        $prior=$node.Proposal
        if (-not $prior.ReusableRejection -or $prior.EvidenceIdentity -cne $EvidenceIdentity -or $prior.Verb -cne $Mutation.Verb -or $prior.Arguments.Count -ne $Mutation.Arguments.Count) { continue }
        $same=$true
        for ($j=0;$j -lt $prior.Arguments.Count;$j++) { if ($prior.Arguments[$j] -cne $Mutation.Arguments[$j]) { $same=$false;break } }
        if ($same) { $rejections++;$sources.Add($node.Id) }
    }
    [pscustomobject]@{ReusableRejections=$rejections;NodesInspected=$inspected;SourceNodes=$sources.ToArray();Scope='SameRepresentationEvidenceAndAdmission';Truncated=($Store.AllNodes.Count -gt $inspected)}
}

function Test-PerceptRelationPattern {
    param([object[]]$Pattern)
    if ($Pattern.Count -eq 0 -or $Pattern.Count -gt 8) { throw 'A relation pattern requires one to eight edges.' }
    $edges=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($edge in $Pattern) {
        foreach ($field in @('Relation','From','To')) {
            $value=$edge.$field
            if ($value -isnot [string] -or $value.Length -eq 0 -or $value.Length -gt 256) { throw 'Invalid relation pattern field.' }
        }
        # Length prefixes preserve identity even when role text contains separators.
        $identity=($edge.Relation.Length.ToString()+':'+$edge.Relation+$edge.From.Length.ToString()+':'+$edge.From+$edge.To.Length.ToString()+':'+$edge.To)
        if (-not $edges.Add($identity)) { throw 'Duplicate relation edge.' }
    }
}

function Find-PerceptRoleBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$SourcePattern,[Parameter(Mandatory)][object[]]$TargetPattern,[ValidateRange(1,4096)][int]$BindingBudget=256,[switch]$InferRelationBindings)
    Test-PerceptRelationPattern $SourcePattern
    Test-PerceptRelationPattern $TargetPattern
    if ($SourcePattern.Count -ne $TargetPattern.Count) { return [pscustomobject]@{Status='DifferentTopology';Bindings=@();BindingAttempts=0} }
    $stack=[Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{Index=0;Map=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);RelationMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);Used=[int[]]@()})
    $attempts=0;$solutions=[Collections.Generic.List[object]]::new();$relationSolutions=[Collections.Generic.List[object]]::new()
    while ($stack.Count -gt 0) {
        $state=$stack.Pop()
        if ($state.Index -eq $SourcePattern.Count) {
            $solutions.Add($state.Map)
            $relationSolutions.Add($state.RelationMap)
            if ($solutions.Count -gt 1) { return [pscustomobject]@{Status='Ambiguous';Bindings=@();BindingAttempts=$attempts} }
            continue
        }
        $source=$SourcePattern[$state.Index]
        for ($i=0;$i -lt $TargetPattern.Count;$i++) {
            if ($i -in $state.Used) { continue }
            $target=$TargetPattern[$i]
            if (-not $InferRelationBindings -and -not [StringComparer]::Ordinal.Equals($source.Relation,$target.Relation)) { continue }
            $attempts++
            if ($attempts -gt $BindingBudget) { return [pscustomobject]@{Status='BudgetExhausted';Bindings=@();BindingAttempts=$BindingBudget} }
            $map=[Collections.Generic.Dictionary[string,string]]::new($state.Map,[StringComparer]::Ordinal)
            $relationMap=[Collections.Generic.Dictionary[string,string]]::new($state.RelationMap,[StringComparer]::Ordinal)
            if ($InferRelationBindings) {
                if ($relationMap.ContainsKey($source.Relation)) {
                    if (-not [StringComparer]::Ordinal.Equals($relationMap[$source.Relation],$target.Relation)) { continue }
                } else {
                    if ($relationMap.ContainsValue($target.Relation)) { continue }
                    $relationMap.Add($source.Relation,$target.Relation)
                }
            }
            $valid=$true
            foreach ($pair in @(@($source.From,$target.From),@($source.To,$target.To))) {
                if ($map.ContainsKey($pair[0])) {
                    if (-not [StringComparer]::Ordinal.Equals($map[$pair[0]],$pair[1])) { $valid=$false;break }
                } else {
                    if ($map.ContainsValue($pair[1])) { $valid=$false;break }
                    $map.Add($pair[0],$pair[1])
                }
            }
            if ($valid) { $stack.Push([pscustomobject]@{Index=$state.Index+1;Map=$map;RelationMap=$relationMap;Used=[int[]]@($state.Used+$i)}) }
        }
    }
    [pscustomobject]@{Status=$(if ($solutions.Count -eq 1) {'Matched'} else {'DifferentTopology'});Bindings=$solutions.ToArray();RelationBindings=$relationSolutions.ToArray();BindingAttempts=$attempts;RelationEquivalence='NotProved'}
}

function Get-AnalogicalPerceptProposals {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Pattern,[Parameter(Mandatory)][PerceptionStore]$Store,[ValidateRange(1,4096)][int]$BindingBudget=256,[ValidateRange(1,4096)][int]$NodeBudget=256,[switch]$InferRelationBindings)
    Test-PerceptRelationPattern $Pattern
    $proposals=[Collections.Generic.List[object]]::new();$attempts=0;$status='Completed'
    # Only current-path retained percepts are knowledge; abandoned kept branches are not active.
    $path=[Collections.Generic.List[PerceptionProvenanceNode]]::new();$node=$Store.Current
    $visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($null -ne $node) {
        if (-not $visited.Add($node.Id)) { throw 'Provenance ancestry contains a cycle or duplicate identity.' }
        if ($path.Count -ge $NodeBudget) { $status='NodeBudgetExhausted';break }
        $path.Add($node);$node=if ($node.Parents.Count -gt 0) {$node.Parents[0]} else {$null}
    }
    foreach ($node in $path) {
        if ($node.Outcome -cne 'kept' -or $node.Proposal -isnot [RepresentationMutation] -or $node.Proposal.Pattern.Count -eq 0) { continue }
        $remaining=$BindingBudget-$attempts
        if ($remaining -le 0) { $status='BindingBudgetExhausted';break }
        $match=Find-PerceptRoleBinding $node.Proposal.Pattern $Pattern -BindingBudget $remaining -InferRelationBindings:$InferRelationBindings
        $attempts+=$match.BindingAttempts
        if ($match.Status -ceq 'BudgetExhausted') { $status='BindingBudgetExhausted';break }
        if ($match.Status -cne 'Matched') { continue }
        $map=$match.Bindings[0];$arguments=[Collections.Generic.List[string]]::new();$applicable=$true
        foreach ($argument in $node.Proposal.Arguments) {
            if (-not $map.ContainsKey($argument)) { $applicable=$false;break }
            $arguments.Add($map[$argument])
        }
        if (-not $applicable) { continue }
        $mutation=[RepresentationMutation]::new($node.Proposal.Verb,$arguments.ToArray())
        $mutation.Pattern=@($Pattern | ForEach-Object { [pscustomobject]@{Relation=$_.Relation;From=$_.From;To=$_.To} })
        $mutation.Evidence=[string[]]@($node.Proposal.Evidence)
        $proposals.Add([pscustomobject]@{Mutation=$mutation;SourceNode=$node.Id;RoleBindings=$map;RelationBindings=$match.RelationBindings[0];RelationEquivalence='NotProved';Status='ProposalOnly'})
    }
    [pscustomobject]@{Proposals=$proposals.ToArray();BindingAttempts=$attempts;NodesVisited=$path.Count;SearchStatus=$status;Admission='NotPerformed'}
}
