# Runner for the Pester unit tests (issue #20) on Windows PowerShell 5.1.
# Installs Pester 5.x to a user scope only if no suitable version exists -
# non-interactively (the stock PS 5.1 NuGet-provider prompt would hang
# unattended runs). CI (pwsh) ships Pester 5 and can call this too.
#
#   powershell -ExecutionPolicy Bypass -File tests/run-pester.ps1

$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
if (-not $pester) {
    Write-Host 'Pester 5.x not found - installing to user scope (non-interactive)...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
    $pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
    if (-not $pester) { throw 'Pester 5.x installation failed' }
}
Import-Module Pester -MinimumVersion 5.0 -DisableNameChecking

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $PSScriptRoot 'mumu-menu.Tests.ps1'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
