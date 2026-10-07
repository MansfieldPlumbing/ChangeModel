Set-StrictMode -Version Latest

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
    param([Parameter(Mandatory)][object[]]$SourcePattern,[Parameter(Mandatory)][object[]]$TargetPattern,[ValidateRange(1,4096)][int]$BindingBudget=256)
    Test-PerceptRelationPattern $SourcePattern
    Test-PerceptRelationPattern $TargetPattern
    if ($SourcePattern.Count -ne $TargetPattern.Count) { return [pscustomobject]@{Status='DifferentTopology';Bindings=@();BindingAttempts=0} }
    $stack=[Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{Index=0;Map=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);Used=[int[]]@()})
    $attempts=0;$solutions=[Collections.Generic.List[object]]::new()
    while ($stack.Count -gt 0) {
        $state=$stack.Pop()
        if ($state.Index -eq $SourcePattern.Count) {
            $solutions.Add($state.Map)
            if ($solutions.Count -gt 1) { return [pscustomobject]@{Status='Ambiguous';Bindings=@();BindingAttempts=$attempts} }
            continue
        }
        $source=$SourcePattern[$state.Index]
        for ($i=0;$i -lt $TargetPattern.Count;$i++) {
            if ($i -in $state.Used) { continue }
            $target=$TargetPattern[$i]
            if (-not [StringComparer]::Ordinal.Equals($source.Relation,$target.Relation)) { continue }
            $attempts++
            if ($attempts -gt $BindingBudget) { return [pscustomobject]@{Status='BudgetExhausted';Bindings=@();BindingAttempts=$BindingBudget} }
            $map=[Collections.Generic.Dictionary[string,string]]::new($state.Map,[StringComparer]::Ordinal)
            $valid=$true
            foreach ($pair in @(@($source.From,$target.From),@($source.To,$target.To))) {
                if ($map.ContainsKey($pair[0])) {
                    if (-not [StringComparer]::Ordinal.Equals($map[$pair[0]],$pair[1])) { $valid=$false;break }
                } else {
                    if ($map.ContainsValue($pair[1])) { $valid=$false;break }
                    $map.Add($pair[0],$pair[1])
                }
            }
            if ($valid) { $stack.Push([pscustomobject]@{Index=$state.Index+1;Map=$map;Used=[int[]]@($state.Used+$i)}) }
        }
    }
    [pscustomobject]@{Status=$(if ($solutions.Count -eq 1) {'Matched'} else {'DifferentTopology'});Bindings=$solutions.ToArray();BindingAttempts=$attempts}
}

function Get-AnalogicalPerceptProposals {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Pattern,[Parameter(Mandatory)][PerceptionStore]$Store,[ValidateRange(1,4096)][int]$BindingBudget=256,[ValidateRange(1,4096)][int]$NodeBudget=256)
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
        $match=Find-PerceptRoleBinding $node.Proposal.Pattern $Pattern -BindingBudget $remaining
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
        $proposals.Add([pscustomobject]@{Mutation=$mutation;SourceNode=$node.Id;RoleBindings=$map;Status='ProposalOnly'})
    }
    [pscustomobject]@{Proposals=$proposals.ToArray();BindingAttempts=$attempts;NodesVisited=$path.Count;SearchStatus=$status;Admission='NotPerformed'}
}
