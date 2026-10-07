@{
    RootModule = 'Dev.MansfieldPlumbing.PowerShell.Perception.psm1'
    ModuleVersion = '0.1.0'
    CompatiblePSEditions = @('Core')
    GUID = '8f43c3a1-10c4-42ea-a4e9-ec36940be6d2'
    Author = 'Mansfield Plumbing'
    CompanyName = 'Mansfield Plumbing'
    Copyright = '(c) Mansfield Plumbing. All rights reserved.'
    Description = 'Counterexample-guided percept refinement engine.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
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
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Perception', 'Refinement', 'SMA', 'Counterexample')
            ProjectUri = 'https://github.com/MansfieldPlumbing/PSPerception'
        }
    }
}
