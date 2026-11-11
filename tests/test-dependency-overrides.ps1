#requires -Version 5.1
# Dependency security gate for the repo-only npm tree.
#
# Why: disk@1.8.0 pins an older dependency set, so `undici` and
# `fast-xml-parser` sat at versions with open advisories (Dependabot #1-#4) and
# there was no upstream release to wait for. Overrides in package.json fixed
# that - but a table of "known bad" versions in this file only guards the
# advisories somebody already knew about, and every new advisory (or every
# newly pinned transitive dependency) needed a code change here before CI
# noticed. This gate reads the advisories themselves instead.
#
# Two layers, neither with a hard-coded package list:
#
#   1. Structural (offline, always): each `overrides` entry in package.json
#      must be a single version floor, and package-lock.json must resolve that
#      package at or above it - including nested copies, because a nested copy
#      means the override never applied. A newly added override is guarded
#      automatically; nothing here names a package.
#
#   2. Advisory (npm audit, the real gate): the resolved tree must be clean
#      according to npm's advisory database. A new advisory, or an override
#      lowered/removed so the next install resolves a vulnerable version,
#      fails here without touching this file. Lowering a floor is not caught
#      structurally on purpose - the committed lockfile still resolves the
#      patched version - so this layer is what enforces the floor, and it
#      reports the package, the advisory and the version to override to.
#
# These packages are repo tooling: the release ZIP ships only scripts and docs,
# so a hit blocks the repo's CI, not a user's install.
#
# Run:
#   pwsh -NoProfile -File tests/test-dependency-overrides.ps1
#   pwsh -NoProfile -File tests/test-dependency-overrides.ps1 -SkipAdvisory   # offline
#   pwsh -NoProfile -File tests/test-dependency-overrides.ps1 -AuditJson <saved npm audit --json>
#   pwsh -NoProfile -File tests/test-dependency-overrides.ps1 -SelfTest      # offline
# CI: .github/workflows/changelog-check.yml (job changelog-sync), a
# REQUIRED_LEGS release-gate leg - a regression blocks the release too.

param(
    [string]$PackagePath = '',
    [string]$LockPath = '',
    [string]$AuditJson = '',
    [switch]$SkipAdvisory,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $PackagePath) { $PackagePath = Join-Path $root 'package.json' }
if (-not $LockPath) { $LockPath = Join-Path $root 'package-lock.json' }

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
# the first non-numeric/dot character: a prerelease sorts below its own
# release, so treating it as that release is the conservative reading.
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
# Anything that is not a single floor (an OR, a range, a wildcard, a Git URL,
# 'latest') yields $null and is reported rather than guessed at.
function Get-FloorFromSpec {
    param([string]$Spec)
    if (-not $Spec) { return $null }
    $s = $Spec.Trim()
    if ($s.Contains('|')) { return $null }
    $s = $s -replace '^[\^~]', ''
    $s = $s -replace '^>=\s*', ''
    $s = $s.Trim()
    if (@($s -split '\s+' | Where-Object { $_ }).Count -ne 1) { return $null }
    if ($s -match '^\d+(\.\d+){0,2}$') { return $s }
    return $null
}

# ── layer 1: structural ───────────────────────────────────────────────────
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

$overrides = @{}
if ($pkgMap.ContainsKey('overrides') -and $pkgMap['overrides'] -is [System.Collections.IDictionary]) {
    $overrides = $pkgMap['overrides']
}

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

if ($overrides.Count -eq 0) {
    $checked += 'package.json declares no overrides (nothing to pin structurally)'
}

foreach ($name in @($overrides.Keys)) {
    $spec = [string]$overrides[$name]
    $floor = Get-FloorFromSpec -Spec $spec
    if (-not $floor) {
        $failures += ("override for {0} is `"{1}`", which is not a single version floor - use a plain floor such as `"{2}`" so the minimum the tree may resolve to stays visible and checkable" -f $name, $spec, '1.2.3')
        continue
    }
    $checked += ("{0} override `"{1}`" (floor {2})" -f $name, $spec, $floor)

    if ($null -eq $lockMap) { continue }
    if (-not $lockEntries.ContainsKey($name)) {
        $checked += ("{0} not present in package-lock.json" -f $name)
        continue
    }
    foreach ($e in $lockEntries[$name]) {
        if ((Compare-Version -Left $e.Version -Right $floor) -lt 0) {
            $where = if ($e.Path) { $e.Path } else { 'root' }
            $failures += ("package-lock.json resolves {0}@{1} at '{2}', below the override floor {3} - run `"npm install`" so the override applies; a nested copy means it did not apply at all" -f $name, $e.Version, $where, $floor)
        } else {
            $checked += ("{0}@{1} locked at '{2}'" -f $name, $e.Version, $e.Path)
        }
    }
}

# ── layer 2: advisories (npm audit) ───────────────────────────────────────
# Parsed rather than trusted: `npm audit` exits 1 whenever it finds something,
# so the exit code says nothing about success, and a registry/network failure
# must be reported as "could not check", never as green.
function Get-AuditText {
    param([string]$Path)
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "audit JSON not found: $Path" }
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'npm is not on PATH, so the advisory database cannot be queried' }
    $out = (& npm audit --json --audit-level=low 2>$null | Out-String)
    if (-not $out -or -not $out.Trim()) { throw 'npm audit produced no output (npm or registry failure)' }
    return $out
}

function Get-AdvisorySummary {
    param($Vulnerability)
    $v = $Vulnerability
    $severity = ''
    if ($v -is [System.Collections.IDictionary] -and $v.ContainsKey('severity')) { $severity = [string]$v['severity'] }
    $titles = @()
    $patched = ''
    if ($v -is [System.Collections.IDictionary]) {
        if ($v.ContainsKey('via')) {
            foreach ($item in @($v['via'])) {
                if ($item -is [System.Collections.IDictionary]) {
                    $t = ''
                    if ($item.ContainsKey('title')) { $t = [string]$item['title'] }
                    $u = ''
                    if ($item.ContainsKey('url')) { $u = [string]$item['url'] }
                    if ($t) {
                        if ($u) { $titles += ("{0} <{1}>" -f $t, $u) } else { $titles += $t }
                    }
                } else {
                    $titles += ("transitive via {0}" -f [string]$item)
                }
            }
        }
        if ($v.ContainsKey('fixAvailable')) {
            $fix = $v['fixAvailable']
            if ($fix -is [System.Collections.IDictionary] -and $fix.ContainsKey('version')) { $patched = [string]$fix['version'] }
        }
        if (-not $patched -and $v.ContainsKey('range')) { $patched = '' }
    }
    $advice = 'add or raise an override for it in package.json until the tree no longer resolves a vulnerable version'
    if ($patched) { $advice = ("add or raise an override so the tree resolves >= {0}, then run 'npm install'" -f $patched) }
    $detail = ($titles | Where-Object { $_ }) -join '; '
    if (-not $detail) { $detail = 'no advisory detail in the report' }
    return ("{0} vulnerability: {1} ({2})" -f $severity, $detail, $advice)
}

$auditChecked = $false
if (-not $SkipAdvisory) {
    try {
        $auditMap = ConvertFrom-JsonDictionary -Text (Get-AuditText -Path $AuditJson)
    } catch {
        $auditMap = $null
        $failures += ("advisory check could not run: {0}. The gate fails closed on purpose - rerun with network access, or -SkipAdvisory to check only the structural layer" -f $_.Exception.Message)
    }
    if ($null -ne $auditMap) {
        if (-not $auditMap.ContainsKey('vulnerabilities') -or $auditMap['vulnerabilities'] -isnot [System.Collections.IDictionary]) {
            $failures += 'advisory check could not run: npm audit did not return a "vulnerabilities" block (registry or network error). Rerun with network access, or -SkipAdvisory for the structural layer only'
        } elseif ($auditMap['vulnerabilities'].Count -eq 0) {
            $auditChecked = $true
            $checked += 'npm advisory database: no vulnerabilities in the resolved tree'
        } else {
            foreach ($name in @($auditMap['vulnerabilities'].Keys)) {
                $failures += ("{0}: {1}" -f $name, (Get-AdvisorySummary -Vulnerability $auditMap['vulnerabilities'][$name]))
            }
        }
    }
} else {
    $checked += 'advisory check skipped (-SkipAdvisory) - structural layer only'
}

# ── self-test: mutate fixtures and assert the gate catches each shape ─────
if ($SelfTest) {
    if ($failures.Count -gt 0) {
        Write-Host 'Self-test aborted: the real manifests must pass first:' -ForegroundColor Red
        foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
        exit 1
    }
    Write-Host ''
    Write-Host 'Self-test: the gate must fail on each unsafe state' -ForegroundColor Cyan
    $script:stFailures = 0
    $script:stChecks = 0
    $stTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dep-overrides-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stTmp -Force | Out-Null

    # Synthetic audit reports: the self-test must not need the network, and a
    # hit has to be shaped like the real thing so the parser is exercised.
    $cleanAudit = '{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}'
    $hitAudit = '{"auditReportVersion":2,"vulnerabilities":{"undici":{"name":"undici","severity":"high","isDirect":false,' +
    '"via":[{"source":1,"name":"undici","dependency":"undici","title":"DoS via unhandled error on excessive content-encodings",' +
    '"url":"https://github.com/advisories/GHSA-xjj6-f33q-929c","severity":"high","range":">= 8.0.0, < 8.12.2"}],' +
    '"effects":["disk"],"range":">= 8.0.0, < 8.12.2","nodes":["node_modules/undici"],' +
    '"fixAvailable":{"name":"undici","version":"8.12.2","isSemVerMajor":false}}},' +
    '"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":1,"critical":0,"total":1}}}'
    $brokenAudit = '{"error":{"code":"ENETUNREACH","summary":"network down"}}'
    $cleanAuditPath = Join-Path $stTmp 'audit-clean.json'
    $hitAuditPath = Join-Path $stTmp 'audit-hit.json'
    $brokenAuditPath = Join-Path $stTmp 'audit-broken.json'
    [System.IO.File]::WriteAllText($cleanAuditPath, $cleanAudit)
    [System.IO.File]::WriteAllText($hitAuditPath, $hitAudit)
    [System.IO.File]::WriteAllText($brokenAuditPath, $brokenAudit)

    # Probe package/version for the mutations: whatever the first override is.
    if ($overrides.Count -eq 0) {
        Write-Host 'Self-test aborted: package.json has no overrides to mutate.' -ForegroundColor Red
        Remove-Item -LiteralPath $stTmp -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }
    $probe = [string]@($overrides.Keys)[0]
    $probeFloor = Get-FloorFromSpec -Spec ([string]$overrides[$probe])
    $belowParts = @(ConvertTo-VersionParts -Version $probeFloor)
    $belowParts[$belowParts.Count - 1] = $belowParts[$belowParts.Count - 1] - 1
    $script:stProbe = $probe
    $script:stProbeBelow = ($belowParts -join '.')

    function Invoke-OverrideCheck {
        param([string]$Name, [string]$AuditFile, [scriptblock]$Mutate, [switch]$ExpectFail, [string]$MessageMustMatch = '')
        $script:stChecks++
        $p = Join-Path $stTmp ("pkg-$Name.json")
        $l = Join-Path $stTmp ("lock-$Name.json")
        Copy-Item -LiteralPath $PackagePath -Destination $p -Force
        Copy-Item -LiteralPath $LockPath -Destination $l -Force
        $beforeP = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        $beforeL = (Get-FileHash -LiteralPath $l -Algorithm SHA256).Hash
        if ($Mutate) { & $Mutate $p $l }
        # A mutation that matched nothing would pass every "expect fail" case
        # for the wrong reason, so an unchanged fixture is a self-test failure.
        if ($ExpectFail -and $Mutate -and
            (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -eq $beforeP -and
            (Get-FileHash -LiteralPath $l -Algorithm SHA256).Hash -eq $beforeL) {
            Write-Host "  [FAIL] $Name (mutation changed nothing)" -ForegroundColor Red
            $script:stFailures++
            return
        }
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -PackagePath $p -LockPath $l -AuditJson $AuditFile 2>&1) | Out-String
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
            Write-Host ($out.Trim() -replace '(?m)^', '         ') -ForegroundColor DarkGray
            $script:stFailures++
        }
    }

    # 1. sanity: untouched manifests and a clean report pass
    Invoke-OverrideCheck -Name 'clean manifests pass' -AuditFile $cleanAuditPath

    # 2. a new advisory the repo never saw (no table to update, must still fail)
    Invoke-OverrideCheck -Name 'new advisory fails' -AuditFile $hitAuditPath -ExpectFail -MessageMustMatch 'undici: high vulnerability: DoS via unhandled error'

    # 3. the report names the version to override to
    Invoke-OverrideCheck -Name 'reports the patched version' -AuditFile $hitAuditPath -ExpectFail -MessageMustMatch 'resolves >= 8\.12\.2'

    # 4. an unreadable audit report is "could not check", not green
    Invoke-OverrideCheck -Name 'unreadable audit fails closed' -AuditFile $brokenAuditPath -ExpectFail -MessageMustMatch 'did not return a "vulnerabilities" block'

    # 5. an override that is a range, not a floor, cannot be checked
    Invoke-OverrideCheck -Name 'range override rejected' -AuditFile $cleanAuditPath -ExpectFail -MessageMustMatch 'not a single version floor' -Mutate {
        param($p, $l)
        $t = Get-Content -LiteralPath $p -Raw
        $t = [regex]::Replace($t, '("' + [regex]::Escape($script:stProbe) + '"\s*:\s*)"[^"]*"', '$1">=8.0.0 <9"')
        [System.IO.File]::WriteAllText($p, $t)
    }

    # 6. lockfile below the override floor (override added, install not run)
    Invoke-OverrideCheck -Name 'lockfile below floor' -AuditFile $cleanAuditPath -ExpectFail -MessageMustMatch 'below the override floor' -Mutate {
        param($p, $l)
        $t = Get-Content -LiteralPath $l -Raw
        $t = [regex]::Replace($t, '("node_modules/' + [regex]::Escape($script:stProbe) + '":\s*\{\s*"version":\s*)"[^"]*"', ('$1"' + $script:stProbeBelow + '"'))
        [System.IO.File]::WriteAllText($l, $t)
    }

    # 7. a nested copy surviving under a parent - the override did not apply
    Invoke-OverrideCheck -Name 'nested copy below floor' -AuditFile $cleanAuditPath -ExpectFail -MessageMustMatch 'below the override floor' -Mutate {
        param($p, $l)
        $obj = ConvertFrom-JsonDictionary -Text (Get-Content -LiteralPath $l -Raw -Encoding UTF8)
        $obj['packages']['node_modules/some-parent/node_modules/' + $script:stProbe] = [ordered]@{
            name = $script:stProbe; version = $script:stProbeBelow
        }
        [System.IO.File]::WriteAllText($l, ($obj | ConvertTo-Json -Depth 100 -Compress))
    }

    # 8. the real regression shape: override gone AND the tree regressed to the
    #    vulnerable version. The advisory layer is what catches it - no table.
    Invoke-OverrideCheck -Name 'override removed, tree regressed' -AuditFile $hitAuditPath -ExpectFail -MessageMustMatch 'undici: high vulnerability' -Mutate {
        param($p, $l)
        $t = Get-Content -LiteralPath $p -Raw
        $t = [regex]::Replace($t, '\s*"' + [regex]::Escape($script:stProbe) + '"\s*:\s*"[^"]*"\s*,?', '')
        [System.IO.File]::WriteAllText($p, $t)
        $raw = Get-Content -LiteralPath $l -Raw
        $raw = [regex]::Replace($raw, '("node_modules/' + [regex]::Escape($script:stProbe) + '":\s*\{\s*"version":\s*)"[^"]*"', ('$1"' + $script:stProbeBelow + '"'))
        [System.IO.File]::WriteAllText($l, $raw)
    }

    Remove-Item -LiteralPath $stTmp -Recurse -Force -ErrorAction SilentlyContinue

    if ($script:stFailures -gt 0) {
        Write-Host ("Self-test FAILED ({0} failure(s))." -f $script:stFailures) -ForegroundColor Red
        exit 1
    }
    Write-Host ("Self-test passed: {0}/{0} scenarios." -f $script:stChecks) -ForegroundColor Green
    exit 0
}

# ── verdict ───────────────────────────────────────────────────────────────
if ($failures.Count -gt 0) {
    Write-Host 'Dependency tree is NOT clean:' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Fix: add or raise the override in package.json, run `npm install` so package-lock.json' -ForegroundColor Yellow
    Write-Host '     resolves the patched version, and commit package.json + package-lock.json together.' -ForegroundColor Yellow
    exit 1
}

$auditState = if ($auditChecked) { 'advisory scan clean' } else { 'advisory scan skipped' }
Write-Host ("Dependency gate OK ({0}): {1} check(s) passed." -f $auditState, $checked.Count) -ForegroundColor Green
foreach ($c in $checked) { Write-Host "  $c" -ForegroundColor DarkGray }
exit 0
