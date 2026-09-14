#requires -Version 5.1
# Changelog consistency check for README.md.
#
# The Release workflow builds the published release body from the README's
# «Что нового» sections. A changelog table row without a matching section
# therefore silently drops that version from the published release notes -
# this happened to v1.19.1 (journal release), whose notes were missing from
# the v1.19.2 release body until patched by hand.
#
# What this check enforces:
#   - every table row "| vX.Y.Z | ..." has a matching "### vX.Y.Z" section
#   - every "### vX.Y.Z" section has a matching table row
#   - no duplicated rows or sections
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -ReadmePath <path-to-mutated-copy>
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -SelfTest
# CI: .github/workflows/changelog-check.yml

param(
    [string]$ReadmePath = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $ReadmePath) { $ReadmePath = Join-Path $root 'README.md' }
if (-not (Test-Path -LiteralPath $ReadmePath -PathType Leaf)) { throw "Not found: $ReadmePath" }

$lines = Get-Content -LiteralPath $ReadmePath -Encoding UTF8

$rowVersions     = @($lines | Where-Object { $_ -match '^\|\s*(v\d+\.\d+\.\d+)\s*\|'   } | ForEach-Object { $Matches[1] })
$sectionVersions = @($lines | Where-Object { $_ -match '^###\s+(v\d+\.\d+\.\d+)(\s|$)' } | ForEach-Object { $Matches[1] })

if ($rowVersions.Count -eq 0)     { Write-Host 'No changelog table rows found - is the table still there?' -ForegroundColor Red; exit 1 }
if ($sectionVersions.Count -eq 0) { Write-Host 'No «Что нового» sections found - is the section still there?' -ForegroundColor Red; exit 1 }

$failures = @()

foreach ($v in $rowVersions) {
    if ($sectionVersions -notcontains $v) {
        $failures += "table row '$v' has no matching «Что нового» section (### $v) - this version would be missing from published release notes"
    }
}
foreach ($v in $sectionVersions) {
    if ($rowVersions -notcontains $v) {
        $failures += "section '$v' has no matching changelog table row (| $v |)"
    }
}
foreach ($dup in @($rowVersions | Group-Object | Where-Object { $_.Count -gt 1 })) {
    $failures += "duplicate changelog table rows for $($dup.Name) ($($dup.Count)x)"
}
foreach ($dup in @($sectionVersions | Group-Object | Where-Object { $_.Count -gt 1 })) {
    $failures += "duplicate «Что нового» sections for $($dup.Name) ($($dup.Count)x)"
}

# ── Self-test mode: mutate temp copies, assert the check catches each case ──
if ($SelfTest) {
    if ($failures.Count -gt 0) {
        Write-Host 'Self-test aborted: the real README must be consistent first:' -ForegroundColor Red
        foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
        exit 1
    }
    Write-Host ''
    Write-Host 'Self-test: the check must fail on injected inconsistencies' -ForegroundColor Cyan
    $script:stFailures = 0
    $stTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("chg-sync-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stTmp -Force | Out-Null
    try {
        function Invoke-Check {
            param([string]$Name, [scriptblock]$Mutate)
            $copy = Join-Path $stTmp ("README-" + $Name + ".md")
            Copy-Item -LiteralPath $ReadmePath -Destination $copy -Force
            & $Mutate $copy
            $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ReadmePath $copy 2>&1
            if ($LASTEXITCODE -eq 1) {
                Write-Host "  [PASS] fails on: $Name" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] check did NOT fail on: $Name" -ForegroundColor Red
                $script:stFailures++
            }
        }
        # 1. remove a section, keep the row (the v1.19.1 regression)
        Invoke-Check -Name 'row-without-section' -Mutate {
            param($p)
            $t = @(Get-Content -LiteralPath $p -Encoding UTF8 | Where-Object { $_ -notmatch '^###\s+v1\.19\.1(\s|$)' })
            Set-Content -LiteralPath $p -Value $t -Encoding UTF8
        }
        # 2. remove a row, keep the section
        Invoke-Check -Name 'section-without-row' -Mutate {
            param($p)
            $t = @(Get-Content -LiteralPath $p -Encoding UTF8 | Where-Object { $_ -notmatch '^\|\s*v1\.19\.1\s*\|' })
            Set-Content -LiteralPath $p -Value $t -Encoding UTF8
        }
        # 3. duplicate row
        Invoke-Check -Name 'duplicate-row' -Mutate {
            param($p)
            $t  = @(Get-Content -LiteralPath $p -Encoding UTF8)
            $i  = @($t | Select-String -Pattern '^\|\s*v1\.19\.1\s*\|').LineNumber[0] - 1
            Set-Content -LiteralPath $p -Value (@($t[0..$i]) + $t[$i] + @($t[($i + 1)..($t.Count - 1)])) -Encoding UTF8
        }
        # 4. duplicate section heading
        Invoke-Check -Name 'duplicate-section' -Mutate {
            param($p)
            $t  = @(Get-Content -LiteralPath $p -Encoding UTF8)
            $i  = @($t | Select-String -Pattern '^###\s+v1\.19\.1(\s|$)').LineNumber[0] - 1
            Set-Content -LiteralPath $p -Value (@($t[0..$i]) + $t[$i] + @($t[($i + 1)..($t.Count - 1)])) -Encoding UTF8
        }
        # 5. sanity: unmutated copy must pass
        $copyClean = Join-Path $stTmp 'README-clean.md'
        Copy-Item -LiteralPath $ReadmePath -Destination $copyClean -Force
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ReadmePath $copyClean 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  [PASS] clean copy passes' -ForegroundColor Green
        } else {
            Write-Host '  [FAIL] clean copy did not pass' -ForegroundColor Red
            $script:stFailures++
        }
    } finally {
        Remove-Item -LiteralPath $stTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:stFailures -gt 0) { Write-Host "Self-test FAILED ($($script:stFailures) failure(s))." -ForegroundColor Red; exit 1 }
    Write-Host 'Self-test passed: 5/5 scenarios.' -ForegroundColor Green
    exit 0
}

# ── Normal mode ──────────────────────────────────────────────────────────
if ($failures.Count -gt 0) {
    Write-Host 'README changelog is INCONSISTENT:' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Fix: add the missing «Что нового» section / table row, or remove the orphan.' -ForegroundColor Yellow
    exit 1
}

Write-Host ("README changelog OK: {0} table rows <-> {1} sections, all matched, no duplicates" -f $rowVersions.Count, $sectionVersions.Count) -ForegroundColor Green
exit 0
