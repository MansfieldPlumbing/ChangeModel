[CmdletBinding()]
param(
    [scriptblock]$CustomProposalProvider = $null
)

$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\src\World.ps1
. $PSScriptRoot\..\src\Representation.ps1
. $PSScriptRoot\..\src\Experience.ps1
. $PSScriptRoot\..\src\Prediction.ps1
. $PSScriptRoot\..\src\Search.ps1
. $PSScriptRoot\..\src\Proposal.ps1

$history = [System.Collections.Generic.List[object]]::new()

# Generate history where same X produces incompatible deltas (+1 vs -1) due to hidden Direction
$s1 = [WorldState]::new(); $s1.X = 5; $s1.Direction = 1; $next1 = Invoke-WorldStep $s1
$history.Add([pscustomobject]@{ CanonicalBefore = $s1; Action = 'Step'; ActualDelta = ($next1.X - $s1.X) })

$s2 = [WorldState]::new(); $s2.X = 5; $s2.Direction = -1; $next2 = Invoke-WorldStep $s2
$history.Add([pscustomobject]@{ CanonicalBefore = $s2; Action = 'Step'; ActualDelta = ($next2.X - $s2.X) })

$s3 = [WorldState]::new(); $s3.X = 6; $s3.Direction = 1; $next3 = Invoke-WorldStep $s3
$history.Add([pscustomobject]@{ CanonicalBefore = $s3; Action = 'Step'; ActualDelta = ($next3.X - $s3.X) })

$r1 = [Representation]::new([string[]]@('X'))

# Verify initial crippled representation has structural residuals
$measureR1 = Measure-Experience -History $history -Rep $r1 -RepVersion "R1"
if ($measureR1.Contradictions -eq 0) {
    throw "Precondition failure: Expected contradictions under crippled R1."
}

$residualsR1 = Get-Residuals -MeasureResult $measureR1
if (-not $residualsR1.HasStructuralResidual) {
    throw "Precondition failure: Expected structural residual under R1."
}

# -------------------------------------------------------------------------
# Test 1: Spurious model proposal is REJECTED by deterministic verifier
# The model proposes an unhelpful feature; verifier must reject it.
# -------------------------------------------------------------------------
$spuriousProvider = {
    param($currentRep, $experience, $residuals)
    # Model hallucinating or proposing an irrelevant distinction
    return "AddFeature UnrelatedNoise"
}

$spuriousAudit = Test-RepresentationProposal `
    -CurrentRepresentation $r1 `
    -Experience $history `
    -ProposalProvider $spuriousProvider

if ($spuriousAudit.Accepted) {
    throw "Security/correctness violation: Verifier accepted a spurious model proposal!"
}

# -------------------------------------------------------------------------
# Test 2: Destructive model proposal is REJECTED by deterministic verifier
# -------------------------------------------------------------------------
$destructiveProvider = {
    param($currentRep, $experience, $residuals)
    return "RemoveFeature X"
}

$destructiveAudit = Test-RepresentationProposal `
    -CurrentRepresentation $r1 `
    -Experience $history `
    -ProposalProvider $destructiveProvider

if ($destructiveAudit.Accepted) {
    throw "Security/correctness violation: Verifier accepted destructive proposal removing critical feature!"
}

# -------------------------------------------------------------------------
# Test 3: Model proposal with commentary/markdown is parsed cleanly
# and valid proposal is ACCEPTED strictly based on replay evidence
# -------------------------------------------------------------------------
$validProvider = if ($CustomProposalProvider) {
    $CustomProposalProvider
} else {
    {
        param($currentRep, $experience, $residuals)
        # Deterministic proposal provider simulating an LLM response with formatting
        "I observed that identical condition X=5 produces incompatible transitions +1 and -1.`n" +
        "The missing distinction is Direction.`n" +
        "````text`n" +
        "AddFeature Direction`n" +
        "````"
    }
}

$validAudit = Test-RepresentationProposal `
    -CurrentRepresentation $r1 `
    -Experience $history `
    -ProposalProvider $validProvider

if (-not $validAudit.Accepted) {
    throw "Verifier rejected a valid proposal that resolves contradictions: $($validAudit.Reason)"
}

if ($validAudit.CandidateMeasure.Contradictions -ne 0) {
    throw "Expected 0 contradictions under accepted candidate representation."
}

if (-not ($validAudit.CandidateRepresentation.Features -contains 'Direction')) {
    throw "Accepted representation does not contain 'Direction'."
}

# -------------------------------------------------------------------------
# Test 4: Verify held-out generalizability under accepted representation
# -------------------------------------------------------------------------
$heldOut = [System.Collections.Generic.List[object]]::new()
for ($i = 20; $i -lt 25; $i++) {
    $s = [WorldState]::new(); $s.X = $i; $s.Direction = if ($i % 2 -eq 0) { 1 } else { -1 }
    $next = Invoke-WorldStep $s
    $heldOut.Add([pscustomobject]@{ CanonicalBefore = $s; Action = 'Step'; ActualDelta = ($next.X - $s.X) })
}

$heldOutMeasure = Measure-Experience `
    -History $heldOut `
    -Rep $validAudit.CandidateRepresentation `
    -RepVersion "R_Accepted"

if ($heldOutMeasure.Contradictions -ne 0) {
    throw "Held-out verification failed: contradictions detected under accepted representation."
}

Write-Host "GATE3_MODEL_PROPOSAL=PASS"
