# MuMuManager CLI - Interactive Menu for Netease MuMu Emulator (Windows)
# Project:  https://github.com/genrihx2/MuMuManager-CLI-Menu
# License:  Open Source - MIT (see LICENSE)
# Purpose:  launch/stop/restart emulator instances, install/uninstall APKs,
#           tune performance, spoof device model/SIM operator, back up instance data.
# AV Analyst Note: This is NOT malware. All actions are LOCAL and USER-INITIATED
#           via explicit menu selections. No silent execution, no persistence,
#           no network exfiltration, no process injection. Emulator management
#           via MuMuManager.exe (local), backup via robocopy/tar, remote update
#           ONLY on user [U] confirmation over HTTPS from the repo above.
#           Device-ID spoofing (IMEI/AndroidID/MAC/device model) is DUAL-USE
#           privacy/testing feature for the USER'S OWN emulator instances only;
#           requires explicit consent ([O]/[9] YES, [A] session consent). Not for
#           unlawful use. See README "Примечание для AV-аналитиков" and SECURITY.md.
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
# Fix file:/// URL paths (PS5.1 edge case)
if ($ScriptDir -match '^file:///') {
    $ScriptDir = [System.Uri]::new($ScriptDir).LocalPath
}
$ScriptDir = $ScriptDir.TrimEnd('\', '/')
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
            $raw = (Get-Content -LiteralPath $DpapiTokenFile -Raw).Trim()
            $sec = $raw | ConvertTo-SecureString -ErrorAction Stop
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

$scriptVer = '1.13.29'
$InstalledVersion = $null

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
    $curlArgs = @('-s', '--retry', '3', '--retry-delay', '3', '--connect-timeout', '30', '--max-time', "$TimeoutSec")
    if ($Url -match '^https://api\.github\.com/repos/.+/contents/') {
        $curlArgs += @('-H', 'Accept: application/vnd.github.raw')
    } elseif ($Url -match '^https://api\.github\.com/') {
        $curlArgs += @('-H', 'Accept: application/vnd.github.v3+json')
    }
    if ($GitHubToken) {
        $curlArgs += @('-H', "Authorization: token $GitHubToken")
    }
    # Write to temp file for proper UTF-8 handling
    $tmpFile = Join-Path $env:TEMP ('gh_resp_' + [Guid]::NewGuid().ToString('N') + '.json')
    $curlArgs += @('-o', $tmpFile)
    for ($i = 1; $i -le 3; $i++) {
        & curl.exe @curlArgs $Url 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpFile)) {
            $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
            if ($bytes -and $bytes.Length -gt 0) {
                $enc = [System.Text.Encoding]::UTF8
                return $enc.GetString($bytes).TrimEnd()
            }
        }
        Start-Sleep -Seconds 2
    }
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
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
    # Strip UTF-8 BOM (U+FEFF) so local ReadAllText (which strips BOM)
    # and raw remote bytes (which include BOM) produce the same hash.
    $norm = $norm.TrimStart([char]0xFEFF)
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

        # Fast check: compare local version tag against release tag (no download)
        $localTag = ''
        if (Test-Path -LiteralPath $VersionFile) {
            try { $localTag = (Get-Content -LiteralPath $VersionFile -Raw).Trim() } catch { Write-Debug "Version file read failed: $($_.Exception.Message)" }
        }

        if ($localTag -eq $tag) {
            if (-not $Passive) {
                Write-Host "  Up to date ($tag)" -ForegroundColor DarkGray
            }
            return
        }

        # Tag mismatch — verify by comparing file content (handles manual edits)
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

        Write-Host "  Update available!" -ForegroundColor $(if ($Passive) { 'DarkGray' } else { 'Yellow' })
        if ($Passive) {
            Write-Host '  Nothing was downloaded. Select [U] Check for updates' -ForegroundColor DarkGray
            Write-Host '  in the menu to review and install it manually.' -ForegroundColor DarkGray
            return
        }

        # --- Release info panel ---
        Write-Host ''
        Write-Host '  ============================================' -ForegroundColor Cyan
        Write-Host '    RELEASE  $tag' -ForegroundColor White
        Write-Host '  ============================================' -ForegroundColor Cyan
        # Tag info
        Write-Host "  Tag:        $tag" -ForegroundColor White
        if ($release.target_commitish) {
            Write-Host "  Branch:     $($release.target_commitish)" -ForegroundColor DarkGray
        }
        if ($release.author -and $release.author.login) {
            Write-Host "  Author:     $($release.author.login)" -ForegroundColor DarkGray
        }
        if ($release.prerelease) {
            Write-Host '  Status:     Pre-release' -ForegroundColor Yellow
        }
        if ($remoteDate) {
            $published = try { [datetime]::Parse($remoteDate).ToString('yyyy-MM-dd HH:mm') } catch { $remoteDate }
            Write-Host "  Published:  $published" -ForegroundColor DarkGray
        }
        $releaseUrl = "https://github.com/$GitHubRepo/releases/tag/$tag"
        Write-Host "  URL:        $releaseUrl" -ForegroundColor DarkGray
        # Show asset list if available
        if ($release.assets -and $release.assets.Count -gt 0) {
            Write-Host "  Assets:     $($release.assets.Count) file(s)" -ForegroundColor DarkGray
            foreach ($asset in $release.assets) {
                $assetSize = if ($asset.size -gt 1MB) { "$([math]::Round($asset.size/1MB, 1)) MB" } elseif ($asset.size -gt 1KB) { "$([math]::Round($asset.size/1KB, 1)) KB" } else { "$($asset.size) B" }
                Write-Host "               - $($asset.name) ($assetSize)" -ForegroundColor DarkGray
            }
        }
        # Local version info
        $localTag = ''
        if (Test-Path -LiteralPath $VersionFile) {
            try {
                $localTag = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
            } catch {
                Write-Debug "Version file read failed: $($_.Exception.Message)"
            }
        }
        if ($localTag) {
            Write-Host "  Current:    $localTag" -ForegroundColor DarkGray
            Write-Host "  New:        $tag" -ForegroundColor Green
        }
        Write-Host '  ============================================' -ForegroundColor Cyan

        # --- Releases list (all available releases) ---
        try {
            $releasesUrl = "https://api.github.com/repos/$GitHubRepo/releases"
            $releasesJson = Invoke-GitHubGet $releasesUrl 15
            $releasesList = $releasesJson | ConvertFrom-Json
            if ($releasesList -and $releasesList.Count -gt 0) {
                Write-Host ''
                Write-Host '  ============================================' -ForegroundColor Cyan
                Write-Host '    RELEASES' -ForegroundColor White
                Write-Host '  ============================================' -ForegroundColor Cyan
                foreach ($rel in $releasesList) {
                    $rTag = $rel.tag_name
                    $rTitle = if ($rel.name) { $rel.name } else { $rTag }
                    $rAuthor = if ($rel.author -and $rel.author.login) { $rel.author.login } else { '' }
                    $rDate = ''
                    if ($rel.published_at) {
                        try { $rDate = [datetime]::Parse($rel.published_at).ToString('yyyy-MM-dd HH:mm') } catch { $rDate = $rel.published_at }
                    }
                    $rBody = if ($rel.body) { $rel.body } else { '' }
                    $rCommit = ''
                    if ($rel.target_commitish) { $rCommit = $rel.target_commitish.Substring(0, [Math]::Min(7, $rel.target_commitish.Length)) }
                    $rUrl = "https://github.com/$GitHubRepo/releases/tag/$rTag"
                    # Badge
                    $badge = ''
                    $badgeColor = 'DarkGray'
                    if ($rel.prerelease) { $badge = ' [Pre-release]'; $badgeColor = 'Yellow' }
                    elseif ($rel.tag_name -eq $tag) { $badge = ' [Latest]'; $badgeColor = 'Green' }
                    # Version marker
                    $marker = ''
                    if ($rTag -eq $localTag -and $rTag -eq $tag) { $marker = ' <-- current (latest)' }
                    elseif ($rTag -eq $localTag) { $marker = ' <-- current' }
                    elseif ($rTag -eq $tag) { $marker = ' <-- latest' }
                    # Header
                    Write-Host ''
                    Write-Host '  ----------------------------------------' -ForegroundColor DarkGray
                    Write-Host "  $rTitle" -ForegroundColor White -NoNewline
                    if ($badge) { Write-Host $badge -ForegroundColor $badgeColor -NoNewline }
                    if ($marker) { Write-Host $marker -ForegroundColor Yellow -NoNewline }
                    Write-Host ''
                    # Meta: author | date | tag | commit
                    $meta = @()
                    if ($rAuthor) { $meta += "by $rAuthor" }
                    if ($rDate) { $meta += $rDate }
                    if ($rTag) { $meta += "tag: $rTag" }
                    if ($rCommit -and $rCommit -ne $rTag) { $meta += "commit: $rCommit" }
                    if ($meta.Count -gt 0) {
                        Write-Host "  $($meta -join ' | ')" -ForegroundColor DarkGray
                    }
                    # Assets with sizes
                    if ($rel.assets -and $rel.assets.Count -gt 0) {
                        foreach ($asset in $rel.assets) {
                            $aSize = if ($asset.size -gt 1MB) { "$([math]::Round($asset.size/1MB, 1)) MB" } elseif ($asset.size -gt 1KB) { "$([math]::Round($asset.size/1KB, 1)) KB" } else { "$($asset.size) B" }
                            Write-Host "    $($asset.name) ($aSize)" -ForegroundColor DarkGray
                        }
                    }
                    # Release notes (first 6 lines)
                    if ($rBody) {
                        $rLines = $rBody -split "`n"
                        $rShown = 0
                        foreach ($rLine in $rLines) {
                            if ($rShown -ge 6) {
                                Write-Host '    ... (more in GitHub releases)' -ForegroundColor DarkGray
                                break
                            }
                            if ($rLine.Trim()) {
                                if ($rLine -match '^#{1,3}\s') {
                                    Write-Host "    $rLine" -ForegroundColor Yellow
                                } elseif ($rLine -match '^-\s|^-\s\[') {
                                    Write-Host "    $rLine" -ForegroundColor Green
                                } else {
                                    Write-Host "    $rLine" -ForegroundColor White
                                }
                                $rShown++
                            }
                        }
                    }
                    # Links
                    Write-Host "    $rUrl" -ForegroundColor DarkGray
                }
                Write-Host ''
                Write-Host '  ============================================' -ForegroundColor Cyan
            }
        } catch {
            Write-Debug "Releases list fetch failed: $($_.Exception.Message)"
        }

        # --- Tags panel ---
        try {
            $tagsUrl = "https://api.github.com/repos/$GitHubRepo/tags"
            $tagsJson = Invoke-GitHubGet $tagsUrl 15
            $tagsList = $tagsJson | ConvertFrom-Json
            if ($tagsList -and $tagsList.Count -gt 0) {
                Write-Host ''
                Write-Host '  ============================================' -ForegroundColor Cyan
                Write-Host '    TAGS' -ForegroundColor White
                Write-Host '  ============================================' -ForegroundColor Cyan
                foreach ($t in $tagsList) {
                    $tName = $t.name
                    $tCommit = ''
                    if ($t.commit -and $t.commit.sha) {
                        $tCommit = $t.commit.sha.Substring(0, [Math]::Min(7, $t.commit.sha.Length))
                    }
                    $tMarker = ''
                    if ($tName -eq $localTag -and $tName -eq $tag) { $tMarker = ' <-- current (latest)' }
                    elseif ($tName -eq $localTag) { $tMarker = ' <-- current' }
                    elseif ($tName -eq $tag) { $tMarker = ' <-- latest' }
                    $tColor = if ($tMarker -match 'current') { 'Green' } elseif ($tMarker -match 'latest') { 'Green' } else { 'White' }
                    Write-Host "  $tName" -ForegroundColor $tColor -NoNewline
                    if ($tCommit) { Write-Host "  ($tCommit)" -ForegroundColor DarkGray -NoNewline }
                    if ($tMarker) { Write-Host $tMarker -ForegroundColor Yellow -NoNewline }
                    Write-Host ''
                }
                Write-Host '  ----------------------------------------' -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '  ============================================' -ForegroundColor Cyan
            }
        } catch {
            Write-Debug "Tags fetch failed: $($_.Exception.Message)"
        }

        # Show changelog
        if ($remoteBody) {
            Write-Host ''
            Write-Host '  --- Release notes ---' -ForegroundColor Cyan
            $lines = $remoteBody -split "`n"
            $shown = 0
            foreach ($line in $lines) {
                if ($shown -ge 30) {
                    Write-Host '  ... (more in GitHub releases)' -ForegroundColor DarkGray
                    break
                }
                if ($line.Trim()) {
                    # Highlight markdown headings
                    if ($line -match '^#{1,3}\s') {
                        Write-Host "  $line" -ForegroundColor Yellow
                    } elseif ($line -match '^-\s|^-\s\[') {
                        Write-Host "  $line" -ForegroundColor Green
                    } else {
                        Write-Host "  $line" -ForegroundColor White
                    }
                    $shown++
                }
            }
            Write-Host '  ---------------------' -ForegroundColor Cyan
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

        $failed = 0

        # Download files with progress bar (curl.exe -# shows speed/size)
        $dlHeaders = @()
        if ($GitHubToken) { $dlHeaders += @('-H', "Authorization: token $GitHubToken") }

        foreach ($f in $files) {
            $dest = Join-Path $ScriptDir $f
            $rawUrl = "https://api.github.com/repos/$GitHubRepo/contents/$SkillPath/$f`?ref=$tag"
            Write-Host "  Downloading $f..." -ForegroundColor Yellow
            try {
                $tmpDl = Join-Path $env:TEMP ('mumu_dl_' + [Guid]::NewGuid().ToString('N') + '.tmp')
                $dlCmd = 'curl.exe -# --retry 3 --retry-delay 3 --connect-timeout 30 --max-time 120 -L -H "Accept: application/vnd.github.v3.raw" -o "' + $tmpDl + '"'
                if ($GitHubToken) { $dlCmd += ' -H "Authorization: token ' + $GitHubToken + '"' }
                $dlCmd += ' "' + $rawUrl + '"'
                $dlOutput = & cmd /c $dlCmd 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpDl)) {
                    $detail = if ($dlOutput) { $dlOutput.Trim() } else { "exit code $LASTEXITCODE" }
                    throw "curl failed for $f - $detail"
                }
                $bytes = [System.IO.File]::ReadAllBytes($tmpDl)
                Remove-Item $tmpDl -Force -ErrorAction SilentlyContinue
                if (-not $bytes -or $bytes.Length -eq 0) { throw 'empty download' }

                # Check for JSON error response or API metadata instead of raw content
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                if ($text -match '"message"\s*:\s*"') {
                    $errMsg = if ($text -match '"message"\s*:\s*"([^"]+)"') { $Matches[1] } else { 'API error' }
                    throw $errMsg
                }
                if ($text -match '"encoding"\s*:\s*"base64"') {
                    throw 'Received base64 JSON instead of raw content - Accept header may be missing'
                }
                if ($text -match '"name"\s*:\s*"' -and $text -match '"_links"') {
                    throw 'Received GitHub API JSON metadata instead of raw file content'
                }

                $dlSize = if ($bytes.Length -gt 1MB) { "$([math]::Round($bytes.Length / 1MB, 1)) MB" }
                          elseif ($bytes.Length -gt 1KB) { "$([math]::Round($bytes.Length / 1KB, 1)) KB" }
                          else { "$($bytes.Length) B" }

                # Self-update: can't overwrite the running script directly.
                # Write .new file, apply on next startup.
                if ($f -eq 'mumu-menu.ps1') {
                    $newPath = $dest + '.new'
                    [System.IO.File]::WriteAllBytes($newPath, $bytes)
                    Write-Host "    $f saved as .new ($dlSize) (will apply on restart)" -ForegroundColor Green
                } else {
                    [System.IO.File]::WriteAllBytes($dest, $bytes)
                    Write-Host "    $f OK ($dlSize)" -ForegroundColor Green
                }
            } catch {
                $errMsg = $_.Exception.Message
                if (-not $errMsg) { $errMsg = 'Unknown error - check network connection and try again' }
                Write-Host "    Failed: $errMsg" -ForegroundColor Red
                if ($tmpDl -and (Test-Path $tmpDl)) { Remove-Item $tmpDl -Force -ErrorAction SilentlyContinue }
                $failed++
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

# Apply pending self-update (.new file from previous [U] update)
try {
    $selfNew = Join-Path $ScriptDir 'mumu-menu.ps1.new'
    if (Test-Path -LiteralPath $selfNew) {
        $selfDest = Join-Path $ScriptDir 'mumu-menu.ps1'
        $selfOld = $selfDest + '.old'
        # Backup current to .old
        if (Test-Path -LiteralPath $selfDest) {
            try {
                if (Test-Path -LiteralPath $selfOld) { Remove-Item -LiteralPath $selfOld -Force -ErrorAction SilentlyContinue }
                Copy-Item -LiteralPath $selfDest -Destination $selfOld -Force
            } catch { Write-Debug "Backup old script failed: $($_.Exception.Message)" }
        }
        # Apply .new
        Copy-Item -LiteralPath $selfNew -Destination $selfDest -Force
        Remove-Item -LiteralPath $selfNew -Force -ErrorAction SilentlyContinue
        Write-Host '  Applied pending update from .new file' -ForegroundColor Green
    }
} catch {
    Write-Debug "Update apply failed: $($_.Exception.Message)"
}

# Clean up .old backup
try {
    $selfOld = Join-Path $ScriptDir 'mumu-menu.ps1.old'
    if (Test-Path -LiteralPath $selfOld) {
        Remove-Item -LiteralPath $selfOld -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Debug ".old cleanup failed: $($_.Exception.Message)"
}

# Read-only update check at startup; installs only via menu option [U]
try { Update-FromGitHub -Passive } catch { Write-Debug "Startup update check failed: $($_.Exception.Message)" }

# Check MuMu version
$MinVersion = [version]'4.0.0.3179'
try {
    $verJson = & $MumuPath version 2>$null | ConvertFrom-Json
    if ($verJson.version) { $InstalledVersion = [version]$verJson.version }
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
        $muVer = if ($InstalledVersion) { "$InstalledVersion" } else { 'unknown' }
        Write-Host "  v$scriptVer | MuMu $muVer | $running/$total running" -ForegroundColor DarkGray
    } catch {
        $muVer = if ($InstalledVersion) { "$InstalledVersion" } else { 'unknown' }
        Write-Host "  v$scriptVer | MuMu $muVer" -ForegroundColor DarkGray
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
    Write-Host '  [AF] ADB file transfer (push/pull/list)' -ForegroundColor Yellow
    Write-Host '  [AS] ADB screen capture (screenshot/record)' -ForegroundColor Yellow
    Write-Host '  [AH] ADB interactive shell' -ForegroundColor Yellow
    Write-Host '  [O] Clear app data' -ForegroundColor Yellow
    Write-Host '  [P] Force stop app' -ForegroundColor Yellow
    Write-Host '  [T] Start app' -ForegroundColor Yellow
    Write-Host '  [E] Export emulator data' -ForegroundColor Yellow
    Write-Host '  [BA] Backup instance data' -ForegroundColor Yellow
    Write-Host '  [RE] Restore from backup' -ForegroundColor Yellow
    Write-Host '  [K] Update GitHub token' -ForegroundColor Yellow
    Write-Host '  [VK] Set VirusTotal API key' -ForegroundColor Yellow
    Write-Host '  [CRT] Create/sign certificate' -ForegroundColor Yellow
    Write-Host '  [Z] Security audit (disabled)' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Tests ---' -ForegroundColor Green
    Write-Host '  [TC] Connection test' -ForegroundColor Yellow
    Write-Host '  [TN] Network test' -ForegroundColor Yellow
    Write-Host '  [TD] Dependencies test' -ForegroundColor Yellow
    Write-Host '  [VT] VirusTotal scan' -ForegroundColor Yellow
    Write-Host '  [UW] Fix Unicode / encoding' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Spoofing ---' -ForegroundColor Green
    Write-Host '  [DM] Spoof device model' -ForegroundColor Yellow
    Write-Host '  [SIM] Change SIM operator / country (MCC/MNC)' -ForegroundColor Yellow
    Write-Host '  [DI] Random device IDs' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Info ---' -ForegroundColor Green
    Write-Host '  [V] Version info' -ForegroundColor Yellow
    Write-Host '  [U] Check for updates' -ForegroundColor Yellow
    Write-Host '  [DL] Download repository' -ForegroundColor Yellow
    Write-Host '  [CR] Create release' -ForegroundColor Yellow
    Write-Host '  [FR] Fix release encoding' -ForegroundColor Yellow
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

function Restore-EmulatorData {
    # Check both backup folders (backups/ for emulator data, backup/ for script updates)
    $backupDirs = @()
    $b1 = Join-Path $ScriptDir 'backups'
    $b2 = Join-Path $ScriptDir 'backup'
    if (Test-Path -LiteralPath $b1) { $backupDirs += $b1 }
    if (Test-Path -LiteralPath $b2) { $backupDirs += $b2 }

    if ($backupDirs.Count -eq 0) {
        Write-Host 'No backup folders found.' -ForegroundColor Yellow
        Write-Host "Expected: $b1 or $b2" -ForegroundColor DarkGray
        return
    }

    # Collect backup folders AND .zip archives from all backup dirs
    $entries = [System.Collections.ArrayList]::new()
    foreach ($backupRoot in $backupDirs) {
        $dirs = Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            $null = $entries.Add([pscustomobject]@{
                Name = $d.Name
                Path = $d.FullName
                IsZip = $false
                Size = (Get-ChildItem -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                LastWriteTime = $d.LastWriteTime
            })
        }
        $zips = Get-ChildItem -LiteralPath $backupRoot -Filter '*.zip' -File -ErrorAction SilentlyContinue
        foreach ($z in $zips) {
            $null = $entries.Add([pscustomobject]@{
                Name = $z.Name
                Path = $z.FullName
                IsZip = $true
                Size = $z.Length
                LastWriteTime = $z.LastWriteTime
            })
        }
    } # end foreach backupRoot
    $entries = @($entries | Sort-Object LastWriteTime -Descending)

    if ($entries.Count -eq 0) {
        Write-Host 'No backups found.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host 'Available backups:' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $e = $entries[$i]
        $age = (Get-Date) - $e.LastWriteTime
        $ageStr = if ($age.TotalDays -ge 1) { "{0:N0}d ago" -f $age.TotalDays }
                  elseif ($age.TotalHours -ge 1) { "{0:N0}h ago" -f $age.TotalHours }
                  else { "{0:N0}m ago" -f $age.TotalMinutes }
        $instMatch = [regex]::Match($e.Name, 'emu_(\d+)_')
        $instLabel = if ($instMatch.Success) { "instance #$($instMatch.Groups[1].Value)" } else { 'unknown' }
        $typeTag = if ($e.IsZip) { 'ZIP' } else { 'DIR' }
        $sizeStr = if ($e.Size / 1GB -ge 1) { "{0:N2} GB" -f ($e.Size / 1GB) } else { "{0:N2} MB" -f ($e.Size / 1MB) }

        $tagColor = if ($e.IsZip) { 'Cyan' } else { 'DarkGray' }
        Write-Host "  [$($i + 1)] $($e.Name)" -NoNewline -ForegroundColor White
        Write-Host "  [$typeTag]" -ForegroundColor $tagColor
        Write-Host "       Instance: $instLabel  |  Size: $sizeStr  |  $ageStr" -ForegroundColor DarkGray
    }

    Write-Host ''
    $sel = Read-Host 'Select backup to restore (number)'
    if (-not ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $entries.Count)) {
        Write-Host 'Invalid selection.' -ForegroundColor Red
        return
    }
    $chosen = $entries[[int]$sel - 1]
    $isZipRestore = $chosen.IsZip

    # Show contents
    Write-Host ''
    Write-Host "Contents of $($chosen.Name):" -ForegroundColor Cyan

    if ($isZipRestore) {
        # Show zip contents
        $zipSize = '{0:N2} MB' -f ($chosen.Size / 1MB)
        Write-Host "  [ZIP] $($chosen.Name)  ($zipSize)" -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Extracting contents list...' -ForegroundColor DarkGray
        $tmpExtract = Join-Path $env:TEMP ("mumu_list_" + [Guid]::NewGuid().ToString('N'))
        try {
            $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
            if (Test-Path $tarExe) {
                New-Item -ItemType Directory -Path $tmpExtract -Force | Out-Null
                & $tarExe -xf $chosen.Path -C $tmpExtract 2>&1 | Out-Null
            } else {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($chosen.Path)
                try {
                    foreach ($entry in $zip.Entries) {
                        $destPath = Join-Path $tmpExtract $entry.FullName
                        $dir = Split-Path $destPath -Parent
                        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                        if ($entry.Name) { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true) }
                    }
                } finally {
                    $zip.Dispose()
                }
            }
            $zipItems = Get-ChildItem -LiteralPath $tmpExtract -Recurse -ErrorAction SilentlyContinue | Select-Object -First 20
            $totalItems = (Get-ChildItem -LiteralPath $tmpExtract -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
            foreach ($item in $zipItems) {
                $rel = $item.FullName.Substring($tmpExtract.Length + 1)
                if ($item.PSIsContainer) {
                    Write-Host "  [DIR]  $rel" -ForegroundColor DarkGray
                } else {
                    $sz = '{0:N2} MB' -f ($item.Length / 1MB)
                    Write-Host "  [FILE] $rel  ($sz)" -ForegroundColor DarkGray
                }
            }
            if ($totalItems -gt 20) {
                Write-Host "  ... and $($totalItems - 20) more items" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  Failed to list ZIP contents: $($_.Exception.Message)" -ForegroundColor Yellow
        } finally {
            if (Test-Path $tmpExtract) { Remove-Item -LiteralPath $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } else {
        $items = Get-ChildItem -LiteralPath $chosen.Path -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                $itemSize = (Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                $sz = '{0:N2} GB' -f ($itemSize / 1GB)
                Write-Host "  [DIR]  $($item.Name)  ($sz)" -ForegroundColor DarkGray
            } else {
                $sz = '{0:N2} MB' -f ($item.Length / 1MB)
                Write-Host "  [FILE] $($item.Name)  ($sz)" -ForegroundColor DarkGray
            }
        }
    }

    # Extract instance index from name (folder or zip)
    $instMatch = [regex]::Match($chosen.Name, 'emu_(\d+)[_.]')
    $defaultIndex = if ($instMatch.Success) { $instMatch.Groups[1].Value } else { '' }

    Write-Host ''
    if ($defaultIndex) {
        Write-Host "Detected instance: #$defaultIndex" -ForegroundColor Cyan
        $indexInput = Read-Host "Press Enter for instance #$defaultIndex, or type a different index"
        $index = if ($indexInput.Trim()) { $indexInput.Trim() } else { $defaultIndex }
    } else {
        $index = Get-InstanceIndex 'Target instance index to restore into'
    }
    if (-not $index) { return }

    # Find target folder
    $nxDir = Split-Path $MumuPath -Parent
    $installRoot = Split-Path $nxDir -Parent
    $vmsRoot = Join-Path $installRoot 'vms'

    $targets = @()
    if (Test-Path -LiteralPath $vmsRoot) {
        foreach ($d in (Get-ChildItem -LiteralPath $vmsRoot -Directory)) {
            $m = [regex]::Match($d.Name, '-(\d+)$')
            if ($m.Success -and $m.Groups[1].Value -eq $index) {
                $targets += $d.FullName
            }
        }
    }

    if ($targets.Count -gt 0) {
        $dest = $targets[0]
        if ($targets.Count -gt 1) {
            Write-Host ''
            Write-Host 'Multiple data folders found:' -ForegroundColor Yellow
            for ($i = 0; $i -lt $targets.Count; $i++) {
                Write-Host "  [$($i + 1)] $($targets[$i])" -ForegroundColor White
            }
            $tsel = Read-Host 'Select target folder (number)'
            if ($tsel -match '^\d+$' -and [int]$tsel -ge 1 -and [int]$tsel -le $targets.Count) {
                $dest = $targets[[int]$tsel - 1]
            }
        }
    } else {
        Write-Host "No data folder found for instance #$index under $vmsRoot" -ForegroundColor Yellow
        $dest = (Read-Host 'Enter target folder path').Trim()
    }

    $customDest = (Read-Host "Press Enter to use: $dest`nOr type a different path").Trim()
    if ($customDest) { $dest = $customDest }

    if (-not ($dest -and (Test-Path -LiteralPath $dest))) {
        Write-Host "Target folder not found: $dest" -ForegroundColor Red
        return
    }

    # Check if instance is running
    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    if ($info.is_process_started) {
        Write-Host ''
        Write-Host 'WARNING: instance is running. Restore may be inconsistent or fail.' -ForegroundColor Yellow
        $ans = Read-Host 'Shutdown instance before restore? (Y/n)'
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
                Write-Host 'Instance did not stop. Restore cancelled.' -ForegroundColor Red
                return
            }
            Write-Host 'Instance shut down.' -ForegroundColor Green
        }
    }

    # Confirm overwrite
    Write-Host ''
    Write-Host "Target: $dest" -ForegroundColor Cyan
    Write-Host 'All data in the target folder will be OVERWRITTEN.' -ForegroundColor Yellow
    $confirm = Read-Host 'Type YES to confirm restore'
    if ($confirm -ne 'YES') {
        Write-Host 'Restore cancelled.' -ForegroundColor Yellow
        return
    }

    # Optional: create safety backup of current data
    $safetyAns = Read-Host 'Create safety backup of current data first? (Y/n)'
    if ($safetyAns -ne 'n' -and $safetyAns -ne 'N') {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safetyDest = Join-Path $ScriptDir "backups\pre_restore_${index}_$stamp"
        New-Item -ItemType Directory -Path $safetyDest -Force | Out-Null
        Write-Host "  Safety backup -> $safetyDest" -ForegroundColor DarkGray
        & robocopy $dest $safetyDest /E /NDL /NJH /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -lt 8) {
            Write-Host '  Safety backup complete.' -ForegroundColor Green
        } else {
            Write-Host "  Safety backup warning (robocopy code: $($LASTEXITCODE))" -ForegroundColor Yellow
        }
    }

    # Restore
    Write-Host ''
    Write-Host "Restoring from $($chosen.Name)..." -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Get-ChildItem -LiteralPath $dest -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    if ($isZipRestore) {
        # Extract ZIP to temp, then robocopy from there
        $tmpZip = Join-Path $env:TEMP ("mumu_restore_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpZip -Force | Out-Null
        try {
            $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
            if (Test-Path $tarExe) {
                & $tarExe -xf $chosen.Path -C $tmpZip 2>&1 | Out-Null
                $extractCode = $LASTEXITCODE
            } else {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($chosen.Path)
                try {
                    foreach ($entry in $zip.Entries) {
                        $entryDest = Join-Path $tmpZip $entry.FullName
                        $entryDir = Split-Path $entryDest -Parent
                        if ($entryDir -and -not (Test-Path $entryDir)) {
                            New-Item -ItemType Directory -Path $entryDir -Force | Out-Null
                        }
                        if ($entry.Name) {
                            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $entryDest, $true)
                        }
                    }
                } finally {
                    $zip.Dispose()
                }
                $extractCode = 0
            }

            if ($extractCode -ge 8) {
                Write-Host "ZIP extraction FAILED (exit code $extractCode)" -ForegroundColor Red
                return
            }

            # The ZIP may contain a nested folder (e.g. emu_1_20260828_123456/)
            $zipContents = Get-ChildItem -LiteralPath $tmpZip -ErrorAction SilentlyContinue
            $srcPath = if ($zipContents.Count -eq 1 -and $zipContents[0].PSIsContainer) {
                $zipContents[0].FullName
            } else {
                $tmpZip
            }

            & robocopy $srcPath $dest /E /NDL /NJH /NP /R:2 /W:2 | Out-Null
            $code = $LASTEXITCODE
        } finally {
            Remove-Item -LiteralPath $tmpZip -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        & robocopy $chosen.Path $dest /E /NDL /NJH /NP /R:2 /W:2 | Out-Null
        $code = $LASTEXITCODE
    }
    $sw.Stop()

    if ($code -ge 8) {
        Write-Host "Restore FAILED (robocopy exit code $code)" -ForegroundColor Red
        return
    }

    $restored = (Get-ChildItem -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Host ''
    Write-Host ("Restore complete! {0:N2} GB in {1:mm\:ss}" -f ($restored / 1GB), $sw.Elapsed) -ForegroundColor Green
    $srcType = if ($isZipRestore) { 'ZIP archive' } else { 'backup folder' }
    Write-Host "  Instance #${index} data restored from ${srcType}: $($chosen.Name)" -ForegroundColor DarkGray

    $startAns = Read-Host 'Start instance now? (y/N)'
    if ($startAns -eq 'y' -or $startAns -eq 'Y') {
        Write-Host 'Starting instance...' -ForegroundColor Cyan
        & $MumuPath control -v $index launch 2>&1 | Out-Null
        Write-Host 'Instance started.' -ForegroundColor Green
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
            $rawUser = & curl.exe -s --connect-timeout 30 --max-time 30 -D "$tmpHead" -H "Authorization: token $GitHubToken" 'https://api.github.com/user' 2>$null
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

    $tracked = git -C $ScriptDir -c safe.directory='*' ls-files '.github-token*' 2>$null
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

function Test-EmulatorConnection {
    $index = Get-InstanceIndex 'Select instance to test'
    if (-not $index) { return }
    Write-Host ''
    Write-Host '=== Emulator Connection Test ===' -ForegroundColor Cyan
    Write-Host ''

    # Helper: run ADB shell command through MuMuManager (targets specific instance)
    $run = { param($cmd) & $MumuPath adb -v $index -c "shell $cmd" 2>&1 | Out-String }

    # 1. Instance status
    Write-Host '[1] Instance status' -ForegroundColor Yellow
    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    if ($info.is_process_started) {
        Write-Host '  Running: YES' -ForegroundColor Green
    } else {
        Write-Host '  Running: NO' -ForegroundColor Red
        Write-Host '  Cannot test ADB connection on stopped instance.' -ForegroundColor Yellow
        return
    }

    # 2. MuMuManager ADB shell test
    Write-Host ''
    Write-Host '[2] ADB shell' -ForegroundColor Yellow
    $shellResult = & $run 'echo ok'
    if ($shellResult.Trim() -eq 'ok') {
        Write-Host '  Shell: OK' -ForegroundColor Green
    } else {
        Write-Host "  Shell: FAILED ($($shellResult.Trim()))" -ForegroundColor Red
    }

    # 3. ADB properties
    Write-Host ''
    Write-Host '[3] Device properties' -ForegroundColor Yellow
    $props = @('ro.build.display.id', 'ro.product.model', 'ro.build.version.sdk', 'ro.product.cpu.abi', 'ro.build.version.release')
    foreach ($p in $props) {
        $val = (& $run "getprop $p").Trim()
        if ($val) {
            $short = $p -replace '^ro\.', ''
            Write-Host "  ${short}: $val" -ForegroundColor White
        }
    }

    # 4. Internet connectivity
    Write-Host ''
    Write-Host '[4] Internet test' -ForegroundColor Yellow
    $netResult = & $run 'ping -c 2 -W 5 8.8.8.8'
    if ($netResult -match '(\d+) packets transmitted') {
        $sent = [int]($Matches[1])
        $recv = if ($netResult -match '(\d+) received') { [int]($Matches[1]) } else { 0 }
        if ($recv -gt 0) {
            $loss = (($sent - $recv) / $sent) * 100
            Write-Host "  Ping: OK (sent=$sent recv=$recv loss=$loss%)" -ForegroundColor Green
        } else {
            Write-Host '  Ping: FAILED (0 received)' -ForegroundColor Red
        }
    } else {
        Write-Host "  Ping: FAILED" -ForegroundColor Red
    }

    # 5. Memory
    Write-Host ''
    Write-Host '[5] Memory' -ForegroundColor Yellow
    $memInfo = & $run 'cat /proc/meminfo'
    if ($memInfo -match 'MemTotal:\s+(\d+)') {
        $totalMB = [int]$Matches[1] / 1024
        $freeMB = 0
        if ($memInfo -match 'MemAvailable:\s+(\d+)') { $freeMB = [int]$Matches[1] / 1024 }
        elseif ($memInfo -match 'MemFree:\s+(\d+)') { $freeMB = [int]$Matches[1] / 1024 }
        $usedMB = $totalMB - $freeMB
        $pct = if ($totalMB -gt 0) { ($usedMB / $totalMB) * 100 } else { 0 }
        $color = if ($pct -gt 90) { 'Red' } elseif ($pct -gt 70) { 'Yellow' } else { 'Green' }
        Write-Host ("  RAM: {0:N0} MB / {1:N0} MB ({2:N1}% used)" -f $usedMB, $totalMB, $pct) -ForegroundColor $color
    }

    # 6. Storage
    Write-Host ''
    Write-Host '[6] Storage' -ForegroundColor Yellow
    $storage = & $run 'df /data'
    $storLines = $storage -split "`n" | Where-Object { $_ -match '/data$' }
    if ($storLines) {
        $parts = $storLines[0] -split '\s+'
        if ($parts.Count -ge 4) {
            $totalGB = [int]$parts[1] / 1048576
            $usedGB = [int]$parts[2] / 1048576
            $availGB = [int]$parts[3] / 1048576
            Write-Host ("  /data: {0:N1} GB / {1:N1} GB used ({2:N1} GB free)" -f $usedGB, $totalGB, $availGB) -ForegroundColor White
        }
    }

    Write-Host ''
    Write-Host 'Test complete.' -ForegroundColor Green
}

function Test-Network {
    $index = Get-InstanceIndex 'Select instance to test'
    if (-not $index) { return }
    Write-Host ''
    Write-Host '=== Network Test ===' -ForegroundColor Cyan
    Write-Host ''

    $info = & $MumuPath info -v $index 2>$null | ConvertFrom-Json
    if (-not $info.is_process_started) {
        Write-Host 'Instance is not running.' -ForegroundColor Red
        return
    }

    # Helper: run ADB shell command through MuMuManager (targets specific instance)
    $run = { param($cmd) & $MumuPath adb -v $index -c "shell $cmd" 2>&1 | Out-String }

    # Ping test
    Write-Host '[1] Ping test' -ForegroundColor Yellow
    $targets = @('8.8.8.8', '1.1.1.1', '223.5.5.5', 'google.com', 'github.com')
    foreach ($t in $targets) {
        $result = & $run "ping -c 2 -W 5 $t"
        if ($result -match 'rtt min.*=\s*([\d.]+)/([\d.]+)/([\d.]+)') {
            Write-Host "  $t : OK (avg $($Matches[2])ms)" -ForegroundColor Green
        } elseif ($result -match '(\d+) received') {
            $recv = [int]$Matches[1]
            if ($recv -gt 0) { Write-Host "  $t : OK" -ForegroundColor Green }
            else { Write-Host "  $t : FAILED" -ForegroundColor Red }
        } else {
            Write-Host "  $t : FAILED" -ForegroundColor Red
        }
    }

    # DNS resolution
    Write-Host ''
    Write-Host '[2] DNS resolution' -ForegroundColor Yellow
    $dnsTargets = @('google.com', 'github.com', 'baidu.com')
    foreach ($d in $dnsTargets) {
        $result = & $run "nslookup $d"
        if ($result -match 'Address:\s+\d') {
            Write-Host "  $d : OK" -ForegroundColor Green
        } else {
            Write-Host "  $d : FAILED" -ForegroundColor Red
        }
    }

    # HTTP test
    Write-Host ''
    Write-Host '[3] HTTP test' -ForegroundColor Yellow
    $httpTargets = @(
        @{ Url = 'http://connectivitycheck.gstatic.com/generate_204'; Name = 'Google' },
        @{ Url = 'http://www.baidu.com'; Name = 'Baidu' },
        @{ Url = 'https://github.com'; Name = 'GitHub' }
    )
    foreach ($h in $httpTargets) {
        $result = & $run "curl -s -o /dev/null -w '%{http_code}' --max-time 10 $($h.Url)"
        $code = $result.Trim()
        if ($code -match '^(200|301|302|204)$') {
            Write-Host "  $($h.Name) ($code) : OK" -ForegroundColor Green
        } else {
            Write-Host "  $($h.Name) ($code) : FAILED" -ForegroundColor Red
        }
    }

    # WiFi info
    Write-Host ''
    Write-Host '[4] WiFi info' -ForegroundColor Yellow
    $wifi = & $run 'dumpsys wifi | grep "mWifiInfo"'
    if ($wifi) {
        if ($wifi -match 'SSID:\s*"([^"]+)"') {
            Write-Host "  SSID: $($Matches[1])" -ForegroundColor White
        }
        if ($wifi -match 'link speed:\s*(\d+)') {
            Write-Host "  Speed: $($Matches[1]) Mbps" -ForegroundColor White
        }
    } else {
        # Fallback: try ip addr
        $ipInfo = & $run 'ip addr show wlan0 2>/dev/null || ip addr show eth0'
        if ($ipInfo -match 'inet (\d+[\.\d]+)') {
            Write-Host "  IP: $($Matches[1])" -ForegroundColor White
        }
    }

    Write-Host ''
    Write-Host 'Test complete.' -ForegroundColor Green
}

function Set-VTApiKeyMenu {
    Write-Host ''
    Write-Host '=== VirusTotal API Key ===' -ForegroundColor Cyan
    Write-Host ''

    $dpapiFile = Join-Path $ScriptDir '.vt-apikey.dpapi'
    $plainFile = Join-Path $ScriptDir '.vt-apikey'

    # Show current status
    $currentKey = Get-VTApiKey
    if ($currentKey) {
        $masked = $currentKey.Substring(0, [Math]::Min(4, $currentKey.Length)) + '****'
        $encrypted = Test-Path -LiteralPath $dpapiFile
        $store = if ($encrypted) { 'DPAPI-encrypted' } else { 'plaintext' }
        Write-Host "  Current: $masked ($store)" -ForegroundColor Green
    } else {
        Write-Host '  Current: not set' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '  Get free key at: https://www.virustotal.com/gui/my-apikey' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  [1] Save new key' -ForegroundColor Yellow
    Write-Host '  [2] Delete key' -ForegroundColor Yellow
    Write-Host '  [3] Test key' -ForegroundColor Yellow
    Write-Host ''
    $action = Read-Host 'Select (1/2/3)'

    switch ($action) {
        '1' {
            $newKey = (Read-Host '  Enter VT API key').Trim()
            if (-not $newKey) { Write-Host '  Cancelled.' -ForegroundColor Yellow; return }
            if (Save-VTApiKey $newKey) {
                Write-Host '  Saved ENCRYPTED via DPAPI (.vt-apikey.dpapi)' -ForegroundColor Green
                # Verify
                $verify = Get-VTApiKey
                if ($verify -eq $newKey) {
                    Write-Host '  Verified: key decrypted successfully' -ForegroundColor Green
                } else {
                    Write-Host '  Warning: key verification failed' -ForegroundColor Yellow
                }
            }
        }
        '2' {
            if (Remove-VTApiKey) {
                Write-Host '  VT API key deleted.' -ForegroundColor Green
            } else {
                Write-Host '  No key to delete.' -ForegroundColor DarkGray
            }
        }
        '3' {
            $testKey = if ($currentKey) { $currentKey } else { $null }
            if (-not $testKey) {
                $testKey = (Read-Host '  Enter key to test').Trim()
            }
            if (-not $testKey) { Write-Host '  No key.' -ForegroundColor Yellow; return }
            try {
                $result = Invoke-RestMethod -Uri 'https://www.virustotal.com/api/v3/users/me' -Headers @{ 'x-apikey' = $testKey } -ErrorAction Stop
                $name = $result.data.attributes.username
                $quota = $result.data.attributes.reputation
                Write-Host "  Valid! User: $name" -ForegroundColor Green
            } catch {
                Write-Host '  Invalid key or API error.' -ForegroundColor Red
            }
        }
        default { Write-Host '  Invalid selection.' -ForegroundColor Red }
    }
}

function Get-VTApiKey {
    # Read VT API key from DPAPI-encrypted file, legacy plaintext, or env
    $key = $null
    $dpapiFile = Join-Path $ScriptDir '.vt-apikey.dpapi'
    $plainFile = Join-Path $ScriptDir '.vt-apikey'

    # 1. Try DPAPI-encrypted file
    if (Test-Path -LiteralPath $dpapiFile) {
        try {
            $raw = (Get-Content -LiteralPath $dpapiFile -Raw).Trim()
            $sec = $raw | ConvertTo-SecureString -ErrorAction Stop
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        } catch {
            Write-Host "  Warning: Cannot decrypt VT key ($($_.Exception.Message))" -ForegroundColor Yellow
        }
    }

    # 2. Migrate legacy plaintext file
    if (-not $key -and (Test-Path -LiteralPath $plainFile)) {
        try {
            $key = (Get-Content -LiteralPath $plainFile -Raw).Trim()
            if ($key) {
                $sec = ConvertTo-SecureString $key -AsPlainText -Force
                ConvertFrom-SecureString -SecureString $sec | Set-Content -Path $dpapiFile -NoNewline -Encoding UTF8
                Remove-Item -LiteralPath $plainFile -Force -ErrorAction SilentlyContinue
                Write-Host '  VT key migrated to encrypted storage (.vt-apikey.dpapi)' -ForegroundColor DarkGray
            }
        } catch { Write-Debug "VT key migration failed: $($_.Exception.Message)" }
    }

    # 3. Environment variable
    if (-not $key -and $env:VT_API_KEY) { $key = $env:VT_API_KEY }

    return $key
}

function Save-VTApiKey {
    param([string]$PlainKey)
    $dpapiFile = Join-Path $ScriptDir '.vt-apikey.dpapi'
    $plainFile = Join-Path $ScriptDir '.vt-apikey'
    try {
        $sec = ConvertTo-SecureString $PlainKey -AsPlainText -Force
        ConvertFrom-SecureString -SecureString $sec | Set-Content -Path $dpapiFile -NoNewline -Encoding UTF8
        if (Test-Path -LiteralPath $plainFile) {
            Remove-Item -LiteralPath $plainFile -Force -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Write-Host "  Failed to encrypt key: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Remove-VTApiKey {
    $dpapiFile = Join-Path $ScriptDir '.vt-apikey.dpapi'
    $plainFile = Join-Path $ScriptDir '.vt-apikey'
    $removed = $false
    if (Test-Path -LiteralPath $dpapiFile) {
        Remove-Item -LiteralPath $dpapiFile -Force -ErrorAction SilentlyContinue; $removed = $true
    }
    if (Test-Path -LiteralPath $plainFile) {
        Remove-Item -LiteralPath $plainFile -Force -ErrorAction SilentlyContinue; $removed = $true
    }
    if ($env:VT_API_KEY) { $env:VT_API_KEY = $null }
    return $removed
}

function Scan-VirusTotal {
    Write-Host ''
    Write-Host '=== VirusTotal ===' -ForegroundColor Cyan
    Write-Host ''

    $apiKey = Get-VTApiKey

    # Sub-menu
    Write-Host '  [1] Scan files' -ForegroundColor Yellow
    Write-Host '  [2] Save API key' -ForegroundColor Yellow
    Write-Host '  [3] Delete API key' -ForegroundColor Yellow
    Write-Host '  [4] Open VT in browser' -ForegroundColor Yellow
    Write-Host ''
    $action = Read-Host 'Select (1/2/3/4)'

    switch ($action) {
        '2' {
            Write-Host ''
            if ($apiKey) {
                $masked = $apiKey.Substring(0, [Math]::Min(4, $apiKey.Length)) + '****'
                Write-Host "  Current key: $masked" -ForegroundColor DarkGray
            }
            $newKey = (Read-Host '  Enter VT API key').Trim()
            if (-not $newKey) { Write-Host '  Cancelled.' -ForegroundColor Yellow; return }
            if (Save-VTApiKey $newKey) {
                Write-Host '  Saved ENCRYPTED via DPAPI (.vt-apikey.dpapi)' -ForegroundColor Green
                $apiKey = $newKey
            }
        }
        '3' {
            if (Remove-VTApiKey) {
                Write-Host '  VT API key deleted.' -ForegroundColor Green
            } else {
                Write-Host '  No key to delete.' -ForegroundColor DarkGray
            }
            return
        }
        '4' {
            Start-Process 'https://www.virustotal.com/gui/home/upload'
            return
        }
        { $_ -ne '1' } {
            Write-Host '  Invalid selection.' -ForegroundColor Red
            return
        }
    }

    if (-not $apiKey) {
        Write-Host ''
        Write-Host '  No API key configured.' -ForegroundColor Yellow
        Write-Host '  Select [2] to save your key, or [4] to open VT in browser.' -ForegroundColor DarkGray
        return
    }

    # Files to scan
    $files = @()
    $menuPath = Join-Path $ScriptDir 'mumu-menu.ps1'
    $bootPath = Join-Path $ScriptDir 'bootstrap-update.ps1'
    if (Test-Path -LiteralPath $menuPath) { $files += @{ Name = 'mumu-menu.ps1'; Path = $menuPath } }
    if (Test-Path -LiteralPath $bootPath) { $files += @{ Name = 'bootstrap-update.ps1'; Path = $bootPath } }

    if ($files.Count -eq 0) {
        Write-Host '  No script files found.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host '  Scanning files...' -ForegroundColor Cyan
    Write-Host ''

    $clean = 0
    $dirty = 0

    foreach ($f in $files) {
        $hash = (Get-FileHash -Path $f.Path -Algorithm SHA256).Hash.ToLower()
        Write-Host "  $($f.Name)" -ForegroundColor White -NoNewline
        Write-Host "  SHA256: $($hash.Substring(0,16))..." -ForegroundColor DarkGray -NoNewline

        # Check if already scanned
        try {
            $url = "https://www.virustotal.com/api/v3/files/$hash"
            $result = Invoke-RestMethod -Uri $url -Headers @{ 'x-apikey' = $apiKey } -ErrorAction Stop
            $stats = $result.data.attributes.last_analysis_stats
            $m = $stats.malicious; $s = $stats.suspicious; $u = $stats.undetected; $h = $stats.harmless
            $t = $m + $s + $u + $h
            if ($m -gt 0 -or $s -gt 0) {
                Write-Host "  DETECTED: $m malicious, $s suspicious / $t" -ForegroundColor Red
                $dirty++
            } else {
                Write-Host "  0/$t clean" -ForegroundColor Green
                $clean++
            }
            Write-Host "    https://www.virustotal.com/gui/file/$hash" -ForegroundColor DarkGray
        } catch {
            # Not on VT yet - upload
            Write-Host '  uploading...' -ForegroundColor Yellow -NoNewline
            try {
                $boundary = [Guid]::NewGuid().ToString()
                $fileName = [IO.Path]::GetFileName($f.Path)
                $fileBytes = [IO.File]::ReadAllBytes($f.Path)
                $hdr = [Text.Encoding]::UTF8.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$fileName`"`r`nContent-Type: application/octet-stream`r`n`r`n")
                $ftr = [Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
                $body = New-Object byte[] ($hdr.Length + $fileBytes.Length + $ftr.Length)
                [Buffer]::BlockCopy($hdr, 0, $body, 0, $hdr.Length)
                [Buffer]::BlockCopy($fileBytes, 0, $body, $hdr.Length, $fileBytes.Length)
                [Buffer]::BlockCopy($ftr, 0, $body, $hdr.Length + $fileBytes.Length, $ftr.Length)
                $null = Invoke-RestMethod -Uri 'https://www.virustotal.com/api/v3/files' -Method Post -Headers @{ 'x-apikey' = $apiKey } -ContentType "multipart/form-data; boundary=$boundary" -Body $body -ErrorAction Stop
                Write-Host ' done (analyzing...)' -ForegroundColor Green
                Write-Host "    https://www.virustotal.com/gui/file/$hash" -ForegroundColor DarkGray
            } catch {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host ''
    if ($clean -gt 0 -and $dirty -eq 0) {
        Write-Host "  All $clean file(s) clean!" -ForegroundColor Green
    } elseif ($dirty -gt 0) {
        Write-Host "  WARNING: $dirty file(s) detected!" -ForegroundColor Red
    }
}

function Fix-Unicode {
    Write-Host ''
    Write-Host '=== Fix Unicode / Encoding ===' -ForegroundColor Cyan
    Write-Host ''

    Write-Host 'Options:' -ForegroundColor Yellow
    Write-Host '  [1] Scan files for encoding issues' -ForegroundColor White
    Write-Host '  [2] Fix file encoding (convert to UTF-8)' -ForegroundColor White
    Write-Host '  [3] Fix mojibake (garbled Cyrillic/Unicode)' -ForegroundColor White
    Write-Host '  [4] Show file encoding info' -ForegroundColor White
    Write-Host ''
    $mode = Read-Host 'Select option (1/2/3/4)'

    if ($mode -eq '1') {
        # Scan for encoding issues
        Write-Host ''
        Write-Host 'Scanning files...' -ForegroundColor Cyan
        $files = Get-ChildItem -LiteralPath $ScriptDir -File -Include '*.ps1','*.md','*.txt','*.yml','*.json' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\.git\\' -and $_.FullName -notmatch '\\.freebuff\\' }

        $ok = 0
        $warn = 0
        $bad = 0

        foreach ($f in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            $hasBOM = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $mojibake = $false

            # Check for double-encoded UTF-8 (common mojibake)
            $utf8Text = [System.Text.Encoding]::UTF8.GetString($bytes)
            if ($utf8Text -match '\u00C2[\x80-\xBF]|\u00C3[\x80-\xBF]') { $mojibake = $true }

            # Check for replacement characters
            $hasReplacement = $utf8Text -match '\uFFFD'

            $status = 'OK'
            $color = 'Green'
            if ($mojibake -or $hasReplacement) {
                $status = 'MOJIBAKE'
                $color = 'Red'
                $bad++
            } elseif ($hasBOM) {
                $status = 'UTF-8 BOM (OK but BOM present)'
                $color = 'Yellow'
                $warn++
            } else {
                $ok++
            }

            $rel = $f.FullName.Substring($ScriptDir.Length + 1)
            Write-Host "  [$status] $rel" -ForegroundColor $color
        }

        Write-Host ''
        Write-Host "  OK: $ok  |  Warnings: $warn  |  Mojibake: $bad" -ForegroundColor Cyan

    } elseif ($mode -eq '2') {
        # Fix encoding - convert to UTF-8 without BOM
        Write-Host ''
        $path = (Read-Host 'Enter file path (or folder)').Trim()
        $path = $path.Trim('"').Trim()

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host 'Path not found.' -ForegroundColor Red
            return
        }

        $files = if ((Get-Item -LiteralPath $path).PSIsContainer) {
            Get-ChildItem -LiteralPath $path -File -Include '*.ps1','*.md','*.txt','*.yml','*.json' -Recurse -ErrorAction SilentlyContinue
        } else {
            Get-Item -LiteralPath $path
        }

        foreach ($f in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)

            # Detect encoding
            $encoding = 'unknown'

            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $encoding = 'UTF-8 BOM'
            } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                $encoding = 'UTF-16 LE BOM'
            } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                $encoding = 'UTF-16 BE BOM'
            } else {
                # Try to detect UTF-8 without BOM
                $isUtf8 = $true
                try {
                    $dec = [System.Text.UTF8Encoding]::new($false, $true, $true)
                    $null = $dec.GetString($bytes)
                } catch {
                    $isUtf8 = $false
                }
                if ($isUtf8) { $encoding = 'UTF-8 no BOM' }
                else { $encoding = 'ANSI/other' }
            }

            if ($encoding -eq 'UTF-8 no BOM') {
                Write-Host "  $($f.Name): already UTF-8 no BOM - skipped" -ForegroundColor DarkGray
                continue
            }

            # Convert to UTF-8 without BOM
            $content = [System.IO.File]::ReadAllText($f.FullName)
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($f.FullName, $content, $utf8NoBom)

            $rel = $f.FullName.Substring($ScriptDir.Length + 1)
            Write-Host "  Fixed: $rel ($encoding -> UTF-8 no BOM)" -ForegroundColor Green
        }

    } elseif ($mode -eq '3') {
        # Fix mojibake
        Write-Host ''
        Write-Host 'Fix mojibake (garbled Cyrillic/Unicode)...' -ForegroundColor Cyan
        Write-Host ''
        $path = (Read-Host 'Enter file path').Trim()
        $path = $path.Trim('"').Trim()

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host 'File not found.' -ForegroundColor Red
            return
        }

        $bytes = [System.IO.File]::ReadAllBytes($path)

        # Common mojibake: CP1251 bytes interpreted as Latin-1
        # Try CP1251 -> UTF-8
        $cp1251 = [System.Text.Encoding]::GetEncoding(1251)
        $utf8 = [System.Text.Encoding]::UTF8

        # Read raw bytes as CP1251
        $decoded = $cp1251.GetString($bytes)

        # Check if it looks like real Cyrillic (not random garbage)
        $cyrillicCount = 0
        foreach ($ch in $decoded.ToCharArray()) {
            $cp = [int]$ch
            if ($cp -ge 0x0400 -and $cp -le 0x04FF) { $cyrillicCount++ }
        }

        $totalChars = $decoded.Length
        $cyrillicPct = if ($totalChars -gt 0) { ($cyrillicCount / $totalChars) * 100 } else { 0 }

        if ($cyrillicPct -gt 5) {
            # Looks like valid Cyrillic encoded in CP1251
            $fixed = $utf8.GetBytes($decoded)
            [System.IO.File]::WriteAllBytes($path, $fixed)
            Write-Host "  Fixed: $path" -ForegroundColor Green
            Write-Host "  Detected: CP1251 ($([math]::Round($cyrillicPct, 1))% Cyrillic)" -ForegroundColor DarkGray
            Write-Host "  Converted to: UTF-8" -ForegroundColor DarkGray
        } else {
            # Try UTF-8
            $utf8Decoded = $utf8.GetString($bytes)
            $hasCyrillic = $false
            foreach ($ch in $utf8Decoded.ToCharArray()) {
                $cp = [int]$ch
                if ($cp -ge 0x0400 -and $cp -le 0x04FF) { $hasCyrillic = $true; break }
            }
            if ($hasCyrillic) {
                Write-Host "  File is already valid UTF-8 with Cyrillic" -ForegroundColor Green
            } else {
                Write-Host "  Cannot detect encoding - file may not contain Cyrillic" -ForegroundColor Yellow
            }
        }

    } elseif ($mode -eq '4') {
        # Show encoding info
        Write-Host ''
        $path = (Read-Host 'Enter file path').Trim()
        $path = $path.Trim('"').Trim()

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host 'File not found.' -ForegroundColor Red
            return
        }

        $bytes = [System.IO.File]::ReadAllBytes($path)
        $size = (Get-Item -LiteralPath $path).Length

        Write-Host "  File: $path" -ForegroundColor White
        Write-Host "  Size: $size bytes" -ForegroundColor DarkGray

        # BOM detection
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Write-Host '  BOM: UTF-8 BOM' -ForegroundColor Yellow
        } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            Write-Host '  BOM: UTF-16 LE BOM' -ForegroundColor Yellow
        } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            Write-Host '  BOM: UTF-16 BE BOM' -ForegroundColor Yellow
        } else {
            Write-Host '  BOM: None' -ForegroundColor DarkGray
        }

        # UTF-8 validation
        $isUtf8 = $true
        try {
            $dec = [System.Text.UTF8Encoding]::new($false, $true, $true)
            $null = $dec.GetString($bytes)
        } catch {
            $isUtf8 = $false
        }
        Write-Host "  Valid UTF-8: $(if ($isUtf8) { 'YES' } else { 'NO' })" -ForegroundColor $(if ($isUtf8) { 'Green' } else { 'Red' })

        # High bytes analysis
        $highCount = 0
        foreach ($b in $bytes) { if ($b -gt 127) { $highCount++ } }
        Write-Host "  High bytes (>127): $highCount" -ForegroundColor DarkGray

        # Cyrillic detection
        if ($isUtf8) {
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $cyrillicCount = 0
            foreach ($ch in $text.ToCharArray()) {
                $cp = [int]$ch
                if ($cp -ge 0x0400 -and $cp -le 0x04FF) { $cyrillicCount++ }
            }
            if ($cyrillicCount -gt 0) {
                Write-Host "  Cyrillic chars: $cyrillicCount" -ForegroundColor Cyan
            }
        }

        # First 200 chars preview
        if ($isUtf8) {
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $preview = $text.Substring(0, [Math]::Min(200, $text.Length))
            Write-Host "  Preview: $preview" -ForegroundColor DarkGray
        }
    }
}

function Test-ScriptDependencies {
    Write-Host ''
    Write-Host '=== Script Dependencies Test ===' -ForegroundColor Cyan
    Write-Host ''

    $ok = 0
    $fail = 0

    # 1. MuMuManager.exe
    Write-Host '[1] MuMuManager.exe' -ForegroundColor Yellow
    if (Test-Path -LiteralPath $MumuPath) {
        Write-Host "  Path: $MumuPath" -ForegroundColor DarkGray
        $ver = & $MumuPath version 2>&1 | Out-String
        Write-Host "  Version: $($ver.Trim())" -ForegroundColor Green
        $ok++
    } else {
        Write-Host "  NOT FOUND: $MumuPath" -ForegroundColor Red
        $fail++
    }

    # 2. ADB
    Write-Host ''
    Write-Host '[2] ADB' -ForegroundColor Yellow
    $adb = Join-Path (Split-Path $MumuPath -Parent) 'shell\adb.exe'
    if (Test-Path $adb) {
        $adbVer = & $adb version 2>&1 | Out-String
        Write-Host "  Path: $adb" -ForegroundColor DarkGray
        Write-Host "  $($adbVer.Trim().Split("`n")[0])" -ForegroundColor Green
        $ok++
    } else {
        $sysAdb = Get-Command adb.exe -ErrorAction SilentlyContinue
        if ($sysAdb) {
            Write-Host "  System ADB: $($sysAdb.Source)" -ForegroundColor Green
            $ok++
        } else {
            Write-Host '  NOT FOUND' -ForegroundColor Red
            $fail++
        }
    }

    # 3. Java
    Write-Host ''
    Write-Host '[3] Java' -ForegroundColor Yellow
    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($java) {
        $javaVer = & java.exe -version 2>&1 | Out-String
        Write-Host "  $($javaVer.Trim().Split("`n")[0])" -ForegroundColor Green
        $ok++
    } else {
        Write-Host '  NOT FOUND (optional for ADB-based features)' -ForegroundColor DarkGray
    }

    # 4. tar.exe
    Write-Host ''
    Write-Host '[4] tar.exe' -ForegroundColor Yellow
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        Write-Host '  Available' -ForegroundColor Green
        $ok++
    } else {
        Write-Host '  NOT FOUND (backup archiving will use Compress-Archive)' -ForegroundColor DarkGray
    }

    # 5. robocopy
    Write-Host ''
    Write-Host '[5] robocopy' -ForegroundColor Yellow
    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        Write-Host '  Available' -ForegroundColor Green
        $ok++
    } else {
        Write-Host '  NOT FOUND (backup/restore will use Copy-Item)' -ForegroundColor Red
        $fail++
    }

    # 6. curl.exe
    Write-Host ''
    Write-Host '[6] curl.exe' -ForegroundColor Yellow
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        Write-Host '  Available' -ForegroundColor Green
        $ok++
    } else {
        Write-Host '  NOT FOUND (updates will not work)' -ForegroundColor Red
        $fail++
    }

    # 7. gh CLI
    Write-Host ''
    Write-Host '[7] GitHub CLI (gh)' -ForegroundColor Yellow
    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($gh) {
        Write-Host '  Available' -ForegroundColor Green
        $ok++
    } else {
        Write-Host '  NOT FOUND (optional)' -ForegroundColor DarkGray
    }

    # 8. GitHub token
    Write-Host ''
    Write-Host '[8] GitHub token' -ForegroundColor Yellow
    if ($GitHubToken) {
        Write-Host '  Loaded: YES' -ForegroundColor Green
        $ok++
    } else {
        Write-Host '  Loaded: NO (public repo OK, private needs token)' -ForegroundColor DarkGray
    }

    # Summary
    Write-Host ''
    Write-Host '=== Summary ===' -ForegroundColor Cyan
    Write-Host "  OK: $ok  |  Failed: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Yellow' } else { 'Green' })
    if ($fail -eq 0) {
        Write-Host '  STATUS: ALL DEPENDENCIES OK' -ForegroundColor Green
    } else {
        Write-Host '  STATUS: SOME DEPENDENCIES MISSING' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Update-Token {
    Write-Host ''
    Write-Host 'GitHub Token Manager' -ForegroundColor Cyan
    Write-Host ''

    $stored = $false
    $tokenPath = $null
    if (Test-Path -LiteralPath $DpapiTokenFile -PathType Leaf) {
        $tokenPath = $DpapiTokenFile
        $stored = $true
    } elseif (Test-Path -LiteralPath $TokenFile -PathType Leaf) {
        $tokenPath = $TokenFile
        $stored = $true
    }

    if ($stored) {
        # Show token info
        try {
            $plain = if ($tokenPath -eq $DpapiTokenFile) {
                $enc = (Get-Content -LiteralPath $DpapiTokenFile -Raw).Trim()
                $sec = ConvertTo-SecureString $enc
                ConvertFrom-SecureToken $sec
            } else {
                Get-Content -LiteralPath $TokenFile -Raw
            }
            $masked = if ($plain.Length -gt 8) {
                $plain.Substring(0, 4) + '****' + $plain.Substring($plain.Length - 4)
            } else { '****' }

            $rawUser = & curl.exe -s --connect-timeout 30 --max-time 30 -H "Authorization: token $plain" 'https://api.github.com/user' 2>$null
            $user = (@($rawUser) | Out-String | ConvertFrom-Json)

            if ($user.login) {
                Write-Host "  Token:   $masked" -ForegroundColor Green
                Write-Host "  User:    $($user.login)" -ForegroundColor Green
                Write-Host "  Scope:   $($user.permissions -join ', ')" -ForegroundColor DarkGray
                Write-Host "  Type:    $(if ($user.plan) { 'OAuth' } else { 'Classic PAT' })" -ForegroundColor DarkGray
            } else {
                Write-Host "  Token:   $masked (INVALID)" -ForegroundColor Red
            }
        } catch {
            Write-Host '  Token:   exists but cannot read' -ForegroundColor Yellow
        }
        Write-Host "  Storage: $(if ($tokenPath -eq $DpapiTokenFile) { 'DPAPI encrypted' } else { 'Plaintext (legacy)' })" -ForegroundColor $(if ($tokenPath -eq $DpapiTokenFile) { 'Green' } else { 'Yellow' })
        Write-Host ''
        Write-Host '  [1] Update token' -ForegroundColor Yellow
        Write-Host '  [2] Test token' -ForegroundColor Yellow
        Write-Host '  [3] Remove token (public repo)' -ForegroundColor Yellow
        Write-Host '  [0] Cancel' -ForegroundColor Yellow
        $choice = Read-Host 'Select option'

        if ($choice -eq '3') {
            Remove-Item -LiteralPath $DpapiTokenFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
            Write-Host 'Token removed! Auto-update works without token for public repos.' -ForegroundColor Green
            return
        } elseif ($choice -eq '2') {
            if ($user.login) {
                Write-Host "Token is valid for user: $($user.login)" -ForegroundColor Green
            } else {
                Write-Host 'Token is invalid or expired!' -ForegroundColor Red
            }
            return
        } elseif ($choice -ne '1') {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host 'No token configured.' -ForegroundColor Yellow
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
    Write-Host 'Enter new token (input hidden):' -ForegroundColor Cyan
    $sec = Read-Host -AsSecureString
    if (ConvertFrom-SecureToken $sec) {
        $plain = ConvertFrom-SecureToken $sec
        Write-Host 'Testing...' -ForegroundColor Yellow
        $rawUser = & curl.exe -s --connect-timeout 30 --max-time 30 -H "Authorization: token $plain" 'https://api.github.com/user' 2>$null
        $user = (@($rawUser) | Out-String | ConvertFrom-Json)
        if (-not $user.login) {
            Write-Host 'Token invalid! Nothing was saved.' -ForegroundColor Red
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
        Write-Host "Token valid! User: $($user.login)" -ForegroundColor Green
        Write-Host 'Saved ENCRYPTED via DPAPI (.github-token.dpapi)' -ForegroundColor Green
    } else {
        Write-Host 'Cancelled (empty input).' -ForegroundColor Yellow
    }
}

function Download-Repository {
    Write-Host ''
    Write-Host '=== Download Repository ===' -ForegroundColor Cyan
    Write-Host "  Repo: $GitHubRepo" -ForegroundColor DarkGray
    Write-Host ''

    # Helper: get target path with shortcuts
    function Get-TargetPath {
        param([string]$Prompt = 'Target directory')
        Write-Host ''
        Write-Host 'Quick paths:' -ForegroundColor DarkGray
        Write-Host "  [D] Desktop\MuMuManager-CLI-Menu" -ForegroundColor White
        Write-Host "  [W] Downloads\MuMuManager-CLI-Menu" -ForegroundColor White
        Write-Host "  [C] Current folder ($PWD.Path)" -ForegroundColor White
        Write-Host "  [B] Browse for folder..." -ForegroundColor White
        Write-Host ''
        $userInput = (Read-Host "$Prompt (D/W/C/B or path)").Trim()
        $userInput = $userInput.Trim('"').Trim()
        switch ($userInput.ToUpper()) {
            'D' { return Join-Path ([Environment]::GetFolderPath('Desktop')) 'MuMuManager-CLI-Menu' }
            'W' { return Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\MuMuManager-CLI-Menu' }
            'C' { return $PWD.Path }
            'B' {
                try {
                    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                    $dialog.Description = 'Select folder for MuMuManager-CLI-Menu'
                    $dialog.ShowNewFolderButton = $true
                    $dialog.SelectedPath = $PWD.Path
                    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        return Join-Path $dialog.SelectedPath 'MuMuManager-CLI-Menu'
                    }
                    return $null
                } catch {
                    Write-Host '  Folder browser unavailable, enter path manually' -ForegroundColor Yellow
                    $manual = (Read-Host 'Enter full path').Trim()
                    return $manual.Trim('"').Trim()
                }
            }
            default {
                if ($userInput) { return $userInput }
                else { return Join-Path $PWD.Path 'MuMuManager-CLI-Menu' }
            }
        }
    }

    # 1. Choose download method
    Write-Host 'Download method:' -ForegroundColor Yellow
    Write-Host '  [1] Git clone (full repo with history)' -ForegroundColor White
    Write-Host '  [2] Download release ZIP (specific version)' -ForegroundColor White
    Write-Host '  [3] Download latest release ZIP' -ForegroundColor White
    Write-Host '  [4] Update from GitHub (pull latest changes)' -ForegroundColor White
    Write-Host '  [5] Download single file from repo' -ForegroundColor White
    Write-Host ''
    $method = Read-Host 'Select method (1/2/3/4/5)'

    if ($method -eq '1') {
        # Git clone
        $targetDir = Get-TargetPath 'Clone to'
        if (-not $targetDir) { return }

        # Fetch available branches
        Write-Host ''
        Write-Host 'Fetching branches...' -ForegroundColor DarkGray
        $branchCmd = "curl.exe -s --connect-timeout 15 --max-time 15 -H `"Accept: application/vnd.github.v3+json`""
        if ($GitHubToken) { $branchCmd += " -H `"Authorization: token $GitHubToken`"" }
        $branchCmd += " `"https://api.github.com/repos/$GitHubRepo/branches`""
        $branchJson = & cmd /c $branchCmd 2>$null | Out-String
        try { $branches = $branchJson | ConvertFrom-Json } catch { $branches = @() }

        if ($branches -and $branches.Count -gt 0) {
            Write-Host '  Available branches:' -ForegroundColor DarkGray
            foreach ($b in $branches) {
                $marker = if ($b.name -eq 'main') { ' <-- default' } else { '' }
                Write-Host "    $($b.name)$marker" -ForegroundColor White
            }
        }
        $branch = (Read-Host "Branch (Enter=main)").Trim()
        if (-not $branch) { $branch = 'main' }

        $repoName = ($GitHubRepo -split '/')[-1]
        # If target dir already ends with repo name, don't double-nest
        if ($targetDir.TrimEnd('\','/') -ieq (Join-Path (Split-Path $targetDir -Parent) $repoName).TrimEnd('\','/')) {
            $clonePath = $targetDir
        } else {
            $clonePath = Join-Path $targetDir $repoName
        }

        if (Test-Path -LiteralPath $clonePath) {
            Write-Host "  Directory already exists: $clonePath" -ForegroundColor Yellow
            $over = Read-Host 'Overwrite? (y/N)'
            if ($over -ne 'y' -and $over -ne 'Y') { return }
            Remove-Item -LiteralPath $clonePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host ''
        Write-Host "Cloning $GitHubRepo ($branch)..." -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $cloneUrl = "https://github.com/$GitHubRepo.git"
        if ($GitHubToken) {
            $cloneUrl = "https://$($GitHubToken)@github.com/$GitHubRepo.git"
        }
        $cloneOutput = & git clone -b $branch $cloneUrl $clonePath 2>&1 | Out-String
        $progressMatch = [regex]::Matches($cloneOutput, 'Receiving objects.*?\d+%')
        if ($progressMatch.Count -gt 0) {
            Write-Host "  $($progressMatch[$progressMatch.Count - 1].Value)" -ForegroundColor DarkGray
        }
        $sw.Stop()
        Write-Host ''

        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $clonePath)) {
            $size = (Get-ChildItem -LiteralPath $clonePath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            Write-Host ("Clone complete! {0:N2} MB in {1:mm\:ss}" -f ($size / 1MB), $sw.Elapsed) -ForegroundColor Green
            Write-Host "  Location: $clonePath" -ForegroundColor DarkGray
        } else {
            Write-Host 'Clone failed!' -ForegroundColor Red
        }

    } elseif ($method -eq '2') {
        # Specific release
        Write-Host ''
        Write-Host 'Fetching releases...' -ForegroundColor DarkGray
        $relListCmd = "curl.exe -s --connect-timeout 30 --max-time 30 -H `"Accept: application/vnd.github.v3+json`""
        if ($GitHubToken) { $relListCmd += " -H `"Authorization: token $GitHubToken`"" }
        $relListCmd += " `"https://api.github.com/repos/$GitHubRepo/releases?per_page=20`""
        $relListJson = & cmd /c $relListCmd 2>$null | Out-String
        try { $releases = $relListJson | ConvertFrom-Json } catch { $releases = @() }

        if (-not $releases -or $releases.Count -eq 0) {
            Write-Host 'No releases found.' -ForegroundColor Yellow
            return
        }

        Write-Host ''
        Write-Host 'Available releases:' -ForegroundColor Cyan
        Write-Host ''
        for ($i = 0; $i -lt $releases.Count; $i++) {
            $r = $releases[$i]
            $marker = if ($i -eq 0) { ' <-- latest' } else { '' }
            $date = if ($r.published_at) { ($r.published_at -replace 'T.*','') } else { '' }
            $assetInfo = if ($r.assets -and $r.assets.Count -gt 0) {
                $zipCount = ($r.assets | Where-Object { $_.name -match '\.zip$' }).Count
                if ($zipCount -gt 0) { " [$zipCount ZIP]" } else { " [$($r.assets.Count) assets]" }
            } else { ' [no assets]' }
            $bodyPreview = if ($r.body) { ($r.body -split "`n" | Select-Object -First 1).Trim() } else { '' }
            if ($bodyPreview.Length -gt 60) { $bodyPreview = $bodyPreview.Substring(0, 57) + '...' }
            Write-Host "  [$($i + 1)] $($r.tag_name)  $date$assetInfo$marker" -ForegroundColor White
            if ($bodyPreview) { Write-Host "      $bodyPreview" -ForegroundColor DarkGray }
        }

        Write-Host ''
        $sel = Read-Host 'Select release (number)'
        if (-not ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $releases.Count)) {
            Write-Host 'Invalid selection.' -ForegroundColor Red
            return
        }
        $release = $releases[[int]$sel - 1]
        $tagName = $release.tag_name

        # Show release details
        Write-Host ''
        Write-Host "  Release: $($release.name)" -ForegroundColor Cyan
        Write-Host "  Tag:     $tagName" -ForegroundColor DarkGray
        if ($release.body) {
            $bodyLines = $release.body -split "`n" | Select-Object -First 5
            foreach ($line in $bodyLines) {
                if ($line.Trim()) { Write-Host "  $($line.Trim())" -ForegroundColor DarkGray }
            }
        }

        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1

        if (-not $zipAsset) {
            Write-Host ''
            Write-Host '  No ZIP asset found - downloading files individually...' -ForegroundColor Yellow

            $targetDir = Get-TargetPath 'Download to'
            if (-not $targetDir) { return }

            $dlFiles = @('mumu-menu.ps1', 'README.md', 'SKILL.md', '.version')
            $ok = 0; $fail = 0
            foreach ($f in $dlFiles) {
                $fUrl = "https://api.github.com/repos/$GitHubRepo/contents/$f?ref=$tagName"
                $fDest = Join-Path $targetDir $f
                Write-Host "  $f" -ForegroundColor Yellow -NoNewline
                $dlCmd = "curl.exe -sS --fail --retry 2 --connect-timeout 30 --max-time 60 -L -H `"Accept: application/vnd.github.v3.raw`" -o `"$fDest`" $fUrl"
                if ($GitHubToken) { $dlCmd += " -H `"Authorization: token $GitHubToken`"" }
                cmd /c $dlCmd 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $fDest) -and (Get-Item -LiteralPath $fDest).Length -gt 0) {
                    # Validate: detect JSON metadata instead of raw content
                    $fContent = Get-Content -LiteralPath $fDest -Raw -ErrorAction SilentlyContinue
                    if ($fContent -and $fContent.TrimStart().StartsWith('{') -and $fContent -match '"name"|"_links"|"encoding"') {
                        Remove-Item -LiteralPath $fDest -Force
                        Write-Host "  FAILED (JSON metadata returned)" -ForegroundColor Red
                        $fail++
                    } else {
                        $sz = '{0:N0}' -f ((Get-Item -LiteralPath $fDest).Length / 1KB)
                        Write-Host "  OK  ${sz} KB" -ForegroundColor Green
                        $ok++
                    }
                } else {
                    if (Test-Path -LiteralPath $fDest) { Remove-Item -LiteralPath $fDest -Force -ErrorAction SilentlyContinue }
                    Write-Host "  FAILED" -ForegroundColor Red
                    $fail++
                }
            }
            Write-Host ''
            Write-Host "Downloaded: $ok ok, $fail failed" -ForegroundColor $(if ($fail -gt 0) { 'Yellow' } else { 'Green' })
            return
        }

        $zipUrl = $zipAsset.browser_download_url
        $zipSize = '{0:N1} MB' -f ($zipAsset.size / 1MB)
        Write-Host "  Asset: $($zipAsset.name) ($zipSize)" -ForegroundColor White

        # Download location
        $targetDir = Get-TargetPath 'Download to'
        if (-not $targetDir) { return }

        $zipPath = Join-Path $targetDir $zipAsset.name

        Write-Host ''
        Write-Host "Downloading $($zipAsset.name)..." -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $curlCmd = "curl.exe -# --fail --connect-timeout 30 --max-time 300 --retry 3 --retry-delay 3 -L -o `"$zipPath`" $zipUrl"
        if ($GitHubToken) { $curlCmd += " -H Authorization:token $GitHubToken" }
        & cmd /c $curlCmd 2>$null
        $sw.Stop()

        if (-not (Test-Path -LiteralPath $zipPath)) {
            Write-Host 'Download failed!' -ForegroundColor Red
            return
        }


        $actualSize = (Get-Item -LiteralPath $zipPath).Length
        Write-Host ''
        Write-Host ("Downloaded: {0:N1} MB in {1:mm\:ss}" -f ($actualSize / 1MB), $sw.Elapsed) -ForegroundColor Green

        # Extract
        $extract = Read-Host 'Extract now? (Y/n)'
        if ($extract -ne 'n' -and $extract -ne 'N') {
            $extractDir = Join-Path $targetDir ($zipAsset.name -replace '\.zip$', '')
            if (Test-Path -LiteralPath $extractDir) {
                Write-Host "  Extract dir exists: $extractDir" -ForegroundColor Yellow
                $ow = Read-Host 'Overwrite? (y/N)'
                if ($ow -ne 'y' -and $ow -ne 'Y') { return }
                Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            Write-Host 'Extracting...' -ForegroundColor Cyan
            $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
            if (Test-Path $tarExe) {
                & $tarExe -xf $zipPath -C $targetDir 2>&1 | Out-Null
            } else {
                Expand-Archive -Path $zipPath -DestinationPath $targetDir -Force
            }
            Write-Host "  Extracted to: $extractDir" -ForegroundColor Green
        }

    } elseif ($method -eq '3') {
        # Latest release
        Write-Host ''
        Write-Host 'Fetching latest release...' -ForegroundColor DarkGray
        $relCmd = "curl.exe -s --connect-timeout 30 --max-time 30 -H `"Accept: application/vnd.github.v3+json`""
        if ($GitHubToken) { $relCmd += " -H `"Authorization: token $GitHubToken`"" }
        $relCmd += " `"https://api.github.com/repos/$GitHubRepo/releases/latest`""
        $relJson = & cmd /c $relCmd 2>$null | Out-String
        try { $release = $relJson | ConvertFrom-Json } catch { $release = $null }

        if (-not $release -or -not $release.tag_name) {
            Write-Host 'No releases found.' -ForegroundColor Yellow
            return
        }

        Write-Host ''
        Write-Host "  Latest: $($release.name) ($($release.tag_name))" -ForegroundColor Green
        Write-Host "  Date:   $($release.published_at)" -ForegroundColor DarkGray

        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
        if (-not $zipAsset) {
            Write-Host ''
            Write-Host '  No ZIP asset attached to this release.' -ForegroundColor Yellow
            Write-Host '  Falling back to individual file download...' -ForegroundColor DarkGray

            $targetDir = Get-TargetPath 'Download to'
            if (-not $targetDir) { return }

            $tag = $release.tag_name
            $dlFiles = @('mumu-menu.ps1', 'README.md', 'SKILL.md', '.version')
            $ok = 0; $fail = 0
            foreach ($f in $dlFiles) {
                $fUrl = "https://api.github.com/repos/$GitHubRepo/contents/$f?ref=$tag"
                $fDest = Join-Path $targetDir $f
                Write-Host "  $f" -ForegroundColor Yellow -NoNewline
                $dlCmd = "curl.exe -sS --fail --retry 2 --connect-timeout 30 --max-time 60 -L -H `"Accept: application/vnd.github.v3.raw`" -o `"$fDest`" $fUrl"
                if ($GitHubToken) { $dlCmd += " -H `"Authorization: token $GitHubToken`"" }
                cmd /c $dlCmd 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $fDest) -and (Get-Item -LiteralPath $fDest).Length -gt 0) {
                    # Validate: detect JSON metadata instead of raw content
                    $fContent = Get-Content -LiteralPath $fDest -Raw -ErrorAction SilentlyContinue
                    if ($fContent -and $fContent.TrimStart().StartsWith('{') -and $fContent -match '"name"|"_links"|"encoding"') {
                        Remove-Item -LiteralPath $fDest -Force
                        Write-Host "  FAILED (JSON metadata returned)" -ForegroundColor Red
                        $fail++
                    } else {
                        $sz = '{0:N0}' -f ((Get-Item -LiteralPath $fDest).Length / 1KB)
                        Write-Host "  OK  ${sz} KB" -ForegroundColor Green
                        $ok++
                    }
                } else {
                    if (Test-Path -LiteralPath $fDest) { Remove-Item -LiteralPath $fDest -Force -ErrorAction SilentlyContinue }
                    Write-Host "  FAILED" -ForegroundColor Red
                    $fail++
                }
            }
            Write-Host ''
            Write-Host "Downloaded: $ok ok, $fail failed" -ForegroundColor $(if ($fail -gt 0) { 'Yellow' } else { 'Green' })
            return
        }

        $zipUrl = $zipAsset.browser_download_url
        $zipSize = '{0:N1} MB' -f ($zipAsset.size / 1MB)
        Write-Host "  Asset:  $($zipAsset.name) ($zipSize)" -ForegroundColor White

        $targetDir = Get-TargetPath 'Download to'
        if (-not $targetDir) { return }

        $zipPath = Join-Path $targetDir $zipAsset.name

        Write-Host ''
        Write-Host "Downloading $($zipAsset.name)..." -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $curlCmd = "curl.exe -# --fail --connect-timeout 30 --max-time 300 --retry 3 --retry-delay 3 -L -o `"$zipPath`" $zipUrl"
        if ($GitHubToken) { $curlCmd += " -H Authorization:token $GitHubToken" }
        & cmd /c $curlCmd 2>$null
        $sw.Stop()

        if (-not (Test-Path -LiteralPath $zipPath)) {
            Write-Host 'Download failed!' -ForegroundColor Red
            return
        }


        $actualSize = (Get-Item -LiteralPath $zipPath).Length
        Write-Host ''
        Write-Host ("Downloaded: {0:N1} MB in {1:mm\:ss}" -f ($actualSize / 1MB), $sw.Elapsed) -ForegroundColor Green

        $extract = Read-Host 'Extract now? (Y/n)'
        if ($extract -ne 'n' -and $extract -ne 'N') {
            $extractDir = Join-Path $targetDir ($zipAsset.name -replace '\.zip$', '')
            if (Test-Path -LiteralPath $extractDir) {
                Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host 'Extracting...' -ForegroundColor Cyan
            $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
            if (Test-Path $tarExe) {
                & $tarExe -xf $zipPath -C $targetDir 2>&1 | Out-Null
            } else {
                Expand-Archive -Path $zipPath -DestinationPath $targetDir -Force
            }
            Write-Host "  Extracted to: $extractDir" -ForegroundColor Green
        }
    } elseif ($method -eq '4') {
        # Update from GitHub
        Write-Host ''
        Write-Host '=== Update from GitHub ===' -ForegroundColor Cyan
        Write-Host ''

        # Check if we're in a git repo
        $inGitRepo = $false
        try {
            & git rev-parse --git-dir 2>$null | Out-Null
            $inGitRepo = $LASTEXITCODE -eq 0
        } catch { Write-Debug "Git detection failed: $($_.Exception.Message)" }

        if ($inGitRepo) {
            # Git repo - use git pull
            Write-Host 'Detected git repository. Using git pull...' -ForegroundColor Cyan
            Write-Host ''

            # Check current branch
            $currentBranch = & git branch --show-current 2>$null | Out-String
            $currentBranch = $currentBranch.Trim()
            Write-Host "  Current branch: $currentBranch" -ForegroundColor DarkGray

            # Check remote status
            Write-Host '  Fetching from remote...' -ForegroundColor DarkGray
            & git fetch origin 2>&1 | Out-Null

            # Check if there are changes
            $localHash = & git rev-parse HEAD 2>$null | Out-String
            $remoteHash = & git rev-parse "origin/$currentBranch" 2>$null | Out-String
            $localHash = $localHash.Trim()
            $remoteHash = $remoteHash.Trim()

            if ($localHash -eq $remoteHash) {
                Write-Host '  Already up to date!' -ForegroundColor Green
                return
            }

            # Show what will be updated
            Write-Host ''
            Write-Host '  Changes available:' -ForegroundColor Yellow
            $commits = & git log --oneline "$localHash..origin/$currentBranch" 2>&1 | Out-String
            if ($commits) {
                $commitLines = $commits.Trim() -split "`n" | Select-Object -First 10
                foreach ($line in $commitLines) {
                    Write-Host "    $line" -ForegroundColor White
                }
                $totalCommits = ($commits.Trim() -split "`n").Count
                if ($totalCommits -gt 10) {
                    Write-Host "    ... and $($totalCommits - 10) more commits" -ForegroundColor DarkGray
                }
            }

            Write-Host ''
            $confirm = Read-Host '  Pull changes? (Y/n)'
            if ($confirm -eq 'n' -or $confirm -eq 'N') {
                Write-Host '  Cancelled.' -ForegroundColor Yellow
                return
            }

            Write-Host ''
            Write-Host '  Pulling changes...' -ForegroundColor Cyan
            $result = & git pull origin $currentBranch 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                Write-Host ''
                Write-Host '  Update complete!' -ForegroundColor Green
                Write-Host "  $result" -ForegroundColor DarkGray
            } else {
                Write-Host ''
                Write-Host '  Pull failed!' -ForegroundColor Red
                Write-Host "  $result" -ForegroundColor Red
            }

        } else {
            # Not a git repo - download latest release
            Write-Host 'Not a git repository. Checking for updates...' -ForegroundColor Cyan
            Write-Host ''

            # Get latest release
            $relCmd = "curl.exe -s --connect-timeout 30 --max-time 30 -H `"Accept: application/vnd.github.v3+json`""
        if ($GitHubToken) { $relCmd += " -H `"Authorization: token $GitHubToken`"" }
        $relCmd += " `"https://api.github.com/repos/$GitHubRepo/releases/latest`""
        $relJson = & cmd /c $relCmd 2>$null | Out-String
            try { $release = $relJson | ConvertFrom-Json } catch { $release = $null }

            if (-not $release -or -not $release.tag_name) {
                Write-Host 'No releases found.' -ForegroundColor Yellow
                return
            }

            # Check current version
            $localVer = ''
            if (Test-Path -LiteralPath $VersionFile) {
                try { $localVer = (Get-Content -LiteralPath $VersionFile -Raw).Trim() } catch { Write-Debug "Version file read failed: $($_.Exception.Message)" }
            }

            $remoteTag = $release.tag_name
            if ($localVer -eq $remoteTag) {
                Write-Host "  Up to date ($remoteTag)" -ForegroundColor Green
                return
            }

            # Show release info
            Write-Host "  Latest: $($release.name) ($remoteTag)" -ForegroundColor Green
            if ($release.published_at) {
                $published = try { [datetime]::Parse($release.published_at).ToString('yyyy-MM-dd HH:mm') } catch { $release.published_at }
                Write-Host "  Date:   $published" -ForegroundColor DarkGray
            }
            if ($localVer) {
                Write-Host "  Current: $localVer" -ForegroundColor DarkGray
            }

            # Show changelog
            if ($release.body) {
                Write-Host ''
                Write-Host '  --- Release notes ---' -ForegroundColor Cyan
                $lines = $release.body -split "`n"
                $shown = 0
                foreach ($line in $lines) {
                    if ($shown -ge 15) {
                        Write-Host '  ... (more in GitHub releases)' -ForegroundColor DarkGray
                        break
                    }
                    if ($line.Trim()) {
                        if ($line -match '^#{1,3}\s') {
                            Write-Host "  $line" -ForegroundColor Yellow
                        } elseif ($line -match '^-\s|^-\s\[') {
                            Write-Host "  $line" -ForegroundColor Green
                        } else {
                            Write-Host "  $line" -ForegroundColor White
                        }
                        $shown++
                    }
                }
                Write-Host '  ---------------------' -ForegroundColor Cyan
            }

            $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
            if ($zipAsset) {
                $zipSize = '{0:N1} MB' -f ($zipAsset.size / 1MB)
                Write-Host "  Asset:  $($zipAsset.name) ($zipSize)" -ForegroundColor White
            }

            $confirm = Read-Host '  Download and update? (Y/n)'
            if ($confirm -eq 'n' -or $confirm -eq 'N') {
                Write-Host '  Cancelled.' -ForegroundColor Yellow
                return
            }

            if (-not $zipAsset) {
                # Fallback: download files individually from the release tag
                Write-Host ''
                Write-Host '  No ZIP asset found. Downloading files individually...' -ForegroundColor Yellow
                Write-Host ''
                $dlFiles = @('mumu-menu.ps1', 'README.md', 'SKILL.md', '.version')
                $ok = 0; $fail = 0
                foreach ($f in $dlFiles) {
                    $fUrl = "https://api.github.com/repos/$GitHubRepo/contents/$f?ref=$remoteTag"
                    $fDest = Join-Path $ScriptDir $f
                    Write-Host "  $f" -ForegroundColor Yellow -NoNewline
                    $dlCmd = "curl.exe -sS --fail --retry 2 --connect-timeout 30 --max-time 60 -L -H `"Accept: application/vnd.github.v3.raw`" -o `"$fDest`" $fUrl"
                    if ($GitHubToken) { $dlCmd += " -H `"Authorization: token $GitHubToken`"" }
                    cmd /c $dlCmd 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $fDest) -and (Get-Item -LiteralPath $fDest).Length -gt 0) {
                        $fContent = Get-Content -LiteralPath $fDest -Raw -ErrorAction SilentlyContinue
                        if ($fContent -and $fContent.TrimStart().StartsWith('{') -and $fContent -match '"name"|"_links"|"encoding"') {
                            Remove-Item -LiteralPath $fDest -Force
                            Write-Host '  FAILED (JSON metadata)' -ForegroundColor Red
                            $fail++
                        } else {
                            $sz = '{0:N0}' -f ((Get-Item -LiteralPath $fDest).Length / 1KB)
                            Write-Host "  OK  ${sz} KB" -ForegroundColor Green
                            $ok++
                        }
                    } else {
                        if (Test-Path -LiteralPath $fDest) { Remove-Item -LiteralPath $fDest -Force -ErrorAction SilentlyContinue }
                        Write-Host '  FAILED' -ForegroundColor Red
                        $fail++
                    }
                }
                Write-Host ''
                if ($fail -eq 0) {
                    Set-Content -Path $VersionFile -Value $remoteTag -NoNewline -ErrorAction SilentlyContinue
                    Write-Host "  Updated $ok file(s) to $remoteTag" -ForegroundColor Green
                } else {
                    Write-Host "  Updated $ok file(s), failed $fail" -ForegroundColor Yellow
                }
                Write-Host '  Restart the script to use the updated version.' -ForegroundColor Yellow
                return
            }

            # Backup current files
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupDir = Join-Path $ScriptDir "backup\$stamp"
            $filesToBackup = @('mumu-menu.ps1', 'SKILL.md', 'README.md', '.version')
            foreach ($f in $filesToBackup) {
                $p = Join-Path $ScriptDir $f
                if (Test-Path $p) {
                    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                    Copy-Item -LiteralPath $p -Destination (Join-Path $backupDir $f) -Force
                }
            }
            if (Test-Path $backupDir) {
                Write-Host "  Backup saved: backup\$stamp" -ForegroundColor DarkGray
            }

            # Download ZIP
            $tmp = Join-Path $env:TEMP "mumu_update_$stamp.zip"
            Write-Host ''
            Write-Host "  Downloading $($zipAsset.name)..." -ForegroundColor Cyan
            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            $curlCmd = "curl.exe -# --fail --connect-timeout 30 --max-time 300 --retry 3 --retry-delay 3 -L -o `"$tmp`" $zipUrl"
            if ($GitHubToken) { $curlCmd += " -H Authorization:token $GitHubToken" }
            & cmd /c $curlCmd 2>$null
            $sw.Stop()

            if (-not (Test-Path -LiteralPath $tmp)) {
                Write-Host '  Download failed!' -ForegroundColor Red
                return
            }

            $actualSize = (Get-Item -LiteralPath $tmp).Length
            Write-Host ''
            Write-Host ("  Downloaded: {0:N1} MB in {1:mm\:ss}" -f ($actualSize / 1MB), $sw.Elapsed) -ForegroundColor Green

            # Extract and update
            Write-Host ''
            Write-Host '  Extracting and updating files...' -ForegroundColor Cyan
            $tmpDir = Join-Path $env:TEMP "mumu_update_$stamp"
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

            $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
            if (Test-Path $tarExe) {
                & $tarExe -xf $tmp -C $tmpDir 2>$null
            } else {
                Expand-Archive -Path $tmp -DestinationPath $tmpDir -Force
            }

            # Find extracted folder
            $extractedDir = Get-ChildItem -LiteralPath $tmpDir -Directory | Select-Object -First 1
            if (-not $extractedDir) {
                $extractedDir = [pscustomobject]@{ FullName = $tmpDir }
            }

            # Copy files
            $updated = 0
            $failed = 0
            foreach ($f in $filesToBackup) {
                $src = Join-Path $extractedDir.FullName $f
                $dst = Join-Path $ScriptDir $f
                if (Test-Path -LiteralPath $src) {
                    try {
                        # Handle self-update: rename running script first
                        if ($f -eq 'mumu-menu.ps1') {
                            $oldFile = "$dst.old"
                            if (Test-Path -LiteralPath $oldFile) {
                                Remove-Item -LiteralPath $oldFile -Force -ErrorAction SilentlyContinue
                            }
                            Copy-Item -LiteralPath $dst -Destination $oldFile -Force -ErrorAction SilentlyContinue
                        }
                        Copy-Item -LiteralPath $src -Destination $dst -Force
                        $updated++
                    } catch {
                        Write-Host "    Failed: $f - $($_.Exception.Message)" -ForegroundColor Red
                        $failed++
                    }
                }
            }

            # Update .version file
            if ($updated -gt 0 -and $failed -eq 0) {
                try {
                    Set-Content -Path $VersionFile -Value $remoteTag -NoNewline -Encoding UTF8 -Force
                } catch {
                    Write-Host "  Warning: Could not update .version ($($_.Exception.Message))" -ForegroundColor Yellow
                }
            }

            # Cleanup
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

            Write-Host ''
            if ($updated -gt 0 -and $failed -eq 0) {
                Write-Host "  Updated $updated file(s) to $remoteTag!" -ForegroundColor Green
            } elseif ($updated -gt 0) {
                Write-Host "  Updated $updated file(s), failed $failed" -ForegroundColor Yellow
            }
            if ($failed -gt 0) {
                Write-Host "  Failed: $failed file(s)" -ForegroundColor Red
            }
            Write-Host "  Backup: backup\$stamp" -ForegroundColor DarkGray
            Write-Host ''
            Write-Host '  Restart the script to use the updated version.' -ForegroundColor Yellow
        }

    } elseif ($method -eq '5') {
        # Download single file
        Write-Host ''
        Write-Host 'Download single file from repository' -ForegroundColor Cyan
        Write-Host ''

        # Choose source
        Write-Host 'Source:' -ForegroundColor Yellow
        Write-Host '  [1] From latest release' -ForegroundColor White
        Write-Host '  [2] From specific tag/branch' -ForegroundColor White
        Write-Host ''
        $src = Read-Host 'Select (1/2)'
        $ref = ''
        if ($src -eq '2') {
            $ref = (Read-Host 'Tag or branch name (Enter=main)').Trim()
            if (-not $ref) { $ref = 'main' }
        } else {
            # Get latest tag
            $ltCmd = "curl.exe -s --connect-timeout 15 -H `"Accept: application/vnd.github.v3+json`""
            if ($GitHubToken) { $ltCmd += " -H `"Authorization: token $GitHubToken`"" }
            $ltCmd += " `"https://api.github.com/repos/$GitHubRepo/releases/latest`""
            $ltJson = & cmd /c $ltCmd 2>$null | Out-String
            try { $lt = $ltJson | ConvertFrom-Json } catch { $lt = $null }
            if ($lt.tag_name) { $ref = $lt.tag_name; Write-Host "  Using: $ref" -ForegroundColor DarkGray }
            else { $ref = 'main'; Write-Host '  Using: main (no releases found)' -ForegroundColor DarkGray }
        }

        # List files in repo root
        Write-Host ''
        Write-Host "Fetching file list ($ref)..." -ForegroundColor DarkGray
        $listCmd = "curl.exe -s --connect-timeout 15 -H `"Accept: application/vnd.github.v3+json`""
        if ($GitHubToken) { $listCmd += " -H `"Authorization: token $GitHubToken`"" }
        $listCmd += " `"https://api.github.com/repos/$GitHubRepo/contents/?ref=$ref`""
        $listJson = & cmd /c $listCmd 2>$null | Out-String
        try { $files = $listJson | ConvertFrom-Json } catch { $files = @() }

        if (-not $files -or $files.Count -eq 0) {
            Write-Host 'No files found.' -ForegroundColor Yellow
            return
        }

        # Show files
        Write-Host ''
        $idx = 0
        $fileList = @()
        foreach ($f in $files) {
            if ($f.type -eq 'file') {
                $idx++
                $sz = if ($f.size -gt 1MB) { "$([math]::Round($f.size/1MB, 1)) MB" }
                      elseif ($f.size -gt 1KB) { "$([math]::Round($f.size/1KB, 1)) KB" }
                      else { "$($f.size) B" }
                Write-Host "  [$idx] $($f.name) ($sz)" -ForegroundColor White
                $fileList += $f
            }
        }

        if ($fileList.Count -eq 0) {
            Write-Host 'No files in repository root.' -ForegroundColor Yellow
            return
        }

        # Also allow manual path entry
        Write-Host ''
        Write-Host "  [0] Enter file path manually" -ForegroundColor DarkGray
        Write-Host ''
        $fSel = Read-Host "Select file (1-$($fileList.Count) or 0 for manual path)"

        $downloadUrl = ''
        $fileName = ''
        if ($fSel -eq '0') {
            $filePath = (Read-Host 'File path (e.g. mumu-menu.ps1)').Trim()
            if (-not $filePath) { return }
            $fileName = Split-Path $filePath -Leaf
            $downloadUrl = "https://api.github.com/repos/$GitHubRepo/contents/$filePath`?ref=$ref"
        } elseif ($fSel -match '^\d+$' -and [int]$fSel -ge 1 -and [int]$fSel -le $fileList.Count) {
            $chosen = $fileList[[int]$fSel - 1]
            $fileName = $chosen.name
            $downloadUrl = $chosen.url
        } else {
            Write-Host 'Invalid selection.' -ForegroundColor Red
            return
        }

        # Download
        $targetDir = Get-TargetPath 'Save to'
        if (-not $targetDir) { return }

        Write-Host ''
        Write-Host "Downloading $fileName from $ref..." -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $dlCmd = 'curl.exe -sL --connect-timeout 30 --max-time 120 -o "' + (Join-Path $targetDir $fileName) + '"'
        if ($GitHubToken) { $dlCmd += ' -H "Authorization: token ' + $GitHubToken + '"' }
        $dlCmd += ' -H "Accept: application/vnd.github.v3.raw" "' + $downloadUrl + '"'
        & cmd /c $dlCmd 2>&1 | Out-Null
        $sw.Stop()

        $destFile = Join-Path $targetDir $fileName
        if (Test-Path -LiteralPath $destFile) {
            $size = (Get-Item -LiteralPath $destFile).Length
            # Validate: detect JSON metadata instead of raw content
            $content = Get-Content -LiteralPath $destFile -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.TrimStart().StartsWith('{')) {
                $isApiJson = $content -match '"name"|"sha"|"encoding"|"message"|"_links"'
                if ($isApiJson) {
                    Remove-Item -LiteralPath $destFile -Force
                    $apiMsg = try { ($content | ConvertFrom-Json).message } catch { 'JSON metadata returned instead of raw file' }
                    Write-Host "  API error: $apiMsg" -ForegroundColor Red
                    Write-Host '  (Server returned JSON; Accept header may be missing)' -ForegroundColor DarkGray
                    return
                }
            }
            $sz = '{0:N1} KB' -f ($size / 1KB)
            Write-Host ("  Saved: $fileName ($sz) in {0:mm\:ss}" -f $sw.Elapsed) -ForegroundColor Green
        } else {
            Write-Host '  Download failed!' -ForegroundColor Red
        }
    }
}

function Fix-ReleaseEncoding {
    if (-not $GitHubToken) {
        Write-Host ''
        Write-Host 'GitHub token is required.' -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '=== Fix Release Encoding ===' -ForegroundColor Cyan
    Write-Host ''

    # Fetch releases
    Write-Host 'Fetching releases...' -ForegroundColor DarkGray
    $relJson = & curl.exe -s --connect-timeout 30 --max-time 30 -H "Accept: application/vnd.github.v3+json" -H "Authorization: token $GitHubToken" "https://api.github.com/repos/$GitHubRepo/releases" 2>$null | Out-String
    try { $releases = $relJson | ConvertFrom-Json } catch { $releases = @() }

    if (-not $releases -or $releases.Count -eq 0) {
        Write-Host 'No releases found.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host 'Releases:' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $releases.Count; $i++) {
        $r = $releases[$i]
        $hasCyrillic = $false
        if ($r.body) {
            foreach ($ch in $r.body.ToCharArray()) {
                $cp = [int]$ch
                if ($cp -ge 0x0400 -and $cp -le 0x04FF) { $hasCyrillic = $true; break }
            }
        }
        $status = if ($hasCyrillic) { 'OK' } else { 'CHECK' }
        $color = if ($hasCyrillic) { 'Green' } else { 'Yellow' }
        $marker = if ($i -eq 0) { ' <-- latest' } else { '' }
        Write-Host "  [$($i + 1)] $($r.tag_name) [$status]$marker" -ForegroundColor $color
    }

    Write-Host ''
    $sel = Read-Host 'Select release to fix (number, or Enter to cancel)'
    if (-not ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $releases.Count)) {
        return
    }
    $chosen = $releases[[int]$sel - 1]

    Write-Host ''
    Write-Host "Release: $($chosen.tag_name)" -ForegroundColor Cyan
    Write-Host "Title:   $($chosen.name)" -ForegroundColor White

    # Check current body for encoding issues
    $body = if ($chosen.body) { $chosen.body } else { '' }
    $hasCyrillic = $false
    $hasMojibake = $false
    foreach ($ch in $body.ToCharArray()) {
        $cp = [int]$ch
        if ($cp -ge 0x0400 -and $cp -le 0x04FF) { $hasCyrillic = $true }
        if ($cp -ge 0xC0 -and $cp -le 0xFF -and $cp -ne 0x2013 -and $cp -ne 0x2014) { $hasMojibake = $true }
    }

    if ($hasCyrillic -and -not $hasMojibake) {
        Write-Host '  Encoding: OK (valid Cyrillic detected)' -ForegroundColor Green
        $fix = Read-Host '  Re-encode anyway? (y/N)'
        if ($fix -ne 'y' -and $fix -ne 'Y') { return }
    } elseif ($hasMojibake) {
        Write-Host '  Encoding: MOJIBAKE DETECTED' -ForegroundColor Red
    } else {
        Write-Host '  Encoding: No Cyrillic in body' -ForegroundColor Yellow
    }

    # New notes
    Write-Host ''
    Write-Host 'Enter new release notes (empty line to finish):' -ForegroundColor Yellow
    $newNotes = ''
    while ($true) {
        $line = Read-Host '> '
        if (-not $line) { break }
        $newNotes += "$line`n"
    }

    if (-not $newNotes) {
        Write-Host 'No notes entered. Cancelled.' -ForegroundColor Yellow
        return
    }

    # Write notes as UTF-8 bytes (avoids PS5.1 corruption)
    $bodyFile = Join-Path $env:TEMP ('fix_body_' + [Guid]::NewGuid().ToString('N') + '.txt')
    [System.IO.File]::WriteAllText($bodyFile, $newNotes, [System.Text.UTF8Encoding]::new($false))

    # Build JSON
    $jsonObj = [ordered]@{
        body = $newNotes
    }
    $jsonStr = $jsonObj | ConvertTo-Json -Depth 5
    $jsonFile = Join-Path $env:TEMP ('fix_release_' + [Guid]::NewGuid().ToString('N') + '.json')
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($jsonFile, $jsonStr, $utf8NoBom)

    Write-Host ''
    Write-Host 'Updating release notes...' -ForegroundColor Cyan
    $result = & curl.exe -s --connect-timeout 30 --max-time 60 -X PATCH -H "Authorization: token $GitHubToken" -H "Accept: application/vnd.github.v3+json" -H "Content-Type: application/json; charset=utf-8" -d "@$jsonFile" "https://api.github.com/repos/$GitHubRepo/releases/$($chosen.id)" 2>$null | Out-String

    Remove-Item $jsonFile -Force -ErrorAction SilentlyContinue
    Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue

    try {
        $updated = $result | ConvertFrom-Json
        if ($updated.html_url) {
            Write-Host ''
            Write-Host 'Release updated successfully!' -ForegroundColor Green
            Write-Host "  URL: $($updated.html_url)" -ForegroundColor Cyan

            # Verify encoding
            $verifyBody = if ($updated.body) { $updated.body } else { '' }
            $verifyCyrillic = $false
            foreach ($ch in $verifyBody.ToCharArray()) {
                $cp = [int]$ch
                if ($cp -ge 0x0400 -and $cp -le 0x04FF) { $verifyCyrillic = $true; break }
            }
            if ($verifyCyrillic) {
                Write-Host '  Encoding verified: Cyrillic OK' -ForegroundColor Green
            } else {
                Write-Host '  Warning: No Cyrillic detected in updated body' -ForegroundColor Yellow
            }
        } else {
            Write-Host "Error: $($updated.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Failed: $result" -ForegroundColor Red
    }
}

function Create-GitHubRelease {
    if (-not $GitHubToken) {
        Write-Host ''
        Write-Host 'GitHub token is required to create releases.' -ForegroundColor Red
        Write-Host 'Add a token: menu option [K] Update GitHub token.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host '=== Create GitHub Release ===' -ForegroundColor Cyan
    Write-Host ''

    # 1. Fetch existing tags
    Write-Host 'Fetching tags...' -ForegroundColor DarkGray
    $tagsJson = & curl.exe -s --connect-timeout 30 --max-time 30 -H "Authorization: token $GitHubToken" "https://api.github.com/repos/$GitHubRepo/tags" 2>$null | Out-String
    try { $tags = $tagsJson | ConvertFrom-Json } catch { $tags = @() }

    if ($tags -and $tags.Count -gt 0) {
        Write-Host "  Found $($tags.Count) tag(s)" -ForegroundColor DarkGray
    } else {
        Write-Host '  No tags found' -ForegroundColor Yellow
    }

    # 2. Fetch latest release to get default title
    $latestTag = ''
    $latestName = ''
    if ($tags -and $tags.Count -gt 0) {
        $latestTag = $tags[0].name
        $latestName = $tags[0].name
        if ($latestName -match '^v?([\d.]+)$') {
            $latestName = "MuMuManager CLI Menu v$($Matches[1])"
        }
    }

    # 3. Get next version suggestion
    $suggestedVersion = ''
    if ($latestTag -match 'v?(\d+)\.(\d+)\.(\d+)') {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        $patch = [int]$Matches[3]
        $patch++
        $suggestedVersion = "v$major.$minor.$patch"
        $suggestedTitle = "MuMuManager CLI Menu $suggestedVersion"
    } else {
        $suggestedVersion = 'v1.0.0'
        $suggestedTitle = 'MuMuManager CLI Menu v1.0.0'
    }

    # 4. Tag name
    Write-Host ''
    Write-Host "Suggested tag: $suggestedVersion" -ForegroundColor Cyan
    $tagName = (Read-Host "Enter tag name (Enter=$suggestedVersion)").Trim()
    if (-not $tagName) { $tagName = $suggestedVersion }

    # 5. Release title
    Write-Host ''
    Write-Host "Suggested title: $suggestedTitle" -ForegroundColor Cyan
    $title = (Read-Host "Enter release title (Enter='$suggestedTitle')").Trim()
    if (-not $title) { $title = $suggestedTitle }

    # 6. Select base tag for generated notes
    $baseTag = ''
    if ($tags -and $tags.Count -gt 0) {
        Write-Host ''
        Write-Host 'Select previous tag for release notes:' -ForegroundColor Cyan
        Write-Host ''
        Write-Host "  [0] (none - write notes manually)" -ForegroundColor DarkGray
        for ($i = 0; $i -lt [Math]::Min($tags.Count, 10); $i++) {
            $t = $tags[$i]
            $marker = if ($i -eq 0) { ' <-- latest' } else { '' }
            Write-Host "  [$($i + 1)] $($t.name)$marker" -ForegroundColor White
        }
        Write-Host ''
        $tagSel = Read-Host 'Select base tag (number)'
        if ($tagSel -match '^\d+$' -and [int]$tagSel -ge 1 -and [int]$tagSel -le [Math]::Min($tags.Count, 10)) {
            $baseTag = $tags[[int]$tagSel - 1].name
        }
    }

    # 7. Generate or write release notes
    $notes = ''
    if ($baseTag) {
        # Generate notes from git log between base tag and HEAD
        Write-Host ''
        Write-Host "Generating notes from $baseTag to HEAD..." -ForegroundColor DarkGray

        # Try git log first
        $gitLog = & git log --oneline --no-decorate "$baseTag..HEAD" 2>&1 | Out-String
        if ($gitLog -and $LASTEXITCODE -eq 0 -and $gitLog.Trim()) {
            $lines = $gitLog.Trim() -split "`n" | Where-Object { $_.Trim() }
            $notes = "## What's changed since $baseTag`n`n"
            foreach ($line in $lines) {
                $notes += "- $line`n"
            }
        } else {
            # Fallback: use GitHub compare API
            Write-Host '  git log unavailable, using GitHub API...' -ForegroundColor DarkGray
            $compareJson = & curl.exe -s --connect-timeout 30 --max-time 30 -H "Authorization: token $GitHubToken" "https://api.github.com/repos/$GitHubRepo/compare/$baseTag...$tagName" 2>$null | Out-String
            try {
                $compare = $compareJson | ConvertFrom-Json
                if ($compare.commits) {
                    $notes = "## What's changed since $baseTag`n`n"
                    foreach ($c in $compare.commits) {
                        $msg = ($c.commit.message -split "`n")[0]
                        $sha = $c.sha.Substring(0, 7)
                        $author = $c.commit.author.name
                        $notes += "- $sha $msg ($author)`n"
                    }
                }
            } catch { Write-Debug "Release notes generation failed: $($_.Exception.Message)" }
        }

        if ($notes) {
            Write-Host ''
            Write-Host '--- Generated release notes ---' -ForegroundColor Cyan
            Write-Host $notes -ForegroundColor White
            Write-Host '---' -ForegroundColor Cyan

            $editAns = Read-Host 'Edit notes before publishing? (y/N)'
            if ($editAns -eq 'y' -or $editAns -eq 'Y') {
                Write-Host ''
                Write-Host 'Enter release notes (empty line to finish):' -ForegroundColor Yellow
                $notes = ''
                while ($true) {
                    $line = Read-Host '> '
                    if (-not $line) { break }
                    $notes += "$line`n"
                }
            }
        }
    }

    if (-not $notes) {
        Write-Host ''
        Write-Host 'Enter release notes (empty line to finish):' -ForegroundColor Yellow
        while ($true) {
            $line = Read-Host '> '
            if (-not $line) { break }
            $notes += "$line`n"
        }
    }

    # 8. Options
    Write-Host ''
    $prerelease = (Read-Host 'Mark as pre-release? (y/N)') -eq 'y'
    $draft = (Read-Host 'Save as draft? (y/N)') -eq 'y'
    $generateNotes = (Read-Host 'Auto-generate notes from GitHub? (y/N)') -eq 'y'

    # 9. Upload ZIP asset
    $zipPath = ''
    Write-Host ''
    $uploadAns = Read-Host 'Attach a ZIP file? (y/N)'
    if ($uploadAns -eq 'y' -or $uploadAns -eq 'Y') {
        Write-Host 'Enter path to ZIP file:' -ForegroundColor Yellow
        $zipPath = (Read-Host 'Path').Trim()
        $zipPath = $zipPath.Trim('"').Trim()
        if ($zipPath -and -not (Test-Path -LiteralPath $zipPath)) {
            Write-Host "  File not found: $zipPath" -ForegroundColor Red
            $zipPath = ''
        } elseif ($zipPath) {
            $zipSize = (Get-Item -LiteralPath $zipPath).Length
            $sz = '{0:N1} MB' -f ($zipSize / 1MB)
            Write-Host "  Attached: $(Split-Path $zipPath -Leaf) ($sz)" -ForegroundColor Green
        }
    }

    # 10. Review
    Write-Host ''
    Write-Host '=== Release Summary ===' -ForegroundColor Cyan
    Write-Host "  Tag:       $tagName" -ForegroundColor White
    Write-Host "  Title:     $title" -ForegroundColor White
    Write-Host "  Base:      $(if ($baseTag) { $baseTag } else { '(none)' })" -ForegroundColor White
    Write-Host "  Draft:     $draft" -ForegroundColor White
    Write-Host "  Pre-rel:   $prerelease" -ForegroundColor White
    Write-Host "  Auto-notes: $generateNotes" -ForegroundColor White
    if ($zipPath) { Write-Host "  Asset:     $(Split-Path $zipPath -Leaf)" -ForegroundColor White }
    Write-Host ''
    Write-Host '--- Notes ---' -ForegroundColor Cyan
    Write-Host $notes -ForegroundColor White
    Write-Host '---' -ForegroundColor Cyan
    Write-Host ''

    $confirm = Read-Host 'Create this release? (y/N)'
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }

    # 11. Write notes to temp file (avoid PS5.1 encoding issues)
    $notesFile = Join-Path $env:TEMP ('release_notes_' + [Guid]::NewGuid().ToString('N') + '.md')
    [System.IO.File]::WriteAllText($notesFile, $notes, [System.Text.UTF8Encoding]::new($false))

    try {
        # 12. Create release via GitHub API (no gh CLI required)
        Write-Host 'Creating release...' -ForegroundColor Cyan
        $body = @{
            tag_name = $tagName
            name = $title
            body = $notes
            draft = $draft
            prerelease = $prerelease
            generate_release_notes = $generateNotes
        } | ConvertTo-Json -Depth 3
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $tmpPayload = Join-Path $env:TEMP ('gh_release_' + [Guid]::NewGuid().ToString('N') + '.json')
        [System.IO.File]::WriteAllBytes($tmpPayload, $bodyBytes)

        $releaseUrl = "https://api.github.com/repos/$GitHubRepo/releases"
        $tmpResp = Join-Path $env:TEMP ('gh_release_resp_' + [Guid]::NewGuid().ToString('N') + '.txt')
        $curlCmd = "curl.exe -s -X POST -H `"Authorization: token $GitHubToken`" -H `"Accept: application/vnd.github.v3+json`" -H `"Content-Type: application/json`" -d @$tmpPayload -o `"$tmpResp`" $releaseUrl"
        & cmd /c $curlCmd 2>$null

        $response = ''
        if (Test-Path -LiteralPath $tmpResp) {
            $response = Get-Content -LiteralPath $tmpResp -Raw
            Remove-Item $tmpResp -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $tmpPayload -Force -ErrorAction SilentlyContinue

        $resultObj = $null
        try { $resultObj = $response | ConvertFrom-Json } catch { Write-Debug "Release response JSON parse failed: $($_.Exception.Message)" }

        if ($resultObj -and $resultObj.html_url) {
            Write-Host ''
            Write-Host 'Release created successfully!' -ForegroundColor Green
            Write-Host "  URL: $($resultObj.html_url)" -ForegroundColor Cyan
            if ($zipPath) {
                Write-Host "  Asset: $(Split-Path $zipPath -Leaf) will be uploaded" -ForegroundColor Green
            }
        } else {
            Write-Host "Release creation failed!" -ForegroundColor Red
            if ($resultObj -and $resultObj.message) {
                Write-Host "  $($resultObj.message)" -ForegroundColor Red
            } else {
                Write-Host "  Response: $($response.Substring(0, [Math]::Min(200, $response.Length)))" -ForegroundColor Red
            }
        }
    } finally {
        Remove-Item -LiteralPath $notesFile -Force -ErrorAction SilentlyContinue
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
    $job = Start-Job -ScriptBlock {
        param($mp, $idx)
        & $mp adb -v $idx -c 'shell pm list packages -3' 2>&1
    } -ArgumentList $MumuPath, $index
    $timeout = 30
    if (Wait-Job $job -Timeout $timeout) {
        $output = Receive-Job $job
    } else {
        Stop-Job $job
        Remove-Job $job -Force
        Write-Host 'Timed out (30s) — ADB is slow or emulator is not responding.' -ForegroundColor Red
        Write-Host 'Try restarting the emulator.' -ForegroundColor Yellow
        return
    }
    Remove-Job $job -Force
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

        $job2 = Start-Job -ScriptBlock {
            param($mp, $idx)
            & $mp adb -v $idx -c 'shell pm list packages' 2>&1
        } -ArgumentList $MumuPath, $index
        if (Wait-Job $job2 -Timeout $timeout) {
            $allOut = Receive-Job $job2
        } else {
            Stop-Job $job2
            Remove-Job $job2 -Force
            Write-Host 'Timed out (30s) — could not list system packages.' -ForegroundColor Red
            return
        }
        Remove-Job $job2 -Force
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

    # Script version (defined at script scope)
    Write-Host "Script version: $scriptVer" -ForegroundColor Green

    # Check for updates
    try {
        $latest = (Invoke-WebRequest -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest" -UseBasicParsing -TimeoutSec 10).Content | ConvertFrom-Json
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

function ADB-FileTransfer {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    if (-not (Confirm-AdbConsent)) { return }
    Write-Host ''
    Write-Host 'ADB File Transfer' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [1] Push file TO emulator' -ForegroundColor White
    Write-Host '  [2] Pull file FROM emulator' -ForegroundColor White
    Write-Host '  [3] List files on emulator' -ForegroundColor White
    Write-Host ''
    $mode = Read-Host 'Select (1/2/3)'

    if ($mode -eq '1') {
        # Push
        $localPath = (Read-Host 'Local file path').Trim().Trim('"')
        if (-not $localPath -or -not (Test-Path -LiteralPath $localPath)) {
            Write-Host 'File not found.' -ForegroundColor Red
            return
        }
        $remotePath = (Read-Host 'Remote path on emulator (e.g. /sdcard/Download/)').Trim()
        if (-not $remotePath) { $remotePath = '/sdcard/Download/' }
        $size = '{0:N1} KB' -f ((Get-Item -LiteralPath $localPath).Length / 1KB)
        Write-Host "  Pushing $(Split-Path $localPath -Leaf) ($size) to $remotePath..." -ForegroundColor Cyan
        $result = & $MumuPath adb -v $index -c "push \"$localPath\" $remotePath" 2>&1 | Out-String
        if ($result -match 'pushed|bytes') {
            Write-Host '  Done!' -ForegroundColor Green
        } else {
            Write-Host "  Result: $($result.Trim())" -ForegroundColor Yellow
        }
    } elseif ($mode -eq '2') {
        # Pull
        $remotePath = (Read-Host 'Remote file path (e.g. /sdcard/Download/file.txt)').Trim()
        if (-not $remotePath) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
        $localDir = (Read-Host 'Local save directory (Enter=current)').Trim().Trim('"')
        if (-not $localDir) { $localDir = $PWD.Path }
        if (-not (Test-Path -LiteralPath $localDir)) {
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        }
        Write-Host "  Pulling $remotePath..." -ForegroundColor Cyan
        $result = & $MumuPath adb -v $index -c "pull $remotePath \"$localDir\"" 2>&1 | Out-String
        if ($result -match 'pulled|bytes') {
            Write-Host "  Saved to: $localDir" -ForegroundColor Green
        } else {
            Write-Host "  Result: $($result.Trim())" -ForegroundColor Yellow
        }
    } elseif ($mode -eq '3') {
        # List
        $path = (Read-Host 'Path to list (Enter=/sdcard/)').Trim()
        if (-not $path) { $path = '/sdcard/' }
        Write-Host "  Listing $path..." -ForegroundColor Cyan
        $result = & $MumuPath adb -v $index -c "shell ls -la $path" 2>&1
        $result | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    }
}

function ADB-ScreenCapture {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    if (-not (Confirm-AdbConsent)) { return }
    Write-Host ''
    Write-Host 'ADB Screen Capture' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [1] Take screenshot' -ForegroundColor White
    Write-Host '  [2] Record screen (max 180s)' -ForegroundColor White
    Write-Host ''
    $mode = Read-Host 'Select (1/2)'

    if ($mode -eq '1') {
        # Screenshot
        $remotePath = '/sdcard/screenshot.png'
        $localDir = (Read-Host 'Save to directory (Enter=current)').Trim().Trim('"')
        if (-not $localDir) { $localDir = $PWD.Path }
        Write-Host '  Taking screenshot...' -ForegroundColor Cyan
        & $MumuPath adb -v $index -c "shell screencap -p $remotePath" 2>&1 | Out-Null
        $result = & $MumuPath adb -v $index -c "pull $remotePath \"$localDir\screenshot_$($index).png\"" 2>&1 | Out-String
        & $MumuPath adb -v $index -c "shell rm $remotePath" 2>&1 | Out-Null
        if ($result -match 'pulled|bytes') {
            $file = Join-Path $localDir "screenshot_$($index).png"
            $size = '{0:N1} KB' -f ((Get-Item -LiteralPath $file).Length / 1KB)
            Write-Host "  Saved: $file ($size)" -ForegroundColor Green
        } else {
            Write-Host "  Failed: $($result.Trim())" -ForegroundColor Red
        }
    } elseif ($mode -eq '2') {
        # Screen record
        $duration = (Read-Host 'Duration in seconds (max 180, Enter=30)').Trim()
        if (-not $duration -or -not ($duration -match '^\d+$')) { $duration = 30 }
        $duration = [Math]::Min([int]$duration, 180)
        $remotePath = '/sdcard/recording.mp4'
        $localDir = (Read-Host 'Save to directory (Enter=current)').Trim().Trim('"')
        if (-not $localDir) { $localDir = $PWD.Path }
        Write-Host "  Recording screen for ${duration}s... (Ctrl+C to stop early)" -ForegroundColor Cyan
        try {
            & $MumuPath adb -v $index -c "shell screenrecord --time-limit $duration $remotePath" 2>&1 | Out-Null
        } catch { Write-Debug "Recording interrupted: $($_.Exception.Message)" }
        $result = & $MumuPath adb -v $index -c "pull $remotePath \"$localDir\ recording_$($index).mp4\"" 2>&1 | Out-String
        & $MumuPath adb -v $index -c "shell rm $remotePath" 2>&1 | Out-Null
        if ($result -match 'pulled|bytes') {
            $file = Join-Path $localDir "recording_$($index).mp4"
            $size = '{0:N1} KB' -f ((Get-Item -LiteralPath $file).Length / 1KB)
            Write-Host "  Saved: $file ($size)" -ForegroundColor Green
        } else {
            Write-Host "  Failed: $($result.Trim())" -ForegroundColor Red
        }
    }
}

function ADB-InteractiveShell {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    if (-not (Confirm-AdbConsent)) { return }
    Write-Host ''
    Write-Host "Interactive ADB shell (instance $index)" -ForegroundColor Cyan
    Write-Host '  Type commands directly. Type "exit" to return.' -ForegroundColor DarkGray
    Write-Host ''
    while ($true) {
        $cmd = (Read-Host 'adb>').Trim()
        if (-not $cmd -or $cmd -eq 'exit' -or $cmd -eq 'quit') { break }
        & $MumuPath adb -v $index -c "shell $cmd" 2>&1 | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host 'Shell closed.' -ForegroundColor DarkGray
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
        'vk' { Set-VTApiKeyMenu }
        'z' { Test-Security }
        'tc' { Test-EmulatorConnection }
        'tn' { Test-Network }
        'td' { Test-ScriptDependencies }
        'vt' { Scan-VirusTotal }
        'uw' { Fix-Unicode }
        'dm' { Set-DeviceModel }
        'sim' { Set-SimOperator }
        'di' { Set-RandomDeviceIds }
        'ba' { Backup-EmulatorData }
        're' { Restore-EmulatorData }
        'a' { Invoke-ADBCommand }
        'af' { ADB-FileTransfer }
        'as' { ADB-ScreenCapture }
        'ah' { ADB-InteractiveShell }
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
        'dl' { Download-Repository }
        'cr' { Create-GitHubRelease }
        'fr' { Fix-ReleaseEncoding }
        'crt' { Create-Certificate }
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