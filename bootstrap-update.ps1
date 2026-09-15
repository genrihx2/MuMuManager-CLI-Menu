# Bootstrap Update Script - Run this SEPARATELY from PowerShell
# Downloads the latest mumu-menu.ps1 and replaces the old one.
# Use when the [U] menu option is broken (e.g. after a failed update).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -TargetDir "C:\MyPath"
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -Force
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -LogDir "D:\logs"
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -VerifyHash
#
# Post-download verification (parity with the [U] updater): after each
# successful download the file is re-hashed and compared with the expected
# SHA-256 computed from the release tag content. A mismatch fails the update
# like a failed download. Skip with -NoVerify.
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -VerifyZip "MuMuManager-CLI-Menu-v1.19.6.zip"
#
# Update journal: every completed run appends one event to
# update-journal.log (same file the menu [U] updater uses). Override the
# location with -LogDir (e.g. when the install dir is read-only).
#
# Self-refresh: bootstrap-update.ps1 updates ITSELF on every run - the new
# copy is downloaded as .new and applied at the end of a successful run
# (PowerShell has parsed the file by then). If the file is busy, the menu
# applies the pending .new at startup.

param(
    [string]$TargetDir = $PSScriptRoot,
    [string]$LogDir = '',
    [switch]$Force,
    [string]$VerifyZip = '',
    [string]$ZipTag = '',
    [switch]$NoVerify
)

if (-not $TargetDir) { $TargetDir = $PWD.Path }

$ErrorActionPreference = 'Stop'

# ── TLS ──────────────────────────────────────────────────────────────
try {
    [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12)
} catch {
    Write-Host "  Warning: Could not force TLS 1.2 ($($_.Exception.Message))" -ForegroundColor Yellow
}

# ── Config ───────────────────────────────────────────────────────────
$repo       = 'genrihx2/MuMuManager-CLI-Menu'
$apiBase    = "https://api.github.com/repos/$repo"
$files      = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')
$maxRetries = 3
$retryDelay = 3   # seconds between retries

# ── Update journal (shared with the menu [U] updater) ────────────────
# Tab-separated UTF-8, one event per line:
#   timestamp<TAB>actor<TAB>event<TAB>from<TAB>to<TAB>detail
# Rotates at 256 KB keeping a single .old generation. Journal writes are
# best-effort: a logging failure must never break the update itself.
$journalFile = if ($LogDir) { Join-Path $LogDir 'update-journal.log' } else { Join-Path $TargetDir 'update-journal.log' }

function Write-UpdateJournal {
    param([string]$EventType, [string]$From = '', [string]$To = '', [string]$Detail = '')
    try {
        $oldPath = "$journalFile.old"
        if ((Test-Path -LiteralPath $journalFile -PathType Leaf) -and (Get-Item -LiteralPath $journalFile).Length -gt 256KB) {
            Move-Item -LiteralPath $journalFile -Destination $oldPath -Force
        }
        $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f @(
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), 'bootstrap', $EventType, $From, $To,
            ($Detail -replace "`t", ' ' -replace "`r?`n", ' | ')
        )
        [System.IO.File]::AppendAllText($journalFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Debug "Update journal write failed: $($_.Exception.Message)"
    }
}

# ── Self-refresh: apply a pending bootstrap-update.ps1.new ───────────
# The updater cannot safely overwrite itself while running, so the fresh
# copy is downloaded as .new and applied afterwards. If the copy is
# blocked (file lock), the .new stays and the menu applies it at startup.
function Apply-PendingUpdater {
    param([string]$Dir, [string]$From = '', [string]$To = '')
    $newPath = Join-Path $Dir 'bootstrap-update.ps1.new'
    $curPath = Join-Path $Dir 'bootstrap-update.ps1'
    if (-not (Test-Path -LiteralPath $newPath -PathType Leaf)) { return $false }
    try {
        $oldPath = $curPath + '.old'
        if (Test-Path -LiteralPath $curPath -PathType Leaf) {
            Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $curPath -Destination $oldPath -Force
        }
        Copy-Item -LiteralPath $newPath -Destination $curPath -Force
        Remove-Item -LiteralPath $newPath -Force -ErrorAction SilentlyContinue
        Write-UpdateJournal -EventType 'updater-refresh' -From $From -To $To -Detail 'bootstrap-update.ps1 updated from .new'
        return $true
    } catch {
        Write-Debug "Updater self-apply failed: $($_.Exception.Message)"
        return $false
    }
}

# ── Single-flight update lock (issue #24) ─────────────────────────────
# The menu's [U] updater and this script write the same files; a concurrent
# run could corrupt state or double-apply. The lock is a .update-lock file
# created with CreateNew - the create call itself is the atomic test-and-
# set, so two processes can never both win. Content: PID + timestamp.
# A lock older than 10 minutes is treated as the leftover of a crashed
# process and is broken. Always released in finally, including Ctrl+C.
# (Same implementation as mumu-menu.ps1; both scripts run standalone.)
$script:UpdateLockStaleMinutes = 10

function Test-UpdateLockStale {
    param([string]$LockPath)
    $limit = if ($script:UpdateLockStaleMinutes) { [int]$script:UpdateLockStaleMinutes } else { 10 }
    try {
        if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { return $false }
        $age = ((Get-Date) - (Get-Item -LiteralPath $LockPath).LastWriteTime).TotalMinutes
        return ($age -gt $limit)
    } catch {
        Write-Debug "Lock staleness check failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-UpdateLockMessage {
    param([string]$LockPath)
    $owner = ''
    try {
        if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
            $owner = (Get-Content -LiteralPath $LockPath -TotalCount 1 -ErrorAction SilentlyContinue)
        }
    } catch { Write-Debug "Lock owner read failed: $($_.Exception.Message)" }
    $limit = if ($script:UpdateLockStaleMinutes) { [int]$script:UpdateLockStaleMinutes } else { 10 }
    $age = ''
    try {
        if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
            $mins = [math]::Round(((Get-Date) - (Get-Item -LiteralPath $LockPath).LastWriteTime).TotalMinutes, 1)
            $age = ", age ${mins} min"
        }
    } catch { Write-Debug "Lock age read failed: $($_.Exception.Message)" }
    return ("held by {0}{1}. Close that updater or wait; if it crashed, the lock expires after {2} minutes." -f $owner, $age, $limit)
}

function New-UpdateLock {
    # Atomically claim the update lock. Returns $true if WE hold it now.
    # Handles the stale case (break + retry once, create-then-break to close
    # the classic break/recreate race window) and rethrows anything else.
    param([string]$Dir)
    $lockPath = Join-Path $Dir '.update-lock'
    $now = Get-Date
    $payload = "PID $PID started $($now.ToString('yyyy-MM-dd HH:mm:ss'))"
    try {
        $s = [System.IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None')
        $w = [System.IO.StreamWriter]::new($s)
        $w.Write($payload)
        $w.Flush(); $w.Dispose(); $s.Dispose()
        return $true
    } catch [System.IO.IOException] {
        if (-not (Test-UpdateLockStale -LockPath $lockPath)) {
            Write-Host ''
            Write-Host '  Another update is already running:' -ForegroundColor Yellow
            Write-Host ("  " + (Get-UpdateLockMessage -LockPath $lockPath)) -ForegroundColor Yellow
            Write-UpdateJournal -EventType 'update-skipped' -Detail '.update-lock held by another process'
            return $false
        }
        # Stale lock: create-then-break. Only the process that successfully
        # creates .update-lock.new may delete and re-create the lock, so two
        # racers cannot both end up holding it.
        $claimPath = "$lockPath.new"
        try {
            $c = [System.IO.File]::Open($claimPath, 'CreateNew', 'Write', 'None')
            $cw = [System.IO.StreamWriter]::new($c)
            $cw.Write("stale-break by PID $PID")
            $cw.Flush(); $cw.Dispose(); $c.Dispose()
        } catch {
            Write-Host '  Another update is already breaking a stale lock.' -ForegroundColor Yellow
            Write-UpdateJournal -EventType 'update-skipped' -Detail '.update-lock stale-break race lost'
            return $false
        }
        try {
            Remove-Item -LiteralPath $lockPath -Force
            Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
            Write-Host '  Removed a stale update lock (leftover of a crashed updater).' -ForegroundColor DarkGray
            $s2 = [System.IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None')
            $w2 = [System.IO.StreamWriter]::new($s2)
            $w2.Write($payload)
            $w2.Flush(); $w2.Dispose(); $s2.Dispose()
            return $true
        } catch {
            Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
            Write-Host '  Another update started while the stale lock was being broken.' -ForegroundColor Yellow
            Write-UpdateJournal -EventType 'update-skipped' -Detail '.update-lock lost stale-break race'
            return $false
        }
    }
}

function Remove-UpdateLock {
    param([string]$Dir)
    try { Remove-Item -LiteralPath (Join-Path $Dir '.update-lock') -Force -ErrorAction SilentlyContinue } catch { Write-Debug "Lock removal failed: $($_.Exception.Message)" }
    try { Remove-Item -LiteralPath (Join-Path $Dir '.update-lock.new') -Force -ErrorAction SilentlyContinue } catch { Write-Debug "Lock claim cleanup failed: $($_.Exception.Message)" }
}

# ── Release ZIP self-test (issue #19) ────────────────────────────────
# Mirrors the CI checks (release.yml) on the client, before any install:
#   1. the ZIP's SHA-256 equals the .sha256 sidecar
#   2. the archive contains exactly the release file set (5 files, no extras)
#   3. mumu-menu.ps1's $scriptVer matches the release tag
# Release ZIPs are flat (files at the archive root, git archive output).
# Returns a report object so tests can assert the logic without IO side
# effects beyond reading the archive.
function Test-ReleaseZip {
    param(
        [Parameter(Mandatory = $true)] [string]$ZipPath,
        [Parameter(Mandatory = $true)] [string]$ExpectedTag,
        [string]$SidecarPath = "$ZipPath.sha256"
    )
    $expectedFiles = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1', '.version')
    $checks = @()
    $ok = $true
    $zipVer = ''
    $names = @()

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $false; ZipHash = ''; SidecarHash = ''; Checks = @("zip: MISSING ($ZipPath)"); EntryNames = @(); ZipVersion = '' }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    # Check 1: ZIP hash vs sidecar
    $zipHash = ''
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($ZipPath)
        try { $zipHash = ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLower() } finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
    $sidecarHash = ''
    if (Test-Path -LiteralPath $SidecarPath -PathType Leaf) {
        $first = (Get-Content -LiteralPath $SidecarPath -TotalCount 1) -as [string]
        if ($first -match '^([0-9a-fA-F]{64})\b') { $sidecarHash = $Matches[1].ToLower() }
    }
    $sidecarOk = ($sidecarHash -ne '') -and ($sidecarHash -eq $zipHash)
    if ($sidecarOk) {
        $checks += "sha256: OK (match with sidecar)"
    } else {
        $sidecarShown = if ($sidecarHash) { $sidecarHash.Substring(0, [Math]::Min(16, $sidecarHash.Length)) + '...' } else { 'MISSING' }
        $checks += "sha256: MISMATCH (zip=$($zipHash.Substring(0, 16))... sidecar=$sidecarShown)"
        $ok = $false
    }

    # Checks 2 + 3: archive contents
    $zip = $null
    try { $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath) } catch {
        $checks += "archive: unreadable ($($_.Exception.Message))"
        $ok = $false
    }
    if ($zip) {
        try {
            $names = @($zip.Entries | ForEach-Object { $_.FullName } | Where-Object { $_ -and ($_ -notmatch '/$') } | ForEach-Object { $_ -replace '^\./', '' -replace '^.*[/\\]', '' } | Sort-Object -Unique)
            $missing = @($expectedFiles | Where-Object { $names -notcontains $_ })
            $extras = @($names | Where-Object { $expectedFiles -notcontains $_ })
            if (($missing.Count -eq 0) -and ($extras.Count -eq 0)) {
                $checks += "file set: OK ($($expectedFiles.Count) files)"
            } else {
                $parts = @()
                if ($missing.Count -gt 0) { $parts += "missing: $($missing -join ', ')" }
                if ($extras.Count -gt 0) { $parts += "unexpected: $($extras -join ', ')" }
                $checks += "file set: MISMATCH ($($parts -join '; '))"
                $ok = $false
            }

            $menuEntry = $zip.Entries | Where-Object { (($_.FullName -replace '^\./', '') -replace '^.*[/\\]', '') -eq 'mumu-menu.ps1' } | Select-Object -First 1
            if ($menuEntry) {
                $reader = New-Object System.IO.StreamReader($menuEntry.Open(), [System.Text.Encoding]::UTF8)
                try {
                    for ($i = 0; ($i -lt 320) -and (-not $reader.EndOfStream); $i++) {
                        $line = $reader.ReadLine()
                        if ($line -match "^\s*\`$scriptVer\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'") { $zipVer = $Matches[1]; break }
                    }
                } finally { $reader.Dispose() }
            }
            $expectedVer = $ExpectedTag -replace '^v', ''
            if ($zipVer -and ($zipVer -eq $expectedVer)) {
                $checks += "scriptVer: OK ($zipVer matches $ExpectedTag)"
            } else {
                $checks += "scriptVer: MISMATCH (zip=$(if ($zipVer) { $zipVer } else { 'NOT FOUND' }) expected=$expectedVer)"
                $ok = $false
            }
        } finally { $zip.Dispose() }
    }

    [pscustomobject]@{ Ok = $ok; ZipHash = $zipHash; SidecarHash = $sidecarHash; Checks = $checks; EntryNames = $names; ZipVersion = $zipVer }
}

# ── Verify-only mode: check a release ZIP + sidecar and exit (#19) ────
if ($VerifyZip) {
    $zipPath = $VerifyZip
    $zipTag = if ($ZipTag) { $ZipTag } else {
        if ([IO.Path]::GetFileName($zipPath) -match '(v[0-9]+\.[0-9]+\.[0-9]+)') { $Matches[1] } else { '' }
    }
    if (-not $zipTag) {
        Write-Host "ERROR: cannot infer the release tag from the file name - pass -ZipTag vX.Y.Z" -ForegroundColor Red
        exit 1
    }
    Write-Host ''
    Write-Host "=== Verify release ZIP: $([IO.Path]::GetFileName($zipPath)) ($zipTag) ===" -ForegroundColor Cyan
    $r = Test-ReleaseZip -ZipPath $zipPath -ExpectedTag $zipTag
    foreach ($c in $r.Checks) {
        Write-Host "  $c" -ForegroundColor $(if ($c -match ': OK') { 'Green' } else { 'Red' })
    }
    if ($r.Ok) {
        Write-Host "ZIP: OK ($($r.EntryNames.Count) files, sha256 match)" -ForegroundColor Green
        Write-UpdateJournal -EventType 'zip-verify-ok' -From '' -To $zipTag -Detail "sha256 match; $($r.EntryNames.Count) files"
        exit 0
    } else {
        Write-Host "ZIP: FAILED - do not install from this archive" -ForegroundColor Red
        Write-UpdateJournal -EventType 'zip-verify-fail' -From '' -To $zipTag -Detail ($r.Checks -join '; ')
        exit 1
    }
}

Write-Host ''
Write-Host '=== Bootstrap Update ===' -ForegroundColor Cyan
Write-Host "  Target: $TargetDir" -ForegroundColor DarkGray
Write-Host ''

# ── Validate target directory ────────────────────────────────────────
if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
    Write-Host "ERROR: Target directory does not exist: $TargetDir" -ForegroundColor Red
    exit 1
}

# ── GitHub token (DPAPI-encrypted) ──────────────────────────────────
$token = $null
$tokenFile = Join-Path $TargetDir '.github-token.dpapi'
if (Test-Path -LiteralPath $tokenFile) {
    try {
        $raw = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
        $sec = $raw | ConvertTo-SecureString -ErrorAction Stop
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch {
        Write-Host "  Warning: Cannot decrypt token: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($token) {
    Write-Host "  Token: loaded" -ForegroundColor DarkGray
} else {
    Write-Host "  Token: not found (60 req/hr limit)" -ForegroundColor DarkGray
}
Write-Host ''

# ── Helper: curl GET with retry and auth fallback ───────────────────
function Invoke-CurlGet {
    param([string]$Url)
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        $curlCmd = "curl.exe -sS --fail --connect-timeout 30 --max-time 30 -H `"Accept: application/vnd.github.v3+json`""
        if ($token) { $curlCmd += " -H `"Authorization: token $token`"" }
        $curlCmd += " `"$Url`" 2>nul"
        $result = & cmd /c $curlCmd
        if ($LASTEXITCODE -eq 0 -and $result) {
            $resultStr = $result | Out-String
            # Bad credentials fallback — retry without token
            if ($token -and $resultStr -match '"message"\s*:\s*"Bad credentials"') {
                Write-Host "  Token rejected — retrying without auth..." -ForegroundColor Yellow
                $noAuthCmd = "curl.exe -sS --fail --connect-timeout 30 --max-time 30 -H `"Accept: application/vnd.github.v3+json`" `"$Url`" 2>nul"
                $result2 = & cmd /c $noAuthCmd
                if ($LASTEXITCODE -eq 0 -and $result2) {
                    return ($result2 | Out-String)
                }
                return $null
            }
            return $resultStr
        }
        if ($attempt -lt $maxRetries) {
            Write-Host "  Attempt $attempt failed - retrying in ${retryDelay}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $retryDelay
        }
    }
    return $null
}

# ── Helper: Download file with curl and auth fallback ───────────────
function Download-File {
    param([string]$Url, [string]$Dest)
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        $tmpFile = $Dest + '.tmp'
        $dlCmd = "curl.exe -sS --fail --retry 2 --connect-timeout 30 --max-time 120 -L -H `"Accept: application/vnd.github.v3.raw`" -o `"$tmpFile`""
        if ($token) { $dlCmd += " -H `"Authorization: token $token`"" }
        $dlCmd += " `"$Url`" 2>nul"
        & cmd /c $dlCmd | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmpFile) -and (Get-Item -LiteralPath $tmpFile).Length -gt 0) {
            $size = (Get-Item -LiteralPath $tmpFile).Length
            # Validate: detect JSON error or metadata instead of raw content.
            # JSON checks apply ONLY when the body actually starts with '{':
            # raw scripts legitimately contain JSON-looking strings, and an
            # unanchored match false-positived on mumu-menu.ps1 itself.
            try {
                $body = [System.IO.File]::ReadAllText($tmpFile)
                $isJsonBody = $body.TrimStart().StartsWith('{')
                if ($isJsonBody -and $body -match '"message"\s*:\s*"Bad credentials"') {
                    Remove-Item -LiteralPath $tmpFile -Force
                    if ($token) {
                        Write-Host "  Token rejected — retrying without auth..." -ForegroundColor Yellow
                        $token = $null
                        continue
                    }
                    return 0
                }
                if ($isJsonBody -and $body -match '"message"\s*:\s*"') {
                    $errMsg = if ($body -match '"message"\s*:\s*"([^"]+)"') { $Matches[1] } else { 'API error' }
                    Remove-Item -LiteralPath $tmpFile -Force
                    Write-Host "  Error: $errMsg" -ForegroundColor Red
                    return 0
                }
                if ($isJsonBody -and $body -match '"encoding"\s*:\s*"base64"') {
                    Remove-Item -LiteralPath $tmpFile -Force
                    Write-Host "  Error: Received JSON metadata instead of raw file" -ForegroundColor Red
                    return 0
                }
                if ($isJsonBody -and $body -match '"name"\s*:\s*"' -and $body -match '"_links"') {
                    Remove-Item -LiteralPath $tmpFile -Force
                    Write-Host "  Error: Received JSON metadata instead of raw file" -ForegroundColor Red
                    return 0
                }
            } catch {
                Write-Debug "Validation failed: $($_.Exception.Message)"
            }
            Move-Item -LiteralPath $tmpFile -Destination $Dest -Force
            return $size
        }
        if (Test-Path -LiteralPath $tmpFile) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
        if ($attempt -lt $maxRetries) {
            Write-Host "  Attempt $attempt failed - retrying in ${retryDelay}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $retryDelay
        }
    }
    return 0
}

# ── Post-download SHA-256 verification (parity with [U], issue #20) ──
# Same hashing rules as mumu-menu.ps1's Get-ContentHash: CR stripped, BOM
# stripped, trailing whitespace trimmed (mirrors Invoke-CurlGet, which
# Out-Strings the response body without the blob's trailing newline).
function Get-ContentHash {
    param([string]$Text)
    $norm = $Text -replace "`r", ''
    $norm = $norm.TrimStart([char]0xFEFF).TrimEnd()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))) -replace '-', '')
    } finally {
        $sha.Dispose()
    }
}

# Raw byte-exact fetch for hashing. Invoke-CurlGet (used for release JSON)
# captures output through cmd /c, which decodes in the console OEM codepage -
# any non-ASCII content (the README/SKILL are largely Cyrillic) would be
# mangled and produce garbage reference hashes (caught live in v1.20.2).
# Mirrors the menu's Invoke-GitHubGet: curl writes to a temp file, bytes are
# read and decoded as UTF-8. Returns the decoded string or $null.
function Invoke-CurlGetRaw {
    param([string]$Url)
    $tmpFile = Join-Path $env:TEMP ('gh_raw_' + [Guid]::NewGuid().ToString('N') + '.bin')
    try {
        $curlArgs = @('-sS', '--fail', '--retry', '2', '--retry-delay', '3', '--connect-timeout', '30', '--max-time', '60', '-H', 'Accept: application/vnd.github.raw', '-o', $tmpFile)
        if ($token) { $curlArgs += @('-H', "Authorization: token $token") }
        $curlArgs += $Url
        & curl.exe @curlArgs 2>$null
        if ((Test-Path -LiteralPath $tmpFile -PathType Leaf) -and (Get-Item -LiteralPath $tmpFile).Length -gt 0) {
            return ([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($tmpFile))).TrimEnd()
        }
        return $null
    } catch {
        Write-Debug "Raw fetch failed: $($_.Exception.Message)"
        return $null
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

# Issue #22: a 40-hex SHA gate. The contents API resolves ?ref=<tag> at
# fetch time, so a CDN edge can serve the previous commit's blob after a
# tag push. A commit SHA is immutable - requests through a pinned URL are
# immune by construction.
function Test-GitSha {
    param([string]$S)
    return ($S -match '^[0-9a-fA-F]{40}$')
}

# Expected SHA-256 per file, from the tag content via the contents API
# (bodies that start with '{' are API errors/rate limits - skipped, never
# treated as content; a missing entry means 'unknown', not 'zero').
# The tag URL is pinned to the tag's commit SHA first (issue #22): the
# contents API resolves ?ref=<tag> at fetch time, so an edge can serve the
# previous commit's blob minutes after the tag push. A commit SHA is
# immutable - a stale read is impossible by construction.
function Get-ExpectedHashes {
    param([string]$Tag, [string[]]$Names)
    $result = @{}
    $ref = $Tag
    if ($Tag -and -not (Test-GitSha $Tag)) {
        try {
            $r = Invoke-CurlGetRaw "https://api.github.com/repos/$repo/git/ref/tags/$Tag"
            $t = if ($r) { $r.Trim() } else { '' }
            if ($t -and -not ($t.StartsWith('{') -and $t -match '"message"\s*:\s*')) {
                $obj = ($t | ConvertFrom-Json).object
                if ($obj -and $obj.sha -and (Test-GitSha $obj.sha)) {
                    $ref = $obj.sha
                    if ($obj.type -eq 'tag') {
                        $r2 = Invoke-CurlGetRaw "https://api.github.com/repos/$repo/git/tags/$($obj.sha)"
                        $t2 = if ($r2) { $r2.Trim() } else { '' }
                        if ($t2 -and -not ($t2.StartsWith('{') -and $t2 -match '"message"\s*:\s*')) {
                            $obj2 = ($t2 | ConvertFrom-Json).object
                            if ($obj2 -and $obj2.sha -and (Test-GitSha $obj2.sha)) { $ref = $obj2.sha }
                        }
                    }
                }
            }
        } catch {
            Write-Debug "Ref resolve failed for ${Tag}: $($_.Exception.Message)"
        }
    }
    foreach ($n in $Names) {
        try {
            $remote = Invoke-CurlGetRaw "https://api.github.com/repos/$repo/contents/$n`?ref=$ref"
            if (-not $remote) { continue }
            $t = $remote.TrimEnd()
            if ($t.StartsWith('{') -and $t -match '"message"\s*:\s*"') { continue }
            $result[$n] = Get-ContentHash $t
        } catch {
            Write-Debug "Expected hash fetch failed for ${n}: $($_.Exception.Message)"
        }
    }
    return $result
}

# ── Fast version check ──────────────────────────────────────────────
$localTag = ''
$versionFile = Join-Path $TargetDir '.version'
if (Test-Path -LiteralPath $versionFile) {
    try { $localTag = (Get-Content -LiteralPath $versionFile -Raw).Trim() } catch { Write-Debug "Version file read failed: $($_.Exception.Message)" }
}

$remoteTag = ''
$remoteBody = ''
$releaseJson = Invoke-CurlGet "$apiBase/releases/latest"
if ($releaseJson) {
    try {
        $release = $releaseJson | ConvertFrom-Json
        if ($release.tag_name) {
            $remoteTag  = $release.tag_name
            $remoteBody = if ($release.body) { $release.body } else { '' }
        }
    } catch {
        Write-Host "  Could not parse release: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $remoteTag) {
    Write-Host "  Could not check releases. Run with -Force to download anyway." -ForegroundColor Yellow
    if (-not $Force) { exit 1 }
}

if ($localTag -eq $remoteTag -and -not $Force) {
    Write-Host "  Up to date ($localTag) - nothing to download." -ForegroundColor Green
    Write-Host "  Use -Force to re-download anyway." -ForegroundColor DarkGray
    exit 0
}

# ── Single-flight lock (issue #24) ───────────────────────────────────
# Acquired before anything on disk is touched and released in the finally
# below - including update failures and Ctrl+C. The menu writes the same
# files via [U], so both paths honor the same lock.
if (-not (New-UpdateLock -Dir $TargetDir)) { exit 1 }
try {

if ($remoteTag) {
    Write-Host "  Local:  $localTag" -ForegroundColor DarkGray
    Write-Host "  Remote: $remoteTag" -ForegroundColor Green
    if ($remoteBody) {
        $firstLine = ($remoteBody -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
        if ($firstLine) { Write-Host "  Note:   $firstLine" -ForegroundColor DarkGray }
    }
    Write-Host ''
}

# ── Backup ───────────────────────────────────────────────────────────
$backupDir = Join-Path $TargetDir "backup\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$backedUp = $false
foreach ($f in $files) {
    $src = Join-Path $TargetDir $f
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        if (-not $backedUp) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
            Write-Host "  Backup: $backupDir" -ForegroundColor DarkGray
            $backedUp = $true
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $backupDir $f) -Force
    }
}
if ($backedUp) { Write-Host '' }

# ── Download files ───────────────────────────────────────────────────
$ok   = 0
$fail = 0
$unverified = 0
$expectedHashes = @{}
if ($remoteTag -and -not $NoVerify) {
    $expectedHashes = Get-ExpectedHashes -Tag $remoteTag -Names $files
    if ($expectedHashes.Count -eq 0) {
        Write-Host "  Note: expected hashes unavailable - proceeding without post-download verification." -ForegroundColor Yellow
    }
}

foreach ($f in $files) {
    $dest = Join-Path $TargetDir $f
    # The updater itself goes to .new: never overwrite the running script.
    if ($f -eq 'bootstrap-update.ps1') { $dest = "$dest.new" }
    $tag = if ($remoteTag) { $remoteTag } else { 'main' }
    # Issue #22: pin a tag name to its commit SHA before fetching. The
    # contents API resolves ?ref=<tag> at fetch time, so a CDN edge can
    # serve the previous commit's blob minutes after a tag push; a commit
    # SHA is immutable. Failure to resolve keeps the plain tag URL (and the
    # SHA-256 verification still covers every downloaded byte).
    if (-not (Test-GitSha $tag)) {
        $pinned = Invoke-CurlGetRaw "https://api.github.com/repos/$repo/git/ref/tags/$tag"
        $pt = if ($pinned) { $pinned.Trim() } else { '' }
        if ($pt -and -not ($pt.StartsWith('{') -and $pt -match '"message"\s*:\s*')) {
            try {
                $po = ($pt | ConvertFrom-Json).object
                if ($po -and $po.sha -and (Test-GitSha $po.sha)) {
                    if ($po.type -eq 'tag') {
                        $p2 = Invoke-CurlGetRaw "https://api.github.com/repos/$repo/git/tags/$($po.sha)"
                        $p2t = if ($p2) { $p2.Trim() } else { '' }
                        if ($p2t -and -not ($p2t.StartsWith('{') -and $p2t -match '"message"\s*:\s*')) {
                            $po2 = ($p2t | ConvertFrom-Json).object
                            if ($po2 -and $po2.sha -and (Test-GitSha $po2.sha)) { $tag = $po2.sha } else { $tag = $po.sha }
                        } else { $tag = $po.sha }
                    } else { $tag = $po.sha }
                    Write-Host "  (tag pinned to commit $($tag.Substring(0, 8)))" -ForegroundColor DarkGray
                }
            } catch { Write-Debug "Download-loop ref pin failed: $($_.Exception.Message)" }
        }
    }
    $url = "https://api.github.com/repos/$repo/contents/$f`?ref=$tag"

    Write-Host "  $f" -ForegroundColor Yellow -NoNewline
    $size = Download-File $url $dest
    if ($size -gt 0) {
        # Post-download verification (parity with [U], issue #20): compare the
        # downloaded body against the expected hash. Mismatch fails the update
        # like a failed download - $fail advances, so .version is not advanced,
        # the journal shows update-fail, and the self-refresh is skipped (a
        # tampered updater copy must not be applied).
        if ($expectedHashes.ContainsKey($f)) {
            $actual = Get-ContentHash ([System.IO.File]::ReadAllText($dest))
            if ($actual -eq $expectedHashes[$f]) {
                $sizeKB = '{0:N1}' -f ($size / 1024)
                Write-Host "  OK  ${sizeKB} KB  (hash OK)" -ForegroundColor Green
                $ok++
            } else {
                Write-Host "  HASH MISMATCH (expected $($expectedHashes[$f].Substring(0, 16))..., got $($actual.Substring(0, 16))...)" -ForegroundColor Red
                $fail++
            }
        } else {
            $sizeKB = '{0:N1}' -f ($size / 1024)
            Write-Host "  OK  ${sizeKB} KB" -ForegroundColor Green
            $ok++
            $unverified++
        }
    } else {
        Write-Host "  FAILED" -ForegroundColor Red
        $fail++
    }
}

# ── Update .version file ─────────────────────────────────────────────
# Only claim the new version when EVERY file was replaced successfully —
# a partial failure must not leave .version ahead of the actual script.
if ($remoteTag -and $fail -eq 0 -and $ok -gt 0) {
    try {
        Set-Content -Path $versionFile -Value $remoteTag -NoNewline -Encoding UTF8 -Force
    } catch {
        Write-Host "  Warning: Could not update .version ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ''
if ($fail -eq 0 -and $ok -gt 0) {
    $detail = "$ok file(s) updated"
    if ($unverified -gt 0) { $detail += ", $unverified unverified (expected hashes unavailable)" }
    Write-UpdateJournal -EventType 'update-ok' -From $localTag -To $remoteTag -Detail $detail
    # Self-refresh: apply the freshly downloaded updater now - PowerShell
    # has already parsed this script, so overwriting the file is safe.
    if (Apply-PendingUpdater -Dir $TargetDir -From $localTag -To $remoteTag) {
        Write-Host "  Updater refreshed: bootstrap-update.ps1 now matches $remoteTag." -ForegroundColor Green
    } elseif (Test-Path -LiteralPath (Join-Path $TargetDir 'bootstrap-update.ps1.new')) {
        Write-Host "  Updater .new saved (file busy) - the menu will apply it at startup." -ForegroundColor Yellow
    }
    $doneMsg = "Done: $ok file(s) updated to $remoteTag"
    if ($unverified -gt 0) { $doneMsg += " ($unverified unverified - hashes unavailable)" }
    Write-Host $doneMsg -ForegroundColor Green
    Write-Host "Restart the menu to use the new version." -ForegroundColor Green
} elseif ($fail -gt 0) {
    Write-UpdateJournal -EventType 'update-fail' -From $localTag -To $remoteTag -Detail "$ok ok, $fail failed"
    Write-Host "Done: $ok ok, $fail failed" -ForegroundColor Yellow
    if ($backedUp) {
        Write-Host "Backup saved: $backupDir" -ForegroundColor DarkGray
        Write-Host "To restore: copy files from backup back to $TargetDir" -ForegroundColor DarkGray
    }
} else {
    Write-Host "Nothing downloaded." -ForegroundColor Yellow
}

} finally {
    # Covers normal exit, update-fail paths and Ctrl+C mid-download.
    Remove-UpdateLock -Dir $TargetDir
}
