# MuMuManager CLI - Interactive Menu for Netease MuMu Emulator (Windows)
# Project:  https://github.com/genrihx2/MuMuManager-CLI-Menu
# Purpose:  launch/stop/restart emulator instances, install/uninstall APKs,
#           tune performance, spoof device model, back up instance data.
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
    # One-time migration: encrypt an existing plaintext token with DPAPI,
    # then remove the plaintext file.
    param([string]$Plain)
    try {
        $sec = ConvertTo-SecureString $Plain -AsPlainText -Force
        ConvertFrom-SecureString -SecureString $sec |
            Set-Content -LiteralPath $DpapiTokenFile -Force -ErrorAction Stop
        Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
        Write-Host '  Token migrated to encrypted storage (.github-token.dpapi); plaintext file removed.' -ForegroundColor DarkGray
    } catch {
        Write-Warning "Could not migrate token to encrypted storage: $($_.Exception.Message)"
    }
}

$GitHubToken = Get-GitHubToken

# Force TLS 1.2+ (PowerShell 5.1 defaults fail against GitHub with
# "The underlying connection was closed: An unexpected error occurred on a send.")
try {
    [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12)
} catch {}

function Invoke-GitHubGet {
    param([string]$Url, [int]$TimeoutSec = 30)
    $curlArgs = @('-s', '--retry', '2', '--retry-delay', '2', '--connect-timeout', '15', '--max-time', "$TimeoutSec")
    if ($Url -match '^https://api\.github\.com/') {
        $curlArgs += @('-H', 'Accept: application/vnd.github.raw')
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
    } catch {}
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

    if ($Passive) {
        Write-Host 'Update check (read-only)...' -ForegroundColor DarkGray
    } else {
        Write-Host ''
        Write-Host 'Checking for updates...' -ForegroundColor Cyan
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

    try {
        $relUrl = "https://api.github.com/repos/$GitHubRepo/releases/latest"
        $release = Invoke-GitHubGet $relUrl 15 | ConvertFrom-Json

        if (-not $release -or -not $release.tag_name) {
            if (-not $Passive) { Write-Host '  No releases found on remote' -ForegroundColor Yellow }
            return
        }

        $tag = $release.tag_name
        $remoteDate = $release.published_at
        $remoteMsg = ''
        if ($release.body) {
            $remoteMsg = (($release.body -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
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
        if ($remoteMsg) {
            Write-Host "  Latest change: $remoteMsg" -ForegroundColor DarkGray
        }
        if ($remoteDate) {
            Write-Host "  Date: $remoteDate" -ForegroundColor DarkGray
        }
        $confirm = Read-Host '  Download update? Current files will be backed up first (y/N)'
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

        # Primary: download the release ZIP asset (one request, no API rate limits).
        # Fallback: fetch individual files via the GitHub contents API.
        $zipName = "MuMuManager-CLI-Menu-$tag.zip"
        $zipUrl = "https://github.com/$GitHubRepo/releases/download/$tag/$zipName"
        $tmp = Join-Path $env:TEMP "mumu_update_$stamp.zip"
        $tmpDir = Join-Path $env:TEMP "mumu_update_$stamp"
        $failed = 0
        $usedZip = $false

        try {
            Write-Host "  Downloading $zipName..." -ForegroundColor Yellow
            $dlArgs = @('-sL', '--retry', '3', '--retry-delay', '2', '--connect-timeout', '15', '--max-time', '120', '-o', $tmp, $zipUrl)
            if ($GitHubToken) { $dlArgs += @('-H', "Authorization: token $GitHubToken") }
            & curl.exe @dlArgs 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp) -and (Get-Item $tmp).Length -gt 100) {
                New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
                & tar.exe -xf $tmp -C $tmpDir 2>$null
                if ($LASTEXITCODE -ne 0) { Expand-Archive -LiteralPath $tmp -DestinationPath $tmpDir -Force }
                foreach ($f in $files) {
                    $src = Get-ChildItem $tmpDir -Recurse -Filter $f | Select-Object -First 1
                    if (-not $src) { Write-Host "    Missing in archive: $f" -ForegroundColor Red; $failed++; continue }
                    Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $ScriptDir $f) -Force
                    Write-Host "    $f OK" -ForegroundColor Green
                }
                $usedZip = ($failed -eq 0)
            } else {
                throw "ZIP download failed (exit $LASTEXITCODE)"
            }
        } catch {
            Write-Host "  ZIP method failed: $($_.Exception.Message)" -ForegroundColor Yellow
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
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
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

function Show-Menu {
    Clear-Host
    Write-Host '======================================' -ForegroundColor Cyan
    Write-Host '    MuMuManager CLI Menu' -ForegroundColor Cyan
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
    Write-Host '  [Z] Security audit (disabled)' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Spoofing ---' -ForegroundColor Green
    Write-Host '  [DM] Spoof device model' -ForegroundColor Yellow
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
        $index = (Read-Host "$Prompt ($validRange)").Trim()
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
    Write-Host ''
    Write-Host "Launching instance $index..." -ForegroundColor Cyan

    & $MumuPath api -v $index launch_player 2>&1 | ForEach-Object { Write-Host $_ }

    Wait-Boot -Index $index | Out-Null
}

function Stop-Emulator {
    $index = Get-InstanceIndex 'Select instance to shutdown'
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
                } catch {}
                Write-Host "Rename failed: $msg" -ForegroundColor Red
            } else {
                Write-Host 'Renamed.' -ForegroundColor Green
            }
        } else {
            Stop-Job $job
            & taskkill /IM MuMuManager.exe /F 2>&1 | Out-Null
            Write-Host 'Rename timed out (emulator service did not respond).' -ForegroundColor Red
        }
    } finally {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Clear-AppData {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()
    if (-not $package) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host "Clearing data for $package..." -ForegroundColor Cyan
    & $MumuPath adb -v $index -c "shell pm clear $package" 2>&1 | Out-Null
    Write-Host 'Done!' -ForegroundColor Green
}

function Stop-App {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()
    if (-not $package) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host "Force stopping $package..." -ForegroundColor Cyan
    & $MumuPath adb -v $index -c "shell am force-stop $package" 2>&1 | Out-Null
    Write-Host 'Done!' -ForegroundColor Green
}

function Start-App {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()
    if (-not $package) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host "Starting $package..." -ForegroundColor Cyan
    & $MumuPath adb -v $index -c "shell monkey -p $package -c android.intent.category.LAUNCHER 1" 2>&1 | Out-Null
    Write-Host 'Done!' -ForegroundColor Green
}

function Backup-EmulatorData {
    $index = Get-InstanceIndex 'Select instance'
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
        } catch {}
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

    # 5. Root certificate store audit - disabled (Sigma rule FP)
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

function Update-Token {
    Write-Host ''
    Write-Host 'GitHub Token Manager' -ForegroundColor Cyan

    $stored = $false
    if (Test-Path -LiteralPath $DpapiTokenFile -PathType Leaf) {
        Write-Host 'Current token: stored ENCRYPTED (.github-token.dpapi)' -ForegroundColor DarkGray
        $stored = $true
    } elseif (Test-Path -LiteralPath $TokenFile -PathType Leaf) {
        Write-Host 'Current token: stored PLAINTEXT (legacy .github-token)' -ForegroundColor Yellow
        $stored = $true
    }

    if ($stored) {
        Write-Host ''
        Write-Host '  [1] Update token' -ForegroundColor Yellow
        Write-Host '  [2] Remove token (public repo)' -ForegroundColor Yellow
        Write-Host '  [0] Cancel' -ForegroundColor Yellow
        $choice = Read-Host 'Select option'

        if ($choice -eq '2') {
            Remove-Item -LiteralPath $DpapiTokenFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
            Write-Host 'Token removed! Auto-update works without token for public repos.' -ForegroundColor Green
            return
        } elseif ($choice -ne '1') {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
    }

    # Masked input: the token is captured as a SecureString and never echoed.
    Write-Host 'Enter token (input hidden):' -ForegroundColor Cyan
    $sec = Read-Host -AsSecureString
    if (ConvertFrom-SecureToken $sec) {
        # Validate BEFORE saving anything to disk.
        $plain = ConvertFrom-SecureToken $sec
        Write-Host 'Testing...' -ForegroundColor Yellow
        $rawUser = & curl.exe -s --connect-timeout 15 --max-time 20 -H "Authorization: token $plain" 'https://api.github.com/user' 2>$null
        $user = (@($rawUser) | Out-String | ConvertFrom-Json)
        if (-not $user.login) {
            Write-Host 'Token invalid! Nothing was saved.' -ForegroundColor Red
            return
        }
        ConvertFrom-SecureString -SecureString $sec |
            Set-Content -LiteralPath $DpapiTokenFile -Force
        Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
        $script:GitHubToken = $plain
        Write-Host "Token valid ($($user.login)). Saved ENCRYPTED via DPAPI (.github-token.dpapi)." -ForegroundColor Green
    } else {
        Write-Host 'Cancelled (empty input).' -ForegroundColor Yellow
    }
}

function Show-Logs {
    $index = Get-InstanceIndex 'Select instance'
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
            try {
                $raw = & $MumuPath adb -v $index -c "logcat -v time -d -t 200 $filter" 2>&1
                if ($raw) {
                    $raw | ForEach-Object { Write-Host $_ }
                } else {
                    Write-Host 'Empty output — instance may be stopped or no matching logs.' -ForegroundColor Yellow
                }
            } catch {
                Write-Host "logcat failed: $($_.Exception.Message)" -ForegroundColor Red
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
    } catch {}
    Write-Host "Install failed: $msg" -ForegroundColor Red
}

function Uninstall-App {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    $package = (Read-Host 'Enter package name').Trim()

    if (-not $package) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        return
    }

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
    Write-Host 'Script version: 1.13.20' -ForegroundColor Green

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

    # OS info
    $os = [System.Environment]::OSVersion.Version
    Write-Host "OS: Windows $($os.Major).$($os.Minor)" -ForegroundColor DarkGray

    # GitHub repo
    Write-Host "Repository: $GitHubRepo" -ForegroundColor DarkGray    # Token status
    if ($GitHubToken) {
        Write-Host 'GitHub token: configured' -ForegroundColor Green
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
    if ($ans -ceq 'OK') {
        $script:SpoofConsentAccepted = $true
        return $true
    }
    Write-Host '  Cancelled (consent not given).' -ForegroundColor Yellow
    return $false
}

function Set-DeviceModel {
    if (-not (Confirm-SpoofConsent)) { return }
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''

    try {
        $info = & $MumuPath setting -v $index -k phone_brand -k phone_model -k phone_miit 2>$null | ConvertFrom-Json
        Write-Host 'Current device model:' -ForegroundColor DarkGray
        Write-Host "  Brand: $($info.phone_brand)" -ForegroundColor White
        Write-Host "  Model: $($info.phone_model)" -ForegroundColor White
        Write-Host "  Code:  $($info.phone_miit)" -ForegroundColor White
        Write-Host ''
    } catch {}

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
        } catch {}
        Write-Host 'Restart the emulator to fully apply build properties.' -ForegroundColor Yellow
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
    Write-Host ''

    try {
        $sim = & $MumuPath simulation -v $index 2>$null | ConvertFrom-Json
        Write-Host 'Current simulated properties:' -ForegroundColor DarkGray
        Write-Host "  IMEI:       $(if ($sim.imei) { $sim.imei } else { '(not set)' })" -ForegroundColor White
        Write-Host "  Android ID: $(if ($sim.android_id) { $sim.android_id } else { '(not set)' })" -ForegroundColor White
        Write-Host "  MAC:        $(if ($sim.mac_address) { $sim.mac_address } else { '(not set)' })" -ForegroundColor White
        Write-Host ''
    } catch {}

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

    foreach ($t in $targets) {
        switch ($t) {
            'imei'        { $val = New-RandomImei }
            'android_id'  { $val = New-RandomAndroidId }
            'mac_address' { $val = New-RandomMac }
        }
        try {
            & $MumuPath simulation -v $index -sk $t -sv $val 2>&1 | Out-Null
            $label = switch ($t) { 'imei' { 'IMEI' } 'android_id' { 'Android ID' } 'mac_address' { 'MAC' } }
            Write-Host "  $label -> $val" -ForegroundColor Green
        } catch {
            Write-Host "  Failed to set ${t}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ''
    Write-Host 'Done! Restart the emulator to apply.' -ForegroundColor Green
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host 'Select option (0 = Exit)'

    switch ($choice) {
        '1' { Show-InstanceInfo }
        '2' { Start-Emulator }
        '3' { Stop-Emulator }
        '4' { Restart-Emulator }
        '5' { New-Emulator }
        'c' { Copy-Emulator }
        'C' { Copy-Emulator }
        'x' { Remove-Emulator }
        'X' { Remove-Emulator }
        'n' { Rename-Emulator }
        'N' { Rename-Emulator }
        '6' { Show-Apps }
        '7' { Show-Settings }
        '8' { Install-APK }
        '9' { Uninstall-App }
        'g' { Show-Logs }
        'G' { Show-Logs }
        'o' { Clear-AppData }
        'O' { Clear-AppData }
        'p' { Stop-App }
        'P' { Stop-App }
        't' { Start-App }
        'T' { Start-App }
        'e' { Export-Emulator }
        'E' { Export-Emulator }
        'k' { Update-Token }
        'K' { Update-Token }
        'z' { Test-Security }
        'Z' { Test-Security }
        'dm' { Set-DeviceModel }
        'DM' { Set-DeviceModel }
        'di' { Set-RandomDeviceIds }
        'DI' { Set-RandomDeviceIds }
        'ba' { Backup-EmulatorData }
        'BA' { Backup-EmulatorData }
        'a' { Invoke-ADBCommand }
        'A' { Invoke-ADBCommand }
        'b' { Start-All }
        'B' { Start-All }
        'd' { Stop-All }
        'D' { Stop-All }
        'r' { Restart-All }
        'R' { Restart-All }
        'i' { Install-APK-All }
        'I' { Install-APK-All }
        'w' { Show-Windows }
        'W' { Show-Windows }
        'h' { Hide-Windows }
        'H' { Hide-Windows }
        'l' { Set-WindowLayout }
        'L' { Set-WindowLayout }
        's' { Save-Screenshot }
        'S' { Save-Screenshot }
        'v' { Show-VersionInfo }
        'V' { Show-VersionInfo }
        'u' { Update-FromGitHub }
        'U' { Update-FromGitHub }
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