#requires -Version 5.1
# Installed-copy smoke test.
#
# WHY: the repo-side checks answer "is the source tree consistent?", but a user
# runs an INSTALLED copy (a release ZIP unpacked somewhere, e.g. C:\test).
# After a self-update that copy can drift in ways nothing here caught:
#   - .version says the new tag while $scriptVer inside mumu-menu.ps1 still
#     holds the old one (a half-applied update),
#   - the version sources agree but the [RL] screen / release assets for that
#     tag do not exist or are unreadable,
#   - the archive on the remote is fine for GitHub but the installed copy
#     cannot verify it (missing bootstrap-update.ps1, wrong file set).
# This script drives the REAL code from the target directory - the [RL] screen
# functions and the bootstrap verifier are extracted/executed from the copy
# under test via AST, never re-implemented - so a green run means that exact
# install reports, lists and verifies its own version.
#
# What it checks:
#   S1. Version sources agree: mumu-menu.ps1 $scriptVer == .version == the
#       top "### vX.Y.Z" heading of README.md (the release/ZIP tag).
#   S2. [RL] lists the current tag: the target copy's own Show-ReleaseList
#       renders the release list and the FIRST row is the installed tag.
#       Uses the saved DPAPI token when present (same loader the menu uses) or
#       $env:GITHUB_TOKEN in CI; anonymous GitHub is 60 req/h and is routinely
#       exhausted.
#       -PreRelease (CI gate use): the tag under test is not published yet -
#       the screen must still render, and either the tag is already listed or
#       the newest published tag is OLDER than it (a release in flight). A
#       published tag NEWER than the install is a real failure: that copy lags.
#   S3. bootstrap verifies the release ZIP: the target copy's own
#       bootstrap-update.ps1 -VerifyZip accepts the published archive
#       (sha256 sidecar + 9-file set + scriptVer) for the installed tag.
#       With -PreRelease nothing is downloaded (the asset does not exist yet);
#       pass -ZipPath with an archive built from the checkout instead.
#
# Network-dependent steps (S2, S3 download) report SKIP instead of FAIL when
# the environment cannot reach GitHub - a rate limit is not a broken install.
# Pass -RequireNetwork to turn those skips into a non-zero exit (CI use).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tests\test-installed-smoke.ps1
#   powershell -ExecutionPolicy Bypass -File tests\test-installed-smoke.ps1 -TargetDir C:\test\MuMuManager-CLI-Menu
#   powershell -ExecutionPolicy Bypass -File tests\test-installed-smoke.ps1 -TargetDir C:\test\MuMuManager-CLI-Menu -SkipNetwork
#   powershell -ExecutionPolicy Bypass -File tests\test-installed-smoke.ps1 -ZipPath .\MuMuManager-CLI-Menu-v10.4.8.zip
#   # CI / pre-release gate: the tag is not published yet, archive built locally
#   powershell -ExecutionPolicy Bypass -File tests\test-installed-smoke.ps1 -TargetDir <fixture> -ZipPath <zip> -PreRelease -RequireNetwork
#
# Exit codes: 0 = all checks passed (skips allowed), 1 = failure,
#             2 = -RequireNetwork and a network check was skipped.
#
# CI: .github/workflows/tests.yml job "installed-smoke" (both engines, against
# an installed-layout fixture, -PreRelease -RequireNetwork). That leg is listed
# in REQUIRED_LEGS in release.yml, so a red run here blocks publishing.

param(
    # Installed copy to verify. Defaults to this checkout, which holds the
    # same deployed file set as an install.
    [string]$TargetDir = '',
    # Expected tag (vX.Y.Z). Empty = take it from the copy's .version.
    [string]$Tag = '',
    # Verify this archive instead of downloading the published one. The
    # ".sha256" sidecar must sit next to it (bootstrap's own contract).
    [string]$ZipPath = '',
    # Skip every network step (offline run: S1 only).
    [switch]$SkipNetwork,
    # A network skip counts as a failure (CI gate).
    [switch]$RequireNetwork,
    # The tag under test has no published release yet (the Release workflow
    # runs this before it builds the assets). Relaxes S2's "newest row is the
    # installed tag" to "the tag is listed, or the newest published one is
    # older" and makes S3 require -ZipPath instead of downloading.
    [switch]$PreRelease
)

$ErrorActionPreference = 'Stop'

if (-not $TargetDir) { $TargetDir = Split-Path -Parent $PSScriptRoot }
$TargetDir = (Resolve-Path -LiteralPath $TargetDir).Path

$script:failures = 0
$script:skips    = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host ("  [PASS] {0}" -f $Name) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0}  {1}" -f $Name, $Detail) -ForegroundColor Red
        $script:failures++
    }
}

function Skip-Check {
    param([string]$Name, [string]$Reason)
    Write-Host ("  [SKIP] {0}  {1}" -f $Name, $Reason) -ForegroundColor Yellow
    $script:skips++
}

function Read-TextFile {
    # Byte-exact read: Get-Content -Raw decodes with the console codepage on
    # PS 5.1 and mangles the Cyrillic README/relnotes text we parse below.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
}

function Test-TagOlder {
    # True when $Older is a strictly older version than $Newer ('v1.2.3' or
    # '1.2.3'). Unparseable tags answer $false: an unknown tag is never
    # evidence of an in-flight release.
    param([string]$Older, [string]$Newer)
    try {
        $a = [version]($Older.TrimStart('v'))
        $b = [version]($Newer.TrimStart('v'))
        return ($a -lt $b)
    } catch {
        return $false
    }
}

$menuPath     = Join-Path $TargetDir 'mumu-menu.ps1'
$versionPath  = Join-Path $TargetDir '.version'
$readmePath   = Join-Path $TargetDir 'README.md'
$bootstrapPath = Join-Path $TargetDir 'bootstrap-update.ps1'

Write-Host ''
Write-Host ('=== Installed-copy smoke: {0} ===' -f $TargetDir) -ForegroundColor Cyan

# The engine that runs the child bootstrap/zip verification: the same edition
# this script runs on, so a 5.1 run stays a 5.1 run.
$engineExe = Join-Path $PSHOME 'powershell.exe'
if ($PSVersionTable.PSEdition -ne 'Desktop') { $engineExe = Join-Path $PSHOME 'pwsh.exe' }
if (-not (Test-Path -LiteralPath $engineExe -PathType Leaf)) { $engineExe = 'powershell.exe' }

# ── S1: the three version sources agree ─────────────────────────────
Write-Host 'S1: version sources agree (scriptVer / .version / README heading)' -ForegroundColor Cyan

$menuText = Read-TextFile -Path $menuPath
$scriptVer = ''
$mVer = [regex]::Match($menuText, "(?m)^\s*\`$scriptVer\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'")
if ($mVer.Success) { $scriptVer = $mVer.Groups[1].Value }

$versionRaw = (Read-TextFile -Path $versionPath).Trim()
$readmeText = Read-TextFile -Path $readmePath
# Top heading of the «Что нового» block - the same anchor test-changelog-sync
# uses, so both checks agree on what "the released version" means.
$readmeTag = ''
$mRd = [regex]::Match($readmeText, '(?m)^###\s+(v[0-9]+\.[0-9]+\.[0-9]+)(\s|$)')
if ($mRd.Success) { $readmeTag = $mRd.Groups[1].Value }

Assert-True -Name 'mumu-menu.ps1 is present and exposes $scriptVer' -Condition ($scriptVer -ne '') -Detail "no \$scriptVer in $menuPath"
Assert-True -Name '.version marker is present and well formed' -Condition ($versionRaw -match '^v[0-9]+\.[0-9]+\.[0-9]+$') -Detail "got '$versionRaw' in $versionPath"
Assert-True -Name 'README.md has a «Что нового» heading' -Condition ($readmeTag -ne '') -Detail 'no ### vX.Y.Z heading found'

if (-not $Tag) { $Tag = $versionRaw }
Assert-True -Name '.version equals the requested tag' -Condition ($versionRaw -eq $Tag) -Detail "marker=$versionRaw requested=$Tag"
Assert-True -Name 'scriptVer matches .version' -Condition ($scriptVer -eq $versionRaw.TrimStart('v')) -Detail "scriptVer=$scriptVer .version=$versionRaw"
Assert-True -Name 'README heading matches .version' -Condition ($readmeTag -eq $versionRaw) -Detail "README=$readmeTag .version=$versionRaw"

if ($Tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') {
    Write-Host "  [FAIL] cannot continue without a valid tag (got '$Tag')" -ForegroundColor Red
    $script:failures++
}

# Release repository, read from the copy under test - a fork install must
# verify ITS own releases, not this repo's hard-coded default.
$repo = 'genrihx2/MuMuManager-CLI-Menu'
$mRepo = [regex]::Match($menuText, "(?m)^\`$GitHubRepo\s*=\s*'([^']+)'")
if ($mRepo.Success) { $repo = $mRepo.Groups[1].Value }
Write-Host ('  (repository: {0}, tag: {1})' -f $repo, $Tag) -ForegroundColor DarkGray

# ── S2: [RL] lists the installed tag ────────────────────────────────
Write-Host 'S2: [RL] lists the installed tag' -ForegroundColor Cyan

# Runner for the real [RL] screen, written to scratch space and executed by
# the SAME engine this script runs on. It extracts the production functions
# out of the copy under test (the technique tests/mumu-menu.Tests.ps1 uses),
# so the screen and its transport are the installed code - not a copy that
# could drift. stdin supplies the single "0" its closing Read-Host wants.
$harnessText = @'
param(
    [string]$MenuPath,
    [string]$Repo,
    [string]$TargetDir
)

$ErrorActionPreference = 'Stop'
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($MenuPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count) {
    Write-Output ('SMOKE-ERROR: ' + $parseErrors[0].Message)
    exit 3
}

$need = @(
    'Show-ReleaseList', 'Write-ScreenFrame', 'Write-ScreenNote', 'Write-MenuGroup',
    'Write-KeyValue', 'Split-MenuWrappedText', 'Invoke-GitHubApiGet', 'Get-CurlGitHubArgs',
    'Invoke-CurlUtf8', 'ConvertFrom-SecureToken', 'Get-GitHubToken', 'Initialize-TokenStorage'
)
foreach ($name in $need) {
    $fn = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true) | Select-Object -First 1
    if (-not $fn) {
        Write-Output ('SMOKE-ERROR: missing function ' + $name)
        exit 3
    }
    . ([scriptblock]::Create($fn.Extent.Text))
}

# State the extracted functions read, pointed at the copy under test so the
# saved token is the one that copy would use.
$GitHubRepo = $Repo
$DpapiTokenFile = Join-Path $TargetDir '.github-token.dpapi'
$TokenFile = Join-Path $TargetDir '.github-token'
$script:CurlRetryArgs = @('--retry', '3', '--retry-delay', '2')
$script:GitHubToken = Get-GitHubToken
$authSource = 'dpapi'
if (-not $script:GitHubToken -and $env:GITHUB_TOKEN) {
    # CI runner: no DPAPI store on a fresh machine, the workflow token is
    # the same-repo identity the other harnesses use.
    $script:GitHubToken = $env:GITHUB_TOKEN
    $authSource = 'env'
}
if ($script:GitHubToken) { Write-Output ('SMOKE-AUTH: ' + $authSource) } else { Write-Output 'SMOKE-AUTH: anonymous' }

Show-ReleaseList
exit 0
'@

$rlName = '[RL] Show-ReleaseList'
if ($SkipNetwork) {
    Skip-Check -Name $rlName -Reason '-SkipNetwork'
} elseif (-not (Test-Path -LiteralPath $menuPath -PathType Leaf)) {
    Assert-True -Name $rlName -Condition $false -Detail 'mumu-menu.ps1 missing'
} else {
    # Extract the production functions out of the copy under test (the same
    # technique tests/mumu-menu.Tests.ps1 uses) - no copied logic that could
    # drift from the code the user actually runs.
    $parseErrors = $null
    $rlAst = [System.Management.Automation.Language.Parser]::ParseFile($menuPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count) {
        Assert-True -Name $rlName -Condition $false -Detail ('mumu-menu.ps1 has syntax errors: ' + $parseErrors[0].Message)
    } else {
        $need = @(
            'Show-ReleaseList', 'Write-ScreenFrame', 'Write-ScreenNote', 'Write-MenuGroup',
            'Write-KeyValue', 'Split-MenuWrappedText', 'Invoke-GitHubApiGet', 'Get-CurlGitHubArgs',
            'Invoke-CurlUtf8', 'ConvertFrom-SecureToken', 'Get-GitHubToken', 'Initialize-TokenStorage'
        )
        $missing = @()
        foreach ($name in $need) {
            $fn = $rlAst.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
                }, $true) | Select-Object -First 1
            if (-not $fn) { $missing += $name }
        }
        Assert-True -Name 'the [RL] screen and its transport exist in this copy' -Condition ($missing.Count -eq 0) -Detail ('missing: ' + ($missing -join ', '))

        if ($missing.Count -eq 0) {
            # The screen runs in a CHILD process, fed one "0" on stdin for its
            # closing Read-Host 'Select'. Driving the real prompt beats
            # shadowing Read-Host/Start-Sleep with local functions: overriding
            # a built-in cmdlet is a PSScriptAnalyzer warning
            # (PSAvoidOverwritingBuiltInCmdlets) and, in the menu's own history,
            # a crash source for Invoke-ScriptAnalyzer in CI. The child keeps
            # the extracted functions out of this script's scope too.
            $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('mumu-smoke-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $scratch -Force | Out-Null
            $harnessPath = Join-Path $scratch 'rl-harness.ps1'
            [System.IO.File]::WriteAllText($harnessPath, $harnessText, (New-Object System.Text.UTF8Encoding($false)))
            try {
                $rlOut = ('0' | & $engineExe -NoProfile -ExecutionPolicy Bypass -File $harnessPath -MenuPath $menuPath -Repo $repo -TargetDir $TargetDir 2>&1 | Out-String)
            } finally {
                Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
            }

            $tokenState = 'anonymous'
            if ($rlOut -match 'SMOKE-AUTH: dpapi') { $tokenState = 'saved token' }
            elseif ($rlOut -match 'SMOKE-AUTH: env') { $tokenState = 'GITHUB_TOKEN (CI)' }
            Write-Host ('  (auth: {0})' -f $tokenState) -ForegroundColor DarkGray

            if ($rlOut -match 'SMOKE-ERROR: (.+)') {
                Assert-True -Name $rlName -Condition $false -Detail ('the screen could not start: ' + $Matches[1].Trim())
            } elseif ($rlOut -match 'cannot list releases') {
                $why = 'empty response'
                $mWhy = [regex]::Match($rlOut, 'cannot list releases - (.+)')
                if ($mWhy.Success) { $why = $mWhy.Groups[1].Value.Trim() }
                Skip-Check -Name $rlName -Reason ('GitHub unreachable/rate-limited: ' + $why)
            } else {
                Assert-True -Name 'the release list rendered' -Condition ($rlOut -match '\(total:\s*\d+ release') -Detail 'no release count line in the output'
                # The screen sorts by published_at descending: row 1 is the
                # newest published tag.
                $mTag = [regex]::Match($rlOut, '(?m)^\s*Tag\s+(\S+)\s*$')
                $topTag = ''
                if ($mTag.Success) { $topTag = $mTag.Groups[1].Value }

                if ($rlOut.Contains($Tag)) {
                    Assert-True -Name ('the list contains ' + $Tag) -Condition $true
                    if (-not $PreRelease) {
                        Assert-True -Name ('the newest listed release is ' + $Tag) -Condition ($topTag -eq $Tag) -Detail ("newest row is '$topTag'")
                    }
                } elseif ($PreRelease -and (Test-TagOlder -Older $topTag -Newer $Tag)) {
                    # Bump in flight: the gate runs before the asset exists.
                    Write-Host ("  [PASS] {0} is not published yet (newest published is {1}) - pre-release run" -f $Tag, $topTag) -ForegroundColor Green
                } elseif ($PreRelease) {
                    Assert-True -Name ('the list contains ' + $Tag) -Condition $false -Detail ("tag absent and the newest published row is '$topTag' - that is not an in-flight release, the installed copy is stale")
                } else {
                    Assert-True -Name ('the list contains ' + $Tag) -Condition $false -Detail ("tag absent; newest row is '$topTag'")
                }
            }
        }
    }
}

# ── S3: bootstrap verifies the published release ZIP ────────────────
Write-Host 'S3: bootstrap verifies the release ZIP for this tag' -ForegroundColor Cyan

$verifyName = 'bootstrap-update.ps1 -VerifyZip'
$zipFull = ''
$tempDir = ''
if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    Assert-True -Name $verifyName -Condition $false -Detail 'bootstrap-update.ps1 missing from the installed copy'
} elseif ($ZipPath) {
    $zipFull = (Resolve-Path -LiteralPath $ZipPath).Path
} elseif ($SkipNetwork -or $PreRelease) {
    $why = '-SkipNetwork'
    if ($PreRelease -and -not $SkipNetwork) { $why = '-PreRelease (the release asset does not exist before publishing; pass -ZipPath to verify a locally built archive)' }
    Skip-Check -Name $verifyName -Reason $why
} else {
    # Pull the published archive and its sidecar into a scratch dir so the
    # verifier sees exactly what a user's [U]/bootstrap download sees.
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('mumu-smoke-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $asset = 'MuMuManager-CLI-Menu-' + $Tag + '.zip'
    $baseUrl = 'https://github.com/' + $repo + '/releases/download/' + $Tag + '/'
    $zipFull = Join-Path $tempDir $asset
    try {
        # PS 5.1 defaults to SSL3/TLS1.0 for .NET web calls and GitHub refuses
        # them - the same explicit opt-in the menu and bootstrap carry.
        [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12) # DevSkim: ignore DS440020,DS440001 - PS 5.1 requires an explicit TLS 1.2 opt-in
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri ($baseUrl + $asset) -OutFile $zipFull -UseBasicParsing -TimeoutSec 120
        Invoke-WebRequest -Uri ($baseUrl + $asset + '.sha256') -OutFile ($zipFull + '.sha256') -UseBasicParsing -TimeoutSec 60
    } catch {
        Skip-Check -Name $verifyName -Reason ('download failed: ' + $_.Exception.Message)
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        $zipFull = ''
        $tempDir = ''
    }
}

if ($zipFull) {
    try {
        $sidecar = $zipFull + '.sha256'
        Assert-True -Name 'a .sha256 sidecar sits next to the archive' -Condition (Test-Path -LiteralPath $sidecar -PathType Leaf) -Detail ("missing $sidecar")

        $bootOut = & $engineExe -NoProfile -ExecutionPolicy Bypass -File $bootstrapPath -VerifyZip $zipFull -ZipTag $Tag -NoAuth 2>&1
        $bootText = ($bootOut | Out-String)
        $bootCode = $LASTEXITCODE
        Write-Host $bootText.TrimEnd() -ForegroundColor DarkGray

        Assert-True -Name 'bootstrap exits 0' -Condition ($bootCode -eq 0) -Detail ("exit $bootCode")
        Assert-True -Name 'sha256 matches the sidecar' -Condition ($bootText -match 'sha256:\s*OK') -Detail 'sha256 not OK'
        Assert-True -Name 'the archive carries the full file set' -Condition ($bootText -match 'file set:\s*OK') -Detail 'file set not OK'
        Assert-True -Name 'scriptVer inside the archive matches the tag' -Condition ($bootText -match 'scriptVer:\s*OK') -Detail 'scriptVer not OK'
        Assert-True -Name 'the archive is accepted (ZIP: OK)' -Condition ($bootText -match 'ZIP:\s*OK') -Detail 'archive rejected'
    } finally {
        if ($tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ── summary ────────────────────────────────────────────────────────
Write-Host ''
if ($script:failures -gt 0) {
    Write-Host ("Smoke test FAILED ({0} failure(s), {1} skip(s))." -f $script:failures, $script:skips) -ForegroundColor Red
    exit 1
}
if ($script:skips -gt 0) {
    Write-Host ("Smoke test passed with {0} skipped network check(s)." -f $script:skips) -ForegroundColor Yellow
    if ($RequireNetwork) {
        Write-Host 'Required network checks were skipped (-RequireNetwork).' -ForegroundColor Red
        exit 2
    }
    exit 0
}
Write-Host 'All installed-copy smoke checks passed.' -ForegroundColor Green
exit 0
