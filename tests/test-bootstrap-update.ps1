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
$maxRetries = 2
$retryDelay = 1
$token      = $null   # public API; bootstrap reads its own token file, tests must not

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
