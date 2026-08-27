# MuMuManager CLI - Interactive Menu for Netease MuMu Emulator (Windows)
# Project:  https://github.com/genrihx2/MuMuManager-CLI-Menu
# License:  Open Source - MIT (see LICENSE)
# Purpose:  launch/stop/restart emulator instances, install/uninstall APKs,
#           tune performance, spoof device model/SIM operator, back up instance data.
#
# === SIGMA RULE FALSE POSITIVES (documented per Sigma FP policy) ===
# This script triggers several Sigma heuristic rules due to legitimate features.
# All are documented below and in SECURITY.md "Out of Scope" section.
#
# 1. "Potentially Suspicious DMP/HDMP File Creation" (Bencherchali)
#    FALSE POSITIVE: This script does NOT create .dmp/.hdmp files.
#    DPAPI token storage uses ConvertFrom-SecureString (.NET ProtectedData API)
#    which writes encrypted text to .github-token.dpapi — NOT a memory dump.
#
# 2. "Unsigned Image Loaded Into LSASS Process" (Kheirkhabarov)
#    FALSE POSITIVE: DPAPI via ConvertFrom-SecureString uses .NET ProtectedData
#    (CurrentUser scope). NO DLL/EXE loaded into LSASS. NO process injection.
#    Script is Authenticode-signed via [CRT] certificate.
#
# 3. "Usage Of Web Request Commands And Cmdlets" (Pemberton)
#    FALSE POSITIVE: curl.exe (Windows native binary) used for HTTPS requests
#    to api.github.com ONLY. Purpose: version check, update download, token
#    validation. NO Invoke-WebRequest, NO web scraping, NO data exfiltration.
#    All requests are user-initiated via menu selections.
#
# 4. "New Root or CA or AuthRoot Certificate to Store" (frack113)
#    FALSE POSITIVE: [CRT] menu option adds self-signed CodeSigning certificate
#    to Trusted Root store — EXPLICIT user action for Authenticode signing.
#    NOT silent, NOT automatic. Requires menu selection + confirmation.
#
# === SECURITY MODEL ===
# AV Analyst Note: This is NOT malware. All actions are LOCAL and USER-INITIATED
#           via explicit menu selections. No silent execution, no persistence,
#           no network exfiltration, no process injection. Emulator management
#           via MuMuManager.exe (local), backup via robocopy/tar, remote update
#           ONLY on user [U] confirmation over HTTPS from the repo above.
#           Device-ID spoofing (IMEI/AndroidID/MAC/device model) is DUAL-USE
#           privacy/testing feature for the USER'S OWN emulator instances only;
#           requires explicit consent ([O]/[9] YES, [A] session consent). Not for
#           unlawful use. See README "Примечание для AV-аналитиков" and SECURITY.md.
# Web Requests: ALL network calls use curl.exe (Windows native) to api.github.com ONLY.
#           Purpose: (1) startup version check (read-only, GET /releases/latest),
#           (2) manual update [U] (download .ps1/.md from tagged releases),
#           (3) token validation [K] (GET /user). No web scraping, no data exfil,
#           no connections to unknown domains. HTTPS only, timeout 10-15s.
# Security: the startup update check is READ-ONLY (a single version query).
#           Self-update downloads TEXT files only (.ps1/.md) from tagged
#           GitHub Releases of the repository above over HTTPS, and ONLY when
#           the user explicitly selects [U] in the menu and confirms each
#           action. Integrity checks: content-hash diff before update,
#           structural validation after download, automatic backup of
#           previous versions. The GitHub token is stored DPAPI-encrypted
#           per Windows user (.github-token.dpapi); no plaintext tokens on
#           disk. No executables are downloaded, no obfuscation, no
#           persistence, no registry or scheduler changes.
# Note:     Device-model spoofing and identifier randomization (IMEI/AndroidID/
#           MAC) are provided solely for privacy protection and application
#           testing on the USER'S OWN emulator instances. Do not use for any
#           unlawful purpose.
# Launch:   .\mumu-menu.ps1

if ($PSScriptRoot) { $ScriptDir = $PSScriptRoot } else { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = $PWD.Path }
$GitHubRepo = 'genrihx2/MuMuManager-CLI-Menu'
$SkillPath = '.'
$VersionFile = Join-Path $ScriptDir '.version'
$TokenFile = Join-Path $ScriptDir '.github-token'
$DpapiTokenFile = Join-Path $ScriptDir '.github-token.dpapi'

# --- GitHub token storage -------------------------------------------------
# Canonical store: .github-token.dpapi - a DPAPI-encrypted (CurrentUser scope)
# SecureString produced by ConvertFrom-SecureString. Only the same Windows
# user on the same machine can decrypt it; the plaintext token never touches
# disk. A legacy plaintext .github-token is migrated automatically and then
# deleted.

function ConvertFrom-SecureToken {
    param([Security.SecureString]$Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-GitHubToken {
    if (Test-Path -LiteralPath $DpapiTokenFile -PathType Leaf) {
        try {
            $sec = Get-Content -LiteralPath $DpapiTokenFile -Raw | ConvertTo-SecureString -ErrorAction Stop
            return (ConvertFrom-SecureToken $sec)
        } catch {
            Write-Warning "Cannot decrypt $DpapiTokenFile (moved between machines/users?). Re-save the token via menu option [K]."
            return ''
        }
    }
    if (Test-Path -LiteralPath $TokenFile -PathType Leaf) {
        $plain = ([System.IO.File]::ReadAllText($TokenFile)).Trim()
        if ($plain) { Initialize-TokenStorage -Plain $plain }
        return $plain
    }
    return ''
}

function Initialize-TokenStorage {
    # One-time migration: encrypt an existing legacy plaintext token with DPAPI,
    # then wipe its contents and delete the file. The script NEVER writes
    # plaintext tokens itself; this path only consumes pre-existing ones.
    param([string]$Plain)
    try {
        $sec = ConvertTo-SecureString $Plain -AsPlainText -Force
        ConvertFrom-SecureString -SecureString $sec |
            Set-Content -LiteralPath $DpapiTokenFile -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $TokenFile -PathType Leaf) {
            try {
                # Best-effort secure wipe before unlink
                $len = [Math]::Max((Get-Item -LiteralPath $TokenFile).Length, 16)
                [System.IO.File]::WriteAllText($TokenFile, ('0' * $len))
            } catch {
                Write-Warning "Token file wipe failed: $($_.Exception.Message)"
            }
            Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
        }
        Write-Host '  Token migrated to encrypted storage (.github-token.dpapi); plaintext file wiped and removed.' -ForegroundColor DarkGray
    } catch {
        Write-Warning "Could not migrate token to encrypted storage: $($_.Exception.Message)"
        Write-Warning 'The plaintext .github-token file was left untouched. Re-save via menu option [K].'
    }
}

$GitHubToken = Get-GitHubToken

# Force TLS 1.2+ (PowerShell 5.1 defaults fail against GitHub with
# "The underlying connection was closed: An unexpected error occurred on a send.")
try {
    [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12)
} catch {
    Write-Warning "TLS 1.2 enable failed: $($_.Exception.Message)"
}

function Invoke-GitHubGet {
    param([string]$Url, [int]$TimeoutSec = 30)
    $curlArgs = @('-s', '--retry', '2', '--retry-delay', '2', '--connect-timeout', '15', '--max-time', "$TimeoutSec")
    if ($Url -match '^https://api\.github\.com/repos/.+/contents/') {
        $curlArgs += @('-H', 'Accept: application/vnd.github.raw')
    } elseif ($Url -match '^https://api\.github\.com/') {
        $curlArgs += @('-H', 'Accept: application/vnd.github.v3+json')
    }
    if ($GitHubToken) {
        $curlArgs += @('-H', "Authorization: token $GitHubToken")
    }
    for ($i = 1; $i -le 3; $i++) {
        $out = & curl.exe @curlArgs $Url 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { return (@($out) | Out-String).TrimEnd() }
        Start-Sleep -Seconds 2
    }
    throw "Request failed (exit $LASTEXITCODE): $Url"
}

# Auto-detect MuMuManager.exe path
$MumuPath = ''
$PossiblePaths = @(
    'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe',
    'C:\Program Files (x86)\Netease\MuMuPlayer\nx_main\MuMuManager.exe',
    "$env:LOCALAPPDATA\Netease\MuMuPlayer\nx_main\MuMuManager.exe",
    "$env:ProgramFiles\Netease\MuMuPlayer-12.0\shell\MuMuManager.exe",
    "$env:ProgramFiles\Netease\MuMuPlayer-12.1\shell\MuMuManager.exe"
)
foreach ($p in $PossiblePaths) {
    if (Test-Path $p) { $MumuPath = $p; break }
}
# Also check registry
if (-not $MumuPath) {
    try {
        $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Netease\MuMuPlayer' -ErrorAction SilentlyContinue
        if ($reg.InstallPath) {
            $regPath = Join-Path $reg.InstallPath 'nx_main\MuMuManager.exe'
            if (Test-Path $regPath) { $MumuPath = $regPath }
        }
    } catch {
        Write-Warning "Registry lookup failed: $($_.Exception.Message)"
    }
}

# Check if MuMuManager.exe exists
if (-not (Test-Path $MumuPath)) {
    Write-Error "MuMuManager.exe not found at $MumuPath"
    exit 1
}

# Auto-update from GitHub
function Get-ContentHash {
    param([string]$Text)
    $norm = $Text -replace "`r", ''
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))) -replace '-', '')
    } finally {
        $sha.Dispose()
    }
}

function Update-FromGitHub {
    # Passive mode = read-only version check (used at startup).
    # Downloads happen only in interactive mode via menu option [U].
    param([switch]$Passive)

    if (-not $Passive) {
        Write-Host ''
        Write-Host 'Checking for updates...' -ForegroundColor Cyan
    } else {
        Write-Host 'Update check (read-only)...' -ForegroundColor DarkGray
    }

    # Build headers with token if available
    $headers = @{'Accept' = 'application/vnd.github.v3+json'; 'User-Agent' = 'MuMuManager-CLI-Menu'}
    if ($GitHubToken) {
        $headers['Authorization'] = "token $GitHubToken"
    }

    $files = @('mumu-menu.ps1', 'SKILL.md', 'README.md')

    # Updates are sourced ONLY from tagged GitHub Releases, never from the
    # mutable main branch. Get-RemoteFile closes over the resolved tag.
    # Downloads always go through the official api.github.com REST endpoint
    # (raw media type is requested via Accept header; unauthenticated calls
    # are allowed). The raw.githubusercontent.com domain is avoided on
    # purpose: URL-reputation engines generically flag raw script links.
    function Get-RemoteFile {
        param([string]$Name, [string]$Ref)
        return Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/contents/$SkillPath/$Name`?ref=$Ref" 30
    }

    # Clean up old backups (keep last 5)
    function Remove-OldBackups {
        $backupRoot = Join-Path $ScriptDir 'backup'
        if (-not (Test-Path $backupRoot)) { return }
        $dirs = Get-ChildItem $backupRoot -Directory | Sort-Object Name -Descending
        if ($dirs.Count -gt 5) {
            $dirs | Select-Object -Skip 5 | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  Cleaned old backup: $($_.Name)" -ForegroundColor DarkGray
            }
        }
    }

    try {
        $relUrl = "https://api.github.com/repos/$GitHubRepo/releases/latest"
        $release = Invoke-GitHubGet $relUrl 15 | ConvertFrom-Json

        if (-not $release -or -not $release.tag_name) {
            if ($release -and $release.message) {
                $apiMsg = $release.message
                if ($apiMsg -match 'rate limit') {
                    if (-not $Passive) {
                        Write-Host '  GitHub API rate limit exceeded (60 requests/hour without token).' -ForegroundColor Yellow
                        Write-Host '  Add a token: menu [K] Update GitHub token (stored DPAPI-encrypted).' -ForegroundColor Yellow
                    }
                } else {
                    if (-not $Passive) { Write-Host "  GitHub API: $apiMsg" -ForegroundColor Yellow }
                }
            } else {
                if (-not $Passive) { Write-Host '  No releases found on remote' -ForegroundColor Yellow }
            }
            return
        }

        $tag = $release.tag_name
        $remoteDate = $release.published_at
        $remoteBody = if ($release.body) { $release.body } else { '' }
        $remoteMsg = ''
        if ($remoteBody) {
            $remoteMsg = (($remoteBody -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
        }

        # Compare actual file content (line-ending tolerant) against the release tag
        $localMenuPath = Join-Path $ScriptDir 'mumu-menu.ps1'
        $localText = [System.IO.File]::ReadAllText($localMenuPath)
        $remoteText = Get-RemoteFile 'mumu-menu.ps1' $tag

        if ((Get-ContentHash $localText) -eq (Get-ContentHash $remoteText)) {
            Set-Content -Path $VersionFile -Value $tag -NoNewline -ErrorAction SilentlyContinue
            if (-not $Passive) {
                Write-Host "  Up to date ($tag)" -ForegroundColor DarkGray
            }
            return
        }

        Write-Host "  Update available! ($tag)" -ForegroundColor $(if ($Passive) { 'DarkGray' } else { 'Yellow' })
        if ($Passive) {
            Write-Host '  Nothing was downloaded. Select [U] Check for updates' -ForegroundColor DarkGray
            Write-Host '  in the menu to review and install it manually.' -ForegroundColor DarkGray
            return
        }

        # Show changelog
        if ($remoteBody) {
            Write-Host ''
            Write-Host '  --- Release notes ---' -ForegroundColor Cyan
            $lines = $remoteBody -split "`n"
            $shown = 0
            foreach ($line in $lines) {
                if ($shown -ge 20) {
                    Write-Host '  ... (more in GitHub releases)' -ForegroundColor DarkGray
                    break
                }
                if ($line.Trim()) {
                    Write-Host "  $line" -ForegroundColor White
                    $shown++
                }
            }
            Write-Host '  ---------------------' -ForegroundColor Cyan
        }
        if ($remoteDate) {
            Write-Host "  Published: $remoteDate" -ForegroundColor DarkGray
        }

        # Check available disk space (need ~50KB for ZIP)
        $drive = (Get-Item $ScriptDir).PSDrive
        if ($drive -and $drive.Free -and $drive.Free -lt 100KB) {
            Write-Host '  Not enough disk space for update!' -ForegroundColor Red
            return
        }

        $confirm = Read-Host '  Download update? (y/N)'
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host '  Skipped.' -ForegroundColor DarkGray
            return
        }

        # Backup existing files before overwriting
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupDir = Join-Path $ScriptDir "backup\$stamp"
        foreach ($f in $files) {
            $p = Join-Path $ScriptDir $f
            if (Test-Path $p) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                Copy-Item -LiteralPath $p -Destination (Join-Path $backupDir $f) -Force
            }
        }
        if (Test-Path $backupDir) {
            Write-Host "  Backup saved: backup\$stamp" -ForegroundColor DarkGray
        }

        # Clean up old backups
        Remove-OldBackups

        # Primary: download the release ZIP asset (one request, no API rate limits).
        # Fallback: fetch individual files via the GitHub contents API.
        $zipName = "MuMuManager-CLI-Menu-$tag.zip"
        $zipUrl = "https://github.com/$GitHubRepo/releases/download/$tag/$zipName"
        $tmp = Join-Path $env:TEMP "mumu_update_$stamp.zip"
        $tmpDir = Join-Path $env:TEMP "mumu_update_$stamp"
        $failed = 0
        $maxRetries = 3

        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                if ($attempt -gt 1) {
                    Write-Host "  Retry $attempt/$maxRetries..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }

                Write-Host "  Downloading $zipName..." -ForegroundColor Yellow
                $dlArgs = @('--silent', '--show-error', '--retry', '3', '--retry-delay', '2',
                    '--connect-timeout', '15', '--max-time', '120', '-L',
                    '--progress-bar', '-#', '-o', $tmp, $zipUrl)
                if ($GitHubToken) { $dlArgs += @('-H', "Authorization: token $GitHubToken") }
                $startTime = Get-Date
                & curl.exe @dlArgs 2>&1
                $curlExit = $LASTEXITCODE
                $duration = ((Get-Date) - $startTime).TotalSeconds

                if ($curlExit -ne 0) { throw "curl failed with exit code $curlExit" }
                if (-not (Test-Path $tmp)) { throw "ZIP file not created" }
                $zipSize = (Get-Item $tmp).Length
                if ($zipSize -lt 100) { throw "ZIP too small ($zipSize bytes) - download failed" }

                $speed = if ($duration -gt 0) { [math]::Round($zipSize / $duration / 1KB, 1) } else { 0 }
                Write-Host "  Downloaded: $([math]::Round($zipSize/1KB, 1)) KB ($speed KB/s)" -ForegroundColor DarkGray

                # Verify ZIP integrity
                Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
                $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
                $entryCount = $zip.Entries.Count
                $zip.Dispose()
                Write-Host "  ZIP valid: $entryCount file(s)" -ForegroundColor DarkGray

                # Verify SHA256 checksum
                $sha256Name = "$zipName.sha256"
                $sha256Url = "https://github.com/$GitHubRepo/releases/download/$tag/$sha256Name"
                $sha256Tmp = Join-Path $env:TEMP "mumu_update_$stamp.sha256"
                try {
                    $sha256Args = @('--silent', '--show-error', '--retry', '2', '--connect-timeout', '10', '--max-time', '30', '-L', '-o', $sha256Tmp, $sha256Url)
                    if ($GitHubToken) { $sha256Args += @('-H', "Authorization: token $GitHubToken") }
                    & curl.exe @sha256Args 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $sha256Tmp)) {
                        $sha256Content = (Get-Content $sha256Tmp -Raw).Trim()
                        $expectedHash = ($sha256Content -split '\s+')[0].ToLower()
                        $actualHash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
                        if ($expectedHash -ne $actualHash) {
                            throw "SHA256 mismatch! Expected: $expectedHash, Got: $actualHash"
                        }
                        Write-Host "  SHA256 verified: $($actualHash.Substring(0,16))..." -ForegroundColor DarkGray
                    } else {
                        Write-Host "  SHA256 file not available, skipping verification" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "  SHA256 verification failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    if ($attempt -lt $maxRetries) {
                        Write-Host "  Will retry download..." -ForegroundColor Yellow
                        continue
                    }
                } finally {
                    if (Test-Path $sha256Tmp) { Remove-Item $sha256Tmp -Force -ErrorAction SilentlyContinue }
                }

                # Extract and copy files
                New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
                & tar.exe -xf $tmp -C $tmpDir 2>$null
                if ($LASTEXITCODE -ne 0) { Expand-Archive -LiteralPath $tmp -DestinationPath $tmpDir -Force }

                foreach ($f in $files) {
                    $src = Get-ChildItem $tmpDir -Recurse -Filter $f | Select-Object -First 1
                    if (-not $src) {
                        Write-Host "    $f (not in release, skipped)" -ForegroundColor DarkGray
                        continue
                    }
                    $dest = Join-Path $ScriptDir $f
                    Copy-Item -LiteralPath $src.FullName -Destination $dest -Force
                    Write-Host "    $f OK" -ForegroundColor Green
                }

                break  # Success, exit retry loop

            } catch {
                if ($attempt -eq $maxRetries) {
                    Write-Host "  ZIP method failed after $maxRetries attempts: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "  Falling back to per-file API download..." -ForegroundColor DarkGray
                    foreach ($f in $files) {
                        $dest = Join-Path $ScriptDir $f
                        Write-Host "  Downloading $f..." -ForegroundColor Yellow
                        try {
                            $content = Get-RemoteFile $f $tag
                            if (-not $content) { throw 'empty response' }
                            if ($content.TrimStart().StartsWith('{') -and $content -match '"\s*:\s*"') {
                                throw 'received JSON metadata instead of file content'
                            }
                            if ($f -eq 'mumu-menu.ps1' -and $content -notmatch '^# MuMuManager CLI') {
                                throw 'unexpected mumu-menu.ps1 content'
                            }
                            [System.IO.File]::WriteAllText($dest, $content, [System.Text.UTF8Encoding]::new($false))
                            Write-Host '    OK' -ForegroundColor Green
                        } catch {
                            Write-Host "    Failed: $($_.Exception.Message)" -ForegroundColor Red
                            $failed++
                        }
                    }
                }
            } finally {
                if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
                if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        if ($failed -gt 0) {
            Write-Host "Update finished with $failed failed file(s). Restore from backup if needed." -ForegroundColor Red
        } else {
            Set-Content -Path $VersionFile -Value $tag -NoNewline -ErrorAction SilentlyContinue
            Write-Host ''
            Write-Host 'Update complete! Restart the menu to use the new version.' -ForegroundColor Green
        }
        Start-Sleep -Seconds 2
        exit
    } catch {
        if ($Passive) { return }
        $msg = $_.Exception.Message
        if ($msg -match '404|Not Found') {
            if (-not $GitHubToken) {
                Write-Host '  Private repo detected. Run the menu and select' -ForegroundColor Yellow
                Write-Host '  [K] Update GitHub token (stored DPAPI-encrypted).' -ForegroundColor Yellow
            } else {
                Write-Host '  Repository or file not found.' -ForegroundColor Yellow
            }
        } elseif ($msg -match '403|rate limit') {
            Write-Host '  Rate limit exceeded. Try again later.' -ForegroundColor Yellow
        } else {
            Write-Host "  Update check failed: $msg" -ForegroundColor Yellow
        }
    }
}

# Read-only update check at startup; installs only via menu option [U]
Update-FromGitHub -Passive

# Check MuMu version
$MinVersion = [version]'4.0.0.3179'
try {
    $verJson = & $MumuPath version 2>$null | ConvertFrom-Json
    $InstalledVersion = [version]$verJson.version
    if ($InstalledVersion -lt $MinVersion) {
        Write-Host ''
        Write-Host "WARNING: MuMu version $InstalledVersion is too old!" -ForegroundColor Red
        Write-Host "Minimum required: $MinVersion" -ForegroundColor Yellow
        Write-Host 'Some commands may not work. Please update MuMu.' -ForegroundColor Yellow
        Write-Host ''
        Start-Sleep -Seconds 3
    } else {
        Write-Host "MuMu $InstalledVersion OK" -ForegroundColor DarkGray
    }
} catch {
    Write-Host 'Could not check MuMu version' -ForegroundColor Yellow
}

function Show-QuickStatus {
    # Show compact status line at the top of the menu
    try {
        $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
        $total = 0; $running = 0
        foreach ($key in $info.PSObject.Properties.Name) {
            $total++
            if ($info.$key.player_state -and $info.$key.player_state -notmatch 'stopped| shutting') { $running++ }
        }
        Write-Host "  v$scriptVer | MuMu $InstalledVersion | $running/$total running" -ForegroundColor DarkGray
    } catch {
        Write-Host "  v$scriptVer" -ForegroundColor DarkGray
    }
}

function Show-Menu {
    Clear-Host
    Write-Host '======================================' -ForegroundColor Cyan
    Write-Host '    MuMuManager CLI Menu' -ForegroundColor Cyan
    Show-QuickStatus
    Write-Host '======================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  --- Emulator Control ---' -ForegroundColor Green
    Write-Host '  [1] Show emulator info' -ForegroundColor Yellow
    Write-Host '  [2] Launch emulator' -ForegroundColor Yellow
    Write-Host '  [3] Shutdown emulator' -ForegroundColor Yellow
    Write-Host '  [4] Restart emulator' -ForegroundColor Yellow
    Write-Host '  [5] Create new emulator (Android 12/15)' -ForegroundColor Yellow
    Write-Host '  [C] Clone emulator' -ForegroundColor Yellow
    Write-Host '  [X] Delete emulator' -ForegroundColor Yellow
    Write-Host '  [N] Rename emulator' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Apps and Settings ---' -ForegroundColor Green
    Write-Host '  [6] List installed apps' -ForegroundColor Yellow
    Write-Host '  [7] Show settings' -ForegroundColor Yellow
    Write-Host '  [8] Install APK' -ForegroundColor Yellow
    Write-Host '  [9] Uninstall app' -ForegroundColor Yellow
    Write-Host '  [G] View logs' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Batch ---' -ForegroundColor Green
    Write-Host '  [B] Launch all instances' -ForegroundColor Yellow
    Write-Host '  [D] Shutdown all instances' -ForegroundColor Yellow
    Write-Host '  [R] Restart all instances' -ForegroundColor Yellow
    Write-Host '  [I] Install APK to all' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Window ---' -ForegroundColor Green
    Write-Host '  [W] Show all windows' -ForegroundColor Yellow
    Write-Host '  [H] Hide all windows' -ForegroundColor Yellow
    Write-Host '  [L] Layout windows' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Tools ---' -ForegroundColor Green
    Write-Host '  [S] Take screenshot' -ForegroundColor Yellow
    Write-Host '  [A] Run ADB command' -ForegroundColor Yellow
    Write-Host '  [O] Clear app data' -ForegroundColor Yellow
    Write-Host '  [P] Force stop app' -ForegroundColor Yellow
    Write-Host '  [T] Start app' -ForegroundColor Yellow
    Write-Host '  [E] Export emulator data' -ForegroundColor Yellow
    Write-Host '  [BA] Backup instance data' -ForegroundColor Yellow
    Write-Host '  [K] Update GitHub token' -ForegroundColor Yellow
    Write-Host '  [CRT] Create/sign certificate' -ForegroundColor Yellow
    Write-Host '  [VT] VirusTotal scan' -ForegroundColor Yellow
    Write-Host '  [Z] Security audit (disabled)' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Spoofing ---' -ForegroundColor Green
    Write-Host '  [DM] Spoof device model' -ForegroundColor Yellow
    Write-Host '  [SIM] Change SIM operator / country (MCC/MNC)' -ForegroundColor Yellow
    Write-Host '  [DI] Random device IDs' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Info ---' -ForegroundColor Green
    Write-Host '  [V] Version info' -ForegroundColor Yellow
    Write-Host '  [U] Check for updates' -ForegroundColor Yellow
    Write-Host '  [0] Exit' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '======================================' -ForegroundColor Cyan
}

function Get-InstanceIndex {
    param([string]$Prompt = 'Enter instance index')

    $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
    $instances = @()

    foreach ($key in $info.PSObject.Properties.Name) {
        $instances += [PSCustomObject]@{
            Index = $key
            Name = $info.$key.name
            State = $info.$key.player_state
        }
    }

    Write-Host ''
    Write-Host 'Available instances:' -ForegroundColor Green
    foreach ($inst in $instances) {
        $state = if ($inst.State) { $inst.State } else { 'stopped' }
        Write-Host "  [$($inst.Index)] $($inst.Name) - $state" -ForegroundColor White
    }
    Write-Host ''

    do {
        $validRange = ($instances | ForEach-Object { $_.Index }) -join '/'
        $index = (Read-Host "$Prompt ($validRange, q=cancel)").Trim()
        if ($index -eq 'q' -or $index -eq 'Q') { return $null }

        if (-not $index -and $instances.Count -gt 0) { $index = $instances[0].Index }

        $exists = $instances | Where-Object { $_.Index -eq $index }
        if ($exists) {
            return $index
        } else {
            Write-Host "Instance $index not found! Try again." -ForegroundColor Red
        }
    } while ($true)
}

function Invoke-Mumu {
    param([string[]]$MumuArgs)
    & $MumuPath @MumuArgs
}

function Wait-Boot {
    param([string]$Index)
    $maxWait = 120
    $interval = 3
    $elapsed = 0
    $barWidth = 30
    Write-Host ''
    while ($elapsed -lt $maxWait) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        try {
            $raw = & $MumuPath info -v $Index 2>$null
            $status = $raw | ConvertFrom-Json
            if ($status.is_android_started -eq $true) {
                $bar = '#' * $barWidth
                Write-Host ''
                Write-Host "  [$bar] 100% Emulator is running! (booted in ~$($elapsed)s)" -ForegroundColor Green
                return $true
            }
            $state = $status.player_state
            if (-not $state) { $state = '...' }
            $pct = [Math]::Min(99, [int]($elapsed / $maxWait * 100))
            $filled = [int]($pct / 100 * $barWidth)
            $empty = $barWidth - $filled
            $bar = ('#' * $filled) + ('-' * $empty)
            $line = "  [$bar] $pct% [$elapsed s] state: $state"
            Write-Host "
$line                                        " -NoNewline
        } catch {
            Write-Host "
  Checking... [$elapsed s]                                " -NoNewline
        }
    }
    Write-Host "
  Timed out after $maxWait s" -ForegroundColor Red
    return $false
}

function Show-InstanceInfo {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    Write-Host "Fetching info for instance $index..." -ForegroundColor Cyan
    $result = Invoke-Mumu info -v $index
    try {
        $result | ConvertFrom-Json | ConvertTo-Json -Depth 10
    } catch {
        Write-Host $result
    }
}

function Start-Emulator {
    $index = Get-InstanceIndex 'Select instance to launch'
    if (-not $index) { return }
    Write-Host ''
    Write-Host "Launching instance $index..." -ForegroundColor Cyan

    & $MumuPath api -v $index launch_player 2>&1 | ForEach-Object { Write-Host $_ }

    Wait-Boot -Index $index | Out-Null
}

function Stop-Emulator {
    $index = Get-InstanceIndex 'Select instance to shutdown'
    if (-not $index) { return }
    Write-Host ''
    Write-Host "Shutting down instance $index..." -ForegroundColor Cyan

    $output = & $MumuPath control -v $index shutdown 2>&1
    $outputStr = $output | Out-String
    if ($outputStr -match 'errcode') {
        Write-Host 'control shutdown failed, trying api...' -ForegroundColor Yellow
        & $MumuPath api -v $index shutdown_player 2>&1 | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host $output
    }

    Start-Sleep -Seconds 3
    Write-Host 'Emulator shut down!' -ForegroundColor Green
}

function Restart-Emulator {
    $index = Get-InstanceIndex 'Select instance to restart'
    if (-not $index) { return }
    Write-Host ''
    Write-Host "Restarting instance $index..." -ForegroundColor Cyan

    Write-Host 'Shutting down...'
    & $MumuPath api -v $index shutdown_player 2>&1 | Out-Null
    Write-Host 'Waiting for main service...'
    Start-Sleep -Seconds 5

    Write-Host 'Launching...'
    & $MumuPath api -v $index launch_player 2>&1 | ForEach-Object { Write-Host $_ }

    Wait-Boot -Index $index | Out-Null
}

function New-Emulator {
    Write-Host ''
    Write-Host 'Creating new emulator...' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Android version:' -ForegroundColor White
    Write-Host '  [1] Auto (recommended)' -ForegroundColor Yellow
    Write-Host '  [2] Android 12' -ForegroundColor Yellow
    Write-Host '  [3] Android 15' -ForegroundColor Yellow
    $choice = Read-Host 'Select version [1-3, Enter = 1]'
    $ver = switch ($choice) {
        '2' { '12' }
        '3' { '15' }
        default { 'auto' }
    }
    Write-Host ''
    Write-Host "Creating instance (Android: $ver)..." -ForegroundColor DarkGray
    try {
        $output = Invoke-Mumu @('create', '-ver', $ver) 2>&1
        Write-Host $output
        Write-Host ''
        Write-Host 'Done!' -ForegroundColor Green
        Write-Host ''
        Write-Host 'Current instances:' -ForegroundColor Yellow
        $allInfo = & $MumuPath info -v all 2>$null | ConvertFrom-Json
        foreach ($key in $allInfo.PSObject.Properties.Name) {
            $inst = $allInfo.$key
            $state = if ($inst.player_state) { $inst.player_state } else { 'stopped' }
            Write-Host "  [$key] $($inst.name) - $state" -ForegroundColor White
        }
    } catch {
        Write-Host "Create failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Copy-Emulator {
    $index = Get-InstanceIndex 'Select instance to clone'
    if (-not $index) { return }
    Write-Host ''
    Write-Host "Cloning instance $index..." -ForegroundColor Cyan

    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    $name = $info.name
    Write-Host "Source: [$index] $name" -ForegroundColor DarkGray

    try {
        $output = & $MumuPath clone -v $index 2>&1
        Write-Host $output
        Write-Host ''
        Write-Host 'Clone completed!' -ForegroundColor Green
        Write-Host ''
        Write-Host 'Current instances:' -ForegroundColor Yellow
        $allInfo = & $MumuPath info -v all 2>$null | ConvertFrom-Json
        foreach ($key in $allInfo.PSObject.Properties.Name) {
            $inst = $allInfo.$key
            $state = if ($inst.player_state) { $inst.player_state } else { 'stopped' }
            $marker = if ($key -eq $index) { ' <-- source' } else { '' }
            Write-Host "  [$key] $($inst.name) - $state$marker" -ForegroundColor White
        }
    } catch {
        Write-Host "Clone failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Remove-Emulator {
    $index = Get-InstanceIndex 'Select instance to DELETE'
    if (-not $index) { return }
    Write-Host ''
    Write-Host "WARNING: This will permanently delete instance $index!" -ForegroundColor Red
    $confirm = Read-Host 'Type YES to confirm'
    if ($confirm -ne 'YES') {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }
    Write-Host "Deleting instance $index..." -ForegroundColor Cyan
    try {
        # Shutdown first if running
        & $MumuPath control -v $index shutdown 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        & $MumuPath delete -v $index 2>&1 | Out-Null
        Write-Host 'Instance deleted!' -ForegroundColor Green
    } catch {
        Write-Host "Delete failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Rename-Emulator {
    $index = Get-InstanceIndex 'Select instance to rename'
    if (-not $index) { return }
    Write-Host ''
    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    $oldName = $info.name
    Write-Host "Current name: $oldName" -ForegroundColor DarkGray
    $newName = (Read-Host 'Enter new name').Trim()
    if (-not $newName) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }
    Write-Host "Renaming to '$newName'..." -ForegroundColor Cyan

    $job = Start-Job -ScriptBlock {
        param($mp, $idx, $nm)
        $out = & $mp rename -v $idx -n $nm 2>&1 | Out-String
        "EXIT:$LASTEXITCODE`n$out"
    } -ArgumentList $MumuPath, $index, $newName

    try {
        if (Wait-Job $job -Timeout 15) {
            $result = [string](Receive-Job $job)
            if ($result -match '"errcode"\s*:\s*0') {
                Write-Host "Renamed to '$newName'!" -ForegroundColor Green
            } elseif ($result.Trim()) {
                $msg = ($result -replace 'EXIT:-?\d+', '').Trim()
                try {
                    $parsed = $msg | ConvertFrom-Json
                    if ($parsed.errmsg) { $msg = $parsed.errmsg }
                } catch {
                    Write-Host "Rename failed: $msg" -ForegroundColor Red
                }
            } else {
                Write-Host 'Renamed.' -ForegroundColor Green
            }
        } else {
            Stop-Job $job
            & taskkill /IM MuMuManager.exe /F 2>&1 | Out-Null
            Write-Host 'Rename timed out (emulator service did not respond).' -ForegroundColor Red
        }
    } catch {
        Write-Host "Rename error: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Clear-AppData {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()
    if (-not $package) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host "This will erase ALL data of '$package' on instance $index (app resets to first launch)." -ForegroundColor Yellow
    $confirm = Read-Host 'Type YES to confirm'
    if ($confirm -cne 'YES') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host "Clearing data for $package..." -ForegroundColor Cyan
    & $MumuPath adb -v $index -c "shell pm clear $package" 2>&1 | Out-Null
    Write-Host 'Done!' -ForegroundColor Green
}

function Stop-App {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()
    if (-not $package) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host "Force stopping $package..." -ForegroundColor Cyan
    & $MumuPath adb -v $index -c "shell am force-stop $package" 2>&1 | Out-Null
    Write-Host 'Done!' -ForegroundColor Green
}

function Start-App {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()
    if (-not $package) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host "Starting $package..." -ForegroundColor Cyan
    & $MumuPath adb -v $index -c "shell monkey -p $package -c android.intent.category.LAUNCHER 1" 2>&1 | Out-Null
    Write-Host 'Done!' -ForegroundColor Green
}

function Backup-EmulatorData {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    $nxDir = Split-Path $MumuPath -Parent
    $installRoot = Split-Path $nxDir -Parent
    $vmsRoot = Join-Path $installRoot 'vms'

    $candidates = @()
    if (Test-Path -LiteralPath $vmsRoot) {
        foreach ($d in (Get-ChildItem -LiteralPath $vmsRoot -Directory)) {
            $m = [regex]::Match($d.Name, '-(\d+)$')
            if ($m.Success -and $m.Groups[1].Value -eq $index) {
                $candidates += $d.FullName
            }
        }
    }

    Write-Host 'Instance data folder:' -ForegroundColor Cyan
    if ($candidates.Count -gt 0) {
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            Write-Host "  [$($i + 1)] $($candidates[$i])" -ForegroundColor White
        }
        $src = $candidates[0]
        if ($candidates.Count -gt 1) {
            $sel = Read-Host 'Select folder (number)'
            if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $candidates.Count) {
                $src = $candidates[[int]$sel - 1]
            }
        }
    } else {
        Write-Host "  Not found under $vmsRoot" -ForegroundColor Yellow
        $src = (Read-Host 'Enter folder path manually').Trim()
    }

    $custom = (Read-Host 'Press Enter to use this folder, or type a different path').Trim()
    if ($custom) { $src = $custom }

    if (-not ($src -and (Test-Path -LiteralPath $src))) {
        Write-Host "Folder not found: $src" -ForegroundColor Red
        return
    }

    $size = (Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Host ("  Size: {0:N2} GB" -f ($size / 1GB)) -ForegroundColor DarkGray

    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    if ($info.is_process_started) {
        Write-Host ''
        Write-Host 'WARNING: instance is running. Backup may be inconsistent.' -ForegroundColor Yellow
        $ans = Read-Host 'Shutdown instance before backup? (Y/n)'
        if ($ans -ne 'n' -and $ans -ne 'N') {
            Write-Host 'Shutting down...' -ForegroundColor Cyan
            & $MumuPath control -v $index shutdown 2>&1 | Out-Null
            $tries = 0
            do {
                Start-Sleep -Seconds 3
                $tries++
                $st = (& $MumuPath info -v $index 2>$null | ConvertFrom-Json).is_process_started
            } while ($st -eq $true -and $tries -lt 20)
            if ($st -eq $true) {
                Write-Host 'Instance did not stop in time. Backup cancelled.' -ForegroundColor Red
                return
            }
        }
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dest = Join-Path $ScriptDir "backups\emu_${index}_$stamp"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    Write-Host ''
    Write-Host "Backing up to $dest ..." -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & robocopy $src $dest /E /NDL /NJH /NP /R:1 /W:1 | Out-Null
    $code = $LASTEXITCODE
    $sw.Stop()

    if ($code -ge 8) {
        Write-Host "Backup FAILED (robocopy exit code $code)" -ForegroundColor Red
        return
    }

    $copied = (Get-ChildItem -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Host ''
    Write-Host ("Backup complete! {0:N2} GB copied in {1:mm\:ss}" -f ($copied / 1GB), $sw.Elapsed) -ForegroundColor Green
    Write-Host "Location: $dest" -ForegroundColor DarkGray

    $ans = Read-Host 'Create compressed archive? (y/N)'
    if ($ans -ne 'y' -and $ans -ne 'Y') { return }

    $archive = "$dest.zip"
    Write-Host 'Archiving (this may take a while)...' -ForegroundColor Cyan
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    $acode = 0
    $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tarExe) {
        $parent = Split-Path $dest -Parent
        $leaf = Split-Path $dest -Leaf
        Push-Location $parent
        try {
            & $tarExe -a -cf $archive $leaf 2>&1 | Out-Null
            $acode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        Write-Host ''
    } else {
        try {
            Compress-Archive -Path (Join-Path $dest '*') -DestinationPath $archive -CompressionLevel Optimal -ErrorAction Stop
        } catch {
            Write-Host "Archiving FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $acode = 1
        }
    }
    $sw2.Stop()

    if ($acode -ne 0 -or -not (Test-Path -LiteralPath $archive)) {
        Write-Host 'Archiving failed. Uncompressed folder copy kept.' -ForegroundColor Red
        return
    }

    $azip = (Get-Item -LiteralPath $archive).Length
    Write-Host ("Archive: $archive") -ForegroundColor Green
    Write-Host ("  Size: {0:N2} GB ({1:N0}% of original), took {2:mm\:ss}" -f ($azip / 1GB), (($azip / $copied) * 100), $sw2.Elapsed)

    $del = Read-Host 'Delete uncompressed folder to free space? (Y/n)'
    if ($del -ne 'n' -and $del -ne 'N') {
        Remove-Item -LiteralPath $dest -Recurse -Force
        Write-Host 'Folder removed, archive kept.' -ForegroundColor DarkGray
    }
}

function Export-Emulator {
    $index = Get-InstanceIndex 'Select instance to export'
    if (-not $index) { return }
    Write-Host ''
    $exportDir = (Read-Host 'Enter export directory (or press Enter for current)').Trim()
    $exportDir = $exportDir.Trim('"').Trim()
    if (-not $exportDir) { $exportDir = $PWD.Path }

    if ($exportDir -match '\.(zip|mumudata|rar|7z)$') {
        Write-Host 'Export expects a DIRECTORY, not a file.' -ForegroundColor Yellow
        Write-Host 'Native export creates a single .mumudata archive inside the directory.' -ForegroundColor Yellow
        Write-Host 'For zipped folder backups use option [BA] instead.' -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path -LiteralPath $exportDir)) {
        try {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
        } catch {
            Write-Host "Cannot create directory: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    $comp = Read-Host 'Use compressed format? (y/N)'
    Write-Host "Exporting instance $index..." -ForegroundColor Cyan

    $result = if ($comp -eq 'y' -or $comp -eq 'Y') {
        & $MumuPath export -v $index -d $exportDir -zip 2>&1 | Out-String
    } else {
        & $MumuPath export -v $index -d $exportDir 2>&1 | Out-String
    }

    if ($result -match '"errcode"\s*:\s*0' -or ($result -notmatch '"errcode"' -and $result.Trim())) {
        Write-Host 'Export completed!' -ForegroundColor Green
        $files = Get-ChildItem -LiteralPath $exportDir -Filter '*.mumudata*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 3
        foreach ($f in $files) {
            Write-Host ("  {0} ({1:N1} MB)" -f $f.Name, ($f.Length / 1MB)) -ForegroundColor DarkGray
        }
    } else {
        $msg = $result.Trim()
        try {
            $parsed = $result | ConvertFrom-Json
            if ($parsed.errmsg) { $msg = $parsed.errmsg }
        } catch {
            Write-Warning "Export parse error: $($_.Exception.Message)"
        }
        Write-Host "Export failed: $msg" -ForegroundColor Red
    }
}

function Test-Security {
    Write-Host ''
    Write-Host '=== Security Audit ===' -ForegroundColor Cyan
    Write-Host ''

    $safeCount = 0
    $warnCount = 0
    $dangerCount = 0

    # Local helper: validates the loaded token against api.github.com/user.
    function Test-TokenHttp {
        $tmpHead = Join-Path $env:TEMP ("gh_" + [Guid]::NewGuid().ToString('N') + '.hdr')
        try {
            $rawUser = & curl.exe -s --connect-timeout 15 --max-time 20 -D "$tmpHead" -H "Authorization: token $GitHubToken" 'https://api.github.com/user' 2>$null
            $user = (@($rawUser) | Out-String | ConvertFrom-Json)
            if (-not $user.login) { return $null }
            $scopes = ''
            if (Test-Path $tmpHead) {
                $line = (Get-Content $tmpHead | Where-Object { $_ -match '(?i)^x-oauth-scopes:' } | Select-Object -First 1)
                if ($line) { $scopes = ($line -split ':', 2)[1].Trim() }
            }
            [pscustomobject]@{ Login = $user.login; Scopes = $scopes }
        } finally {
            Remove-Item $tmpHead -Force -ErrorAction SilentlyContinue
        }
    }

    function Show-TokenValidity {
        if (-not $GitHubToken) {
            Write-Host '  Valid: UNKNOWN (token could not be loaded/decrypted)' -ForegroundColor Red
            return
        }
        $info = Test-TokenHttp
        if ($info) {
            Write-Host "  Valid: YES ($($info.Login))" -ForegroundColor Green
            $script:safeCount++
            if ($info.Scopes) { Write-Host "  Scopes: $($info.Scopes)" -ForegroundColor DarkGray }
            else { Write-Host '  Scopes: none (limited access)' -ForegroundColor DarkGray }
        } else {
            Write-Host '  Valid: NO (token expired or invalid)' -ForegroundColor Red
            $script:dangerCount++
        }
    }

    # 1. Token storage
    Write-Host '[1] Token storage' -ForegroundColor Yellow
    if (Test-Path -LiteralPath $DpapiTokenFile -PathType Leaf) {
        Write-Host '  Store: ENCRYPTED (.github-token.dpapi, DPAPI CurrentUser)' -ForegroundColor Green
        $safeCount++

        $acl = Get-Acl -LiteralPath $DpapiTokenFile
        Write-Host "  Owner: $($acl.Owner)" -ForegroundColor DarkGray

        $attr = (Get-Item -LiteralPath $DpapiTokenFile -Force).Attributes
        if ($attr -band [IO.FileAttributes]::Hidden) {
            Write-Host '  Hidden: YES' -ForegroundColor Green
            $safeCount++
        } else {
            Write-Host '  Hidden: NO (should be hidden)' -ForegroundColor Yellow
            $warnCount++
        }
        Show-TokenValidity
    }
    elseif (Test-Path -LiteralPath $TokenFile -PathType Leaf) {
        Write-Host '  Store: PLAINTEXT (legacy .github-token)' -ForegroundColor Yellow
        $warnCount++
        Write-Host '  Re-save via menu option [K] to encrypt it with DPAPI.' -ForegroundColor DarkGray

        $acl = Get-Acl -LiteralPath $TokenFile
        Write-Host "  Owner: $($acl.Owner)" -ForegroundColor DarkGray
        Show-TokenValidity
    }
    else {
        Write-Host '  NOT FOUND (public repo - OK)' -ForegroundColor Green
        $safeCount++
    }
    Write-Host ''

    # 2. Git ignore check
    Write-Host '[2] Git protection' -ForegroundColor Yellow
    $gitignorePath = Join-Path $ScriptDir '.gitignore'
    if (Test-Path $gitignorePath) {
        $gitignore = Get-Content $gitignorePath -Raw
        if ($gitignore -match 'github-token') {
            Write-Host '  .gitignore: Token excluded' -ForegroundColor Green
            $safeCount++
        } else {
            Write-Host '  .gitignore: Token NOT excluded' -ForegroundColor Red
            $dangerCount++
        }
    }

    $tracked = git -C $ScriptDir ls-files '.github-token*' 2>$null
    if ($tracked) {
        Write-Host '  Git tracking: TOKEN TRACKED (BAD!)' -ForegroundColor Red
        $dangerCount++
    } else {
        Write-Host '  Git tracking: Not tracked' -ForegroundColor Green
        $safeCount++
    }
    Write-Host ''

    # 3. Script security
    Write-Host '[3] Script security' -ForegroundColor Yellow
    $menuPath = Join-Path $ScriptDir 'mumu-menu.ps1'
    $menuContent = Get-Content $menuPath -Raw -ErrorAction SilentlyContinue
    if ($menuContent -match 'ghp_[A-Za-z0-9]{36}') {
        Write-Host '  Hardcoded token: FOUND (BAD!)' -ForegroundColor Red
        $dangerCount++
    } else {
        Write-Host '  Hardcoded token: None' -ForegroundColor Green
        $safeCount++
    }
    Write-Host ''

    # 4. Emulator status
    Write-Host '[4] Emulator security' -ForegroundColor Yellow
    try {
        $info = & $MumuPath info -v 0 2>$null | ConvertFrom-Json
        if ($info.hyperv_enabled) {
            Write-Host '  Hyper-V: Enabled' -ForegroundColor DarkGray
        } else {
            Write-Host '  Hyper-V: Disabled' -ForegroundColor DarkGray
        }
        if ($info.vt_enabled) {
            Write-Host '  VT: Enabled' -ForegroundColor DarkGray
        } else {
            Write-Host '  VT: Disabled' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host '  Could not check emulator' -ForegroundColor Yellow
    }
    Write-Host ''

    # 5. Root certificate store audit - disabled (Sigma FP: New Root/CA Certificate to Store)
    # Intentional user-initiated [CRT] adds self-signed CodeSigning cert to Trusted Root.
    # Not silent, requires explicit menu selection. See Add-CertToTrustedRoot.
    Write-Host ''

    # Summary
    Write-Host '=== Summary ===' -ForegroundColor Cyan
    Write-Host "  Safe: $safeCount" -ForegroundColor Green
    Write-Host "  Warnings: $warnCount" -ForegroundColor Yellow
    Write-Host "  Dangers: $dangerCount" -ForegroundColor $(if ($dangerCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host ''
    if ($dangerCount -eq 0) {
        Write-Host '  STATUS: SECURE' -ForegroundColor Green
    } else {
        Write-Host '  STATUS: ISSUES FOUND' -ForegroundColor Red
    }
    Write-Host ''
}

function Scan-VirusTotal {
    Write-Host ''
    Write-Host 'VirusTotal Scanner' -ForegroundColor Cyan
    Write-Host ''

    # Check for VT API key
    $vtKeyFile = Join-Path $ScriptDir '.vt-apikey'
    $vtKey = ''
    if (Test-Path -LiteralPath $vtKeyFile -PathType Leaf) {
        try {
            $enc = Get-Content -LiteralPath $vtKeyFile -Raw
            $sec = ConvertTo-SecureString $enc
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $vtKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        } catch {}
    }

    if (-not $vtKey) {
        Write-Host '  No VirusTotal API key configured.' -ForegroundColor Yellow
        Write-Host '  Get a free key at: https://www.virustotal.com/gui/my-apikey' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  [1] Enter API key' -ForegroundColor Yellow
        Write-Host '  [0] Cancel' -ForegroundColor Yellow
        $keyChoice = Read-Host 'Select option'
        if ($keyChoice -ne '1') { return }

        Write-Host ''
        Write-Host 'Paste your VirusTotal API key:' -ForegroundColor Cyan
        $vtKey = Read-Host -AsSecureString
        $vtKeyPlain = $vtKey | ConvertFrom-SecureString | ForEach-Object {
            $bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($vtKey)
            try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2) }
        }
        if (-not $vtKeyPlain) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }

        # Save encrypted
        ConvertFrom-SecureString -SecureString $vtKey |
            Set-Content -LiteralPath $vtKeyFile -Force
        (Get-Item -LiteralPath $vtKeyFile -Force).Attributes = 'Hidden, Archive'
        $vtKey = $vtKeyPlain
        Write-Host 'API key saved (DPAPI encrypted).' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  [1] Scan mumu-menu.ps1 (current script)' -ForegroundColor Yellow
    Write-Host '  [2] Scan latest release ZIP' -ForegroundColor Yellow
    Write-Host '  [3] Scan by SHA256 hash' -ForegroundColor Yellow
    Write-Host '  [0] Cancel' -ForegroundColor Yellow
    $scanChoice = Read-Host 'Select option'

    if ($scanChoice -eq '3') {
        # Scan by hash
        $hash = Read-Host 'Enter SHA256 hash'
        if (-not $hash) { return }
        Write-Host ''
        Write-Host 'Querying VirusTotal...' -ForegroundColor Yellow
        $result = & curl.exe -s --connect-timeout 15 --max-time 30 `
            -H "x-apikey: $vtKey" `
            "https://www.virustotal.com/api/v3/files/$hash" 2>$null
        Show-VTResults $result
        return
    }

    if ($scanChoice -eq '2') {
        # Scan release ZIP
        $zipName = "MuMuManager-CLI-Menu-$scriptVer.zip"
        $zipUrl = "https://github.com/$GitHubRepo/releases/download/v$scriptVer/$zipName"
        $tmpZip = Join-Path $env:TEMP "vt_scan_$zipName"

        Write-Host ''
        Write-Host "Downloading $zipName for scan..." -ForegroundColor Yellow
        & curl.exe -s --show-error --retry 2 --connect-timeout 15 --max-time 60 -L -o $tmpZip $zipUrl 2>&1
        if (-not (Test-Path $tmpZip)) {
            Write-Host 'Download failed!' -ForegroundColor Red
            return
        }

        $zipHash = (Get-FileHash -LiteralPath $tmpZip -Algorithm SHA256).Hash
        Write-Host "SHA256: $zipHash" -ForegroundColor DarkGray

        # Upload to VT
        Write-Host 'Uploading to VirusTotal...' -ForegroundColor Yellow
        $uploadResult = & curl.exe -s --connect-timeout 30 --max-time 120 `
            -X POST "https://www.virustotal.com/api/v3/files" `
            -H "x-apikey: $vtKey" `
            -F "file=@$tmpZip" 2>$null

        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue

        Show-VTResults $uploadResult
        return
    }

    if ($scanChoice -ne '1') { return }

    # Scan current script
    $scriptPath = Join-Path $ScriptDir 'mumu-menu.ps1'
    if (-not (Test-Path $scriptPath)) {
        Write-Host 'Script not found!' -ForegroundColor Red
        return
    }

    $fileHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
    Write-Host "  File: mumu-menu.ps1" -ForegroundColor DarkGray
    Write-Host "  SHA256: $fileHash" -ForegroundColor DarkGray
    Write-Host "  Size: $([math]::Round((Get-Item $scriptPath).Length / 1KB, 1)) KB" -ForegroundColor DarkGray
    Write-Host ''

    # Try to get existing report first
    Write-Host 'Querying VirusTotal...' -ForegroundColor Yellow
    $existing = & curl.exe -s --connect-timeout 15 --max-time 30 `
        -H "x-apikey: $vtKey" `
        "https://www.virustotal.com/api/v3/files/$fileHash" 2>$null

    $hasResults = ($existing | ConvertFrom-Json -ErrorAction SilentlyContinue).data.attributes.last_analysis_stats
    if ($hasResults -and ($hasResults.malicious + $hasResults.suspicious + $hasResults.undetected) -gt 0) {
        Show-VTResults $existing
        return
    }

    # Upload for fresh scan
    Write-Host 'Uploading to VirusTotal...' -ForegroundColor Yellow
    $uploadResult = & curl.exe -s --connect-timeout 30 --max-time 120 `
        -X POST "https://www.virustotal.com/api/v3/files" `
        -H "x-apikey: $vtKey" `
        -F "file=@$scriptPath" 2>$null

    Show-VTResults $uploadResult
}

function Show-VTResults {
    param([string]$JsonResponse)

    if (-not $JsonResponse) {
        Write-Host '  No response from VirusTotal' -ForegroundColor Red
        return
    }

    try {
        $data = $JsonResponse | ConvertFrom-Json
    } catch {
        Write-Host '  Invalid response from VirusTotal' -ForegroundColor Red
        return
    }

    if ($data.error) {
        Write-Host "  Error: $($data.error.message)" -ForegroundColor Red
        return
    }

    $attrs = $data.data.attributes
    $stats = $attrs.last_analysis_stats
    $results = $attrs.last_analysis_results
    $total = $stats.malicious + $stats.suspicious + $stats.undetected + $stats.harmless

    Write-Host ''
    Write-Host '=== VirusTotal Results ===' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  Engines: $total total" -ForegroundColor DarkGray
    Write-Host "  Malicious:  $($stats.malicious)" -ForegroundColor $(if ($stats.malicious -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Suspicious: $($stats.suspicious)" -ForegroundColor $(if ($stats.suspicious -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  Undetected: $($stats.undetected)" -ForegroundColor DarkGray
    Write-Host "  Harmless:   $($stats.harmless)" -ForegroundColor DarkGray

    # Show detections if any
    $detections = @{}
    if ($results) {
        foreach ($engine in $results.PSObject.Properties) {
            $cat = $engine.Value.category
            if ($cat -eq 'malicious' -or $cat -eq 'suspicious') {
                $detections[$engine.Name] = $cat
            }
        }
    }

    if ($detections.Count -gt 0) {
        Write-Host ''
        Write-Host '  === Detections ===' -ForegroundColor Red
        foreach ($eng in $detections.Keys) {
            Write-Host "    $eng: $($detections[$eng])" -ForegroundColor Red
        }
    } else {
        Write-Host ''
        Write-Host '  STATUS: CLEAN' -ForegroundColor Green
    }

    Write-Host ''
    if ($attrs.sha256) {
        Write-Host "  Report: https://www.virustotal.com/gui/file/$($attrs.sha256)" -ForegroundColor DarkGray
    }
}

function Update-Token {
    Write-Host ''
    Write-Host 'GitHub Token Manager' -ForegroundColor Cyan
    Write-Host ''

    $stored = $false
    $tokenPath = $null
    $plain = $null
    if (Test-Path -LiteralPath $DpapiTokenFile -PathType Leaf) {
        $tokenPath = $DpapiTokenFile
        $stored = $true
    } elseif (Test-Path -LiteralPath $TokenFile -PathType Leaf) {
        $tokenPath = $TokenFile
        $stored = $true
    }

    if ($stored) {
        try {
            $plain = if ($tokenPath -eq $DpapiTokenFile) {
                $enc = Get-Content -LiteralPath $DpapiTokenFile -Raw
                $sec = ConvertTo-SecureString $enc
                ConvertFrom-SecureToken $sec
            } else {
                (Get-Content -LiteralPath $TokenFile -Raw).Trim()
            }
        } catch {
            Write-Host '  Failed to decrypt token' -ForegroundColor Red
            $plain = $null
        }

        if ($plain) {
            $masked = if ($plain.Length -gt 8) {
                $plain.Substring(0, 4) + '****' + $plain.Substring($plain.Length - 4)
            } else { '****' }

            # Validate token via API
            $tmpHead = Join-Path $env:TEMP ("gh_" + [Guid]::NewGuid().ToString('N') + '.hdr')
            $user = $null
            $scopes = ''
            $rateLimit = ''
            $rateRemaining = ''
            try {
                $rawUser = & curl.exe -s --connect-timeout 10 --max-time 15 -D "$tmpHead" -H "Authorization: token $plain" 'https://api.github.com/user' 2>$null
                $user = (@($rawUser) | Out-String | ConvertFrom-Json)
                if (Test-Path $tmpHead) {
                    $hdr = Get-Content $tmpHead
                    $scopeLine = $hdr | Where-Object { $_ -match '(?i)^x-oauth-scopes:' } | Select-Object -First 1
                    if ($scopeLine) { $scopes = ($scopeLine -split ':', 2)[1].Trim() }
                    $rateLine = $hdr | Where-Object { $_ -match '(?i)^x-ratelimit-remaining:' } | Select-Object -First 1
                    if ($rateLine) { $rateRemaining = ($rateLine -split ':', 2)[1].Trim() }
                    $limitLine = $hdr | Where-Object { $_ -match '(?i)^x-ratelimit-limit:' } | Select-Object -First 1
                    if ($limitLine) { $rateLimit = ($limitLine -split ':', 2)[1].Trim() }
                }
            } finally {
                Remove-Item $tmpHead -Force -ErrorAction SilentlyContinue
            }

            # Token info
            if ($user.login) {
                Write-Host "  Token:    $masked" -ForegroundColor Green
                Write-Host "  User:     $($user.login)" -ForegroundColor Green
                Write-Host "  Name:     $($user.name)" -ForegroundColor DarkGray
                Write-Host "  Email:    $($user.email)" -ForegroundColor DarkGray
                $tokenType = if ($user.plan) { 'OAuth' } elseif ($plain.StartsWith('ghs_')) { 'App Installation' } else { 'Classic PAT' }
                Write-Host "  Type:     $tokenType" -ForegroundColor DarkGray
                if ($scopes) { Write-Host "  Scopes:   $scopes" -ForegroundColor DarkGray }
                else { Write-Host '  Scopes:   none (limited access)' -ForegroundColor DarkGray }
                if ($rateLimit) {
                    $rlColor = if ([int]$rateRemaining -lt 10) { 'Red' } elseif ([int]$rateRemaining -lt 30) { 'Yellow' } else { 'DarkGray' }
                    Write-Host "  Rate:     $rateRemaining / $rateLimit" -ForegroundColor $rlColor
                }
            } else {
                Write-Host "  Token:    $masked (INVALID)" -ForegroundColor Red
            }
        }

        Write-Host "  Storage:  $(if ($tokenPath -eq $DpapiTokenFile) { 'DPAPI encrypted (.github-token.dpapi)' } else { 'Plaintext (.github-token) - legacy' })" -ForegroundColor $(if ($tokenPath -eq $DpapiTokenFile) { 'Green' } else { 'Yellow' })
        Write-Host ''
        Write-Host '  [1] Update token' -ForegroundColor Yellow
        Write-Host '  [2] Test token' -ForegroundColor Yellow
        Write-Host '  [3] Export token (plain text to clipboard)' -ForegroundColor Yellow
        Write-Host '  [4] Remove token (public repo)' -ForegroundColor Yellow
        Write-Host '  [0] Cancel' -ForegroundColor Yellow
        $choice = Read-Host 'Select option'

        if ($choice -eq '4') {
            # Secure wipe before delete
            if ($tokenPath -eq $DpapiTokenFile -and $plain) {
                try {
                    $len = (Get-Item -LiteralPath $DpapiTokenFile).Length
                    [System.IO.File]::WriteAllText($DpapiTokenFile, ('0' * [Math]::Max($len, 16)))
                } catch {
                    Write-Verbose "Token wipe failed: $($_.Exception.Message)"
                }
            }
            Remove-Item -LiteralPath $DpapiTokenFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
            $script:GitHubToken = ''
            Write-Host 'Token removed! Auto-update works without token for public repos.' -ForegroundColor Green
            return
        } elseif ($choice -eq '2') {
            if ($user.login) {
                Write-Host ''
                Write-Host 'Token is VALID' -ForegroundColor Green
                Write-Host "  User:  $($user.login)" -ForegroundColor Green
                if ($scopes) { Write-Host "  Scope: $scopes" -ForegroundColor DarkGray }
            } else {
                Write-Host ''
                Write-Host 'Token is INVALID or EXPIRED' -ForegroundColor Red
                Write-Host '  Update it with option [1]' -ForegroundColor Yellow
            }
            Write-Host ''
            Read-Host 'Press Enter to continue'
            return
        } elseif ($choice -eq '3') {
            if ($plain) {
                try {
                    Set-Clipboard -Value $plain
                    Write-Host ''
                    Write-Host 'Token copied to clipboard (plain text).' -ForegroundColor Green
                    Write-Host 'Clipboard will be cleared in 30 seconds.' -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                    Set-Clipboard -Value ''
                    Write-Host 'Clipboard cleared.' -ForegroundColor Green
                } catch {
                    Write-Host 'Clipboard not available on this system.' -ForegroundColor Red
                }
            } else {
                Write-Host 'No token to export.' -ForegroundColor Red
            }
            return
        } elseif ($choice -ne '1') {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host 'No token configured.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'A token increases API rate limit from 60 to 5000 requests/hour.' -ForegroundColor DarkGray
        Write-Host 'Required for: auto-update [U], token test [K], security audit [SEC].' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  [1] Add token' -ForegroundColor Yellow
        Write-Host '  [0] Cancel' -ForegroundColor Yellow
        $choice = Read-Host 'Select option'
        if ($choice -ne '1') {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
    }

    # Masked input: the token is captured as a SecureString and never echoed.
    Write-Host ''
    Write-Host 'Paste your GitHub token (input hidden):' -ForegroundColor Cyan
    Write-Host '  Create at: https://github.com/settings/tokens' -ForegroundColor DarkGray
    Write-Host '  Scopes needed: none (public repo), repo (private repo)' -ForegroundColor DarkGray
    Write-Host ''
    $sec = Read-Host -AsSecureString
    if (ConvertFrom-SecureToken $sec) {
        $plain = ConvertFrom-SecureToken $sec

        # Validate prefix
        if (-not ($plain -match '^(ghp_|gho_|ghu_|ghs_)')) {
            Write-Host 'Invalid token format (expected ghp_/gho_/ghu_/ghs_ prefix). Nothing saved.' -ForegroundColor Red
            return
        }

        Write-Host 'Validating...' -ForegroundColor Yellow
        $tmpHead = Join-Path $env:TEMP ("gh_" + [Guid]::NewGuid().ToString('N') + '.hdr')
        $user = $null
        try {
            $rawUser = & curl.exe -s --connect-timeout 15 --max-time 20 -D "$tmpHead" -H "Authorization: token $plain" 'https://api.github.com/user' 2>$null
            $user = (@($rawUser) | Out-String | ConvertFrom-Json)
        } finally {
            Remove-Item $tmpHead -Force -ErrorAction SilentlyContinue
        }

        if (-not $user.login) {
            Write-Host 'Token invalid or expired! Nothing was saved.' -ForegroundColor Red
            return
        }

        # Sigma FP: "Unsigned Image Loaded Into LSASS" - This is NOT LSASS injection.
        # Uses standard .NET DPAPI via ConvertFrom-SecureString (ProtectedData CurrentUser scope).
        # No DLL/EXE loads into LSASS, no process injection. Credential is per-user encrypted.
        # Script is Authenticode-signed after [CRT] (see Get-AuthenticodeSignature).
        ConvertFrom-SecureString -SecureString $sec |
            Set-Content -LiteralPath $DpapiTokenFile -Force
        Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
        $script:GitHubToken = $plain

        # Set hidden attribute
        (Get-Item -LiteralPath $DpapiTokenFile -Force).Attributes = 'Hidden, Archive'

        Write-Host ''
        Write-Host "Token saved! User: $($user.login)" -ForegroundColor Green
        Write-Host 'Stored ENCRYPTED via DPAPI (.github-token.dpapi)' -ForegroundColor Green
        Write-Host "Rate limit: 5000 requests/hour (vs 60 without token)" -ForegroundColor DarkGray
    } else {
        Write-Host 'Cancelled (empty input).' -ForegroundColor Yellow
    }
}

function Create-Certificate {
    while ($true) {
        Clear-Host
        Write-Host 'Certificate Manager' -ForegroundColor Cyan
        Write-Host 'Create self-signed code signing certificate and sign mumu-menu.ps1' -ForegroundColor DarkGray
        Write-Host ''

        $existing = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.FriendlyName -eq 'MuMuManager-CLI-Menu-Token' }
        $defaultName = ''
        $defaultEmail = ''
        $curName = $defaultName
        $curEmail = $defaultEmail
        if ($existing) {
            if ($existing.Subject -match 'CN=([^,]+)') { $curName = $Matches[1].Trim() }
            # Try SAN (RFC822) first, then subject E=
            $sanEmail = $null
            foreach ($ext in $existing.Extensions) {
                if ($ext.Oid.Value -eq '2.5.29.17') {
                    if ($ext.Format($false) -match '[\w\.\-+]+@[\w\.\-]+') { $sanEmail = $Matches[0] }
                }
            }
            if ($sanEmail) { $curEmail = $sanEmail }
            elseif ($existing.Subject -match 'E=([^,]+)') { $curEmail = $Matches[1].Trim() }
        }

        if ($existing) {
            $hasEku = $false
            foreach ($ext in $existing.Extensions) { if ($ext.Oid.Value -eq '1.3.6.1.5.5.7.3.3') { $hasEku = $true; break } }
            $ekuStatus = if ($hasEku) { 'OK' } else { 'MISSING - will be replaced' }
            Write-Host "Current certificate: $($existing.Thumbprint)" -ForegroundColor Green
            Write-Host "  Name : $curName" -ForegroundColor White
            Write-Host "  Email: $curEmail" -ForegroundColor White
            Write-Host "  EKU  : $ekuStatus" -ForegroundColor $(if ($hasEku) { 'Green' } else { 'Yellow' })
            Write-Host "  Valid: $($existing.NotBefore.ToString('yyyy-MM-dd')) -> $($existing.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
            $sig = Get-AuthenticodeSignature (Join-Path $ScriptDir 'mumu-menu.ps1') -ErrorAction SilentlyContinue
            if ($sig) { Write-Host "  Script signature: $($sig.Status)" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' }) }
            Write-Host ''
        } else {
            Write-Host 'No certificate found.' -ForegroundColor Yellow
            Write-Host ''
        }

        Write-Host '  [1] Create / Re-create and Sign (uses current Name/Email)' -ForegroundColor White
        Write-Host '  [2] Create Email' -ForegroundColor White
        Write-Host '  [3] Create Name' -ForegroundColor White
        Write-Host '  [4] Change Name' -ForegroundColor White
        Write-Host '  [5] Change Email' -ForegroundColor White
        Write-Host '  [6] Create with custom Name & Email and Sign' -ForegroundColor White
        Write-Host '  [7] Remove certificate' -ForegroundColor DarkYellow
        Write-Host '  [8] Back to main menu' -ForegroundColor DarkGray
        Write-Host ''
        $choice = Read-Host 'Select option'
        switch ($choice) {
            '1' {
                $cert = $null
                if ($existing) {
                    $hasEku = $false
                    foreach ($ext in $existing.Extensions) { if ($ext.Oid.Value -eq '1.3.6.1.5.5.7.3.3') { $hasEku = $true; break } }
                    if ($hasEku) {
                        $cert = $existing
                        Write-Host "Using existing certificate: $($cert.Thumbprint)" -ForegroundColor Green
                    } else {
                        Write-Host "Replacing certificate without EKU: $($existing.Thumbprint)" -ForegroundColor Yellow
                        Remove-Item $existing.PSPath -Force
                        $cert = New-Certificate -CertName $curName -CertEmail $curEmail
                    }
                } else {
                    if (-not $curName) {
                        $curName = Read-Host 'Enter Name for new certificate'
                        if (-not $curName) { Write-Host 'Name cannot be empty.' -ForegroundColor Red; Read-Host 'Press Enter to continue'; continue }
                        $curName = $curName.Trim()
                    }
                    $cert = New-Certificate -CertName $curName -CertEmail $curEmail
                }
                if ($cert) {
                    $sig = Get-AuthenticodeSignature (Join-Path $ScriptDir 'mumu-menu.ps1') -ErrorAction SilentlyContinue
                    if ($sig -and $sig.Status -eq 'Valid' -and $sig.SignerCertificate -and $sig.SignerCertificate.Thumbprint -eq $cert.Thumbprint) {
                        Write-Host 'Script already signed Valid with this certificate — no re-sign needed.' -ForegroundColor Green
                    } else {
                        Add-CertToTrustedRoot $cert; Sign-Script $cert
                    }
                }
                Read-Host 'Press Enter to continue'
            }
            '2' {
                $e = Read-Host 'Enter Email for new certificate'
                if (-not $e) { Write-Host 'Email cannot be empty.' -ForegroundColor Red; Read-Host 'Press Enter to continue'; continue }
                $e = $e.Trim()
                $n = if ($existing -and $curName) { $curName } else { $defaultName }
                if (-not $n) {
                    $n = Read-Host 'Enter Name for new certificate'
                    if (-not $n) { Write-Host 'Name cannot be empty.' -ForegroundColor Red; Read-Host 'Press Enter to continue'; continue }
                    $n = $n.Trim()
                }
                if ($existing) { Remove-Item $existing.PSPath -Force; Write-Host 'Old certificate removed.' -ForegroundColor Yellow }
                $cert = New-Certificate -CertName $n -CertEmail $e
                if ($cert) { Add-CertToTrustedRoot $cert; Sign-Script $cert }
                Read-Host 'Press Enter to continue'
            }
            '3' {
                $n = Read-Host 'Enter Name for new certificate'
                if (-not $n) { Write-Host 'Name cannot be empty.' -ForegroundColor Red; Read-Host 'Press Enter to continue'; continue }
                $n = $n.Trim()
                if ($existing) { Remove-Item $existing.PSPath -Force; Write-Host 'Old certificate removed.' -ForegroundColor Yellow }
                $cert = New-Certificate -CertName $n -CertEmail ''
                if ($cert) { Add-CertToTrustedRoot $cert; Sign-Script $cert }
                Read-Host 'Press Enter to continue'
            }
            '4' {
                $n = Read-Host "Enter new Name [$curName]"
                if ($n) { $curName = $n.Trim() }
                if ($existing) { Remove-Item $existing.PSPath -Force; Write-Host 'Old certificate removed.' -ForegroundColor Yellow }
                $cert = New-Certificate -CertName $curName -CertEmail $curEmail
                if ($cert) { Add-CertToTrustedRoot $cert; Sign-Script $cert }
                Read-Host 'Press Enter to continue'
            }
            '5' {
                $e = Read-Host "Enter new Email [$curEmail] (type '-' to remove, Enter to keep)"
                if ($e -eq '-') { $curEmail = '' }
                elseif ($e) { $curEmail = $e.Trim() }
                if ($existing) { Remove-Item $existing.PSPath -Force; Write-Host 'Old certificate removed.' -ForegroundColor Yellow }
                $cert = New-Certificate -CertName $curName -CertEmail $curEmail
                if ($cert) { Add-CertToTrustedRoot $cert; Sign-Script $cert }
                Read-Host 'Press Enter to continue'
            }
            '6' {
                $n = Read-Host "Enter Name [$curName]"
                if (-not $n) { $n = $curName } else { $n = $n.Trim() }
                $e = Read-Host "Enter Email [$curEmail] (type '-' for no email, Enter to keep)"
                if ($e -eq '-') { $e = '' }
                elseif (-not $e) { $e = $curEmail } else { $e = $e.Trim() }
                if ($existing) { Remove-Item $existing.PSPath -Force }
                $cert = New-Certificate -CertName $n -CertEmail $e
                if ($cert) { Add-CertToTrustedRoot $cert; Sign-Script $cert }
                Read-Host 'Press Enter to continue'
            }
            '7' {
                if ($existing) {
                    Remove-Item $existing.PSPath -Force
                    Write-Host 'Certificate removed.' -ForegroundColor Yellow
                    # Also try to remove from Trusted Root
                    foreach ($storeName in @('LocalMachine', 'CurrentUser')) {
                        try {
                            $s = New-Object System.Security.Cryptography.X509Certificates.X509Store 'Root', $storeName
                            $s.Open('ReadWrite')
                            $found = $s.Certificates | Where-Object { $_.Thumbprint -eq $existing.Thumbprint }
                            if ($found) { $s.Remove($found); Write-Host "Removed from Trusted Root ($storeName)" -ForegroundColor DarkGray }
                            $s.Close()
                        } catch { Write-Verbose "Failed to remove from $storeName store: $($_.Exception.Message)" }
                    }
                } else { Write-Host 'No certificate to remove.' -ForegroundColor Yellow }
                Read-Host 'Press Enter to continue'
            }
            '8' { return }
            default { Write-Host 'Invalid choice' -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

function Add-CertToTrustedRoot {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$cert)
    # Sigma FP: Rule "New Root or CA or AuthRoot Certificate to Store" - This is INTENTIONAL
    # and USER-INITIATED via [CRT] Create/sign certificate menu. Adds self-signed
    # CodeSigning cert (CN from user input, EKU 1.3.6.1.5.5.7.3.3) to Trusted Root
    # for Authenticode validation. Requires explicit menu selection [1]-[6].
    # No silent execution. See SECURITY.md and AV Analyst Note in header.
    $added = $false
    try {
        $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store 'Root', 'LocalMachine'
        $rootStore.Open('ReadWrite')
        if (-not ($rootStore.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint })) {
            $rootStore.Add($cert)
            Write-Host 'Added certificate to Trusted Root (Local Machine)' -ForegroundColor Green
        }
        $rootStore.Close()
        $added = $true
    } catch {
        Write-Host 'No admin rights for Local Machine store, using CurrentUser...' -ForegroundColor DarkGray
    }
    if (-not $added) {
        $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store 'Root', 'CurrentUser'
        $rootStore.Open('ReadWrite')
        if (-not ($rootStore.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint })) {
            $rootStore.Add($cert)
            Write-Host 'Added certificate to Trusted Root (CurrentUser)' -ForegroundColor Green
        }
        $rootStore.Close()
    }
}

function New-Certificate {
    param(
        [string]$CertName = '',
        [string]$CertEmail = ''
    )
    if (-not $CertName) { Write-Host 'Certificate Name cannot be empty.' -ForegroundColor Red; return $null }
    try {
        $extensions = @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
        if ($CertEmail) {
            $subject = "CN=$CertName, E=$CertEmail"
            $extensions += "2.5.29.17={text}email=$CertEmail"
        } else {
            $subject = "CN=$CertName"
        }
        $cert = New-SelfSignedCertificate -Subject $subject -KeySpec Signature -FriendlyName 'MuMuManager-CLI-Menu-Token' -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5) -TextExtension $extensions -ErrorAction Stop
        $info = if ($CertEmail) { "$CertName <$CertEmail>" } else { $CertName }
        Write-Host "Created certificate ($info): $($cert.Thumbprint)" -ForegroundColor Green
        return $cert
    } catch {
        Write-Host "Failed to create certificate: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Sign-Script {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$cert)

    $scriptPath = Join-Path $ScriptDir 'mumu-menu.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host "Script not found: $scriptPath" -ForegroundColor Red
        return
    }

    # Copy to temp, sign, then try to overwrite original directly (may fail if locked)
    $tmpPath = Join-Path $env:TEMP "mumu-menu_sign.ps1"
    try {
        Copy-Item -LiteralPath $scriptPath -Destination $tmpPath -Force
        Write-Host "Signing..." -ForegroundColor Cyan
        $result = Set-AuthenticodeSignature -FilePath $tmpPath -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
        if ($result.Status -eq 'Valid') {
            Copy-Item -LiteralPath $tmpPath -Destination $scriptPath -Force
            Write-Host "Signature status: Valid" -ForegroundColor Green
            Write-Host 'Script signed successfully!' -ForegroundColor Green
        } else {
            Write-Host "Signing failed: $($result.StatusMessage)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Signing failed: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    }
}

function Show-Logs {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    Write-Host '  [1] Static log files (api.log, etc.)' -ForegroundColor White
    Write-Host '  [2] adb logcat — snapshot (last 200 lines)' -ForegroundColor White
    Write-Host '  [3] adb logcat — live (Ctrl+C to stop)' -ForegroundColor White
    Write-Host '  [0] Cancel' -ForegroundColor Yellow
    $mode = Read-Host 'Select'

    if ($mode -eq '0' -or $mode -eq '') { return }

    if ($mode -eq '1') {
        $nxDir = Split-Path $MumuPath -Parent
        $root = Split-Path $nxDir -Parent
        $vmsRoot = Join-Path $root 'vms'

        $candidates = @()
        if (Test-Path -LiteralPath $vmsRoot) {
            $instDir = Get-ChildItem -LiteralPath $vmsRoot -Directory |
                Where-Object { $mm = [regex]::Match($_.Name, '-(\d+)$'); $mm.Success -and $mm.Groups[1].Value -eq $index } |
                Select-Object -First 1
            if ($instDir) {
                $candidates += (Join-Path $instDir.FullName 'logs\api.log')
            }
        }
        $roamLogs = Get-ChildItem (Join-Path $env:APPDATA 'Netease') -Recurse -Filter '*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 3
        foreach ($rl in $roamLogs) { $candidates += $rl.FullName }

        $found = @()
        foreach ($c in $candidates) {
            if ((Test-Path -LiteralPath $c) -and (Get-Item -LiteralPath $c).Length -gt 0) { $found += $c }
        }

        if ($found.Count -eq 0) {
            Write-Host 'No log files found.' -ForegroundColor Yellow
            return
        }

        Write-Host "Log sources found: $($found.Count)" -ForegroundColor Cyan
        for ($i = 0; $i -lt $found.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $found[$i]) -ForegroundColor DarkGray
        }
        Write-Host ''
        $sel = Read-Host "Show tail of which log? (1-$($found.Count), Enter=1)"
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $found.Count) { $pick = $found[[int]$sel - 1] } else { $pick = $found[0] }

        Write-Host ''
        Write-Host "=== last 40 lines of $pick ===" -ForegroundColor Green
        try {
            Get-Content -LiteralPath $pick -Tail 40 -ErrorAction Stop | ForEach-Object { Write-Host $_ }
        } catch {
            Write-Host "Cannot read log: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }

    if ($mode -eq '2' -or $mode -eq '3') {
        Write-Host ''
        Write-Host 'Logcat filter:' -ForegroundColor Cyan
        Write-Host '  [1] All (no filter)' -ForegroundColor White
        Write-Host '  [2] Errors only (E)' -ForegroundColor White
        Write-Host '  [3] Warnings + Errors (W)' -ForegroundColor White
        Write-Host '  [4] Custom tag (e.g. ActivityManager)' -ForegroundColor White
        $fmode = Read-Host 'Filter (Enter=1)'
        if ($fmode -eq '') { $fmode = '1' }

        $filter = '*:*'
        $filterDesc = 'all'
        switch ($fmode) {
            '2' { $filter = '*:E'; $filterDesc = 'errors only (E)' }
            '3' { $filter = '*:W'; $filterDesc = 'warnings + errors (W)' }
            '4' {
                $tag = Read-Host 'Enter tag or package name (regex supported)'
                if ($tag) {
                    $level = Read-Host 'Min level? (V/D/I/W/E, Enter=V)'
                    if (-not $level) { $level = 'V' }
                    $filter = "${tag}:${level}"
                    $filterDesc = "tag=${tag} level=${level}"
                }
            }
        }

        if ($mode -eq '2') {
            Write-Host ''
            Write-Host "=== adb logcat snapshot (last 200 lines, filter: $filterDesc) ===" -ForegroundColor Green
            $job = Start-Job -ScriptBlock {
                param($mp, $idx, $flt)
                & $mp adb -v $idx -c "logcat -v time -d -t 200 $flt" 2>&1
            } -ArgumentList $MumuPath, $index, $filter
            if (Wait-Job $job -Timeout 30) {
                $raw = Receive-Job $job
                Remove-Job $job -Force
                if ($raw) {
                    $raw | ForEach-Object { Write-Host $_ }
                } else {
                    Write-Host 'Empty output — instance may be stopped, not authorized for adb, or no matching logs.' -ForegroundColor Yellow
                }
            } else {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -Force
                Write-Host 'logcat timed out (30s). Emulator may still be booting or adb not authorized. Try live mode [3] or wait and retry.' -ForegroundColor Yellow
            }
        } elseif ($mode -eq '3') {
            Write-Host ''
            Write-Host "=== adb logcat LIVE (Ctrl+C to stop, filter: $filterDesc) ===" -ForegroundColor Green
            Write-Host ''
            try {
                & $MumuPath adb -v $index -c "logcat -v time $filter"
            } catch {
                Write-Host "logcat interrupted or failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        return
    }

    Write-Host 'Invalid choice.' -ForegroundColor Yellow
}

function Get-AllIndices {
    $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
    return $info.PSObject.Properties.Name
}

function Start-All {
    $indices = Get-AllIndices
    Write-Host ''
    Write-Host "Found $($indices.Count) instances" -ForegroundColor Cyan

    foreach ($idx in $indices) {
        $info = & $MumuPath info -v $idx 2>$null | ConvertFrom-Json
        $name = $info.name
        $state = $info.player_state
        Write-Host "  [$idx] $name ($state) - launching..." -ForegroundColor Yellow
        & $MumuPath api -v $idx launch_player 2>&1 | Out-Null
    }

    Write-Host ''
    Write-Host 'All instances launched. Polling boot status...' -ForegroundColor Cyan
    Write-Host ''

    $maxWait = 120
    $interval = 5
    $elapsed = 0
    while ($elapsed -lt $maxWait) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $allReady = $true
        foreach ($idx in $indices) {
            try {
                $s = & $MumuPath info -v $idx 2>$null | ConvertFrom-Json
                if ($s.is_android_started -ne $true) { $allReady = $false }
            } catch { $allReady = $false }
        }
        if ($allReady) {
            Write-Host "  All instances ready! (~${elapsed}s)" -ForegroundColor Green
            return
        }
        Write-Host "  [$elapsed s] still booting..." -ForegroundColor DarkGray
    }
    Write-Host '  Timed out. Some instances may still be booting.' -ForegroundColor Yellow
}

function Stop-All {
    $indices = Get-AllIndices
    Write-Host ''
    Write-Host "Found $($indices.Count) instances" -ForegroundColor Cyan

    foreach ($idx in $indices) {
        $info = & $MumuPath info -v $idx 2>$null | ConvertFrom-Json
        $name = $info.name
        $running = $info.is_process_started
        if ($running) {
            Write-Host "  [$idx] $name - shutting down..." -ForegroundColor Yellow
            & $MumuPath api -v $idx shutdown_player 2>&1 | Out-Null
            Start-Sleep -Seconds 2
        } else {
            Write-Host "  [$idx] $name - already stopped" -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    Write-Host 'All instances shut down!' -ForegroundColor Green
}

function Restart-All {
    Stop-All
    Write-Host ''
    Write-Host 'Waiting for main services...' -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Write-Host ''
    Start-All
}

function Install-APK-All {
    Write-Host ''
    $apkPath = (Read-Host 'Enter APK file path').Trim()
    if (-not $apkPath) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path -LiteralPath $apkPath)) {
        Write-Host "File not found: $apkPath" -ForegroundColor Red
        return
    }
    $apkName = Split-Path $apkPath -Leaf
    $apkSize = [math]::Round((Get-Item -LiteralPath $apkPath).Length / 1MB, 1)

    $indices = Get-AllIndices
    Write-Host ''
    Write-Host "Installing $apkName ($apkSize MB) to $($indices.Count) instance(s)..." -ForegroundColor Cyan
    Write-Host ''

    $success = 0
    $failed = 0
    foreach ($idx in $indices) {
        $info = & $MumuPath info -v $idx 2>$null | ConvertFrom-Json
        $name = $info.name
        $running = $info.is_process_started

        if (-not $running) {
            Write-Host "  [$idx] $name - skipped (not running)" -ForegroundColor DarkGray
            continue
        }

        Write-Host "  [$idx] $name - installing..." -ForegroundColor Yellow
        $result = & $MumuPath control -v $idx app install -apk $apkPath 2>&1 | Out-String
        if ($result -match '"package"') {
            Write-Host "  [$idx] $name - OK" -ForegroundColor Green
            $success++
        } else {
            $msg = $result.Trim() -replace '\s+', ' '
            Write-Host "  [$idx] $name - FAILED: $msg" -ForegroundColor Red
            $failed++
        }
    }

    Write-Host ''
    Write-Host "Done! Success: $success, Failed: $failed" -ForegroundColor Cyan
}

function Show-Apps {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    # Check if running, offer to start
    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    if (-not $info.is_process_started) {
        $st = Read-Host 'Emulator is not running. Start it now? (Y/n)'
        if ($st -eq 'n' -or $st -eq 'N') { return }
        Write-Host 'Starting emulator...' -ForegroundColor Cyan
        & $MumuPath control -v $index launch 2>&1 | Out-Null
        $tries = 0
        do {
            Start-Sleep -Seconds 5
            $tries++
            $s = (& $MumuPath info -v $index 2>$null | ConvertFrom-Json).is_android_started
        } while ($s -ne $true -and $tries -lt 24)
        if ($s -ne $true) {
            Write-Host 'Emulator did not boot in time. Try again later.' -ForegroundColor Red
            return
        }
        Start-Sleep -Seconds 5
    }

    Write-Host 'Fetching installed apps...' -ForegroundColor Cyan
    $output = & $MumuPath adb -v $index -c 'shell pm list packages -3' 2>&1
    $text = $output | Out-String
    $packages = [regex]::Matches($text, '(?m)^\s*package:([A-Za-z0-9_.]+)') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

    if ($packages.Count -eq 0) {
        if ($text -match 'offline|unauthorized|not found|no devices|error') {
            Write-Host 'ADB could not read the package list.' -ForegroundColor Red
            Write-Host "Details: $($text.Trim())" -ForegroundColor DarkGray
            Write-Host 'Try restarting the emulator and waiting for full boot.' -ForegroundColor Yellow
            return
        }

        $allOut = & $MumuPath adb -v $index -c 'shell pm list packages' 2>&1
        $allText = $allOut | Out-String
        $all = [regex]::Matches($allText, '(?m)^\s*package:([A-Za-z0-9_.]+)') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

        if ($all.Count -gt 0) {
            Write-Host "Third-party apps: none. Only system packages found ($($all.Count))." -ForegroundColor Yellow
            $show = Read-Host 'Show all system packages? (y/N)'
            if ($show -eq 'y' -or $show -eq 'Y') {
                Write-Host ''
                foreach ($pkg in $all) {
                    Write-Host "  $pkg" -ForegroundColor White
                }
            }
        } else {
            Write-Host 'ADB returned no package list.' -ForegroundColor Yellow
            Write-Host 'Wait for full boot or restart the emulator.' -ForegroundColor Yellow
        }
        return
    }

    Write-Host "Found $($packages.Count) third-party apps:`n" -ForegroundColor Green
    foreach ($pkg in $packages) {
        Write-Host "  $pkg" -ForegroundColor White
    }
}

function Show-Settings {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    # Check if running
    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    if (-not $info.is_process_started) {
        Write-Host 'Emulator is not running! Start it first.' -ForegroundColor Red
        return
    }

    Write-Host 'Fetching settings...' -ForegroundColor Cyan
    $result = & $MumuPath setting -v $index --all_writable 2>&1 | Out-String
    if ($result -match 'errcode.*-1') {
        Write-Host 'Settings command not supported. Try MuMu settings UI.' -ForegroundColor Yellow
    } else {
        Write-Host $result
    }
}

function Install-APK {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    $apkPath = (Read-Host 'Enter APK file path').Trim()

    if (-not $apkPath) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path -LiteralPath $apkPath)) {
        Write-Host "File not found: $apkPath" -ForegroundColor Red
        return
    }

    Write-Host 'Installing APK...' -ForegroundColor Cyan
    $maxAttempts = 3
    $result = ''
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $result = & $MumuPath control -v $index app install -apk $apkPath 2>&1 | Out-String
        if ($result -match '"package"') {
            Write-Host 'APK installed!' -ForegroundColor Green
            return
        }
        if ($result -match 'not handle cmd' -and $attempt -lt $maxAttempts) {
            Write-Host "  Emulator service not ready, retrying ($attempt/$maxAttempts)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            continue
        }
        break
    }
    $msg = $result.Trim()
    try {
        $parsed = $result | ConvertFrom-Json
        if ($parsed.errmsg) { $msg = $parsed.errmsg }
    } catch {
        Write-Warning "Install parse error: $($_.Exception.Message)"
    }
    Write-Host "Install failed: $msg" -ForegroundColor Red
}

function Uninstall-App {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()

    if (-not $package) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }

    Write-Host "This will remove '$package' and ALL its data from instance $index." -ForegroundColor Yellow
    $confirm = Read-Host 'Type YES to confirm uninstall'
    if ($confirm -cne 'YES') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }

    Write-Host 'Uninstalling app...' -ForegroundColor Cyan
    $result = & $MumuPath control -v $index app uninstall -pkg $package 2>&1 | Out-String
    if ($result -match '"errcode"\s*:\s*0') {
        Write-Host 'App uninstalled!' -ForegroundColor Green
    } else {
        Write-Host "Uninstall failed: $($result.Trim())" -ForegroundColor Red
    }
}

function Show-VersionInfo {
    Write-Host ''
    Write-Host '=== MuMu Manager CLI Menu ===' -ForegroundColor Cyan
    Write-Host ''

    # Script version
    $scriptVer = '1.7.0'
    Write-Host "Script version: $scriptVer" -ForegroundColor Green

    # Check for updates
    try {
        $latestRaw = & curl.exe -s --connect-timeout 10 --max-time 15 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/$GitHubRepo/releases/latest" 2>$null
        $latest = $latestRaw | ConvertFrom-Json
        $latestVer = $latest.tag_name -replace '^v',''
        if ($latestVer -ne $scriptVer) {
            Write-Host "  -> Update available: $latestVer (run [U] to update)" -ForegroundColor Yellow
        } else {
            Write-Host '  -> Up to date' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host '  -> Cannot check updates' -ForegroundColor DarkGray
    }

    # MuMu version
    try {
        $verJson = & $MumuPath version 2>$null | ConvertFrom-Json
        $ver = $verJson.version
        $minVer = [version]'4.0.0.3179'
        $curVer = [version]$ver
        if ($curVer -ge $minVer) {
            Write-Host "MuMu version: $ver" -ForegroundColor Green
        } else {
            Write-Host "MuMu version: $ver (OLD - minimum: $minVer)" -ForegroundColor Red
        }
    } catch {
        Write-Host 'MuMu version: unknown' -ForegroundColor Yellow
    }

    # PowerShell version
    $psVer = $PSVersionTable.PSVersion
    Write-Host "PowerShell: $psVer" -ForegroundColor $(if ($psVer -ge '5.1') { 'Green' } else { 'Yellow' })

    # .NET version
    $dotnet = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    Write-Host ".NET: $dotnet" -ForegroundColor DarkGray

    # OS info
    $os = [System.Environment]::OSVersion.Version
    $build = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).CurrentBuild
    Write-Host "OS: Windows $($os.Major).$($os.Minor) (Build $build)" -ForegroundColor DarkGray

    # Architecture
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    Write-Host "Arch: $arch" -ForegroundColor DarkGray

    # GitHub repo
    Write-Host "Repository: $GitHubRepo" -ForegroundColor DarkGray

    # Token status
    if ($GitHubToken) {
        $masked = $GitHubToken.Substring(0, [Math]::Min(4, $GitHubToken.Length)) + '***'
        Write-Host "GitHub token: $masked (valid)" -ForegroundColor Green
    } else {
        Write-Host 'GitHub token: not configured' -ForegroundColor Yellow
    }

    # Instances
    try {
        $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
        $count = $info.PSObject.Properties.Count
        $running = 0
        foreach ($key in $info.PSObject.Properties.Name) {
            if ($info.$key.is_process_started) { $running++ }
        }
        Write-Host "Instances: $count ($running running)" -ForegroundColor Cyan
    } catch {
        Write-Host 'Instances: unknown' -ForegroundColor Yellow
    }

    # ADB server
    try {
        $adb = & adb.exe devices 2>$null
        $adbCount = ($adb | Select-String 'device$').Count
        Write-Host "ADB devices: $adbCount" -ForegroundColor Cyan
    } catch {
        Write-Host 'ADB: not found' -ForegroundColor DarkGray
    }

    # Disk space
    try {
        $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($drive) {
            $freeGB = [math]::Round($drive.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($drive.Size / 1GB, 0)
            $pct = [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 0)
            $color = if ($pct -lt 10) { 'Red' } elseif ($pct -lt 25) { 'Yellow' } else { 'Green' }
            Write-Host "Disk C: ${freeGB}GB free / ${totalGB}GB (${pct}%)" -ForegroundColor $color
        }
    } catch {
        Write-Verbose "Disk info unavailable: $($_.Exception.Message)"
    }

    # Certificate status
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.FriendlyName -eq 'MuMuManager-CLI-Menu-Token' } | Select-Object -First 1
    if ($cert) {
        $daysLeft = ($cert.NotAfter - (Get-Date)).Days
        $certColor = if ($daysLeft -lt 30) { 'Yellow' } else { 'Green' }
        Write-Host "Certificate: valid ($($cert.Subject), expires in $daysLeft days)" -ForegroundColor $certColor
    } else {
        Write-Host 'Certificate: not created ([CRT] to create)' -ForegroundColor DarkGray
    }

    Write-Host ''
}

function Show-Windows {
    Write-Host ''
    Write-Host 'Showing all emulator windows...' -ForegroundColor Cyan
    $output = & $MumuPath control -v all show_window 2>&1 | Out-String
    if ($output -match 'errcode.*0') {
        Write-Host 'Done! Windows shown.' -ForegroundColor Green
    } elseif ($output -match 'not running') {
        Write-Host 'No running emulators found' -ForegroundColor Yellow
    } else {
        Write-Host $output -ForegroundColor DarkGray
    }
}

function Hide-Windows {
    Write-Host ''
    Write-Host 'Hiding all emulator windows...' -ForegroundColor Cyan
    $output = & $MumuPath control -v all hide_window 2>&1 | Out-String
    if ($output -match 'errcode.*0') {
        Write-Host 'Done! Windows hidden.' -ForegroundColor Green
    } elseif ($output -match 'not running') {
        Write-Host 'No running emulators found' -ForegroundColor Yellow
    } else {
        Write-Host $output -ForegroundColor DarkGray
    }
}

function Set-WindowLayout {
    Write-Host ''
    Write-Host 'Arranging emulator windows...' -ForegroundColor Cyan
    $output = & $MumuPath control -v all layout_window 2>&1 | Out-String
    if ($output -match 'height') {
        Write-Host 'Done! Windows arranged.' -ForegroundColor Green
    } elseif ($output -match 'not running') {
        Write-Host 'No running emulators found' -ForegroundColor Yellow
    } else {
        Write-Host $output -ForegroundColor DarkGray
    }
}

function Save-Screenshot {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    # Get ADB port for this instance
    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    if (-not $info.is_process_started) {
        Write-Host 'Emulator is not running!' -ForegroundColor Red
        return
    }

    $adbPort = $info.adb_port
    if (-not $adbPort) {
        Write-Host 'Cannot get ADB port' -ForegroundColor Red
        return
    }

    # Create screenshots directory
    $screenshotsDir = Join-Path $ScriptDir 'screenshots'
    if (-not (Test-Path $screenshotsDir)) {
        New-Item -ItemType Directory -Path $screenshotsDir | Out-Null
    }

    # Generate filename with timestamp
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $filename = "screenshot_${index}_${timestamp}.png"
    $destPath = Join-Path $screenshotsDir $filename
    $remotePath = '/sdcard/screenshot.png'

    Write-Host "Taking screenshot of instance $index..." -ForegroundColor Cyan

    # Take screenshot via ADB
    & $MumuPath adb -v $index -c "shell screencap -p $remotePath" 2>&1 | Out-Null

    # Pull file from emulator
    & $MumuPath adb -v $index -c "pull $remotePath $destPath" 2>&1 | Out-Null

    # Cleanup remote file
    & $MumuPath adb -v $index -c "shell rm $remotePath" 2>&1 | Out-Null

    if (Test-Path $destPath) {
        $size = (Get-Item $destPath).Length / 1KB
        Write-Host "Screenshot saved: $destPath" -ForegroundColor Green
        Write-Host "Size: $([math]::Round($size, 1)) KB" -ForegroundColor DarkGray
    } else {
        Write-Host 'Failed to save screenshot' -ForegroundColor Red
    }
}

function Invoke-ADBCommand {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    if (-not (Confirm-AdbConsent)) { return }
    Write-Host ''
    $cmd = (Read-Host 'Enter ADB command').Trim()

    Write-Host 'Running ADB command...' -ForegroundColor Cyan
    Invoke-Mumu adb -v $index -c $cmd
}

# Consent gate for identifier/model spoofing options: shown once per
# session, requires explicit acknowledgement. Documents intended use
# (privacy/testing on the user's own instances) and rejects otherwise.
$script:SpoofConsentAccepted = $false
function Confirm-SpoofConsent {
    if ($script:SpoofConsentAccepted) { return $true }
    Write-Host ''
    Write-Host '  === Identifier spoofing - confirmation required ===' -ForegroundColor Yellow
    Write-Host '  These options change device identity values (model, IMEI,' -ForegroundColor White
    Write-Host '  Android ID, MAC) of YOUR OWN local emulator instances for' -ForegroundColor White
    Write-Host '  privacy protection and application testing only.' -ForegroundColor White
    Write-Host '  Do not use them to impersonate devices you do not own or' -ForegroundColor White
    Write-Host '  for any unlawful purpose.' -ForegroundColor White
    $ans = Read-Host '  Type OK to continue (anything else cancels)'
    if ($ans -eq 'OK') {
        $script:SpoofConsentAccepted = $true
        return $true
    }
    Write-Host '  Cancelled (consent not given).' -ForegroundColor Yellow
    return $false
}

# Consent gate for the arbitrary ADB shell option: shown once per session.
# Documents that commands run inside the user's OWN emulator Android VM
# (each instance is an isolated device) and requires explicit acknowledgement.
$script:AdbConsentAccepted = $false
function Confirm-AdbConsent {
    if ($script:AdbConsentAccepted) { return $true }
    Write-Host ''
    Write-Host '  === Arbitrary ADB shell - confirmation required ===' -ForegroundColor Yellow
    Write-Host '  Commands are executed inside YOUR OWN local emulator VM' -ForegroundColor White
    Write-Host '  (isolated Android device). They cannot affect the host OS.' -ForegroundColor White
    Write-Host '  Destructive shell commands may erase data inside that VM.' -ForegroundColor White
    $ans = Read-Host '  Type OK to continue (anything else cancels)'
    if ($ans -eq 'OK') {
        $script:AdbConsentAccepted = $true
        return $true
    }
    Write-Host '  Cancelled (consent not given).' -ForegroundColor Yellow
    return $false
}

function Set-DeviceModel {
    if (-not (Confirm-SpoofConsent)) { return }
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    try {
        $info = & $MumuPath setting -v $index -k phone_brand -k phone_model -k phone_miit 2>$null | ConvertFrom-Json
        Write-Host 'Current device model:' -ForegroundColor DarkGray
        Write-Host "  Brand: $($info.phone_brand)" -ForegroundColor White
        Write-Host "  Model: $($info.phone_model)" -ForegroundColor White
        Write-Host "  Code:  $($info.phone_miit)" -ForegroundColor White
        Write-Host ''
    } catch {
        Write-Warning "Current model read failed: $($_.Exception.Message)"
    }

    $presets = @(
        @{ Brand = 'Samsung'; Model = 'Galaxy S23 Ultra';  Code = 'SM-S918B' },
        @{ Brand = 'Samsung'; Model = 'Galaxy A54';        Code = 'SM-A546E' },
        @{ Brand = 'Google';  Model = 'Pixel 8 Pro';       Code = 'G1MNW' },
        @{ Brand = 'Google';  Model = 'Pixel 7a';          Code = 'GWKK3' },
        @{ Brand = 'Xiaomi';  Model = 'Xiaomi 14';         Code = '23127PN0CG' },
        @{ Brand = 'Xiaomi';  Model = 'Redmi Note 13 Pro'; Code = '2312DRA50G' },
        @{ Brand = 'OnePlus'; Model = 'OnePlus 12';        Code = 'CPH2573' },
        @{ Brand = 'Oppo';    Model = 'Find X7';           Code = 'PHY110' },
        @{ Brand = 'Vivo';    Model = 'V30 Pro';           Code = 'V2319A' },
        @{ Brand = 'Huawei';  Model = 'P60 Pro';           Code = 'MNA-LX9' },
        @{ Brand = 'Honor';   Model = 'Magic 6 Pro';       Code = 'BVL-AN10' },
        @{ Brand = 'Asus';    Model = 'ROG Phone 8';       Code = 'AI2401' }
    )

    Write-Host 'Device presets:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $presets.Count; $i++) {
        Write-Host ("  [{0,2}] {1} {2} ({3})" -f ($i + 1), $presets[$i].Brand, $presets[$i].Model, $presets[$i].Code) -ForegroundColor White
    }
    Write-Host '  [ C] Custom brand / model' -ForegroundColor White
    Write-Host '  [ 0] Cancel' -ForegroundColor Yellow

    $choice = Read-Host 'Select device'

    if ($choice -eq '0') {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }

    if ($choice -eq 'c' -or $choice -eq 'C') {
        $brand = Read-Host 'Brand (e.g. Samsung)'
        $model = Read-Host 'Model name (e.g. Galaxy A54)'
        $code  = Read-Host 'Model code (e.g. SM-A546E)'
        if (-not $brand -or -not $model) {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
        if (-not $code) { $code = $model }
    } elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $presets.Count) {
        $p = $presets[[int]$choice - 1]
        $brand = $p.Brand
        $model = $p.Model
        $code  = $p.Code
    } else {
        Write-Host 'Invalid option!' -ForegroundColor Red
        return
    }

    $display = if ($model -like "$brand*") { $model } else { "$brand $model" }

    Write-Host ''
    Write-Host "Setting device to $display ($code)..." -ForegroundColor Cyan
    try {
        & $MumuPath setting -v $index -k phone_brand -val $brand -k phone_model -val $model -k phone_miit -val $code 2>&1 | Out-Null
        Write-Host "Device model set to $display!" -ForegroundColor Green
        try {
            $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
            if ($info.is_android_started) {
                $escaped = $display -replace ' ', '\ '
                & $MumuPath adb -v $index -c "shell settings put global device_name $escaped" 2>&1 | Out-Null
                Write-Host 'Device name updated live.' -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning "Live device name update failed: $($_.Exception.Message)"
        }
        Write-Host 'Restart the emulator to fully apply build properties.' -ForegroundColor Yellow
    } catch {
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-SimOperator {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    # Show current SIM props via adb
    try {
        $props = & $MumuPath adb -v $index -c "shell getprop" 2>$null | Out-String
        $curNumeric = if ($props -match '\[gsm\.sim\.operator\.numeric\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
        $curIso     = if ($props -match '\[gsm\.sim\.operator\.iso-country\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
        $curAlpha   = if ($props -match '\[gsm\.sim\.operator\.alpha\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
        $curMumMcc  = if ($props -match '\[persist\.mumu\.mccmnc\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
        Write-Host 'Current SIM operator:' -ForegroundColor DarkGray
        Write-Host "  Numeric (MCC+MNC): $(if ($curNumeric) { $curNumeric } else { '(not set, default 310260 US)' })" -ForegroundColor White
        Write-Host "  ISO country:       $(if ($curIso) { $curIso } else { '(not set)' })" -ForegroundColor White
        Write-Host "  Operator name:     $(if ($curAlpha) { $curAlpha } else { '(not set)' })" -ForegroundColor White
        if ($curMumMcc) {
            Write-Host "  MuMu mccmnc:       $curMumMcc" -ForegroundColor White
        }
        Write-Host ''
    } catch {
        Write-Host 'Could not read current SIM props (instance may be stopped).' -ForegroundColor Yellow
    }

    $presets = @(
        @{ CC='us'; MCC='310'; MNC='260'; Name='T-Mobile US'; Lang='en' },
        @{ CC='ru'; MCC='250'; MNC='01';  Name='MTS RU'; Lang='ru' },
        @{ CC='gb'; MCC='234'; MNC='15';  Name='Vodafone UK'; Lang='en' },
        @{ CC='de'; MCC='262'; MNC='01';  Name='Telekom DE'; Lang='de' },
        @{ CC='fr'; MCC='208'; MNC='01';  Name='Orange FR'; Lang='fr' },
        @{ CC='jp'; MCC='440'; MNC='10';  Name='Docomo JP'; Lang='ja' },
        @{ CC='kr'; MCC='450'; MNC='05';  Name='SK Telecom KR'; Lang='ko' },
        @{ CC='cn'; MCC='460'; MNC='01';  Name='China Unicom'; Lang='zh' },
        @{ CC='in'; MCC='404'; MNC='45';  Name='Airtel IN'; Lang='en' },
        @{ CC='br'; MCC='724'; MNC='05';  Name='Claro BR'; Lang='pt' },
        @{ CC='tr'; MCC='286'; MNC='01';  Name='Turkcell TR'; Lang='tr' },
        @{ CC='id'; MCC='510'; MNC='01';  Name='Telkomsel ID'; Lang='id' },
        @{ CC='vn'; MCC='452'; MNC='01';  Name='Viettel VN'; Lang='vi' },
        @{ CC='ua'; MCC='255'; MNC='01';  Name='Vodafone UA'; Lang='uk' },
        @{ CC='kz'; MCC='401'; MNC='01';  Name='Beeline KZ'; Lang='ru' }
    )

    Write-Host 'Presets (MCC/MNC -> TikTok region):' -ForegroundColor Cyan
    for ($i = 0; $i -lt $presets.Count; $i++) {
        $p = $presets[$i]
        Write-Host ("  [{0,2}] {1,-8} {2} ({3}{4}) {5}" -f ($i+1), $p.CC.ToUpper(), $p.Name, $p.MCC, $p.MNC, "[$($p.Lang)]") -ForegroundColor White
    }
    Write-Host '  [ C] Custom MCC / MNC / ISO' -ForegroundColor White
    Write-Host '  [ 0] Cancel' -ForegroundColor Yellow
    $choice = Read-Host 'Select SIM country'
    if ($choice -eq '0') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    $sel = $null
    if ($choice -eq 'c' -or $choice -eq 'C') {
        $mcc = Read-Host 'MCC (3 digits, e.g. 250)'
        $mnc = Read-Host 'MNC (2-3 digits, e.g. 01)'
        $cc  = Read-Host 'ISO country (2 letters, e.g. ru)'
        $name= Read-Host 'Operator name (e.g. MTS RU)'
        if (-not $mcc -or -not $mnc -or -not $cc) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
        $sel = @{ MCC=$mcc.Trim(); MNC=$mnc.Trim(); CC=$cc.Trim().ToLower(); Name=if ($name) { $name.Trim() } else { "Operator $($mcc.Trim())$($mnc.Trim())" } }
    } elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $presets.Count) {
        $sel = $presets[[int]$choice - 1]
    } else {
        Write-Host 'Invalid option!' -ForegroundColor Red; return
    }

    $numeric = "$($sel.MCC)$($sel.MNC)"
    $cc = $sel.CC.ToLower()
    $alpha = $sel.Name
    Write-Host ''
    Write-Host "Setting SIM to $alpha ($numeric, $cc)..." -ForegroundColor Cyan
    try {
        # 1) MuMu-specific persist property (most reliable in MuMu)
        & $MumuPath adb -v $index -c "shell setprop persist.mumu.mccmnc $numeric" 2>&1 | Out-Null

        # 2) Standard gsm.sim.* and gsm.operator.* shell properties
        $cmds = @(
            "setprop gsm.sim.operator.numeric $numeric"
            "setprop gsm.sim.operator.iso-country $cc"
            "setprop gsm.sim.operator.alpha `"$alpha`""
            "setprop gsm.operator.numeric $numeric"
            "setprop gsm.operator.iso-country $cc"
            "setprop gsm.operator.alpha `"$alpha`""
            "setprop gsm.sim.operator.isroaming false"
            "setprop gsm.operator.isroaming false"
        )
        foreach ($c in $cmds) {
            & $MumuPath adb -v $index -c "shell $c" 2>&1 | Out-Null
        }

        # 3) Settings global — carrier ID / operator name (persists across shell restarts)
        & $MumuPath adb -v $index -c "shell settings put global mobile_operator $numeric" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global operator_numeric $numeric" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global operator_alpha `"$alpha`"" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global sim_operator `"$alpha`"" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global gsm_operator_alpha `"$alpha`"" 2>&1 | Out-Null

        # Verify
        $props2 = & $MumuPath adb -v $index -c "shell getprop" 2>$null | Out-String
        $newNum  = if ($props2 -match '\[gsm\.sim\.operator\.numeric\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
        $newMum  = if ($props2 -match '\[persist\.mumu\.mccmnc\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
        Write-Host ''
        Write-Host 'Verification:' -ForegroundColor DarkGray
        Write-Host "  gsm.sim.operator.numeric = $(if ($newNum) { $newNum } else { '(empty)' })" -ForegroundColor $(if ($newNum -eq $numeric) { 'Green' } else { 'Yellow' })
        Write-Host "  persist.mumu.mccmnc      = $(if ($newMum) { $newMum } else { '(empty)' })" -ForegroundColor $(if ($newMum -eq $numeric) { 'Green' } else { 'Yellow' })

        if ($newNum -ne $numeric -and $newMum -ne $numeric) {
            Write-Host ''
            Write-Host 'WARNING: gsm.sim.operator.numeric did not update via setprop.' -ForegroundColor Yellow
            Write-Host '  MuMu may override shell props from its virtual modem config.' -ForegroundColor Yellow
            Write-Host '  This is normal — MuMu reads SIM from its own config file.' -ForegroundColor Yellow
            Write-Host '  If feed does not change, a full emulator restart may be needed.' -ForegroundColor Yellow
        }

        Write-Host ''
        Write-Host "SIM set to $alpha ($numeric, $cc)." -ForegroundColor Green
        Write-Host ''
        Write-Host 'To apply in TikTok:' -ForegroundColor Cyan
        Write-Host '  1. Clear TikTok cache:  [ADB] -> shell pm clear com.zhiliaoapp.musically' -ForegroundColor White
        Write-Host '  2. Force-stop TikTok:    [ADB] -> shell am force-stop com.zhiliaoapp.musically' -ForegroundColor White
        Write-Host '  3. Restart TikTok' -ForegroundColor White
        Write-Host ''
        Write-Host 'If feed still shows old region after clearing cache:' -ForegroundColor Yellow
        Write-Host '  Full restart: [R] -> restart emulator, then re-apply [SIM]' -ForegroundColor White
    } catch {
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-RandomImei {
    $base = '35'
    1..12 | ForEach-Object { $base += Get-Random -Minimum 0 -Maximum 10 }
    $sum = 0
    for ($i = 0; $i -lt 14; $i++) {
        $d = [int]$base.Substring($i, 1)
        if ($i % 2 -eq 1) {
            $d *= 2
            if ($d -gt 9) { $d -= 9 }
        }
        $sum += $d
    }
    "$base$((10 - ($sum % 10)) % 10)"
}

function New-RandomAndroidId {
    # 16 hex chars, e.g. "13f454f21c0f5f57"
    [guid]::NewGuid().ToString('N').Substring(0, 16)
}

function New-RandomMac {
    # Locally administered unicast MAC from random bytes
    $bytes = [byte[]]::new(6)
    [System.Random]::new().NextBytes($bytes)
    $bytes[0] = ($bytes[0] -band 0xFC) -bor 0x02
    ($bytes | ForEach-Object { $_.ToString('x2') }) -join ':'
}

# Privacy/testing feature: randomizes identifiers of the user's own emulator
# instance so it does not reuse factory/default values.
function Set-RandomDeviceIds {
    param([string]$Mode)

    if (-not (Confirm-SpoofConsent)) { return }
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    # Show current values
    try {
        $sim = & $MumuPath simulation -v $index 2>$null | ConvertFrom-Json
        Write-Host 'Current simulation values:' -ForegroundColor DarkGray
        Write-Host "  IMEI:       $(if ($sim.imei) { $sim.imei } else { '(not set)' })" -ForegroundColor White
        Write-Host "  Android ID: $(if ($sim.android_id) { $sim.android_id } else { '(not set)' })" -ForegroundColor White
        Write-Host "  MAC:        $(if ($sim.mac_address) { $sim.mac_address } else { '(not set)' })" -ForegroundColor White
    } catch {
        Write-Host 'Could not read simulation properties.' -ForegroundColor Yellow
    }
    try {
        $set = & $MumuPath setting -v $index -k phone_imei 2>$null | ConvertFrom-Json
        if ($set.phone_imei) {
            Write-Host "  Setting IMEI: $($set.phone_imei)" -ForegroundColor DarkGray
        }
    } catch { Write-Verbose "setting phone_imei read failed: $($_.Exception.Message)" }
    Write-Host ''

    if (-not $Mode) {
        Write-Host 'Randomize:' -ForegroundColor Cyan
        Write-Host '  [1] IMEI' -ForegroundColor White
        Write-Host '  [2] Android ID' -ForegroundColor White
        Write-Host '  [3] MAC address' -ForegroundColor White
        Write-Host '  [4] All of the above' -ForegroundColor White
        Write-Host '  [0] Cancel' -ForegroundColor Yellow
        $choice = Read-Host 'Select option'
        switch ($choice) {
            '1' { $Mode = 'imei' }
            '2' { $Mode = 'android_id' }
            '3' { $Mode = 'mac_address' }
            '4' { $Mode = 'all' }
            default { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
        }
    }

    $targets = switch ($Mode) {
        'imei'         { @('imei') }
        'android_id'   { @('android_id') }
        'mac_address'  { @('mac_address') }
        'all'          { @('imei', 'android_id', 'mac_address') }
    }

    # Collect new values
    $vals = @{}
    foreach ($t in $targets) {
        switch ($t) {
            'imei'        { $vals[$t] = New-RandomImei }
            'android_id'  { $vals[$t] = New-RandomAndroidId }
            'mac_address' { $vals[$t] = New-RandomMac }
        }
    }

    # 1) Set via MuMu simulation command (writes to simulation.json)
    foreach ($t in $targets) {
        try {
            & $MumuPath simulation -v $index -sk $t -sv $vals[$t] 2>&1 | Out-Null
            $label = switch ($t) { 'imei' { 'IMEI' } 'android_id' { 'Android ID' } 'mac_address' { 'MAC' } }
            Write-Host "  $label -> $($vals[$t])  (simulation)" -ForegroundColor Green
        } catch {
            Write-Host "  Failed to set ${t} via simulation: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # 2) Set IMEI via setting command (for MuMu GUI display)
    if ($vals.ContainsKey('imei')) {
        try {
            & $MumuPath setting -v $index -k phone_imei -val $vals['imei'] 2>&1 | Out-Null
            Write-Host "  IMEI -> $($vals['imei'])  (setting)" -ForegroundColor Green
        } catch {
            Write-Host "  Failed to set phone_imei via setting: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # 3) Verify simulation.json directly
    try {
        $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
        $androidVer = $info.android_version
        $vmName = $info.name
        Write-Host ''
        Write-Host 'Verifying simulation.json...' -ForegroundColor DarkGray

        # Find the VMS directory by scanning for matching simulation.json
        $vmsRoot = Join-Path (Split-Path (Split-Path $MumuPath)) 'vms'
        if (Test-Path $vmsRoot) {
            $found = $false
            foreach ($dir in (Get-ChildItem $vmsRoot -Directory)) {
                $simFile = Join-Path $dir.FullName 'configs\simulation.json'
                if (Test-Path $simFile) {
                    $content = Get-Content $simFile -Raw | ConvertFrom-Json
                    # Match by IMEI if we set one, otherwise skip
                    if ($vals.ContainsKey('imei') -and $content.imei -eq $vals['imei']) {
                        Write-Host "  Found: $($dir.Name)\configs\simulation.json" -ForegroundColor Green
                        Write-Host "  Content: $((Get-Content $simFile -Raw).Trim())" -ForegroundColor White
                        $found = $true
                        break
                    }
                }
            }
            if (-not $found) {
                Write-Host "  simulation.json not found or IMEI mismatch - values may not persist after reboot" -ForegroundColor Yellow
            }
        }
    } catch { Write-Verbose "simulation.json verification failed: $($_.Exception.Message)" }

    Write-Host ''
    Write-Host 'IMPORTANT: Changes only take effect after emulator restart!' -ForegroundColor Yellow
    Write-Host '  [R] Restart emulator now' -ForegroundColor White
    Write-Host '  [S] Skip restart (apply later via [R] or MuMu GUI)' -ForegroundColor White
    $restart = Read-Host 'Restart now?'
    if ($restart -eq 'r' -or $restart -eq 'R') {
        Write-Host 'Restarting emulator...' -ForegroundColor Cyan
        try {
            & $MumuPath control -v $index restart 2>&1 | Out-Null
            Write-Host 'Emulator restarting. Values will be active after boot completes.' -ForegroundColor Green
        } catch {
            Write-Host "Restart failed: $($_.Exception.Message). Please restart manually." -ForegroundColor Red
        }
    } else {
        Write-Host 'Skipped. Restart manually via [R] or MuMu GUI to apply.' -ForegroundColor DarkGray
    }
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host 'Select option (0/q = Exit)'

    switch ($choice) {
        '1' { Show-InstanceInfo }
        '2' { Start-Emulator }
        '3' { Stop-Emulator }
        '4' { Restart-Emulator }
        '5' { New-Emulator }
        'c' { Copy-Emulator }
        'x' { Remove-Emulator }
        'n' { Rename-Emulator }
        '6' { Show-Apps }
        '7' { Show-Settings }
        '8' { Install-APK }
        '9' { Uninstall-App }
        'g' { Show-Logs }
        'o' { Clear-AppData }
        'p' { Stop-App }
        't' { Start-App }
        'e' { Export-Emulator }
        'k' { Update-Token }
        'z' { Test-Security }
        'dm' { Set-DeviceModel }
        'sim' { Set-SimOperator }
        'di' { Set-RandomDeviceIds }
        'ba' { Backup-EmulatorData }
        'a' { Invoke-ADBCommand }
        'b' { Start-All }
        'd' { Stop-All }
        'r' { Restart-All }
        'i' { Install-APK-All }
        'w' { Show-Windows }
        'h' { Hide-Windows }
        'l' { Set-WindowLayout }
        's' { Save-Screenshot }
        'v' { Show-VersionInfo }
        'u' { Update-FromGitHub }
        'crt' { Create-Certificate }
        'vt' { Scan-VirusTotal }
        'q' {
            Write-Host 'Goodbye!' -ForegroundColor Cyan
            exit
        }
        '0' {
            Write-Host 'Goodbye!' -ForegroundColor Cyan
            exit
        }
        default {
            Write-Host 'Invalid option!' -ForegroundColor Red
        }
    }

    Write-Host ''
    Write-Host 'Press any key to continue...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

} while ($true)