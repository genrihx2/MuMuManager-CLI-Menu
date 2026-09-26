#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Deployed-layout fixture runner (repo-vs-install drift guard).
#
# WHY: the repo layout and an installed layout differ. A fresh install /
# self-update deploys only mumu-menu.ps1, bootstrap-update.ps1, README.md,
# SKILL.md and .version; repo-only files (relnotes.md, RELEASE-RUNBOOK.md,
# update-readme.ps1, tests/, .gitattributes, ...) never exist there. Tests
# that read repo-only docs would report "red" for a perfectly healthy
# install - exactly what happened on the live machine (v1.22.44 sanity run
# in C:\test): the BOM-hygiene test failed only because the fixture lacked
# relnotes.md. Instead of discovering that from user reports, CI now runs
# the suite inside an installed-layout copy:
#   - a temp dir gets ONLY the deployed file set (a missing deployed file
#     is the failure signal - one missing file breaks both engines),
#   - tests tagged 'RepoFiles' are excluded via run-pester.ps1
#     -ExcludeTag (172 tests, engine-independent count),
#   - the SAME suite runs on BOTH engines (5.1 + pwsh) against the SAME
#     copy, and the private Pester copy is shared with the matrix legs
#     (prepared once per job by .github/actions/pester-unit).
#
# Run locally:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tests/test-deployed-layout.ps1
#   (uses the system Pester 5.x; on both engines when -Engine is omitted)
#
# CI wiring: tests.yml job "pester-unit-deployed" (name prefixed with
# pester-unit so the release gate check-run audit covers it unchanged).

[CmdletBinding()]
param(
    # 'Both' (default) = 5.1 + pwsh against the same fixture copy, exactly
    # the two pinned matrix engines. 'pwsh' = single quick local pass.
    [ValidateSet('Both', 'pwsh')]
    [string]$Engine = 'Both',

    # Private Pester module directory prepared ahead of time (CI passes the
    # pester-unit action's shared copy). Empty = use the system Pester 5.x.
    [string]$ModuleDir = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

# --- 1. Build the installed-layout fixture ---------------------------------
# Deployed file set - keep in sync with the updaters' $files list in
# mumu-menu.ps1 (Update-FromGitHub) and bootstrap-update.ps1.
$deployedFiles = @('mumu-menu.ps1', 'bootstrap-update.ps1', 'README.md', 'SKILL.md', '.version')

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("mumu-deployed-fixture_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
    foreach ($name in $deployedFiles) {
        $src = Join-Path $repoRoot $name
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            throw "Deployed file '$name' is missing from the repo checkout - the fixture would ship a broken install."
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $fixture $name) -Force
    }
    # The suite itself must exist inside the fixture, resolved the same way
    # the tests do it ($PSScriptRoot\..\mumu-menu.ps1).
    $testsDir = Join-Path $fixture 'tests'
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\run-pester.ps1') -Destination (Join-Path $testsDir 'run-pester.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\mumu-menu.Tests.ps1') -Destination (Join-Path $testsDir 'mumu-menu.Tests.ps1') -Force

    # Assert the fixture is genuinely deployed-shaped: none of the repo-only
    # files that a real install never carries may be present.
    $repoOnly = @('relnotes.md', 'RELEASE-RUNBOOK.md', 'update-readme.ps1')
    foreach ($name in $repoOnly) {
        if (Test-Path -LiteralPath (Join-Path $fixture $name)) {
            throw "Fixture pollution: '$name' must not exist in a deployed layout."
        }
    }
    Write-Host "Fixture (deployed layout): $fixture"
    Get-ChildItem -LiteralPath $fixture | ForEach-Object { Write-Host "  $($_.Name)" }

    # --- 2. Run the same suite on the requested engines --------------------
    $engines = if ($Engine -eq 'pwsh') { @('pwsh.exe') } else { @('powershell.exe', 'pwsh.exe') }
    $failed = @()
    foreach ($exe in $engines) {
        Write-Host ""
        Write-Host "=== deployed-layout suite on $exe ===" -ForegroundColor Cyan
        $exeArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path $testsDir 'run-pester.ps1'), '-ExcludeTag', 'RepoFiles')
        if ($ModuleDir) { $exeArgs += @('-ModuleDir', $ModuleDir) }
        & $exe @exeArgs
        if ($LASTEXITCODE -ne 0) { $failed += $exe }
    }

    if ($failed.Count -gt 0) {
        throw "deployed-layout suite failed on: $($failed -join ', ')"
    }
    Write-Host ""
    Write-Host "deployed-layout suite: green on $($engines -join ' + ')" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
