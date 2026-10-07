# Mutation Journal: Persistence and deterministic replay support mechanisms for
# reconstructing runtime representation mutations across process boundaries.
# The journal is formatted as a restricted PowerShell data file (.psd1):
# written via SMA's single-quote escaping, read back with Import-PowerShellDataFile,
# never executed as script.
#
# ARCHITECTURAL BASELINE: Persistence and replay journals are support mechanisms,
# NOT the model, learning objective, or product.
#
# Opcodes (state reconstruction support):
#   Observe     binds the journal to one evidence file; no state change.
#   AddPercept  the representation gains a feature. Inverse: feature is removed.
#   Compose     materializes a learned distinction into SMA as DynamicKeyword entries.
#               Precondition: none of the names is registered. Inverse: remove them.
#   Accept      asserts the runtime state digest reached by preceding steps; no state change.

function ConvertTo-Psd1Text {
    param($Value, [int] $Depth = 0)
    $pad = '    ' * $Depth
    $inner = '    ' * ($Depth + 1)
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
    if ($Value -is [int] -or $Value -is [long]) { return [string] $Value }
    if ($Value -is [string]) {
        return "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'"
    }
    if ($Value -is [Collections.IDictionary]) {
        $lines = [Collections.Generic.List[string]]::new()
        $lines.Add('@{')
        foreach ($key in $Value.Keys) {
            $lines.Add($inner + [string] $key + ' = ' + (ConvertTo-Psd1Text $Value[$key] ($Depth + 1)))
        }
        $lines.Add($pad + '}')
        return $lines -join "`n"
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '@()' }
        $lines = [Collections.Generic.List[string]]::new()
        $lines.Add('@(')
        foreach ($item in $items) { $lines.Add($inner + (ConvertTo-Psd1Text $item ($Depth + 1))) }
        $lines.Add($pad + ')')
        return $lines -join "`n"
    }
    throw "The mutation journal holds only null, bool, integer, string, arrays and dictionaries; got $($Value.GetType().FullName)."
}

function Write-MutationJournal {
    param([Parameter(Mandatory)][Collections.IDictionary] $Journal, [Parameter(Mandatory)][string] $Path)
    $text = (ConvertTo-Psd1Text $Journal) + "`n"
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Read-MutationJournal {
    param([Parameter(Mandatory)][string] $Path)
    Import-PowerShellDataFile -LiteralPath $Path
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string] $Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text)))
}

function New-FeatureContext {
    [pscustomobject]@{
        Features = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    }
}

function Get-DynamicKeywordState {
    $names = foreach ($k in [System.Management.Automation.Language.DynamicKeyword]::GetKeyword()) {
        '{0}/{1}/{2}/{3}' -f $k.Keyword, $k.NameMode, $k.BodyMode, $k.DirectCall
    }
    @($names | Sort-Object -CaseSensitive)
}

function Get-TokenizationDigest {
    param([Parameter(Mandatory)][object[]] $Observations)
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($obs in $Observations) {
        $lines.Add('file|' + $obs.Path + '|' + $obs.Sha256 + '|' + $obs.TokenCount)
        $lines.Add('errors|' + (@($obs.ErrorIds) -join ','))
        $lines.Add('statements|' + (@($obs.StatementTypes) -join ','))
        foreach ($u in $obs.Units) {
            $lines.Add('unit|' + $u.Start + '|' + $u.Length + '|' + $u.Text + '|' + $u.SmaTokenKind + '|' + $u.SmaKeywordFlag + '|' + $u.SmaCommandNameFlag)
        }
    }
    Get-Sha256Hex ($lines -join "`n")
}

function Get-ReferenceDigest {
    param([Parameter(Mandatory)] $Evidence)
    $outcomes = $Evidence.ReferenceOutcomes
    $lines = foreach ($name in ($outcomes.Keys | Sort-Object -CaseSensitive)) { $name + '=' + $outcomes[$name] }
    Get-Sha256Hex ((@($Evidence.Reference.Id, $Evidence.Reference.AuthorityVersion) + @($lines)) -join "`n")
}

function Get-RuntimeStateDigest {
    param([Parameter(Mandatory)] $Context, [Parameter(Mandatory)][object[]] $Observations, [Parameter(Mandatory)] $Evidence)
    $sma = [System.Management.Automation.PSObject].Assembly
    $lines = @(
        'schema=1'
        'powershell=' + $PSVersionTable.PSVersion
        'sma-mvid=' + $sma.ManifestModule.ModuleVersionId
        'features=' + (@($Context.Features) -join ',')
        'dynamic-keywords=' + ((Get-DynamicKeywordState) -join ',')
        'tokenization=' + (Get-TokenizationDigest $Observations)
        'reference=' + (Get-ReferenceDigest $Evidence)
    )
    Get-Sha256Hex ($lines -join "`n")
}

function Invoke-JournalStep {
    param(
        [Parameter(Mandatory)] $Step,
        [Parameter(Mandatory)] $Context,
        [Parameter(Mandatory)][ValidateSet('Forward', 'Inverse')][string] $Direction,
        [scriptblock] $StateDigestBlock
    )
    switch ($Step.Op) {
        'Observe' { }
        'Accept' {
            if ($Direction -eq 'Forward') {
                $actual = & $StateDigestBlock
                if ($actual -cne $Step.StateDigest) { throw "Accept failed: runtime state is $actual, journal expects $($Step.StateDigest)." }
            }
        }
        'AddPercept' {
            if ($Direction -eq 'Forward') {
                if (-not $Context.Features.Add($Step.Name)) { throw "AddPercept '$($Step.Name)': already present." }
            } elseif (-not $Context.Features.Remove($Step.Name)) { throw "Inverse of AddPercept '$($Step.Name)': not present." }
        }
        'Compose' {
            if ($Step.Realization -cne 'DynamicKeyword') { throw "Compose realization '$($Step.Realization)' is not supported." }
            foreach ($word in $Step.Words) {
                $present = [System.Management.Automation.Language.DynamicKeyword]::ContainsKeyword($word)
                if ($Direction -eq 'Forward') {
                    if ($present) { throw "Compose '$word': already registered; the inverse would not be exact." }
                    $k = [System.Management.Automation.Language.DynamicKeyword]::new()
                    $k.Keyword = $word
                    $k.NameMode = [System.Management.Automation.Language.DynamicKeywordNameMode] $Step.NameMode
                    $k.BodyMode = [System.Management.Automation.Language.DynamicKeywordBodyMode] $Step.BodyMode
                    $k.DirectCall = [bool] $Step.DirectCall
                    [System.Management.Automation.Language.DynamicKeyword]::AddKeyword($k)
                } else {
                    if (-not $present) { throw "Inverse of Compose '$word': not registered." }
                    [System.Management.Automation.Language.DynamicKeyword]::RemoveKeyword($word)
                }
            }
        }
        default { throw "Unknown mutation journal opcode '$($Step.Op)'." }
    }
}

function Invoke-MutationJournal {
    param(
        [Parameter(Mandatory)] $Journal,
        [Parameter(Mandatory)] $Context,
        [Parameter(Mandatory)][ValidateSet('Forward', 'Inverse')][string] $Direction,
        [scriptblock] $StateDigestBlock
    )
    $steps = @($Journal.Steps)
    if ($Direction -eq 'Inverse') { [array]::Reverse($steps) }
    foreach ($step in $steps) { Invoke-JournalStep -Step $step -Context $Context -Direction $Direction -StateDigestBlock $StateDigestBlock }
}

function New-LexicalObservationRecords {
    # Transforms lexer observations and reference outcomes into PSPerception observation records.
    param([Parameter(Mandatory)][object[]] $Observations, [Parameter(Mandatory)] $Outcomes)
    foreach ($obs in $Observations) {
        foreach ($u in $obs.Units) {
            [pscustomobject]@{
                SpecimenName = $obs.Path + '@' + $u.Start
                CanonicalBefore = [pscustomobject]@{
                    Text = $u.Text
                    SmaTokenKind = $u.SmaTokenKind
                    SmaKeywordFlag = $u.SmaKeywordFlag
                    SmaCommandNameFlag = $u.SmaCommandNameFlag
                }
                Action = 'Perceive'
                ActualDelta = [int] $Outcomes.($u.Text)
            }
        }
    }
}
