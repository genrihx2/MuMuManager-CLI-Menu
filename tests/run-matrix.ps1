# Replay the CI pester-unit matrix (tests.yml) locally: the same runner,
# the same pinned Pester, the same engines - one command instead of three.
#
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run-matrix.ps1
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run-matrix.ps1 -Quick
#
# Legs (matching the CI matrix):
#   1. Windows PowerShell 5.1 + pinned Pester (-PesterVersion, default 5.7.1)
#   2. pwsh 7                  + pinned Pester
#   3. pwsh 7                  + whatever this machine has preinstalled
#     (-Quick skips leg 3: the canary only makes sense where the module set
#      mirrors the CI image; locally it just re-tests your own Pester)
#
# The pinned Pester is fetched once into a private directory (same layout
# the CI action uses) and reused across runs; the engine-aware install
# logic lives in tests/run-pester.ps1, exactly as in CI. Exit code is the
# first failing leg, 0 when all green.

param(
    # Pinned Pester version for legs 1-2 (must match tests.yml).
    [string]$PesterVersion = '5.7.1',
    # Skip the preinstalled canary leg (leg 3).
    [switch]$Quick
)

$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'run-pester.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Runner not found: $runner" }

# Private module dir shared with the CI action's layout: <temp>\pester-<version>\Pester\<version>.
$moduleDir = Join-Path ([IO.Path]::GetTempPath()) "pester-$PesterVersion"

$legs = @(
    @{ Name = "5.7.1 / powershell"; Exe = 'powershell.exe'; Args = @('-PesterVersion', $PesterVersion, '-ModuleDir', $moduleDir) },
    @{ Name = "5.7.1 / pwsh";       Exe = 'pwsh.exe';       Args = @('-PesterVersion', $PesterVersion, '-ModuleDir', $moduleDir) }
)
if (-not $Quick) {
    $legs += @{ Name = 'preinstalled / pwsh'; Exe = 'pwsh.exe'; Args = @() }
}

$failed = @()
foreach ($leg in $legs) {
    Write-Host ''
    Write-Host "=== pester-unit ($($leg.Name)) ===" -ForegroundColor Cyan
    & $leg.Exe -NoProfile -ExecutionPolicy Bypass -File $runner @($leg.Args)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "leg FAILED: $($leg.Name) (exit $LASTEXITCODE)" -ForegroundColor Red
        $failed += $leg.Name
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ("matrix result: {0} of {1} leg(s) FAILED - {2}" -f $failed.Count, $legs.Count, ($failed -join ', ')) -ForegroundColor Red
    exit 1
}
Write-Host ("matrix result: all {0} leg(s) green" -f $legs.Count) -ForegroundColor Green
