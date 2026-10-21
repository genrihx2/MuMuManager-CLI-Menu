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
#   - (issue #31) the top `## vX.Y.Z` section of relnotes.md matches .version
#     (= the tag the Release workflow publishes) and mumu-menu.ps1's
#     $scriptVer - a lagging source is named explicitly in the failure
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -ReadmePath <path-to-mutated-copy>
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -RelnotesPath <copy> -VersionPath <copy> -MenuPath <copy>
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -SelfTest
# CI: .github/workflows/changelog-check.yml

param(
    [string]$ReadmePath = '',
    [string]$RelnotesPath = '',
    [string]$VersionPath = '',
    [string]$MenuPath = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $ReadmePath)   { $ReadmePath   = Join-Path $root 'README.md' }
if (-not $RelnotesPath) { $RelnotesPath = Join-Path $root 'relnotes.md' }
if (-not $VersionPath)  { $VersionPath  = Join-Path $root '.version' }
if (-not $MenuPath)     { $MenuPath     = Join-Path $root 'mumu-menu.ps1' }
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

# ── Release version sync: relnotes top <-> .version <-> scriptVer (#31) ──
# The Release workflow publishes the tag taken from .version, and the
# published body is built from the README sections - so all three version
# sources must agree before a release makes any of them stale.
$relnotesTop = 'NOT FOUND'
if (Test-Path -LiteralPath $RelnotesPath -PathType Leaf) {
    $relLines = @(Get-Content -LiteralPath $RelnotesPath -Encoding UTF8)
    foreach ($rl in $relLines) {
        if ($rl -match '^##\s+(v\d+\.\d+\.\d+)') { $relnotesTop = $Matches[1]; break }
    }
} else {
    $failures += "relnotes.md not found at $RelnotesPath"
}
$versionTag = 'NOT FOUND'
if (Test-Path -LiteralPath $VersionPath -PathType Leaf) {
    $vRaw = (Get-Content -LiteralPath $VersionPath -Raw -ErrorAction SilentlyContinue)
    if ($vRaw) { $vTrim = $vRaw.Trim(); if ($vTrim -match '^v\d+\.\d+\.\d+$') { $versionTag = $vTrim } else { $versionTag = "INVALID ($vTrim)" } }
} else {
    $failures += ".version not found at $VersionPath"
}
$scriptVer = 'NOT FOUND'
if (Test-Path -LiteralPath $MenuPath -PathType Leaf) {
    $menuHead = (Get-Content -LiteralPath $MenuPath -TotalCount 320 -Encoding UTF8) -join "`n"
    if ($menuHead -match "\`$scriptVer\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'") { $scriptVer = $Matches[1] }
} else {
    $failures += "mumu-menu.ps1 not found at $MenuPath"
}
if ($relnotesTop -ne $versionTag -or $versionTag -ne "v$scriptVer") {
    $failures += "release version mismatch - relnotes.md top section = $relnotesTop, .version = $versionTag, mumu-menu.ps1 scriptVer = $scriptVer; whichever of the three lags behind the release tag is stale and must be updated (bump all three together)"
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

        # ── Version-sync scenarios (issue #31): relnotes top <-> .version <-> scriptVer ──
        function New-VersionFixtures {
            # A consistent fixture set: all three sources claim v9.9.9.
            param([string]$Tag = 'v9.9.9', [string]$Ver = '9.9.9')
            $r = Join-Path $stTmp ("relnotes-" + [Guid]::NewGuid().ToString('N') + ".md")
            $v = Join-Path $stTmp ("version-" + [Guid]::NewGuid().ToString('N') + ".txt")
            $m = Join-Path $stTmp ("menu-" + [Guid]::NewGuid().ToString('N') + ".ps1")
            [System.IO.File]::WriteAllText($r, "# Notes`n`n## $Tag (15.09.2026)`n- something`n`n## v1.0.0 (14.09.2026)`n- old`n")
            [System.IO.File]::WriteAllText($v, "$Tag")
            [System.IO.File]::WriteAllText($m, "`$scriptVer = '$Ver'`n")
            return @{ Relnotes = $r; Version = $v; Menu = $m }
        }
        function Invoke-VersionCheck {
            param([string]$Name, [hashtable]$Fix, [scriptblock]$Mutate, [switch]$ExpectFail, [string]$MessageMustMatch = '')
            $r2 = Join-Path $stTmp ("rel-" + $Name + ".md"); $v2 = Join-Path $stTmp ("ver-" + $Name + ".txt"); $m2 = Join-Path $stTmp ("menu-" + $Name + ".ps1")
            Copy-Item -LiteralPath $Fix.Relnotes -Destination $r2 -Force
            Copy-Item -LiteralPath $Fix.Version  -Destination $v2 -Force
            Copy-Item -LiteralPath $Fix.Menu     -Destination $m2 -Force
            & $Mutate @{ Relnotes = $r2; Version = $v2; Menu = $m2 }
            $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ReadmePath $ReadmePath -RelnotesPath $r2 -VersionPath $v2 -MenuPath $m2 2>&1) | Out-String
            $failed = ($LASTEXITCODE -eq 1)
            $ok = if ($ExpectFail) { $failed -and (-not $MessageMustMatch -or $out -match $MessageMustMatch) } else { -not $failed }
            if ($ok) {
                Write-Host "  [PASS] version-sync: $Name" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] version-sync: $Name (exit=$LASTEXITCODE)" -ForegroundColor Red
                $script:stFailures++
            }
        }
        $fix = New-VersionFixtures
        # 6. sanity: consistent version sources pass
        Invoke-VersionCheck -Name 'consistent sources pass' -Fix $fix -Mutate { param($p) }
        # 7. relnotes top lags behind -> failure names all three sources
        Invoke-VersionCheck -Name 'relnotes top lags' -Fix $fix -ExpectFail -MessageMustMatch 'relnotes\.md top section = v9\.9\.8, \.version = v9\.9\.9, mumu-menu\.ps1 scriptVer = 9\.9\.9' -Mutate {
            param($p)
            $t = (Get-Content -LiteralPath $p.Relnotes -Raw) -replace '## v9\.9\.9', '## v9.9.8'
            [System.IO.File]::WriteAllText($p.Relnotes, $t)
        }
        # 8. .version lags behind
        Invoke-VersionCheck -Name '.version lags' -Fix $fix -ExpectFail -MessageMustMatch '\.version = v9\.9\.8' -Mutate {
            param($p)
            [System.IO.File]::WriteAllText($p.Version, 'v9.9.8')
        }
        # 9. scriptVer lags behind
        Invoke-VersionCheck -Name 'scriptVer lags' -Fix $fix -ExpectFail -MessageMustMatch 'scriptVer = 9\.9\.8' -Mutate {
            param($p)
            [System.IO.File]::WriteAllText($p.Menu, "`$scriptVer = '9.9.8'`n")
        }
        # 10. invalid .version content
        Invoke-VersionCheck -Name 'invalid .version content' -Fix $fix -ExpectFail -MessageMustMatch 'INVALID' -Mutate {
            param($p)
            [System.IO.File]::WriteAllText($p.Version, 'garbage')
        }
    } finally {
        Remove-Item -LiteralPath $stTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:stFailures -gt 0) { Write-Host "Self-test FAILED ($($script:stFailures) failure(s))." -ForegroundColor Red; exit 1 }
    Write-Host 'Self-test passed: 10/10 scenarios.' -ForegroundColor Green
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

Write-Host ("README changelog OK: {0} table rows <-> {1} sections, all matched, no duplicates; release version sync OK: relnotes {2} = .version {3} = scriptVer {4}" -f $rowVersions.Count, $sectionVersions.Count, $relnotesTop, $versionTag, $scriptVer) -ForegroundColor Green
exit 0
