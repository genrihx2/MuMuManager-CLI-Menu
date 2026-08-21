# MuMuManager CLI - Interactive Menu
# Launch: .\mumu-menu.ps1

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GitHubRepo = 'genrihx2/MuMuManager-CLI-Menu'
$SkillPath = '.'
$GitHubRaw = 'https://raw.githubusercontent.com'
$VersionFile = Join-Path $ScriptDir '.version'

$MumuPath = 'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe'

# Check if MuMuManager.exe exists
if (-not (Test-Path $MumuPath)) {
    Write-Error "MuMuManager.exe not found at $MumuPath"
    exit 1
}

# Auto-update from GitHub
function Update-FromGitHub {
    Write-Host ''
    Write-Host 'Checking for updates...' -ForegroundColor Cyan
    try {
        $apiUrl = "https://api.github.com/repos/$GitHubRepo/commits?path=$SkillPath/mumu-menu.ps1&per_page=1"
        $headers = @{'Accept' = 'application/vnd.github.v3+json'}
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -Headers $headers -ErrorAction Stop

        if (-not $response -or $response.Count -eq 0) {
            Write-Host '  No commits found on remote' -ForegroundColor Yellow
            return
        }

        $commit = $response[0]
        if (-not $commit -or -not $commit.sha) {
            Write-Host '  Invalid response from GitHub' -ForegroundColor Yellow
            return
        }

        $remoteHash = $commit.sha.Substring(0, [Math]::Min(7, $commit.sha.Length))
        $remoteDate = ''
        if ($commit.commit -and $commit.commit.committer) {
            $remoteDate = $commit.commit.committer.date
        }

        $localHash = ''
        if (Test-Path $VersionFile) {
            $localHash = (Get-Content $VersionFile -ErrorAction SilentlyContinue).Trim()
        }

        if ($remoteHash -eq $localHash) {
            Write-Host "  Up to date ($remoteHash)" -ForegroundColor DarkGray
            return
        }

        Write-Host "  Update available! ($remoteHash)" -ForegroundColor Yellow
        if ($remoteDate) {
            Write-Host "  Remote: $remoteDate" -ForegroundColor DarkGray
        }
        $confirm = Read-Host '  Download update? (y/N)'
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host '  Skipped.' -ForegroundColor DarkGray
            return
        }

        $files = @('mumu-menu.ps1', 'mumu-profile.ps1', 'SKILL.md', 'README.md')
        foreach ($f in $files) {
            $url = "$GitHubRaw/$GitHubRepo/main/$SkillPath/$f"
            $dest = Join-Path $ScriptDir $f
            Write-Host "  Downloading $f..." -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
                Write-Host "    OK" -ForegroundColor Green
            } catch {
                Write-Host "    Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        Set-Content -Path $VersionFile -Value $remoteHash -NoNewline -ErrorAction SilentlyContinue
        Write-Host ''
        Write-Host 'Update complete! Restart the menu to use the new version.' -ForegroundColor Green
        Start-Sleep -Seconds 2
        exit
    } catch {
        Write-Host "  Update check failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Update-FromGitHub

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
    Write-Host '  [5] Create new emulator' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Apps and Settings ---' -ForegroundColor Green
    Write-Host '  [6] List installed apps' -ForegroundColor Yellow
    Write-Host '  [7] Show settings' -ForegroundColor Yellow
    Write-Host '  [8] Install APK' -ForegroundColor Yellow
    Write-Host '  [9] Uninstall app' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Batch ---' -ForegroundColor Green
    Write-Host '  [B] Launch all instances' -ForegroundColor Yellow
    Write-Host '  [D] Shutdown all instances' -ForegroundColor Yellow
    Write-Host '  [R] Restart all instances' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Other ---' -ForegroundColor Green
    Write-Host '  [A] Run ADB command' -ForegroundColor Yellow
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
        $index = Read-Host "$Prompt (0-9)"
        if (-not $index) { $index = '0' }

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
            Write-Host "$line                                        " -NoNewline
        } catch {
            Write-Host "  Checking... [$elapsed s]                                " -NoNewline
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

    & $MumuPath api -v $index launch_player 2>&1 | ForEach-Object { Write-Host $ }

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
        & $MumuPath api -v $index shutdown_player 2>&1 | ForEach-Object { Write-Host $ }
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
    & $MumuPath api -v $index launch_player 2>&1 | ForEach-Object { Write-Host $ }

    Wait-Boot -Index $index | Out-Null
}

function New-Emulator {
    Write-Host ''
    Write-Host 'Creating new emulator...' -ForegroundColor Cyan

    $output = Invoke-Mumu create 2>&1
    Write-Host $output

    Write-Host 'Done!' -ForegroundColor Green
}

function Get-AllIndices {
    $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
    return $info.PSObject.Properties.Name
}

function Launch-All {
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

function Shutdown-All {
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
    Shutdown-All
    Write-Host ''
    Write-Host 'Waiting for main services...' -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Write-Host ''
    Launch-All
}

function Show-Apps {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    Write-Host 'Fetching installed apps...' -ForegroundColor Cyan
    $result = Invoke-Mumu control -v $index app info -i
    try {
        $result | ConvertFrom-Json | ConvertTo-Json -Depth 10
    } catch {
        Write-Host $result
    }
}

function Show-Settings {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    Write-Host 'Fetching settings...' -ForegroundColor Cyan
    $result = Invoke-Mumu setting -v $index --all_writable
    try {
        $result | ConvertFrom-Json | ConvertTo-Json -Depth 10
    } catch {
        Write-Host $result
    }
}

function Install-APK {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    $apkPath = Read-Host 'Enter APK file path'

    if (Test-Path $apkPath) {
        Write-Host 'Installing APK...' -ForegroundColor Cyan
        Invoke-Mumu control -v $index app install -apk $apkPath
        Write-Host 'Done!' -ForegroundColor Green
    } else {
        Write-Error "File not found: $apkPath"
    }
}

function Uninstall-App {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    $package = Read-Host 'Enter package name'

    Write-Host 'Uninstalling app...' -ForegroundColor Cyan
    Invoke-Mumu control -v $index app uninstall -pkg $package
    Write-Host 'Done!' -ForegroundColor Green
}

function Invoke-ADBCommand {
    $index = Get-InstanceIndex 'Select instance'
    Write-Host ''
    $cmd = Read-Host 'Enter ADB command'

    Write-Host 'Running ADB command...' -ForegroundColor Cyan
    Invoke-Mumu adb -v $index -c $cmd
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host 'Select option (0-9)'

    switch ($choice) {
        '1' { Show-InstanceInfo }
        '2' { Start-Emulator }
        '3' { Stop-Emulator }
        '4' { Restart-Emulator }
        '5' { New-Emulator }
        '6' { Show-Apps }
        '7' { Show-Settings }
        '8' { Install-APK }
        '9' { Uninstall-App }
        'a' { Invoke-ADBCommand }
        'A' { Invoke-ADBCommand }
        'b' { Launch-All }
        'B' { Launch-All }
        'd' { Shutdown-All }
        'D' { Shutdown-All }
        'r' { Restart-All }
        'R' { Restart-All }
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