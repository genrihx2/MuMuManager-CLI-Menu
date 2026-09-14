# Regression tests for the JSON-metadata detector in bootstrap-update.ps1.
#
# Background: bootstrap-update.ps1 and the [U] updater used to reject every
# download of mumu-menu.ps1 with "Received JSON metadata instead of raw file",
# because the JSON checks matched patterns ANYWHERE in the body - and
# mumu-menu.ps1 legitimately contains "name": / _links literals inside its own
# API-response validation code. Since v1.18.8 the checks apply only when the
# body actually starts with '{'.
#
# What this test does:
#   T1. Downloads mumu-menu.ps1 from the real GitHub contents API through the
#       REAL Download-File function (extracted from bootstrap-update.ps1 via
#       AST - no copied detector logic that could drift from production).
#       The download must succeed and the content must be the valid script.
#   T2. Feeds Download-File a deterministic GitHub-style JSON metadata body
#       (via a local file:// URL, so no network flakiness) - must be rejected.
#   T3. Feeds it a "Bad credentials" JSON body with a token configured -
#       must be rejected after the without-auth retry.
#   T4. Informational: verifies the OLD unguarded regexes would still flag
#       the raw script (i.e. the test data really is the regression case).
#   T5. Journal writer: Write-UpdateJournal emits one tab-separated event
#       per call, sanitizes tabs/newlines, and marks failures detectably.
#   T6. Updater self-refresh (issue #21): both updaters' file lists include
#       bootstrap-update.ps1, and Apply-PendingUpdater swaps in the .new
#       copy, removes it and journals the updater-refresh event.
#
# Run locally:
#   powershell -ExecutionPolicy Bypass -File tests\test-bootstrap-update.ps1
# CI: .github/workflows/tests.yml (windows-latest).

#requires -Version 5.1

param(
    [string]$Repo = 'genrihx2/MuMuManager-CLI-Menu',
    [string]$Ref  = 'main'
)

$ErrorActionPreference = 'Stop'
$script:failures = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host ("  [PASS] {0}" -f $Name) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0}  {1}" -f $Name, $Detail) -ForegroundColor Red
        $script:failures++
    }
}

# ── Locate and parse bootstrap-update.ps1 ────────────────────────────
$root      = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $root 'bootstrap-update.ps1'
if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) { throw "Not found: $bootstrap" }

$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrap, [ref]$null, [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count) {
    throw "bootstrap-update.ps1 has syntax errors: $($parseErrors[0].Message)"
}

$fn = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Download-File'
}, $true) | Select-Object -First 1
if (-not $fn) { throw 'Download-File function not found in bootstrap-update.ps1' }

# Dot-source the real function into this script's scope.
. ([scriptblock]::Create($fn.Extent.Text))

# Production-equivalent environment for the extracted function.
# GITHUB_TOKEN: on shared CI runners the anonymous 60 req/hr GitHub quota is
# routinely exhausted by other tenants, so T1's live-API download fails with
# size 0. The workflow passes its own token; locally the variable is usually
# unset (anonymous) or may point to any valid PAT.
$maxRetries = 2
$retryDelay = 1
$ciToken = $env:GITHUB_TOKEN
if ($ciToken) {
    $token = $ciToken
    Write-Host 'T1 auth: using GITHUB_TOKEN from environment' -ForegroundColor DarkGray
} else {
    $token = $null   # public API; anonymous is fine from residential IPs
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('bsreg-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    # ── T1: real download through the production function ────────────
    Write-Host "T1: Download-File against real API ($Repo @ $Ref)" -ForegroundColor Cyan
    $dest1 = Join-Path $tmp 'mumu-menu.ps1'
    $url1  = "https://api.github.com/repos/$Repo/contents/mumu-menu.ps1?ref=$Ref"
    $size1 = Download-File $url1 $dest1
    Assert-True -Name 'raw mumu-menu.ps1 accepted (not flagged as JSON)' -Condition ($size1 -gt 100000) -Detail "returned size: $size1"

    if ($size1 -gt 0) {
        $parseErrors1 = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($dest1, [ref]$null, [ref]$parseErrors1)
        Assert-True -Name 'downloaded file parses as PowerShell' -Condition (-not ($parseErrors1 -and $parseErrors1.Count)) -Detail "parse error: $($parseErrors1[0].Message)"

        $full1 = [System.IO.File]::ReadAllText($dest1)
        Assert-True -Name 'downloaded content looks like the menu script' -Condition (($full1 -match "scriptVer\s*=\s*'[\d\.]+'") -and ($full1 -match 'function Show-Menu')) -Detail 'scriptVer/Show-Menu not found in content'

        # T4 (informational): the OLD unguarded detector would flag this body.
        $oldBody = [System.IO.File]::ReadAllText($dest1)
        $oldWouldFlag = (($oldBody -match '"name"\s*:\s*"') -and ($oldBody -match '_links'))
        Write-Host ("  [INFO] old unguarded detector would flag this raw file: {0}" -f $oldWouldFlag) -ForegroundColor DarkGray
    }

    # ── T2: JSON metadata must be rejected (deterministic 200 via file://) ──
    Write-Host 'T2: GitHub-style JSON metadata must be rejected' -ForegroundColor Cyan
    $metaFile = Join-Path $tmp 'metadata.json'
    @'
{
  "name": "mumu-menu.ps1",
  "path": "mumu-menu.ps1",
  "sha": "e5f3b5b0f8f9d7c2a1b0e9d8c7b6a5f4e3d2c1b0",
  "size": 272557,
  "encoding": "base64",
  "content": "I3JlcXVpcmVzIC0tIHZlcnNpb24gNS4x...",
  "_links": {
    "self": "https://api.github.com/repos/x/y/contents/mumu-menu.ps1",
    "git": "https://api.github.com/repos/x/y/git/blobs/e5f3b5b0",
    "html": "https://github.com/x/y/blob/main/mumu-menu.ps1"
  }
}
'@ | Set-Content -LiteralPath $metaFile -Encoding ASCII
    $metaUrl = 'file:///' + ($metaFile -replace '\\', '/')
    $size2 = Download-File $metaUrl (Join-Path $tmp 't2-out.ps1')
    Assert-True -Name 'JSON metadata body rejected (returns 0)' -Condition ($size2 -eq 0) -Detail "returned size: $size2"
    Assert-True -Name 'no output file left behind for rejected body' -Condition (-not (Test-Path -LiteralPath (Join-Path $tmp 't2-out.ps1'))) -Detail 't2-out.ps1 exists'

    # ── T3: "Bad credentials" JSON must be rejected (with token set) ──
    Write-Host 'T3: Bad-credentials JSON must be rejected' -ForegroundColor Cyan
    $credsFile = Join-Path $tmp 'badcreds.json'
    '{"message":"Bad credentials","documentation_url":"https://docs.github.com/graphql"}' |
        Set-Content -LiteralPath $credsFile -Encoding ASCII
    $credsUrl = 'file:///' + ($credsFile -replace '\\', '/')
    $token  = 'ghp_faketoken0000000000000000000000000000'   # exercise the auth path
    $size3  = Download-File $credsUrl (Join-Path $tmp 't3-out.ps1')
    $token  = $null
    Assert-True -Name 'bad-credentials JSON rejected (returns 0)' -Condition ($size3 -eq 0) -Detail "returned size: $size3"

    # ── T5: journal writer (Write-UpdateJournal) — format + sanitization ──
    Write-Host 'T5: Update journal writer must emit well-formed events' -ForegroundColor Cyan
    $jfn = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-UpdateJournal'
    }, $true) | Select-Object -First 1
    if (-not $jfn) { throw 'Write-UpdateJournal function not found in bootstrap-update.ps1' }
    . ([scriptblock]::Create($jfn.Extent.Text))
    $journalFile = Join-Path $tmp 'update-journal.log'
    Write-UpdateJournal -EventType 'update-ok' -From 'v1.19.0' -To 'v1.19.1' -Detail "mumu-menu.ps1=260.0 KB`tSKILL.md=4.0 KB"
    Write-UpdateJournal -EventType 'update-fail' -From 'v1.19.1' -To 'v1.19.2' -Detail "1 ok, 2 failed`nmumu-menu.ps1 FAILED"
    $jLines = @(Get-Content -LiteralPath $journalFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    Assert-True -Name 'journal file created with one line per event' -Condition ($jLines.Count -eq 2) -Detail "lines: $($jLines.Count)"
    $wellFormed = $true
    foreach ($jl in $jLines) {
        if ((($jl -split "`t").Count -lt 6) -or ($jl -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\t')) { $wellFormed = $false }
    }
    Assert-True -Name 'every event has timestamp + 6 tab-separated fields' -Condition $wellFormed -Detail ($jLines -join ' / ')
    Assert-True -Name 'tabs/newlines in detail are sanitized to spaces' -Condition (-not ($jLines | Where-Object { ($_ -split "`t")[5] -match "[\t\r\n]" })) -Detail 'raw control chars found in detail column'
    Assert-True -Name 'fail event is detectable by viewers (event column contains fail)' -Condition (@($jLines | Where-Object { (($_ -split "`t")[2]) -match 'fail' }).Count -eq 1) -Detail 'no fail-marker line'

    # ── T6: updater self-refresh (#21) — file lists + Apply-PendingUpdater ──
    Write-Host 'T6: updater self-refresh must include bootstrap-update.ps1 in both updaters' -ForegroundColor Cyan
    # The updater is the one file an update could never fix - both file lists
    # must now include it (issue #21).
    $arrayAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.ArrayLiteralAst]
    }, $true)
    $bootHasUpdater = @($arrayAsts | Where-Object {
        ($_.Elements.Value -contains 'bootstrap-update.ps1') -and
        ($_.Elements.Value -contains 'mumu-menu.ps1')
    }).Count -gt 0
    Assert-True -Name 'bootstrap-update.ps1 file list contains itself' -Condition $bootHasUpdater -Detail 'no array literal with mumu-menu.ps1 + SKILL.md + bootstrap-update.ps1 found'

    $menuPath = Join-Path $root 'mumu-menu.ps1'
    if (Test-Path -LiteralPath $menuPath -PathType Leaf) {
        $menuErrors = $null
        $menuAst = [System.Management.Automation.Language.Parser]::ParseFile($menuPath, [ref]$null, [ref]$menuErrors)
        if (-not ($menuErrors -and $menuErrors.Count)) {
            $menuArrays = $menuAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.ArrayLiteralAst]
            }, $true)
            $menuHasUpdater = @($menuArrays | Where-Object {
                ($_.Elements.Value -contains 'bootstrap-update.ps1') -and
                ($_.Elements.Value -contains 'mumu-menu.ps1')
            }).Count -gt 0
            Assert-True -Name 'menu [U] file list contains bootstrap-update.ps1' -Condition $menuHasUpdater -Detail 'no array literal with mumu-menu.ps1 + SKILL.md + bootstrap-update.ps1 found'
        }
    }

    # Self-apply behavior: Apply-PendingUpdater must copy .new over the
    # current updater, remove the .new and journal the updater-refresh event.
    $apFn = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Apply-PendingUpdater'
    }, $true) | Select-Object -First 1
    if (-not $apFn) { throw 'Apply-PendingUpdater function not found in bootstrap-update.ps1' }
    . ([scriptblock]::Create($apFn.Extent.Text))
    $journalFile = Join-Path $tmp 'update-journal-selfrefresh.log'
    $uDir = Join-Path $tmp 'selfrefresh'
    New-Item -ItemType Directory -Path $uDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $uDir 'bootstrap-update.ps1') -Value '# old updater' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $uDir 'bootstrap-update.ps1.new') -Value '# new updater' -Encoding ASCII
    $applied = Apply-PendingUpdater -Dir $uDir -From 'v1.19.1' -To 'v1.19.2'
    Assert-True -Name 'pending updater .new applied (returns true)' -Condition ($applied -eq $true) -Detail "returned: $applied"
    Assert-True -Name '.new removed after apply' -Condition (-not (Test-Path -LiteralPath (Join-Path $uDir 'bootstrap-update.ps1.new'))) -Detail 'bootstrap-update.ps1.new still exists'
    Assert-True -Name 'updater content replaced by .new' -Condition ((Get-Content -LiteralPath (Join-Path $uDir 'bootstrap-update.ps1') -Raw).Trim() -eq '# new updater') -Detail 'content not swapped'
    Assert-True -Name 'updater-refresh event journaled' -Condition (@(Get-Content -LiteralPath $journalFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { (($_ -split "`t")[2]) -eq 'updater-refresh' }).Count -eq 1) -Detail 'no updater-refresh line in journal'
    $noop = Apply-PendingUpdater -Dir $uDir -From 'v1.19.2' -To 'v1.19.2'
    Assert-True -Name 'no .new present - apply is a no-op (returns false)' -Condition ($noop -eq $false) -Detail "returned: $noop"

    # ── T7: drift check (#18) - Test-InstallationIntegrity vs a stubbed API ──
    Write-Host 'T7: drift check must report OK / DRIFT / MISSING per file' -ForegroundColor Cyan
    $menuPath = Join-Path $root 'mumu-menu.ps1'
    if (-not (Test-Path -LiteralPath $menuPath -PathType Leaf)) { throw 'mumu-menu.ps1 not found' }
    $mErrors = $null
    $mAst = [System.Management.Automation.Language.Parser]::ParseFile($menuPath, [ref]$null, [ref]$mErrors)
    if ($mErrors -and $mErrors.Count) { throw "mumu-menu.ps1 has syntax errors: $($mErrors[0].Message)" }
    foreach ($name in 'Test-InstallationIntegrity', 'Get-ContentHash') {
        $f = $mAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true) | Select-Object -First 1
        if (-not $f) { throw "$name function not found in mumu-menu.ps1" }
        . ([scriptblock]::Create($f.Extent.Text))
    }
    # Stub the API helper in this scope: the extracted function resolves it
    # through the scope chain at call time, so no network is touched.
    $stubContent = @{
        'mumu-menu.ps1'        = "# menu`nline2`n"
        'SKILL.md'             = "# skill`n"
        'README.md'            = "# readme`n"
        'bootstrap-update.ps1' = "# updater`n"
        '.version'             = 'v9.9.9'
    }
    function Invoke-GitHubGet {
        param([string]$Url, [int]$TimeoutSec = 30)
        if ($Url -match 'releases/latest') { return '{"tag_name":"vTest"}' }
        if ($Url -match '/contents/([^`?]+)') {
            $name = $Matches[1]
            if ($name -eq 'README.md') { throw "Request failed: $Url" }
            if ($stubContent.ContainsKey($name)) { return $stubContent[$name] }
        }
        throw "Request failed: $Url"
    }
    $vDir = Join-Path $tmp 'verify'
    New-Item -ItemType Directory -Path $vDir -Force | Out-Null
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    # Exact bytes for files that must hash-match the stub responses.
    [System.IO.File]::WriteAllText((Join-Path $vDir 'mumu-menu.ps1'), "# menu`nline2`n", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $vDir 'README.md'), "# readme`n", $utf8NoBom)
    # SKILL.md: present but different content (DRIFT case).
    [System.IO.File]::WriteAllText((Join-Path $vDir 'SKILL.md'), "# skill DRIFTED`n", $utf8NoBom)
    Set-Content -LiteralPath (Join-Path $vDir '.version') -Value 'v9.9.9' -NoNewline -Encoding UTF8
    # bootstrap-update.ps1 deliberately absent (MISSING case)
    $ScriptDir = $vDir
    $out = Test-InstallationIntegrity -Tag 'vTest' *>&1 | Out-String
    $report = Test-InstallationIntegrity -Tag 'vTest'
    Assert-True -Name 'verify-start entry with the tag' -Condition (@($report | Where-Object { $_ -eq 'verify-start|vTest' }).Count -eq 1) -Detail 'missing verify-start'
    Assert-True -Name 'matching file reported OK' -Condition (@($report | Where-Object { $_ -like 'OK|mumu-menu.ps1|*' }).Count -eq 1) -Detail ($report -join ' // ')
    Assert-True -Name 'modified file reported DRIFT with both hashes' -Condition (@($report | Where-Object { $_ -like 'DRIFT|SKILL.md|expected=*local=*' }).Count -eq 1) -Detail ($report -join ' // ')
    Assert-True -Name 'absent file reported MISSING' -Condition (@($report | Where-Object { $_ -eq 'MISSING|bootstrap-update.ps1|' }).Count -eq 1) -Detail ($report -join ' // ')
    Assert-True -Name 'unreachable file reported DOWNLOAD-FAIL (not drift)' -Condition (@($report | Where-Object { $_ -like 'DOWNLOAD-FAIL|README.md|*' }).Count -eq 1) -Detail ($report -join ' // ')
    Assert-True -Name 'current .version marker reported OK' -Condition (@($report | Where-Object { $_ -like 'OK|.version|*' }).Count -eq 1) -Detail ($report -join ' // ')
    Assert-True -Name 'summary line lists drifted+missing files' -Condition (@($report | Where-Object { $_ -eq 'summary|drift|SKILL.md,bootstrap-update.ps1' }).Count -eq 1) -Detail ($report -join ' // ')
    Assert-True -Name 'console output shows drift summary' -Condition ($out -match 'Drift detected \(files: SKILL\.md, bootstrap-update\.ps1\)') -Detail $out.Trim()
    Assert-True -Name 'stale .version marker is flagged in output' -Condition ($out -match '\.version says v9\.9\.9') -Detail $out.Trim()
    Assert-True -Name 'menu label [F] Verify installation present' -Condition ((Get-Content -LiteralPath $menuPath -Raw -Encoding UTF8) -match '\[F\]\s*Verify installation') -Detail 'label not found'
    Assert-True -Name "dispatch 'f' calls Show-InstallVerify" -Condition ((Get-Content -LiteralPath $menuPath -Raw -Encoding UTF8) -match "'f'\s*\{\s*Show-InstallVerify\s*\}") -Detail 'dispatch not found'

    # Rate-limit JSON must be detected as DOWNLOAD-FAIL, never hashed as
    # content (observed live: api.github.com intermittently answers a raw
    # request with a rate-limit body and curl exit 0).
    function script:Invoke-GitHubGet { param([string]$Url, [int]$TimeoutSec = 30) return '{"message":"API rate limit exceeded","documentation_url":"https://docs.github.com/rate_limit"}' }
    $vDir2 = Join-Path $tmp 'verify-rl'
    New-Item -ItemType Directory -Path $vDir2 -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $vDir2 'mumu-menu.ps1'), "# menu`nline2`n", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $vDir2 'SKILL.md'), "# skill`n", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $vDir2 'README.md'), "# readme`n", $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $vDir2 'bootstrap-update.ps1'), "# updater`n", $utf8NoBom)
    $ScriptDir = $vDir2
    $rlReport = Test-InstallationIntegrity -Tag 'vTest'
    Assert-True -Name 'rate-limit body reported as DOWNLOAD-FAIL, not drift' -Condition (@($rlReport | Where-Object { $_ -like 'DOWNLOAD-FAIL|mumu-menu.ps1|API error*' }).Count -eq 1) -Detail ($rlReport -join ' // ')
    Assert-True -Name 'rate-limited run ends partial, not drift' -Condition (@($rlReport | Where-Object { $_ -eq 'summary|partial|download failures' }).Count -eq 1) -Detail ($rlReport -join ' // ')
    Remove-Item -LiteralPath (Join-Path $vDir2 'mumu-menu.ps1') -Force


    $passCount = 0
    if ($script:failures -eq 0) { $passCount = 1 }
    Write-Host ''
    if ($script:failures -gt 0) {
        Write-Host "Regression tests FAILED ($script:failures failure(s))." -ForegroundColor Red
        exit 1
    }
    Write-Host 'All regression tests passed.' -ForegroundColor Green
    exit 0
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
