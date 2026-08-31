# Bootstrap Update Script - Run this SEPARATELY from PowerShell
# Downloads the latest mumu-menu.ps1 and replaces the old one.
# Use when the [U] menu option is broken (e.g. after a failed update).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -TargetDir "C:\MyPath"
#   powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1 -Force

param(
    [string]$TargetDir = $PSScriptRoot,
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
$files      = @('mumu-menu.ps1', 'SKILL.md', 'README.md')
$maxRetries = 3
$retryDelay = 3   # seconds between retries

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
        $enc  = [System.IO.File]::ReadAllBytes($tokenFile)
        $dec  = [System.Security.Cryptography.ProtectedData]::Unprotect(
                    $enc, $null,
                    [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        $token = [System.Text.Encoding]::UTF8.GetString($dec).Trim()
    } catch {
        Write-Host "  Warning: Cannot read token: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

$headers = @{
    'Accept'     = 'application/vnd.github.v3+json'
    'User-Agent' = 'MuMuManager-CLI-Menu-Bootstrap'
}
if ($token) {
    $headers['Authorization'] = "token $token"
    Write-Host "  Token: loaded" -ForegroundColor DarkGray
} else {
    Write-Host "  Token: not found (60 req/hr limit)" -ForegroundColor DarkGray
}
Write-Host ''

# ── Helper: HTTP GET with retry ─────────────────────────────────────
function Invoke-GitHubGet {
    param([string]$Url, [int]$TimeoutSec = 30)
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec
            return $resp.Content
        } catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 403 -or $code -eq 429) {
                Write-Host "  Rate limited ($code) - retrying in ${retryDelay}s..." -ForegroundColor Yellow
            } elseif ($attempt -lt $maxRetries) {
                Write-Host "  Attempt $attempt failed ($code) - retrying in ${retryDelay}s..." -ForegroundColor Yellow
            } else {
                throw
            }
            Start-Sleep -Seconds $retryDelay
        }
    }
}

# ── Helper: Download file with progress ──────────────────────────────
function Download-File {
    param([string]$Url, [string]$Dest)
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $tmpFile = $Dest + '.tmp'
            # Use curl.exe for progress bar (matches main script behavior)
            $curlArgs = @('-s', '-S', '--fail', '--retry', '2', '--retry-delay', '2',
                          '--connect-timeout', '30', '--max-time', '120',
                          '-L', '-o', $tmpFile)
            if ($token) { $curlArgs += @('-H', "Authorization: token $token") }
            $curlArgs += $Url

            $prevBg = $Host.UI.RawUI.BackgroundColor
            & curl.exe @curlArgs 2>&1 | Out-Null
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $tmpFile)) {
                throw "curl exit code $exitCode"
            }

            $size = (Get-Item -LiteralPath $tmpFile).Length
            if ($size -eq 0) { throw 'downloaded file is empty' }

            Move-Item -LiteralPath $tmpFile -Destination $Dest -Force
            return $size
        } catch {
            if (Test-Path -LiteralPath ($Dest + '.tmp')) {
                Remove-Item -LiteralPath ($Dest + '.tmp') -Force -ErrorAction SilentlyContinue
            }
            if ($attempt -lt $maxRetries) {
                Write-Host "  Attempt $attempt failed - retrying in ${retryDelay}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $retryDelay
            } else {
                throw
            }
        }
    }
}

# ── Fast version check ──────────────────────────────────────────────
$localTag = ''
$versionFile = Join-Path $TargetDir '.version'
if (Test-Path -LiteralPath $versionFile) {
    try { $localTag = (Get-Content -LiteralPath $versionFile -Raw).Trim() } catch { Write-Debug "Version file read failed: $($_.Exception.Message)" }
}

$remoteTag = ''
$remoteBody = ''
try {
    $releaseJson = Invoke-GitHubGet "$apiBase/releases/latest" 15
    $release = $releaseJson | ConvertFrom-Json
    if ($release.tag_name) {
        $remoteTag  = $release.tag_name
        $remoteBody = if ($release.body) { $release.body } else { '' }
    }
} catch {
    Write-Host "  Could not check releases: $($_.Exception.Message)" -ForegroundColor Yellow
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
    # Download from the tagged release via raw content endpoint
    $url = "https://raw.githubusercontent.com/$repo/$remoteTag/$f"

    Write-Host "  $f" -ForegroundColor Yellow -NoNewline
    try {
        $size = Download-File $url $dest
        $sizeKB = '{0:N1}' -f ($size / 1024)
        Write-Host "  OK  ${sizeKB} KB" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

# ── Update .version file ─────────────────────────────────────────────
if ($remoteTag -and $ok -gt 0) {
    try {
        Set-Content -Path $versionFile -Value $remoteTag -NoNewline -Encoding UTF8 -Force
    } catch {
        Write-Host "  Warning: Could not update .version ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ''
if ($fail -eq 0 -and $ok -gt 0) {
    Write-Host "Done: $ok file(s) updated to $remoteTag" -ForegroundColor Green
    Write-Host "Restart the menu to use the new version." -ForegroundColor Green
} elseif ($fail -gt 0) {
    Write-Host "Done: $ok ok, $fail failed" -ForegroundColor Yellow
    if ($backedUp) {
        Write-Host "Backup saved: $backupDir" -ForegroundColor DarkGray
        Write-Host "To restore: copy files from backup back to $TargetDir" -ForegroundColor DarkGray
    }
} else {
    Write-Host "Nothing downloaded." -ForegroundColor Yellow
}
