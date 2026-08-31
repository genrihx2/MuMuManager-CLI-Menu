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
        $sec = Get-Content -LiteralPath $tokenFile -Raw | ConvertTo-SecureString -ErrorAction Stop
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

# ── Helper: curl GET with retry ──────────────────────────────────────
function Invoke-CurlGet {
    param([string]$Url)
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        $curlCmd = "curl.exe -sS --fail --connect-timeout 30 --max-time 30 -H `"Accept: application/vnd.github.v3+json`""
        if ($token) { $curlCmd += " -H `"Authorization: token $token`"" }
        $curlCmd += " `"$Url`" 2>nul"
        $result = & cmd /c $curlCmd
        if ($LASTEXITCODE -eq 0 -and $result) {
            return ($result | Out-String)
        }
        if ($attempt -lt $maxRetries) {
            Write-Host "  Attempt $attempt failed - retrying in ${retryDelay}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $retryDelay
        }
    }
    return $null
}

# ── Helper: Download file with curl ──────────────────────────────────
function Download-File {
    param([string]$Url, [string]$Dest)
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        $tmpFile = $Dest + '.tmp'
        $dlCmd = "curl.exe -sS --fail --retry 2 --connect-timeout 30 --max-time 120 -L -o `"$tmpFile`""
        if ($token) { $dlCmd += " -H `"Authorization: token $token`"" }
        $dlCmd += " `"$Url`" 2>nul"
        & cmd /c $dlCmd | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmpFile) -and (Get-Item -LiteralPath $tmpFile).Length -gt 0) {
            $size = (Get-Item -LiteralPath $tmpFile).Length
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
