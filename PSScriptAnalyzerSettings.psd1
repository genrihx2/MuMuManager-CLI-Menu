@{
    # Interactive menu relies on colored Write-Host by design —
    # PSAvoidUsingWriteHost is a pure style rule (all 89 hits are
    # intentional). Excluding it leaves 11 actionable warnings:
    # PSUseShouldProcessForStateChangingFunctions, PSAvoidUsingEmptyCatchBlock, PSUseSingularNouns.
    ExcludeRules = @('PSAvoidUsingWriteHost')
    Severity     = @('Error', 'Warning')
}
