# Bootstrap Update Script - Run this SEPARATELY from PowerShell
# It downloads the latest mumu-menu.ps1 and replaces the old one
# Usage: powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1

param([string]$TargetDir = $PSScriptRoot)

if (-not $TargetDir) { $TargetDir = $PWD.Path }

Write-Host "=== Bootstrap Update ===" -ForegroundColor Cyan
Write-Host "Target: $TargetDir" -ForegroundColor DarkGray
Write-Host ""

# Force TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12) } catch { Write-Debug "TLS 1.2 enable failed: $($_.Exception.Message)" }

$repo = 'genrihx2/MuMuManager-CLI-Menu'
$files = @('mumu-menu.ps1', 'SKILL.md', 'README.md')

$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'MuMuManager-CLI-Menu-Bootstrap')

$ok = 0
$fail = 0

foreach ($f in $files) {
    $dest = Join-Path $TargetDir $f
    $url = "https://raw.githubusercontent.com/$repo/main/$f"

    Write-Host "  Downloading $f..." -ForegroundColor Yellow -NoNewline
    try {
        $bytes = $wc.DownloadData($url)
        if (-not $bytes -or $bytes.Length -eq 0) { throw 'empty download' }
        
        # Check for JSON error
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text.Length -lt 500 -and $text -match '"message"\s*:\s*"') {
            $errMsg = if ($text -match '"message"\s*:\s*"([^"]+)"') { $Matches[1] } else { 'API error' }
            throw $errMsg
        }

        # For mumu-menu.ps1: check if file is locked (running), save as .new
        if ($f -eq 'mumu-menu.ps1') {
            $newPath = $dest + '.new'
            [System.IO.File]::WriteAllBytes($newPath, $bytes)
            Write-Host " saved as .new ($($bytes.Length) bytes)" -ForegroundColor Green
        } else {
            [System.IO.File]::WriteAllBytes($dest, $bytes)
            Write-Host " OK ($($bytes.Length) bytes)" -ForegroundColor Green
        }
        $ok++
    } catch {
        Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "Done: $ok ok, $fail failed" -ForegroundColor $(if ($fail -gt 0) { 'Yellow' } else { 'Green' })

# Check if .new was created
$newFile = Join-Path $TargetDir 'mumu-menu.ps1.new'
if (Test-Path -LiteralPath $newFile) {
    Write-Host ""
    Write-Host "A .new file was created. To apply it:" -ForegroundColor Cyan
    Write-Host "  1. Close all running mumu-menu.ps1 instances" -ForegroundColor White
    Write-Host "  2. Run: Rename-Item '$newFile' 'mumu-menu.ps1' -Force" -ForegroundColor White
    Write-Host "  3. Or just restart the menu - it will apply automatically" -ForegroundColor White
} elseif ($ok -gt 0 -and $fail -eq 0) {
    Write-Host ""
    Write-Host "Update applied! Restart the menu to use the new version." -ForegroundColor Green
}
