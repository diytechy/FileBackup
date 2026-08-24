@{
    # Lint settings for FileBackup. Errors fail CI; the rules excluded below are
    # deliberate design choices for this PowerShell 7+ CLI tool, not defects.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # This is an interactive CLI/automation tool: Write-Host is the intended
        # way to surface progress to the operator and the log tee.
        'PSAvoidUsingWriteHost',

        # Internal worker functions (Update-*, Set-*, New-Reconstruct*) are not
        # user-facing cmdlets; -WhatIf/-Confirm plumbing would be noise.
        'PSUseShouldProcessForStateChangingFunctions',

        # Plural nouns (Get-FileBackupDefaults, Initialize-Dependencies,
        # Optimize-ChangeFolders, Resolve-BackupSetPaths) are intentional and read
        # better than forced singulars.
        'PSUseSingularNouns',

        # PS7+ reads UTF-8 without a BOM; sources intentionally omit the BOM.
        'PSUseBOMForUnicodeEncodedFile',

        # False-positives on parameters captured by nested scriptblocks/closures
        # (e.g. the -Log used inside install-hint scriptblocks).
        'PSReviewUnusedParameter',

        # False-positives on Pester `BeforeAll { $x = ... }` constants that are
        # consumed in sibling `It` blocks (PSSA analyses each scriptblock alone).
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
