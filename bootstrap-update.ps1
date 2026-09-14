# Bootstrap Update Script - Run this SEPARATELY from PowerShell
# Downloads the latest mumu-menu.ps1 and replaces the old one.
# Use when the [U] menu option is broken (e.g. after a failed update).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -TargetDir "C:\MyPath"
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -Force
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -LogDir "D:\logs"
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
    [switch]$Force
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

foreach ($f in $files) {
    $dest = Join-Path $TargetDir $f
    # The updater itself goes to .new: never overwrite the running script.
    if ($f -eq 'bootstrap-update.ps1') { $dest = "$dest.new" }
    $tag = if ($remoteTag) { $remoteTag } else { 'main' }
    $url = "https://api.github.com/repos/$repo/contents/$f`?ref=$tag"

    Write-Host "  $f" -ForegroundColor Yellow -NoNewline
    $size = Download-File $url $dest
    if ($size -gt 0) {
        $sizeKB = '{0:N1}' -f ($size / 1024)
        Write-Host "  OK  ${sizeKB} KB" -ForegroundColor Green
        $ok++
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
    Write-UpdateJournal -EventType 'update-ok' -From $localTag -To $remoteTag -Detail "$ok file(s) updated"
    # Self-refresh: apply the freshly downloaded updater now - PowerShell
    # has already parsed this script, so overwriting the file is safe.
    if (Apply-PendingUpdater -Dir $TargetDir -From $localTag -To $remoteTag) {
        Write-Host "  Updater refreshed: bootstrap-update.ps1 now matches $remoteTag." -ForegroundColor Green
    } elseif (Test-Path -LiteralPath (Join-Path $TargetDir 'bootstrap-update.ps1.new')) {
        Write-Host "  Updater .new saved (file busy) - the menu will apply it at startup." -ForegroundColor Yellow
    }
    Write-Host "Done: $ok file(s) updated to $remoteTag" -ForegroundColor Green
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
