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
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -WhatIf
#
# Dry-run: -WhatIf prints the update plan (action, files, verification,
# backup, journal) and exits - nothing is downloaded, no lock, no backup,
# no writes. Use it to preview what a real run would do.
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
    [switch]$NoVerify,
    [switch]$Diagnose,
    [switch]$WhatIf
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

# Retry flags for curl calls that build cmd strings. curl's own --retry
# ignores TLS handshake failures (exit 35) - the flaky-network class behind
# failed update checks. --retry-all-errors makes it retry transport-level
# errors too, but the option exists only since curl 7.71 and older builds
# abort on unknown options - probe once, degrade to plain --retry.
# No -w probe variant: PS 5.1 drops empty-string args ("no URL specified").
# Returns $true when the given curl accepts --retry-all-errors (curl >= 7.71).
# An unknown option makes curl exit 2 before any network activity; any other
# outcome (success or a network error) means the option was accepted. A curl
# that cannot start -> catch -> $false, degrading callers to plain --retry.
function Test-CurlCapability {
    param([string]$CurlExe = 'curl.exe', [string]$ProbeUrl = 'https://api.github.com/')
    try {
        $null = & $CurlExe -s --retry-all-errors --connect-timeout 10 --max-time 15 -o NUL $ProbeUrl 2>$null
        return ($LASTEXITCODE -ne 2)
    } catch {
        return $false
    }
}
$script:CurlRetryStr = ' --retry 3 --retry-delay 2'
$script:CurlRetryArgs = @('--retry', '3', '--retry-delay', '2')
if (Test-CurlCapability) {
    $script:CurlRetryStr += ' --retry-all-errors'
    $script:CurlRetryArgs += '--retry-all-errors'
}

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

# ── Diagnose: findings report without the menu (issue #29) ───────────
# The entry point when mumu-menu.ps1 itself is broken: prints the same
# classes of findings as the menu's [DIAG] screen - marker vs the scriptVer
# parsed from (possibly unparseable) menu content, update-lock states,
# journal health, MuMu path, disk space. No network, no mutations.
# Exit 0 = no error/warn findings, exit 1 = problems (scriptable).
function Get-ScriptVerFromText {
    # Reads $scriptVer out of raw menu text - works even when the file
    # cannot be parsed as PowerShell (that is the point of -Diagnose).
    param([string]$Text)
    foreach ($line in ($Text -split "`n" | Select-Object -First 320)) {
        if ($line -match "\`$scriptVer\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'") { return $Matches[1] }
    }
    return ''
}
function Get-BootstrapFindings {
    # Subset of the menu's Get-ProblemFindings, implementable without the
    # menu. Returns the same shape: severity, area, message objects.
    param(
        [string]$Dir,
        [string]$MenuPath,
        [string]$VersionFile,
        [string]$JournalFile
    )
    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($sev, $area, $msg) $findings.Add([pscustomobject]@{ severity = $sev; area = $area; message = $msg }) }

    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        & $add 'error' 'install' "install directory not found: $Dir"
        return $findings.ToArray()
    }

    # Marker vs the content's own version claim (wedge detector)
    $marker = ''
    if (Test-Path -LiteralPath $VersionFile -PathType Leaf) {
        try { $marker = (Get-Content -LiteralPath $VersionFile -Raw).Trim() } catch { Write-Debug "marker read failed: $($_.Exception.Message)" }
    }
    $fileVer = ''
    if (Test-Path -LiteralPath $MenuPath -PathType Leaf) {
        try { $fileVer = Get-ScriptVerFromText -Text ([System.IO.File]::ReadAllText($MenuPath)) } catch { Write-Debug "menu read failed: $($_.Exception.Message)" }
    } else {
        & $add 'error' 'install' "mumu-menu.ps1 missing from the install directory"
    }
    if (-not $marker) {
        & $add 'info' 'install' "no .version marker yet - the install has never recorded an update"
    }
    if ($marker -and $fileVer) {
        try {
            $mv = [version]($marker.TrimStart('v'))
            $fv = [version]$fileVer
            if ($mv -gt $fv) {
                & $add 'error' 'install' "marker ($marker) is AHEAD of the installed content ($fileVer) - wedged heal; run bootstrap-update.ps1 -Force to repair"
            } elseif ($mv -lt $fv) {
                & $add 'warn' 'install' "installed content ($fileVer) is newer than the marker ($marker) - an update may have been interrupted"
            }
        } catch {
            & $add 'warn' 'install' "cannot compare marker '$marker' with content version '$fileVer'"
        }
    } elseif ($marker -and -not $fileVer) {
        & $add 'warn' 'install' "could not read a scriptVer from mumu-menu.ps1 - the file may be corrupted"
    }

    # Update lock states
    $lockPath = Join-Path $Dir '.update-lock'
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        if (Test-UpdateLockStale -LockPath $lockPath) {
            & $add 'info' 'lock' ("stale update lock (leftover of a crashed updater) - will be broken on the next update: " + (Get-UpdateLockMessage -LockPath $lockPath))
        } else {
            & $add 'warn' 'lock' ("update lock held right now: " + (Get-UpdateLockMessage -LockPath $lockPath))
        }
    }
    if (Test-Path -LiteralPath "$lockPath.new" -PathType Leaf) {
        & $add 'info' 'lock' "claim residue .update-lock.new found - a stale lock was being broken; harmless"
    }

    # Journal health
    if (-not (Test-Path -LiteralPath $JournalFile -PathType Leaf)) {
        & $add 'info' 'journal' "no update journal yet - no updates have been performed"
    } else {
        $jLines = @()
        try { $jLines = @(Get-Content -LiteralPath $JournalFile -ErrorAction Stop) } catch { $jLines = @() }
        $bad = 0; $fails = 0; $skips = 0
        foreach ($jl in $jLines) {
            if (-not $jl) { continue }
            $p = $jl -split "`t", 6
            if ($p.Count -lt 6) { $bad++; continue }
            switch ($p[2]) {
                'update-fail' { $fails++ }
                'update-skipped' { $skips++ }
            }
        }
        if ($bad -gt 0) { & $add 'warn' 'journal' "$bad malformed journal line(s) - the journal may be truncated" }
        if ($fails -gt 0) { & $add 'warn' 'journal' "$fails failed update event(s) - inspect with [J] option 3 or read $JournalFile" }
        if ($skips -gt 0) { & $add 'info' 'journal' "$skips update-skipped event(s) - concurrent runs refused while one was active" }
        if ((Get-Item -LiteralPath $JournalFile).Length -gt 256KB) { & $add 'info' 'journal' "journal over 256 KB - it will rotate to .old on the next update" }
    }

    # MuMu path (existence only - the emulator probe needs the menu)
    $mumu = $null
    foreach ($p in @('C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe', 'C:\Program Files (x86)\Netease\MuMuPlayer\nx_main\MuMuManager.exe')) {
        if (Test-Path $p) { $mumu = $p; break }
    }
    if (-not $mumu) {
        & $add 'error' 'mumu' "MuMuManager.exe not found - emulator functions will not work"
    }

    # Disk space
    try {
        $drive = (Get-Item -LiteralPath $Dir).PSDrive
        $freeGB = [Math]::Round($drive.Free / 1GB, 1)
        if ($freeGB -lt 2) { & $add 'warn' 'disk' "only $freeGB GB free on $($drive.Name): - updates and backups need headroom" }
    } catch { Write-Debug "disk check failed: $($_.Exception.Message)" }

    return $findings.ToArray()
}

if ($Diagnose) {
    Write-Host ''
    Write-Host "=== Problem diagnostics: $TargetDir ===" -ForegroundColor Cyan
    Write-Host '  (read-only, local-only - no network, nothing is changed)' -ForegroundColor DarkGray
    $f = Get-BootstrapFindings -Dir $TargetDir -MenuPath (Join-Path $TargetDir 'mumu-menu.ps1') -VersionFile (Join-Path $TargetDir '.version') -JournalFile $journalFile
    $icons = @{ error = '[ERROR]'; warn = '[WARN]'; info = '[info]' }
    $colors = @{ error = 'Red'; warn = 'Yellow'; info = 'DarkGray' }
    if (@($f).Count -eq 0) {
        Write-Host '  No problems detected.' -ForegroundColor Green
        Write-Host '  Problems found: 0' -ForegroundColor Green
        exit 0
    }
    foreach ($x in $f) { Write-Host "  $($icons[$x.severity]) $($x.message)" -ForegroundColor $colors[$x.severity] }
    $errCount = @($f | Where-Object { $_.severity -eq 'error' }).Count
    $warnCount = @($f | Where-Object { $_.severity -eq 'warn' }).Count
    $infoCount = @($f | Where-Object { $_.severity -eq 'info' }).Count
    # v1.22.6 parity with the menu [DIAG]: info-only findings are a healthy
    # install - they no longer read as "Problems found: N".
    if ($errCount -eq 0 -and $warnCount -eq 0) {
        Write-Host "  Status: healthy ($infoCount info note(s) - nothing to fix)" -ForegroundColor Green
    } else {
        $color = if ($errCount -gt 0) { 'Red' } else { 'Yellow' }
        Write-Host "  Problems found: $errCount error(s), $warnCount warning(s), $infoCount info" -ForegroundColor $color
    }
    if ($errCount -gt 0 -or $warnCount -gt 0) { exit 1 } else { exit 0 }
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
        $curlArgs = @('-sS', '--fail') + $script:CurlRetryArgs + @('--connect-timeout', '30', '--max-time', '30', '-H', 'Accept: application/vnd.github.v3+json')
        if ($token) { $curlArgs += @('-H', "Authorization: token $token") }
        $curlArgs += $Url
        $result = & curl.exe @curlArgs 2>$null
        if ($LASTEXITCODE -eq 0 -and $result) {
            $resultStr = @($result) | Out-String
            # Bad credentials fallback — retry without token
            if ($token -and $resultStr -match '"message"\s*:\s*"Bad credentials"') {
                Write-Host "  Token rejected — retrying without auth..." -ForegroundColor Yellow
                $noAuthArgs = @('-sS', '--fail') + $script:CurlRetryArgs + @('--connect-timeout', '30', '--max-time', '30', '-H', 'Accept: application/vnd.github.v3+json', $Url)
                $result2 = & curl.exe @noAuthArgs 2>$null
                if ($LASTEXITCODE -eq 0 -and $result2) {
                    return (@($result2) | Out-String)
                }
                return $null
            }
            return $resultStr
        }
        if ($attempt -lt $maxRetries) {
            Write-Host "  Attempt $attempt failed (curl exit $LASTEXITCODE) - retrying in ${retryDelay}s..." -ForegroundColor Yellow
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
        $dlArgs = @('-sS', '--fail') + $script:CurlRetryArgs + @('--connect-timeout', '30', '--max-time', '120', '-L', '-H', 'Accept: application/vnd.github.v3.raw', '-o', $tmpFile)
        if ($token) { $dlArgs += @('-H', "Authorization: token $token") }
        $dlArgs += $Url
        & curl.exe @dlArgs 2>$null | Out-Null
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
        $curlArgs = @('-sS', '--fail') + $script:CurlRetryArgs + @('--connect-timeout', '30', '--max-time', '60', '-H', 'Accept: application/vnd.github.raw', '-o', $tmpFile)
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
    # Say WHY the check failed when the reason is knowable. A rate-limit
    # response arrives as a JSON body with a 'message' - without a token
    # the unauthenticated quota is only 60 requests/hour per IP, and the
    # "Could not check releases" verdict alone sends users chasing
    # network problems (seen live in the v1.22.1 E2E drill).
    $rlBody = "$releaseJson"
    if ($rlBody -match '"message"\s*:\s*"([^"]*rate limit[^"]*)"') {
        Write-Host '  GitHub API rate limit exceeded.' -ForegroundColor Yellow
        if (-not $token) {
            Write-Host '  Without a token the limit is 60 requests/hour per IP - shared networks exhaust it fast.' -ForegroundColor Yellow
            Write-Host '  Fix: run mumu-menu.ps1 once and save a token via [K] (stored DPAPI-encrypted,' -ForegroundColor Yellow
            Write-Host '  bootstrap picks it up automatically). Until then: wait for the hourly reset' -ForegroundColor Yellow
            Write-Host '  or run with -Force to download anyway (downloads also fail while limited).' -ForegroundColor Yellow
        } else {
            Write-Host '  The token quota (5000/hour) is exhausted or the token is invalid - re-save via [K].' -ForegroundColor Yellow
        }
    }
    Write-Host "  Could not check releases. Run with -Force to download anyway." -ForegroundColor Yellow
    if (-not $Force) { exit 1 }
}

if ($localTag -eq $remoteTag -and -not $Force) {
    Write-Host "  Up to date ($localTag) - nothing to download." -ForegroundColor Green
    Write-Host "  Use -Force to re-download anyway." -ForegroundColor DarkGray
    exit 0
}

# ── Dry-run: show the update plan without touching anything (issue: UX) ──
# Everything below this point that mutates state (lock, backup, downloads,
# .version, journal, self-refresh) is skipped. Only two read-only API calls
# were made before here (releases/latest + tag ref pin), exactly like a
# regular check. -Force only removes the up-to-date short-circuit above, so
# a dry-run with -Force shows the re-download plan of the current version.
if ($WhatIf) {
    Write-Host ''
    Write-Host '=== Dry-run: update plan (nothing was downloaded or changed) ===' -ForegroundColor Cyan
    if (-not $remoteTag) {
        Write-Host '  Remote version unknown - the plan cannot be built.' -ForegroundColor Yellow
        Write-Host '  A real run would say: Could not check releases. Run with -Force to download anyway.' -ForegroundColor DarkGray
        exit 1
    }
    $action = if (-not $localTag) {
        "fresh install of $remoteTag (target folder has no .version)"
    } elseif ($localTag -eq $remoteTag) {
        "re-download of the current version $remoteTag (because of -Force)"
    } else {
        "update $localTag -> $remoteTag"
    }
    Write-Host "  Action:    $action" -ForegroundColor White
    Write-Host "  Target:    $TargetDir"
    Write-Host "  Files:     $($files -join ', ')"
    Write-Host '  Sources:   GitHub contents API, tag pinned to its commit SHA (immutable)' -ForegroundColor DarkGray
    if ($NoVerify) {
        Write-Host '  Verify:    SKIPPED (-NoVerify)' -ForegroundColor Yellow
    } else {
        Write-Host '  Verify:    SHA-256 of every downloaded file vs the tag content (hash mismatch fails the update)' -ForegroundColor DarkGray
    }
    Write-Host "  Backup:    existing files would be copied to backup\\<timestamp> before replacing"
    Write-Host "  .version:  would be set to $remoteTag (only if all files succeed)"
    Write-Host "  Updater:   bootstrap-update.ps1 goes to .new and self-applies after a successful run"
    if ($token) {
        Write-Host '  API:       authenticated (5000 req/hr)' -ForegroundColor DarkGray
    } else {
        Write-Host '  API:       unauthenticated - a real run needs ~13 of the 60 req/hr budget' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host 'Run without -WhatIf to apply.' -ForegroundColor Green
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
