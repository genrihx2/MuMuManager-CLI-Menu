#requires -Version 5.1
# Dependency-override gate: the security overrides in package.json must stay
# in place, and the lockfile must actually resolve those packages at or above
# the patched version.
#
# Why: disk@1.8.0 pulls a fixed dependency set, so a transitive package was
# left at a known-vulnerable version with no update path of our own. Dependabot
# alerts #1-#4 (undici 8.10.2, fast-xml-parser 5.11.2) were closed by overrides
# in package.json - but nothing stopped a later `npm install` cleanup or a
# well-meant "remove unused overrides" commit from silently dropping them, and
# a dropped override re-resolves the vulnerable version on the next install.
# The alert would only reappear days later, after a push nobody was watching.
#
# What this check enforces, per guarded package:
#   - package.json has an `overrides` entry for it
#   - the floor of that entry is at or above the patched version
#   - every copy in package-lock.json (top-level or nested under a parent)
#     resolves at or above the patched version - a nested copy means the
#     override did not apply and will be what actually runs
#
# Run: pwsh -NoProfile -File tests/test-dependency-overrides.ps1
#      pwsh -NoProfile -File tests/test-dependency-overrides.ps1 -SelfTest
# CI: .github/workflows/changelog-check.yml (job changelog-sync, a REQUIRED_LEGS
# release gate leg - see release.yml), so a regression blocks the release too.

param(
    [string]$PackagePath = '',
    [string]$LockPath = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $PackagePath) { $PackagePath = Join-Path $root 'package.json' }
if (-not $LockPath) { $LockPath = Join-Path $root 'package-lock.json' }

# Guarded packages. Floor = first patched release from the advisory that
# motivated the override; raising an override is always allowed, lowering it
# below the floor is what fails. Keep the reason short - it is printed with
# the failure so the next reader knows which alert comes back.
$guards = @(
    @{ Package = 'undici'; Floor = '8.12.2'; Reason = 'GHSA-f72v-6w45-q472, GHSA-4qv8-2p9j-2685, GHSA-xjj6-f33q-929c' }
    @{ Package = 'fast-xml-parser'; Floor = '5.12.0'; Reason = 'GHSA-474x-hrwr-fgx4' }
)

# ── helpers ───────────────────────────────────────────────────────────────
# The lockfile root is packages[""], and Windows PowerShell 5.1's
# ConvertFrom-Json rejects an empty property name, so both manifests go
# through a dictionary parser - the same approach as test-changelog-sync.ps1.
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

# '8.12.2' -> @(8,12,2). A prerelease/build suffix ('5.12.0-beta.1') is cut at
# the first non-numeric/dot character: a prerelease is below its own release,
# so treating it as that release is the conservative reading here.
function ConvertTo-VersionParts {
    param([string]$Version)
    if (-not $Version) { return @() }
    $core = ($Version.Trim() -replace '^[vV]', '')
    $core = ($core -split '[-+]')[0]
    $parts = @()
    foreach ($piece in ($core -split '\.')) {
        if ($piece -match '^\d+$') { $parts += [int]$piece } else { break }
    }
    return $parts
}

# -1 / 0 / 1 for $Left <, =, > $Right; missing segments count as 0 so
# 8.12 and 8.12.0 compare equal.
function Compare-Version {
    param([string]$Left, [string]$Right)
    $l = @(ConvertTo-VersionParts -Version $Left)
    $r = @(ConvertTo-VersionParts -Version $Right)
    $n = [Math]::Max($l.Count, $r.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $lv = 0; if ($i -lt $l.Count) { $lv = $l[$i] }
        $rv = 0; if ($i -lt $r.Count) { $rv = $r[$i] }
        if ($lv -lt $rv) { return -1 }
        if ($lv -gt $rv) { return 1 }
    }
    return 0
}

# '^5.12.0' / '>=8.12.2' / '~1.2.3' / '8.12.3' -> '5.12.0' / '8.12.2' / ...
# A range that is not a single floor (an OR, a wildcard, a Git URL, 'latest')
# yields $null, and the caller reports it as unusable rather than guessing.
function Get-FloorFromSpec {
    param([string]$Spec)
    if (-not $Spec) { return $null }
    $s = $Spec.Trim()
    if ($s.Contains('|')) { return $null }
    $s = $s -replace '^[\^~]', ''
    $s = $s -replace '^>=\s*', ''
    $s = $s.Trim()
    # '>= 8.12.2 < 9' or '8.x' is not a single floor: refuse to guess.
    if (@($s -split '\s+' | Where-Object { $_ }).Count -ne 1) { return $null }
    if ($s -match '^[0-9]+(\.[0-9]+){0,2}$') { return $s }
    return $null
}

function Get-OverrideMap {
    param($PackageMap)
    if (-not $PackageMap.ContainsKey('overrides')) { return @{} }
    $raw = $PackageMap['overrides']
    if ($raw -isnot [System.Collections.IDictionary]) { return @{} }
    return $raw
}

# ── checks ────────────────────────────────────────────────────────────────
$failures = @()
$checked = @()

if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
    Write-Host "package.json not found at $PackagePath - an installed copy has no manifests, but the repo does." -ForegroundColor Red
    exit 1
}

try {
    $pkgMap = ConvertFrom-JsonDictionary -Text (Get-Content -LiteralPath $PackagePath -Raw -Encoding UTF8)
} catch {
    Write-Host "package.json is not valid JSON ($PackagePath): $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$overrides = Get-OverrideMap -PackageMap $pkgMap

$lockMap = $null
$lockEntries = @{}
if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
    try {
        $lockMap = ConvertFrom-JsonDictionary -Text (Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8)
    } catch {
        Write-Host "package-lock.json is not valid JSON ($LockPath): $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    if ($lockMap.ContainsKey('packages') -and $lockMap['packages'] -is [System.Collections.IDictionary]) {
        foreach ($key in $lockMap['packages'].Keys) {
            $entry = $lockMap['packages'][$key]
            if ($entry -isnot [System.Collections.IDictionary]) { continue }
            if (-not $entry.ContainsKey('version')) { continue }
            $name = ''
            if ($entry.ContainsKey('name')) { $name = [string]$entry['name'] }
            if (-not $name -and $key -match 'node_modules/([^/]+)$') { $name = $Matches[1] }
            if (-not $name) { continue }
            if (-not $lockEntries.ContainsKey($name)) { $lockEntries[$name] = @() }
            $lockEntries[$name] += @{ Path = $key; Version = [string]$entry['version'] }
        }
    }
} else {
    $failures += "package-lock.json not found at $LockPath - without it the resolved versions cannot be verified"
}

foreach ($g in $guards) {
    $name = $g.Package
    $floor = $g.Floor

    # 1. the override itself must still be declared
    if (-not $overrides.ContainsKey($name)) {
        $failures += ("override for {0} is missing from package.json - it keeps {1} at or above {2} ({3}); re-add it under `"overrides`" (do not delete it as 'unused': disk@1.8.0 pins an older range and the vulnerable version comes back)" -f $name, $name, $floor, $g.Reason)
    } else {
        $spec = [string]$overrides[$name]
        $specFloor = Get-FloorFromSpec -Spec $spec
        if (-not $specFloor) {
            $failures += ("override for {0} is `"{1}`", which is not a single version floor - use a plain floor such as `"{2}`" so the patched minimum stays visible" -f $name, $spec, $floor)
        } elseif ((Compare-Version -Left $specFloor -Right $floor) -lt 0) {
            $failures += ("override for {0} is `"{1}`" (floor {2}) but {3} is the first patched version ({4}); raise it" -f $name, $spec, $specFloor, $floor, $g.Reason)
        } else {
            $checked += ("{0} override {1} >= {2}" -f $name, $spec, $floor)
        }
    }

    # 2. every resolved copy in the lockfile must be at or above the floor
    if ($null -ne $lockMap) {
        if (-not $lockEntries.ContainsKey($name)) {
            $checked += ("{0} not present in package-lock.json" -f $name)
        } else {
            foreach ($e in $lockEntries[$name]) {
                if ((Compare-Version -Left $e.Version -Right $floor) -lt 0) {
                    $where = if ($e.Path) { $e.Path } else { 'root' }
                    $failures += ("package-lock.json resolves {0}@{1} at '{2}', below the patched {3} ({4}) - run `"npm install`" so the override applies; a nested copy means it did not" -f $name, $e.Version, $where, $floor, $g.Reason)
                } else {
                    $checked += ("{0}@{1} locked at '{2}'" -f $name, $e.Version, $e.Path)
                }
            }
        }
    }
}

# ── self-test: mutate copies and assert the gate catches each shape ───────
if ($SelfTest) {
    if ($failures.Count -gt 0) {
        Write-Host 'Self-test aborted: the real manifests must pass first:' -ForegroundColor Red
        foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
        exit 1
    }
    Write-Host ''
    Write-Host 'Self-test: the gate must fail on each removed/lowered override' -ForegroundColor Cyan
    $script:stFailures = 0
    $script:stChecks = 0
    $stTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dep-overrides-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stTmp -Force | Out-Null

    function Invoke-OverrideCheck {
        param([string]$Name, [scriptblock]$Mutate, [switch]$ExpectFail, [string]$MessageMustMatch = '')
        $script:stChecks++
        $p = Join-Path $stTmp ("pkg-$Name.json")
        $l = Join-Path $stTmp ("lock-$Name.json")
        Copy-Item -LiteralPath $PackagePath -Destination $p -Force
        Copy-Item -LiteralPath $LockPath -Destination $l -Force
        $beforeP = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        $beforeL = (Get-FileHash -LiteralPath $l -Algorithm SHA256).Hash
        & $Mutate $p $l
        # A mutation that matched nothing would pass every "expect fail" case
        # for the wrong reason, so an unchanged fixture is a self-test failure.
        if ($ExpectFail -and
            (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -eq $beforeP -and
            (Get-FileHash -LiteralPath $l -Algorithm SHA256).Hash -eq $beforeL) {
            Write-Host "  [FAIL] $Name (mutation changed nothing)" -ForegroundColor Red
            $script:stFailures++
            return
        }
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -PackagePath $p -LockPath $l 2>&1) | Out-String
        $failed = ($LASTEXITCODE -eq 1)
        $ok = if ($ExpectFail) {
            $failed -and (-not $MessageMustMatch -or $out -match $MessageMustMatch)
        } else {
            -not $failed
        }
        if ($ok) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $Name (exit=$LASTEXITCODE)" -ForegroundColor Red
            if (-not $ok) { Write-Host ($out.Trim() -replace '(?m)^', '         ') -ForegroundColor DarkGray }
            $script:stFailures++
        }
    }

    $probe = $guards[0].Package      # undici today
    $probeFloor = $guards[0].Floor
    $belowFloor = @(ConvertTo-VersionParts -Version $probeFloor)
    $belowFloor[$belowFloor.Count - 1] = $belowFloor[$belowFloor.Count - 1] - 1
    $below = ($belowFloor -join '.')
    # The mutations below are scriptblocks invoked with &, so the values they
    # need live in this script's scope - the same pattern test-changelog-sync
    # uses for its probe version.
    $script:stProbe = $probe
    $script:stProbeBelow = $below

    # 1. sanity: untouched copies pass
    Invoke-OverrideCheck -Name 'clean manifests pass' -Mutate { param($p, $l) }

    # 2. the override removed entirely (the "unused override" cleanup)
    Invoke-OverrideCheck -Name 'override removed' -ExpectFail -MessageMustMatch "override for $probe is missing" -Mutate {
        param($p, $l)
        $t = Get-Content -LiteralPath $p -Raw
        # Either position: the guarded package may be the first or the last
        # entry of "overrides", so the separator comma travels with the match.
        $t = [regex]::Replace($t, '\s*"' + [regex]::Escape($script:stProbe) + '"\s*:\s*"[^"]*"\s*,?', '')
        [System.IO.File]::WriteAllText($p, $t)
    }

    # 3. the override present but lowered below the patched version
    Invoke-OverrideCheck -Name 'override lowered' -ExpectFail -MessageMustMatch "below|is the first patched" -Mutate {
        param($p, $l)
        $t = Get-Content -LiteralPath $p -Raw
        $t = [regex]::Replace($t, '("' + [regex]::Escape($script:stProbe) + '"\s*:\s*)"[^"]*"', ('$1"' + $script:stProbeBelow + '"'))
        [System.IO.File]::WriteAllText($p, $t)
    }

    # 4. lockfile left at the vulnerable version (override added, install not run)
    Invoke-OverrideCheck -Name 'lockfile below floor' -ExpectFail -MessageMustMatch 'below the patched' -Mutate {
        param($p, $l)
        $t = Get-Content -LiteralPath $l -Raw
        $t = [regex]::Replace($t, '("node_modules/' + [regex]::Escape($script:stProbe) + '":\s*\{\s*"version":\s*)"[^"]*"', ('$1"' + $script:stProbeBelow + '"'))
        [System.IO.File]::WriteAllText($l, $t)
    }

    # 5. a nested copy surviving under a parent - the override did not apply
    Invoke-OverrideCheck -Name 'nested copy below floor' -ExpectFail -MessageMustMatch 'below the patched' -Mutate {
        param($p, $l)
        $obj = ConvertFrom-JsonDictionary -Text (Get-Content -LiteralPath $l -Raw -Encoding UTF8)
        $nestedKey = 'node_modules/some-parent/node_modules/' + $script:stProbe
        $nested = [ordered]@{ name = $script:stProbe; version = $script:stProbeBelow }
        $obj['packages'][$nestedKey] = $nested
        [System.IO.File]::WriteAllText($l, ($obj | ConvertTo-Json -Depth 100 -Compress))
    }

    Remove-Item -LiteralPath $stTmp -Recurse -Force -ErrorAction SilentlyContinue

    if ($script:stFailures -gt 0) {
        Write-Host ("Self-test FAILED ({0} failure(s))." -f $script:stFailures) -ForegroundColor Red
        exit 1
    }
    Write-Host ("Self-test passed: {0}/{0} scenarios." -f $script:stChecks) -ForegroundColor Green
    exit 0
}

# ── normal mode ───────────────────────────────────────────────────────────
if ($failures.Count -gt 0) {
    Write-Host 'Dependency overrides are NOT enforcing their patched floors:' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Fix: restore the override in package.json under "overrides", then run `npm install` so' -ForegroundColor Yellow
    Write-Host '     package-lock.json resolves the patched version, and commit both files together.' -ForegroundColor Yellow
    exit 1
}

Write-Host ("Dependency overrides OK: {0} guarded package(s), {1} check(s) passed." -f $guards.Count, $checked.Count) -ForegroundColor Green
foreach ($c in $checked) { Write-Host "  $c" -ForegroundColor DarkGray }
exit 0
