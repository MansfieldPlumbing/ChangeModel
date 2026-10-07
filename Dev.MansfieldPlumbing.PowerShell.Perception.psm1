# Dev.MansfieldPlumbing.PowerShell.Perception.psm1
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'src/LinearState.ps1')
. (Join-Path $PSScriptRoot 'src/Representation.ps1')
. (Join-Path $PSScriptRoot 'src/ObservationRecord.ps1')
. (Join-Path $PSScriptRoot 'src/Prediction.ps1')
. (Join-Path $PSScriptRoot 'src/Proposal.ps1')
. (Join-Path $PSScriptRoot 'src/Search.ps1')
. (Join-Path $PSScriptRoot 'src/SmaDataset.ps1')
. (Join-Path $PSScriptRoot 'src/SmaContentfulDataset.ps1')
. (Join-Path $PSScriptRoot 'src/ExpressionFeatures.ps1')
. (Join-Path $PSScriptRoot 'src/PredicateSynthesis.ps1')
. (Join-Path $PSScriptRoot 'src/MutationJournal.ps1')
. (Join-Path $PSScriptRoot 'src/Store.ps1')
. (Join-Path $PSScriptRoot 'src/Refine.ps1')
. (Join-Path $PSScriptRoot 'src/Expectations.ps1')
. (Join-Path $PSScriptRoot 'src/Analogy.ps1')

Export-ModuleMember -Function @(
    'New-PerceptExpectation'
    'Measure-PerceptSurprise'
    'Get-SurpriseAttribution'
    'Find-PerceptRoleBinding'
    'Get-AnalogicalPerceptProposals'
    'New-PerceptionStore'
    'New-PerceptionReceipt'
    'Invoke-PerceptRefine'
    'Get-CollidingObservations'
    'Get-DifferingObservationAttributes'
    'Get-DeltaClassification'
    'Get-GrammarProposals'
    'Invoke-RepresentationSearch'
    'Measure-Representation'
    'Invoke-ApplyMutation'
    'Test-RepresentationProposal'
    'ConvertTo-RepresentationMutation'
    'Format-ProposalPrompt'
    'Get-Residuals'
    'New-ObservationRecord'
    'Get-ConditionKey'
    'Get-ActualDelta'
    'Invoke-LinearStep'
    'ConvertTo-Psd1Text'
    'Write-MutationJournal'
    'Read-MutationJournal'
    'Invoke-MutationJournal'
    'Invoke-JournalStep'
    'New-FeatureContext'
    'New-LexicalObservationRecords'
    'Get-DynamicKeywordState'
    'Get-TokenizationDigest'
    'Get-ReferenceDigest'
    'Get-RuntimeStateDigest'
    'Get-ExpressionSignature'
    'Get-ContentfulDeltaFeatures'
    'Get-CandidatePredicates'
    'Measure-PredicateSufficiency'
)
