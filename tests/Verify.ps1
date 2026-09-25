Write-Host "Running Verification..."
& $PSScriptRoot\Gate1-Wrong.ps1
& $PSScriptRoot\Gate2-NotEvenWrong.ps1
& $PSScriptRoot\Gate3-ModelProposal.ps1
& $PSScriptRoot\Gate4-SmaNotEvenWrong.ps1
& $PSScriptRoot\Gate5-ContentfulDelta.ps1
& $PSScriptRoot\Gate6-RuntimeConceptInvention.ps1
if ($env:JS2PS_ROOT) {
    & $PSScriptRoot\Gate7-WorldReconstruction.ps1 -Js2psRoot $env:JS2PS_ROOT
} else {
    Write-Host 'GATE7_WORLD_RECONSTRUCTION=NOT RUN (set JS2PS_ROOT to a JS2PS checkout at the pinned commit)'
}
