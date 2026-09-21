# Runner for the Pester unit tests (issue #20) - works on Windows PowerShell
# 5.1 and PowerShell 7+ (pwsh). Installs Pester 5.x to a user scope only if no
# suitable version exists - non-interactively (the stock PS 5.1 NuGet-provider
# prompt would hang unattended runs).
#
#   powershell -ExecutionPolicy Bypass -File tests/run-pester.ps1
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run-pester.ps1

$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
if (-not $pester) {
    Write-Host 'Pester 5.x not found - installing to user scope (non-interactive)...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 # DevSkim: ignore DS440020,DS440001 - Windows PowerShell 5.1 test runner needs the explicit TLS 1.2 opt-in
    } catch {
        # Best-effort hardening only: pwsh 7 negotiates TLS 1.2+ by default
        # and may not expose ServicePointManager at all - never fatal here.
        Write-Debug "TLS 1.2 hardening not applied: $($_.Exception.Message)" # DevSkim: ignore DS440001 - prose mention, not a protocol setting
    }
    if ($PSVersionTable.PSEdition -eq 'Core') {
        # PowerShell 7+ ships PowerShellGet 2.x / PSResourceGet - no NuGet
        # provider bootstrap needed, and the gallery must be trusted or
        # Install-Module prompts (which would hang unattended runs).
        # The PSResourceGet store may not exist on a fresh profile - create
        # the directory and an empty store file (the cmdlets don't self-init).
        $storeDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PSResourceGet'
        if (-not (Test-Path -LiteralPath $storeDir -PathType Container)) {
            New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
        }
        $storeFile = Join-Path $storeDir 'PSResourceRepository.xml'
        if (-not (Test-Path -LiteralPath $storeFile -PathType Leaf)) {
            Set-Content -LiteralPath $storeFile -Value '<?xml version="1.0" encoding="utf-8"?><configuration><RepositoryStore /></configuration>' -Encoding UTF8
        }
        Register-PSResourceRepository -PSGallery -Trusted -ErrorAction SilentlyContinue
        Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
    } else {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
    }
    $pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
    if (-not $pester) { throw 'Pester 5.x installation failed' }
}
Import-Module Pester -MinimumVersion 5.0 -DisableNameChecking

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $PSScriptRoot 'mumu-menu.Tests.ps1'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
