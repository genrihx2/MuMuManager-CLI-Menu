@{
    'ExcludeRules' = @(
        'PSAvoidUsingWriteHost'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSingularNouns'
        'PSUseUsingScopeModifierInNewRunspaces'
        'PSReviewUnusedParameter'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSUseApprovedVerbs'
        'PSAvoidUsingPositionalParameters'
    )

    # Compatibility gate: the project ships as "PowerShell 5.1+" (README
    # Requirements), so 7-only syntax must fail CI instead of turning into a
    # parse error on a user's 5.1 box. PSUseCompatibleSyntax is disabled by
    # default and reports Error severity, so enabling it here is the actual
    # gate. TargetVersions lists the engines the code must keep parsing on;
    # 5.1 is the floor, PS 7 accepts that subset too.
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
    }
}
