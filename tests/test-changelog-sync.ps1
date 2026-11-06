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
#   - package.json and the root version fields of package-lock.json carry
#     that same version when the files are present. They are repo-only (the
#     ZIP ships neither, so an installed copy legitimately has no manifests),
#     but in the repo they must be bumped with the release: from v10.3.5 to
#     v10.4.8 the ritual only touched relnotes/.version/$scriptVer, so both
#     froze at 10.3.4 for nine releases before anyone noticed
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -ReadmePath <path-to-mutated-copy>
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -RelnotesPath <copy> -VersionPath <copy> -MenuPath <copy>
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -PackagePath <copy> -LockPath <copy>
#   powershell -ExecutionPolicy Bypass -File tests\test-changelog-sync.ps1 -SelfTest
# CI: .github/workflows/changelog-check.yml, gate step in .github/workflows/release.yml

param(
    [string]$ReadmePath = '',
    [string]$RelnotesPath = '',
    [string]$VersionPath = '',
    [string]$MenuPath = '',
    [string]$PackagePath = '',
    [string]$LockPath = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $ReadmePath)   { $ReadmePath   = Join-Path $root 'README.md' }
if (-not $RelnotesPath) { $RelnotesPath = Join-Path $root 'relnotes.md' }
if (-not $VersionPath)  { $VersionPath  = Join-Path $root '.version' }
if (-not $MenuPath)     { $MenuPath     = Join-Path $root 'mumu-menu.ps1' }
if (-not $PackagePath)  { $PackagePath  = Join-Path $root 'package.json' }
if (-not $LockPath)     { $LockPath     = Join-Path $root 'package-lock.json' }
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

# ── Manifest version sync: package.json / package-lock.json <-> .version ──
# The manifests are private:true and never ship in the ZIP, so an installed
# copy has neither and an absent file is not a failure. When present they must
# carry the release version, or the next bump leaves them behind exactly as it
# left these two at 10.3.4 for nine releases.
#
# Parsing note: a lockfile v2/v3 root is packages[""], and Windows PowerShell
# 5.1's ConvertFrom-Json rejects an empty property name outright. Both engines
# therefore go through a dictionary parser - -AsHashtable on 6+, the framework
# JavaScriptSerializer on 5.1 - so the check behaves identically on the CI
# runner (pwsh) and on a maintainer's 5.1 console.
function ConvertFrom-JsonDictionary {
    param([string]$Text)
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return ($Text | ConvertFrom-Json -AsHashtable)
    }
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    return $serializer.DeserializeObject($Text)
}

$pkgVersion = ''
if (Test-Path -LiteralPath $PackagePath -PathType Leaf) {
    try {
        $pkgMap = ConvertFrom-JsonDictionary -Text (Get-Content -LiteralPath $PackagePath -Raw -Encoding UTF8)
        if ($pkgMap.ContainsKey('version')) { $pkgVersion = [string]$pkgMap['version'] }
    } catch {
        $failures += "package.json is not valid JSON ($PackagePath): $($_.Exception.Message)"
    }
}
$lockFields = @()
if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
    try {
        $lockMap = ConvertFrom-JsonDictionary -Text (Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8)
        # npm keeps the root version twice: top-level `version` and
        # packages[""].version (the workspace root). A half-applied bump
        # updates one and not the other, so both are checked.
        if ($lockMap.ContainsKey('version')) {
            $lockFields += @{ Field = 'version'; Value = [string]$lockMap['version'] }
        }
        if ($lockMap.ContainsKey('packages') -and $lockMap['packages'] -is [System.Collections.IDictionary] -and $lockMap['packages'].ContainsKey('')) {
            $rootPkg = $lockMap['packages']['']
            if ($rootPkg -is [System.Collections.IDictionary] -and $rootPkg.ContainsKey('version')) {
                $lockFields += @{ Field = 'packages[""].version'; Value = [string]$rootPkg['version'] }
            }
        }
    } catch {
        $failures += "package-lock.json is not valid JSON ($LockPath): $($_.Exception.Message)"
    }
}
$manifestChecked = @()
if ($versionTag -match '^v\d+\.\d+\.\d+$') {
    $wantVersion = $versionTag.Substring(1)
    if ($pkgVersion) {
        $manifestChecked += "package.json $pkgVersion"
        if ($pkgVersion -ne $wantVersion) {
            $failures += "package.json version = $pkgVersion but .version = $versionTag; the manifests must be bumped with the release (they were left at 10.3.4 for nine releases when only relnotes/.version/scriptVer were checked)"
        }
    }
    foreach ($lf in $lockFields) {
        if (-not $lf.Value) { continue }
        $manifestChecked += "lock $($lf.Field) $($lf.Value)"
        if ($lf.Value -ne $wantVersion) {
            $failures += "package-lock.json $($lf.Field) = $($lf.Value) but .version = $versionTag; both root version fields in the lockfile must carry the release version"
        }
    }
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
    $script:stChecks = 0
    # Mutations are injected into the version that is actually documented in
    # README.md. The old v1.19.1 regression anchor has been pruned from the
    # changelog table, so a hard-coded version would mutate nothing and the
    # self-test would "fail" without testing anything.
    if ($rowVersions.Count -eq 0) {
        Write-Host 'Self-test aborted: no changelog table rows to mutate.' -ForegroundColor Red
        exit 1
    }
    $script:stProbe   = $rowVersions[0]
    $script:stProbeRe = [regex]::Escape($script:stProbe)
    $stTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("chg-sync-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stTmp -Force | Out-Null
    try {
        function Invoke-Check {
            param([string]$Name, [scriptblock]$Mutate)
            $script:stChecks++
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
        # 1. remove a section, keep the row (the v1.19.1 regression shape)
        Invoke-Check -Name 'row-without-section' -Mutate {
            param($p)
            $t = @(Get-Content -LiteralPath $p -Encoding UTF8 | Where-Object { $_ -notmatch ('^###\s+' + $script:stProbeRe + '(\s|$)') })
            Set-Content -LiteralPath $p -Value $t -Encoding UTF8
        }
        # 2. remove a row, keep the section
        Invoke-Check -Name 'section-without-row' -Mutate {
            param($p)
            $t = @(Get-Content -LiteralPath $p -Encoding UTF8 | Where-Object { $_ -notmatch ('^\|\s*' + $script:stProbeRe + '\s*\|') })
            Set-Content -LiteralPath $p -Value $t -Encoding UTF8
        }
        # 3. duplicate row
        Invoke-Check -Name 'duplicate-row' -Mutate {
            param($p)
            $t  = @(Get-Content -LiteralPath $p -Encoding UTF8)
            $i  = @($t | Select-String -Pattern ('^\|\s*' + $script:stProbeRe + '\s*\|')).LineNumber[0] - 1
            Set-Content -LiteralPath $p -Value (@($t[0..$i]) + $t[$i] + @($t[($i + 1)..($t.Count - 1)])) -Encoding UTF8
        }
        # 4. duplicate section heading
        Invoke-Check -Name 'duplicate-section' -Mutate {
            param($p)
            $t  = @(Get-Content -LiteralPath $p -Encoding UTF8)
            $i  = @($t | Select-String -Pattern ('^###\s+' + $script:stProbeRe + '(\s|$)')).LineNumber[0] - 1
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
            # A consistent fixture set: all three sources and both manifests
            # claim v9.9.9. The manifests are real files because the check
            # parses them as JSON - a stub would not exercise the parser.
            param([string]$Tag = 'v9.9.9', [string]$Ver = '9.9.9')
            $r = Join-Path $stTmp ("relnotes-" + [Guid]::NewGuid().ToString('N') + ".md")
            $v = Join-Path $stTmp ("version-" + [Guid]::NewGuid().ToString('N') + ".txt")
            $m = Join-Path $stTmp ("menu-" + [Guid]::NewGuid().ToString('N') + ".ps1")
            $p = Join-Path $stTmp ("package-" + [Guid]::NewGuid().ToString('N') + ".json")
            $l = Join-Path $stTmp ("lock-" + [Guid]::NewGuid().ToString('N') + ".json")
            [System.IO.File]::WriteAllText($r, "# Notes`n`n## $Tag (15.09.2026)`n- something`n`n## v1.0.0 (14.09.2026)`n- old`n")
            [System.IO.File]::WriteAllText($v, "$Tag")
            [System.IO.File]::WriteAllText($m, "`$scriptVer = '$Ver'`n")
            [System.IO.File]::WriteAllText($p, '{"name":"fixture","version":"' + $Ver + '","private":true}' + "`n")
            [System.IO.File]::WriteAllText($l, '{"name":"fixture","version":"' + $Ver + '","lockfileVersion":3,"packages":{"":{"name":"fixture","version":"' + $Ver + '"}}}' + "`n")
            return @{ Relnotes = $r; Version = $v; Menu = $m; Package = $p; Lock = $l }
        }
        function Invoke-VersionCheck {
            param([string]$Name, [hashtable]$Fix, [scriptblock]$Mutate, [switch]$ExpectFail, [string]$MessageMustMatch = '')
            $script:stChecks++
            $r2 = Join-Path $stTmp ("rel-" + $Name + ".md"); $v2 = Join-Path $stTmp ("ver-" + $Name + ".txt"); $m2 = Join-Path $stTmp ("menu-" + $Name + ".ps1")
            $p2 = Join-Path $stTmp ("pkg-" + $Name + ".json"); $l2 = Join-Path $stTmp ("lock-" + $Name + ".json")
            Copy-Item -LiteralPath $Fix.Relnotes -Destination $r2 -Force
            Copy-Item -LiteralPath $Fix.Version  -Destination $v2 -Force
            Copy-Item -LiteralPath $Fix.Menu     -Destination $m2 -Force
            Copy-Item -LiteralPath $Fix.Package  -Destination $p2 -Force
            Copy-Item -LiteralPath $Fix.Lock     -Destination $l2 -Force
            & $Mutate @{ Relnotes = $r2; Version = $v2; Menu = $m2; Package = $p2; Lock = $l2 }
            $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -ReadmePath $ReadmePath -RelnotesPath $r2 -VersionPath $v2 -MenuPath $m2 -PackagePath $p2 -LockPath $l2 2>&1) | Out-String
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
        # 11. package.json lags behind .version (the nine-release drift)
        Invoke-VersionCheck -Name 'package.json lags' -Fix $fix -ExpectFail -MessageMustMatch 'package\.json version = 9\.9\.8 but \.version = v9\.9\.9' -Mutate {
            param($p)
            [System.IO.File]::WriteAllText($p.Package, '{"name":"fixture","version":"9.9.8","private":true}')
        }
        # 12. lockfile top-level version lags, workspace root is fine
        Invoke-VersionCheck -Name 'lockfile top-level version lags' -Fix $fix -ExpectFail -MessageMustMatch 'package-lock\.json version = 9\.9\.8 but \.version = v9\.9\.9' -Mutate {
            param($p)
            [System.IO.File]::WriteAllText($p.Lock, '{"name":"fixture","version":"9.9.8","lockfileVersion":3,"packages":{"":{"name":"fixture","version":"9.9.9"}}}')
        }
        # 13. only packages[""].version lags - a half-applied bump
        Invoke-VersionCheck -Name 'lockfile workspace-root version lags' -Fix $fix -ExpectFail -MessageMustMatch 'package-lock\.json packages\[""\]\.version = 9\.9\.8' -Mutate {
            param($p)
            [System.IO.File]::WriteAllText($p.Lock, '{"name":"fixture","version":"9.9.9","lockfileVersion":3,"packages":{"":{"name":"fixture","version":"9.9.8"}}}')
        }
        # 14. manifests absent (an installed copy) must stay legal
        Invoke-VersionCheck -Name 'manifests absent still passes' -Fix $fix -Mutate {
            param($p)
            Remove-Item -LiteralPath $p.Package -Force
            Remove-Item -LiteralPath $p.Lock -Force
        }
        # 15. a corrupted manifest is named, not silently skipped
        Invoke-VersionCheck -Name 'malformed package.json is reported' -Fix $fix -ExpectFail -MessageMustMatch 'package\.json is not valid JSON' -Mutate {
            param($p)
            [System.IO.File]::WriteAllText($p.Package, '{not json')
        }
    } finally {
        Remove-Item -LiteralPath $stTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:stFailures -gt 0) { Write-Host "Self-test FAILED ($($script:stFailures) failure(s))." -ForegroundColor Red; exit 1 }
    Write-Host ("Self-test passed: {0}/{0} scenarios." -f $script:stChecks) -ForegroundColor Green
    exit 0
}

# ── Normal mode ──────────────────────────────────────────────────────────
if ($failures.Count -gt 0) {
    Write-Host 'README changelog is INCONSISTENT:' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Fix: add the missing «Что нового» section / table row, or remove the orphan; for a' -ForegroundColor Yellow
    Write-Host '     version mismatch bump relnotes.md + .version + $scriptVer + package.json/lockfile together.' -ForegroundColor Yellow
    exit 1
}

Write-Host ("README changelog OK: {0} table rows <-> {1} sections, all matched, no duplicates; release version sync OK: relnotes {2} = .version {3} = scriptVer {4}" -f $rowVersions.Count, $sectionVersions.Count, $relnotesTop, $versionTag, $scriptVer) -ForegroundColor Green
if ($manifestChecked.Count -gt 0) {
    Write-Host ("Manifest version sync OK: {0}" -f ($manifestChecked -join ', ')) -ForegroundColor Green
} else {
    Write-Host 'Manifest version sync skipped: no package.json / package-lock.json (an installed copy has neither).' -ForegroundColor DarkGray
}
exit 0
