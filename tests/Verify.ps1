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
