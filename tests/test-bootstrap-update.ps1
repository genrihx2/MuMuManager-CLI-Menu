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
#   T8. Release ZIP self-test (issue #19): Test-ReleaseZip must pass a
#       correct ZIP (sha256 + file set + scriptVer) and fail a tampered
#       ZIP, a wrong sidecar hash, a wrong scriptVer, an incomplete file
#       set and a missing archive - before anything is unpacked.
#   T9. Bootstrap post-download hash verification (parity with [U]):
#       Get-ContentHash vectors + symmetric trailing trim;
#       Get-ExpectedHashes hashes tag content via the byte-exact raw
#       fetch (OEM-codepage safe), skips rate-limit JSON bodies and
#       null responses; -NoVerify wiring is present.
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

    # Semantically equal marker spellings must NOT be flagged as stale:
    # the sync-version bot lands after the release tag, so a freshly
    # tagged release can legitimately ship the previous .version spelling
    # (observed live: tag v1.19.6 shipped .version = v1.19.5 and [F]
    # reported DRIFT for a hash-only, content-identical difference).
    $ScriptDir = $vDir
    $outEq = (Test-InstallationIntegrity -Tag 'v9.9.9' *>&1 | Out-String)
    Assert-True -Name 'semantically equal .version marker is not flagged as stale' -Condition ($outEq -notmatch '\.version says') -Detail $outEq.Trim()

    # The marker is compared SEMANTICALLY, not by bytes: when the local
    # marker is NEWER than the tag's lagged marker (tag v1.20.3 ships
    # .version = v1.20.2 while the install already says v1.20.3), the
    # byte-differing marker must not be drift (seen live on v1.20.3).
    function script:Compare-ScriptVersion { param([string]$A, [string]$B)
        $pa = @($A.TrimStart('v', 'V') -split '\.' | ForEach-Object { try { [int]$_ } catch { -1 } })
        $pb = @($B.TrimStart('v', 'V') -split '\.' | ForEach-Object { try { [int]$_ } catch { -1 } })
        if (@($pa | Where-Object { $_ -lt 0 }).Count -gt 0) { return -2 }
        if (@($pb | Where-Object { $_ -lt 0 }).Count -gt 0) { return -2 }
        for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
            $xa = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
            $xb = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
            if ($xa -lt $xb) { return -1 }
            if ($xa -gt $xb) { return 1 }
        }
        return 0
    }
    Set-Content -LiteralPath (Join-Path $vDir '.version') -Value 'v9.9.9' -NoNewline -Encoding UTF8
    $repNewer = Test-InstallationIntegrity -Tag 'v9.9.8'
    Assert-True -Name 'newer local .version marker is not drift (semantic compare)' -Condition (@($repNewer | Where-Object { $_ -like 'OK-SEMANTIC|.version|*' }).Count -eq 1) -Detail ($repNewer -join ' // ')
    Assert-True -Name 'newer-marker run does not list .version as drift' -Condition (@($repNewer | Where-Object { $_ -like 'DRIFT|.version|*' }).Count -eq 0) -Detail ($repNewer -join ' // ')
    # An UNPARSEABLE local marker still falls through to the content compare.
    Set-Content -LiteralPath (Join-Path $vDir '.version') -Value 'not-a-version' -NoNewline -Encoding UTF8
    $repJunk = Test-InstallationIntegrity -Tag 'v9.9.8'
    Assert-True -Name 'unparseable marker falls back to content compare (DRIFT)' -Condition (@($repJunk | Where-Object { $_ -like 'DRIFT|.version|*' }).Count -eq 1) -Detail ($repJunk -join ' // ')
    Set-Content -LiteralPath (Join-Path $vDir '.version') -Value 'v9.9.9' -NoNewline -Encoding UTF8
    Assert-True -Name '[F] missing ZIP path says nothing to verify (not FAILED)' -Condition ((Get-Content -LiteralPath $menuPath -Raw -Encoding UTF8) -match 'nothing to verify') -Detail 'missing-ZIP message not found'
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

    # ── T8: release ZIP self-test (#19) - Test-ReleaseZip before unpacking ──
    Write-Host 'T8: ZIP self-test must pass a correct ZIP and fail tampered/wrong ones' -ForegroundColor Cyan
    foreach ($name in 'Test-ReleaseZip') {
        $zf = $mAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true) | Select-Object -First 1
        if (-not $zf) { throw "$name function not found in mumu-menu.ps1" }
        . ([scriptblock]::Create($zf.Extent.Text))
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    $zDir = Join-Path $tmp 'zipcheck'
    New-Item -ItemType Directory -Path $zDir -Force | Out-Null
    $scriptVerLine = "`$scriptVer = '1.19.6'"

    function New-ZipFixture {
        param([string]$Path, [string]$Ver = '1.19.6', [string[]]$Omit = @(), [string[]]$Extra = @())
        $zipToCreate = Join-Path $zDir ('tmp_' + [IO.Path]::GetFileName($Path) + '.zip')
        if (Test-Path -LiteralPath $zipToCreate) { Remove-Item -LiteralPath $zipToCreate -Force }
        $archive = [System.IO.Compression.ZipFile]::Open($zipToCreate, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $fileBodies = @{
                'mumu-menu.ps1'        = "# menu`n$scriptVerLine`n# body`n"
                'SKILL.md'             = "# skill`n"
                'README.md'            = "# readme`n"
                'bootstrap-update.ps1' = "# updater`n"
                '.version'             = 'v1.19.6'
            }
            foreach ($name in $fileBodies.Keys) {
                if ($Omit -contains $name) { continue }
                $entry = $archive.CreateEntry($name)
                $w = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
                $w.Write($fileBodies[$name]); $w.Dispose()
            }
            foreach ($extra in $Extra) {
                $entry = $archive.CreateEntry($extra)
                $w = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
                $w.Write('extra'); $w.Dispose()
            }
        } finally { $archive.Dispose() }
        Move-Item -LiteralPath $zipToCreate -Destination $Path -Force
        # Sidecar: canonical 'sha256  filename' line
        $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath "$Path.sha256" -Value "$h  $([IO.Path]::GetFileName($Path))" -Encoding Ascii
    }

    # Case 1: correct ZIP -> all three checks OK
    $zipOk = Join-Path $zDir 'MuMuManager-CLI-Menu-v1.19.6.zip'
    New-ZipFixture -Path $zipOk
    $r1 = Test-ReleaseZip -ZipPath $zipOk -ExpectedTag 'v1.19.6'
    Assert-True -Name 'correct ZIP passes all checks' -Condition ($r1.Ok) -Detail ($r1.Checks -join ' // ')
    Assert-True -Name 'sidecar sha256 matched exactly' -Condition ($r1.ZipHash -eq $r1.SidecarHash) -Detail ($r1.Checks -join ' // ')
    Assert-True -Name 'file set check present and OK' -Condition (@($r1.Checks) -contains 'file set: OK (5 files)') -Detail ($r1.Checks -join ' // ')
    Assert-True -Name 'scriptVer read from archive matches tag' -Condition ($r1.ZipVersion -eq '1.19.6') -Detail ($r1.Checks -join ' // ')

    # Case 2: tampered archive (byte flip after sidecar) -> sha256 must fail
    $zipTamper = Join-Path $zDir 'MuMuManager-CLI-Menu-v1.19.6-tampered.zip'
    Copy-Item -LiteralPath $zipOk -Destination $zipTamper -Force
    $bytes = [System.IO.File]::ReadAllBytes($zipTamper); $bytes[200] = $bytes[200] -bxor 0xFF; [System.IO.File]::WriteAllBytes($zipTamper, $bytes)
    $r2 = Test-ReleaseZip -ZipPath $zipTamper -ExpectedTag 'v1.19.6'
    Assert-True -Name 'tampered ZIP fails the sha256 check' -Condition (-not $r2.Ok -and $r2.ZipHash -ne $r2.SidecarHash) -Detail ($r2.Checks -join ' // ')

    # Case 3: wrong sidecar content -> must fail even with a good ZIP
    $zipWrong = Join-Path $zDir 'MuMuManager-CLI-Menu-v1.19.6-wrongsidecar.zip'
    Copy-Item -LiteralPath $zipOk -Destination $zipWrong -Force
    Copy-Item -LiteralPath "$zipOk.sha256" -Destination "$zipWrong.sha256" -Force
    Set-Content -LiteralPath "$zipWrong.sha256" -Value (('0' * 64) + "  wrong") -Encoding Ascii
    $r3 = Test-ReleaseZip -ZipPath $zipWrong -ExpectedTag 'v1.19.6'
    Assert-True -Name 'bad sidecar hash fails verification' -Condition (-not $r3.Ok) -Detail ($r3.Checks -join ' // ')

    # Case 4: scriptVer inside the archive does not match the tag
    $zipVer = Join-Path $zDir 'MuMuManager-CLI-Menu-v1.19.9.zip'
    New-ZipFixture -Path $zipVer -Ver '1.19.6'
    $r4 = Test-ReleaseZip -ZipPath $zipVer -ExpectedTag 'v1.19.9'
    Assert-True -Name 'scriptVer/tag mismatch fails verification' -Condition (-not $r4.Ok -and (@($r4.Checks | Where-Object { $_ -like 'scriptVer: MISMATCH*' }).Count -eq 1)) -Detail ($r4.Checks -join ' // ')

    # Case 5: incomplete file set (missing SKILL.md + .version, extra file)
    $zipSet = Join-Path $zDir 'MuMuManager-CLI-Menu-v1.19.6-badset.zip'
    New-ZipFixture -Path $zipSet -Omit @('SKILL.md', '.version') -Extra @('bonus.txt')
    $r5 = Test-ReleaseZip -ZipPath $zipSet -ExpectedTag 'v1.19.6'
    Assert-True -Name 'incomplete file set fails verification' -Condition (-not $r5.Ok) -Detail ($r5.Checks -join ' // ')
    Assert-True -Name 'missing and unexpected files are named' -Condition ((@($r5.Checks | Where-Object { $_ -match 'missing: SKILL\.md, \.version' }).Count -eq 1) -and (@($r5.Checks | Where-Object { $_ -match 'unexpected: bonus\.txt' }).Count -eq 1)) -Detail ($r5.Checks -join ' // ')

    # Case 6: missing archive -> clean failure, no throw
    $r6 = Test-ReleaseZip -ZipPath (Join-Path $zDir 'no-such-zip.zip') -ExpectedTag 'v1.19.6'
    Assert-True -Name 'missing archive fails cleanly' -Condition ((-not $r6.Ok) -and (@($r6.Checks | Where-Object { $_ -like 'zip: MISSING*' }).Count -eq 1)) -Detail ($r6.Checks -join ' // ')

    # Client entry points: bootstrap -VerifyZip mode and the [F] prompt
    Assert-True -Name 'bootstrap -VerifyZip mode is wired' -Condition ((Get-Content -LiteralPath (Join-Path $root 'bootstrap-update.ps1') -Raw -Encoding UTF8) -match '\$VerifyZip') -Detail 'VerifyZip param not found'
    Assert-True -Name '[F] offers release ZIP verification' -Condition ((Get-Content -LiteralPath $menuPath -Raw -Encoding UTF8) -match 'Verify a downloaded release ZIP') -Detail 'prompt not found'

    # ── T9: bootstrap post-download hash verification (parity with [U]) ──
    Write-Host 'T9: bootstrap hash verify - vectors, symmetric trim, API-error skip, wiring' -ForegroundColor Cyan
    $bErrors = $null
    $bAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'bootstrap-update.ps1'), [ref]$null, [ref]$bErrors)
    if ($bErrors -and $bErrors.Count) { throw "bootstrap-update.ps1 has syntax errors: $($bErrors[0].Message)" }
    $gexText = ''
    foreach ($name in 'Get-ContentHash', 'Get-ExpectedHashes') {
        $bf = $bAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true) | Select-Object -First 1
        if (-not $bf) { throw "$name function not found in bootstrap-update.ps1" }
        if ($name -eq 'Get-ExpectedHashes') { $gexText = $bf.Extent.Text }
        . ([scriptblock]::Create($bf.Extent.Text))
    }
    Assert-True -Name 'Get-ContentHash matches the SHA-256 vector for "abc"' -Condition ((Get-ContentHash 'abc') -eq 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') -Detail (Get-ContentHash 'abc')
    Assert-True -Name 'Get-ContentHash trims trailing whitespace symmetrically (no phantom mismatch)' -Condition ((Get-ContentHash "body`r`n") -eq (Get-ContentHash 'body')) -Detail 'trailing newline changes the hash'
    # Hermetic stub for the API fetch inside Get-ExpectedHashes.
    # Non-ASCII body: with the old console-captured fetch the OEM codepage
    # mangled it (caught live in v1.20.2 - false HASH MISMATCH on every file).
    function Invoke-CurlGetRaw { param([string]$Url)
        if ($Url -match '/contents/([^?]+)\?') { $n = $Matches[1] } else { $n = '' }
        switch ($n) {
            'mumu-menu.ps1'        { return "# меню тело`n" }
            'SKILL.md'             { return '{"message":"API rate limit exceeded for 1.2.3.4.","documentation_url":"https://docs.github.com"}' }
            'README.md'            { return $null }
            default                { return $null }
        }
    }
    $exp = Get-ExpectedHashes -Tag 'v1.20.2' -Names @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')
    Assert-True -Name 'expected hash computed from (non-ASCII) tag content' -Condition ($exp['mumu-menu.ps1'] -eq (Get-ContentHash "# меню тело`n")) -Detail "got: $($exp['mumu-menu.ps1'])"
    Assert-True -Name 'rate-limit JSON body skipped (never treated as content)' -Condition (-not $exp.ContainsKey('SKILL.md')) -Detail 'SKILL.md present in expected hashes'
    Assert-True -Name 'null response skipped' -Condition (-not $exp.ContainsKey('README.md')) -Detail 'README.md present in expected hashes'
    Assert-True -Name 'expected hashes use the byte-exact raw fetch (OEM-codepage safe)' -Condition (($gexText -match 'Invoke-CurlGetRaw') -and ($gexText -notmatch 'Invoke-CurlGet "')) -Detail 'Get-ExpectedHashes must call Invoke-CurlGetRaw, not the console-captured Invoke-CurlGet'
    $bRaw = Get-Content -LiteralPath (Join-Path $root 'bootstrap-update.ps1') -Raw -Encoding UTF8
    Assert-True -Name '-NoVerify opt-out is wired' -Condition ($bRaw -match '\[switch\]\$NoVerify') -Detail 'NoVerify param not found'
    Assert-True -Name 'post-download (hash OK) verdict is wired' -Condition ($bRaw -match 'hash OK') -Detail 'hash OK output not found'
    Assert-True -Name 'expected-hashes fetch is wired before the download loop' -Condition ($bRaw -match 'Get-ExpectedHashes -Tag \$remoteTag') -Detail 'fetch call not found'


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
