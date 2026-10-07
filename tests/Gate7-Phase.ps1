[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Learn', 'Replay')][string] $Phase,
    [Parameter(Mandatory)][string] $Evidence,
    [Parameter(Mandatory)][string] $Js2psRoot,
    [Parameter(Mandatory)][string] $OutDir,
    [int] $LearnProcessId,
    [int] $ParentProcessId
)

# One phase of Gate 7, run in its own pwsh process by Gate7-StateReconstruction.ps1.
# Learn:  observe real JS2PS evidence under pristine SMA (S0), learn a representational
#         delta with PSPerception's existing search, materialize it into SMA, write the
#         .psd1 mutation journal, then exit. The journal is the only state that leaves the process.
# Replay: in a fresh process, recreate S0, replay the journal to S1', compare the live state
#         with the digests the journal recorded, roll back through the exact inverses, require S0.
#         All checks run here on live objects; the exit code reports the result (0 pass, 2 fail).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../src/Representation.ps1')
. (Join-Path $PSScriptRoot '../src/ObservationRecord.ps1')
. (Join-Path $PSScriptRoot '../src/Prediction.ps1')
. (Join-Path $PSScriptRoot '../src/Search.ps1')
. (Join-Path $PSScriptRoot '../src/MutationJournal.ps1')

$nativeFeatures = @('SmaTokenKind', 'SmaKeywordFlag', 'SmaCommandNameFlag')
$candidateFeatures = $nativeFeatures + @('Text')
$journalPath = Join-Path $OutDir 'mutation-journal.psd1'

# The evidence exceeds the default data-file size limits; the safe-value check still applies.
$evidenceData = Import-PowerShellDataFile -LiteralPath $Evidence -SkipLimitCheck
$evidenceSha = (Get-FileHash -LiteralPath $Evidence -Algorithm SHA256).Hash
$js2psHead = (& git -C $Js2psRoot rev-parse HEAD).Trim()
if ($js2psHead -cne $evidenceData.Provenance.JS2PSCommit) {
    throw "JS2PS checkout is $js2psHead; the evidence was produced at $($evidenceData.Provenance.JS2PSCommit)."
}
$lexerProbe = Join-Path $Js2psRoot 'tools/Observe-SmaPerception.ps1'
$trainPaths = @(foreach ($o in $evidenceData.Train) { $o.Path })
$heldOutPaths = @(foreach ($o in $evidenceData.HeldOut) { $o.Path })
$allPaths = $trainPaths + $heldOutPaths
$outcomes = $evidenceData.ReferenceOutcomes

function Get-Observation { @(& $lexerProbe -Path $allPaths -Root $Js2psRoot) }
function Get-NativeMeasure {
    param([object[]] $Observations, [string[]] $Paths)
    $records = @(New-LexicalObservationRecords -Observations @($Observations | Where-Object { $_.Path -in $Paths }) -Outcomes $outcomes)
    $m = Measure-Representation -History $records -Rep ([Representation]::new($nativeFeatures)) -RepVersion 'Native'
    [ordered]@{ Units = $records.Count; Contradictions = $m.Contradictions; ContradictoryKeys = $m.ContradictoryKeys.Count }
}
function Get-LinqAvailability {
    param([object[]] $Observations)
    # SMA lowers a unit to LINQ only after admitting it without parse errors.
    foreach ($obs in $Observations) { $obs.Path + '=' + $(if (@($obs.ErrorIds).Count) { 'unavailable:parse-errors:' + @($obs.ErrorIds).Count } else { 'admitted' }) }
}

$context = New-FeatureContext
if (@(Get-DynamicKeywordState).Count -ne 0) { throw 'S0 is not pristine: DynamicKeywords are registered on this thread.' }
$s0Obs = Get-Observation
$s0StateDigest = Get-RuntimeStateDigest -Context $context -Observations $s0Obs -Evidence $evidenceData
$s0Tokenization = Get-TokenizationDigest $s0Obs
$stateDigestBlock = { Get-RuntimeStateDigest -Context $context -Observations (Get-Observation) -Evidence $evidenceData }

if ($Phase -eq 'Learn') {
    # The live lexer must reproduce the recorded evidence before anything is learned from it.
    if ($s0Tokenization -cne (Get-TokenizationDigest @($evidenceData.Train + $evidenceData.HeldOut))) {
        throw 'The live SMA tokenization of S0 does not reproduce the recorded JS2PS evidence.'
    }
    $history = @(New-LexicalObservationRecords -Observations @($s0Obs | Where-Object { $_.Path -in $trainPaths }) -Outcomes $outcomes)

    # Not even wrong: no subset of SMA's native tokens separates the reference outcomes.
    $native = Invoke-RepresentationSearch -History $history -AllFeatures $nativeFeatures
    if (-not $native.ReachedExhaustiveOptimum -or $native.ExhaustiveBestMeasure.Contradictions -eq 0) {
        throw 'Precondition failed: SMA native tokens already separate the outcomes (not a structural residual).'
    }
    # Representation growth: search candidate features for a zero-contradiction representation.
    $grown = Invoke-RepresentationSearch -History $history -AllFeatures $candidateFeatures
    if (-not $grown.ReachedExhaustiveOptimum -or $grown.FinalMeasure.Contradictions -ne 0) { throw 'Representation search found no zero-contradiction representation.' }

    # The learned distinction: words the reference marks reserved that SMA's native tokens did not.
    $words = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($r in $history) { if ($r.ActualDelta -eq 1 -and $r.CanonicalBefore.SmaKeywordFlag -eq 0) { [void] $words.Add($r.CanonicalBefore.Text) } }
    $defaults = [System.Management.Automation.Language.DynamicKeyword]::new()

    $steps = [Collections.Generic.List[object]]::new()
    $steps.Add([ordered]@{ Op = 'Observe'; EvidenceSha256 = $evidenceSha; JS2PSCommit = $js2psHead; TokenDigest = $s0Tokenization })
    foreach ($f in $grown.FinalRep.Features) { $steps.Add([ordered]@{ Op = 'AddPercept'; Name = $f }) }
    $steps.Add([ordered]@{ Op = 'Compose'; Realization = 'DynamicKeyword'; Words = [string[]] @($words); NameMode = [string] $defaults.NameMode; BodyMode = [string] $defaults.BodyMode; DirectCall = [bool] $defaults.DirectCall })
    $journal = [ordered]@{
        Schema = 1
        Base = [ordered]@{
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            PowerShellSourceCommit = '149ab5cd6cad34869177f86ef9a3da8414f85dc6'
            SmaModuleVersionId = [System.Management.Automation.PSObject].Assembly.ManifestModule.ModuleVersionId.ToString()
            ChangeModelBase = '0b1bcafd88b627dcf2f33c7ecf1e6cfdf744451b'
            StateDigest = $s0StateDigest
        }
        Reference = [ordered]@{ Id = $evidenceData.Reference.Id; Authority = $evidenceData.Reference.Authority; AuthorityVersion = $evidenceData.Reference.AuthorityVersion; ReferenceDigest = Get-ReferenceDigest $evidenceData }
        Steps = $steps
    }
    Invoke-MutationJournal -Journal $journal -Context $context -Direction Forward -StateDigestBlock $stateDigestBlock
    $s1Obs = Get-Observation
    $journal.Steps.Add([ordered]@{
        Op = 'Accept'; StateDigest = (Get-RuntimeStateDigest -Context $context -Observations $s1Obs -Evidence $evidenceData)
        Evidence = [ordered]@{
            NativeContradictionsS0 = $native.ExhaustiveBestMeasure.Contradictions
            GrownContradictions = $grown.FinalMeasure.Contradictions
            GrownFeatures = [string[]] @($grown.FinalRep.Features)
            SearchEvaluations = $grown.Evaluations
            ExhaustiveEvaluations = $grown.ExhaustiveEvaluations
            TokenDigest = Get-TokenizationDigest $s1Obs
            Linq = [string[]] @(Get-LinqAvailability $s1Obs)
        }
    })
    Write-MutationJournal -Journal $journal -Path $journalPath
    exit 0
}

# Replay, in a process that has never seen the learning.
$journalSha = (Get-FileHash -LiteralPath $journalPath -Algorithm SHA256).Hash
$journal = Read-MutationJournal -Path $journalPath
$accept = @($journal.Steps | Where-Object { $_.Op -ceq 'Accept' })
if ($accept.Count -ne 1) { throw "The journal holds $($accept.Count) Accept steps; expected 1." }
$accept = $accept[0]
$observe = @($journal.Steps | Where-Object { $_.Op -ceq 'Observe' })[0]
$s0Native = [ordered]@{ Train = Get-NativeMeasure $s0Obs $trainPaths; HeldOut = Get-NativeMeasure $s0Obs $heldOutPaths }

$checks = [ordered]@{
    'separate processes' = $LearnProcessId -gt 0 -and $ParentProcessId -gt 0 -and $LearnProcessId -ne $PID -and $LearnProcessId -ne $ParentProcessId -and $PID -ne $ParentProcessId
    'journal bound to this evidence' = $observe.EvidenceSha256 -ceq $evidenceSha -and $observe.JS2PSCommit -ceq $js2psHead
    'fresh S0 equals learned S0' = $journal.Base.StateDigest -ceq $s0StateDigest -and $observe.TokenDigest -ceq $s0Tokenization
}
# Forward replay; the Accept step itself throws if the reconstructed state digest differs.
Invoke-MutationJournal -Journal $journal -Context $context -Direction Forward -StateDigestBlock $stateDigestBlock
$s1Obs = Get-Observation
$s1StateDigest = Get-RuntimeStateDigest -Context $context -Observations $s1Obs -Evidence $evidenceData
$s1Tokenization = Get-TokenizationDigest $s1Obs
$s1Native = [ordered]@{ Train = Get-NativeMeasure $s1Obs $trainPaths; HeldOut = Get-NativeMeasure $s1Obs $heldOutPaths }
$checks['S1 state reconstructed'] = $s1StateDigest -ceq $accept.StateDigest
$checks['S1 tokenization reconstructed'] = $s1Tokenization -ceq $accept.Evidence.TokenDigest
$checks['S1 LINQ availability reconstructed'] = (@(Get-LinqAvailability $s1Obs) -join ';') -ceq (@($accept.Evidence.Linq) -join ';')
$checks['SMA tokenization changed'] = $s1Tokenization -cne $s0Tokenization

Invoke-MutationJournal -Journal $journal -Context $context -Direction Inverse
$restoredObs = Get-Observation
$checks['rollback restores S0 state'] = (Get-RuntimeStateDigest -Context $context -Observations $restoredObs -Evidence $evidenceData) -ceq $s0StateDigest
$checks['rollback restores S0 tokenization'] = (Get-TokenizationDigest $restoredObs) -ceq $s0Tokenization
$checks['rollback leaves no DynamicKeywords'] = @(Get-DynamicKeywordState).Count -eq 0

foreach ($c in $checks.GetEnumerator()) { '  {0,-38} {1}' -f $c.Key, $(if ($c.Value) { 'PASS' } else { 'FAIL' }) | Write-Host }
Write-Host ('  S0 state {0}' -f $s0StateDigest)
Write-Host ('  S1 state {0}' -f $s1StateDigest)
Write-Host ('  journal  {0}' -f $journalSha)
Write-Host ('  native contradictions, train:    S0 {0} -> S1 {1}' -f $s0Native.Train.Contradictions, $s1Native.Train.Contradictions)
Write-Host ('  native contradictions, held-out: S0 {0} -> S1 {1}' -f $s0Native.HeldOut.Contradictions, $s1Native.HeldOut.Contradictions)
if (@($checks.Values | Where-Object { -not $_ }).Count) { exit 2 }
exit 0
