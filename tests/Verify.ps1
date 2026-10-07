Write-Host "Running Verification..."
& $PSScriptRoot\Gate1-ParameterCalibration.ps1
& $PSScriptRoot\Gate2-FeatureSelection.ps1
& $PSScriptRoot\Gate3-ProposalValidation.ps1
& $PSScriptRoot\Gate4-SmaFeatureSelection.ps1
& $PSScriptRoot\Gate5-ContentfulDelta.ps1
& $PSScriptRoot\Gate6-PredicateSynthesis.ps1
if ($env:JS2PS_ROOT) {
    & $PSScriptRoot\Gate7-StateReconstruction.ps1 -Js2psRoot $env:JS2PS_ROOT
} else {
    Write-Host 'GATE7_STATE_RECONSTRUCTION=NOT RUN (set JS2PS_ROOT to a JS2PS checkout at the pinned commit)'
}
& $PSScriptRoot\Gate8-RefineLoop.ps1
& $PSScriptRoot\Gate9-InferenceContracts.ps1
& $PSScriptRoot\Gate10-UnseenAnalogicalSearch.ps1
if ($env:PSPERCEPTION_PHONEMIZER_GATE -eq '1') {
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'Gate11-AutomaticPhonemizer.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Gate11 automatic phonemizer failed.' }
} else {
    Write-Host 'GATE_AUTOMATIC_PHONEMIZER=NOT RUN (set PSPERCEPTION_PHONEMIZER_GATE=1 with the pinned inputs installed)'
}
