# Runner for the Pester unit tests (issue #20) - works on Windows PowerShell
# 5.1 and PowerShell 7+ (pwsh). Installs Pester 5.x to a user scope only if no
# suitable version exists - non-interactively (the stock PS 5.1 NuGet-provider
# prompt would hang unattended runs).
#
#   powershell -ExecutionPolicy Bypass -File tests/run-pester.ps1
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run-pester.ps1
#   deployed layout (CI): tests/test-deployed-layout.ps1 - wraps this runner
#   with -ExcludeTag RepoFiles inside a copy holding only deployed files
#
# The CI matrix (.github/workflows/tests.yml + .github/actions/pester-unit)
# calls this same runner with -PesterVersion / -ModuleDir so the suite is
# proven on the exact Pester the repo documents, on BOTH engines, plus one
# unpinned canary leg that tracks whatever the runner image ships next.

param(
    # Exact Pester version to require (e.g. '5.7.1'). Empty = any 5.x+,
    # the historical developer behavior.
    [string]$PesterVersion = '',
    # Private module directory that already holds the pinned Pester
    # (prepared by the CI action or a local Save-Module). Prepended to
    # PSModulePath so the preinstalled Pester can never win resolution.
    [string]$ModuleDir = '',
    # Pester -ExcludeTag value (string array). The deployed-layout runner
    # (tests/test-deployed-layout.ps1) passes 'RepoFiles' so the suite can
    # run inside an installed fixture that carries no repo-only docs.
    [string[]]$ExcludeTag = @()
)

$ErrorActionPreference = 'Stop'

if ($ModuleDir) { $env:PSModulePath = "$ModuleDir;$env:PSModulePath" }

$versionOk = { param($v) ($v.Major -ge 5) -and (-not $PesterVersion -or $v -eq [version]$PesterVersion) }
$pester = Get-Module -ListAvailable Pester | Where-Object { & $versionOk $_.Version } | Select-Object -First 1
if (-not $pester) {
    $want = if ($PesterVersion) { "Pester $PesterVersion" } else { 'Pester 5.x' }
    Write-Host "$want not found - installing to a private directory (non-interactive)..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 # DevSkim: ignore DS440020,DS440001 - Windows PowerShell 5.1 test runner needs the explicit TLS 1.2 opt-in
    } catch {
        # Best-effort hardening only: pwsh 7 negotiates TLS 1.2+ by default
        # and may not expose ServicePointManager at all - never fatal here.
        Write-Debug "TLS 1.2 hardening not applied: $($_.Exception.Message)" # DevSkim: ignore DS440001 - prose mention, not a protocol setting
    }
    if (-not $ModuleDir) { $ModuleDir = Join-Path ([IO.Path]::GetTempPath()) 'pester-runner' }
    New-Item -ItemType Directory -Path $ModuleDir -Force | Out-Null
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
        # PSGallery may already be registered (most pwsh installs pre-register
        # it); 'already exists' is the desired end state, not a failure. A
        # terminating register error surfaces only when the store file the
        # cmdlets would use is genuinely unusable.
        $already = Get-PSResourceRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($already) {
            Write-Debug "PSGallery already registered: $($already.Uri)"
        } else {
            Register-PSResourceRepository -PSGallery -Trusted -ErrorAction Stop
        }
        # Save-PSResource -Path refuses a nonexistent directory.
        New-Item -ItemType Directory -Path $ModuleDir -Force | Out-Null
        if ($PesterVersion) {
            # -SkipModuleManifestValidate exists in PSResourceGet 1.x but was
            # removed in 2.x - probe the cmdlet instead of guessing (a pinned
            # 5.7.1 manifest validates fine either way).
            $skipValidate = if ((Get-Command Save-PSResource).Parameters.ContainsKey('SkipModuleManifestValidate')) { '-SkipModuleManifestValidate' } else { $null }
            if ($skipValidate) {
                Save-PSResource -Name Pester -Version $PesterVersion -Path $ModuleDir -TrustRepository -SkipModuleManifestValidate
            } else {
                Save-PSResource -Name Pester -Version $PesterVersion -Path $ModuleDir -TrustRepository
            }
        } else {
            Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        }
    } else {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        if ($PesterVersion) {
            Save-Module -Name Pester -RequiredVersion $PesterVersion -Path $ModuleDir -Force
        } else {
            Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        }
    }
    $pester = Get-Module -ListAvailable Pester | Where-Object { & $versionOk $_.Version } | Select-Object -First 1
    if (-not $pester) { throw "Pester installation failed (wanted: $(if ($PesterVersion) { $PesterVersion } else { '5.x or newer' }))" }
}
Import-Module Pester -MinimumVersion 5.0 -DisableNameChecking

$loaded = (Get-Module Pester).Version
if ($PesterVersion -and $loaded -ne [version]$PesterVersion) {
    throw "Pester pin failed: loaded $loaded, wanted $PesterVersion (PSModulePath order or stale module?)"
}
Write-Host "Pester $loaded on PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $PSScriptRoot 'mumu-menu.Tests.ps1'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
if ($ExcludeTag.Count -gt 0) { $config.Filter.ExcludeTag = $ExcludeTag }

Invoke-Pester -Configuration $config
