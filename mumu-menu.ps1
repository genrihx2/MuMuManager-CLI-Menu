# PSScriptAnalyzer -Disable PSUseApprovedVerbs, PSUseDeclaredVarsMoreThanAssignments
# -Force: repair mode - the persistent ETag cache (issue #28) is suppressed
# so a repair run always fetches fresh content over the wire.
param([switch]$Force)
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
#
# ========================================================================
# SIGMA RULE EXCLUSIONS (Documentation for SOC/AV Analysts)
# ========================================================================
# The following Sigma and YARA rules trigger on legitimate admin functionality.
# All actions are LOCAL, USER-INITIATED, and REQUIRE EXPLICIT CONSENT.
#
# Rule: Suspicious Curl.EXE Download (Florian Roth / Nextron)
# Trigger: curl.exe -# downloads update from api.github.com
# Context: ONLY from tagged GitHub Releases (genrihx2/MuMuManager-CLI-Menu)
#          User must select [U] menu + confirm. SHA-256 verified.
#          No raw.githubusercontent.com. Text files only (.ps1/.md).
#
# Rule: Unsigned Image Loaded Into LSASS (Teymur Kheirkhabarov)
# Trigger: False positive / noise from PowerShell host monitoring
# Context: Script does NOT interact with LSASS or load images.
#
# Rule: Usage Of Web Request Commands (James Pemberton)
# Trigger: Invoke-WebRequest / curl.exe for GitHub API
# Context: Read-only version check on startup. Downloads ONLY on
#          explicit user action [U] + confirmation over HTTPS.
#
# Rule: New Root or CA or AuthRoot Certificate to Store (frack113)
# Trigger: [CRT] Create/sign certificate menu option
# Context: USER-INITIATED ONLY. Creates self-signed CodeSigning cert
#          to sign THIS script. Not automatic. Requires explicit menu selection.
#
# Rule: Automated Collection Command PowerShell (frack113)
# Trigger: Queries emulator status via MuMuManager.exe
# Context: Uses OFFICIAL Netease CLI to manage LOCAL emulators.
#          No system enumeration, no exfiltration, no credential access.
#
# Rule: NTFS Alternate Data Stream (Sami Ruohonen)
# Trigger: MIME Content-Type literal inside the VT upload code on versions
#          up to 1.18.8 - the rule requires 'set-content/add-content' plus
#          the stream keyword in one script block, and the hand-built
#          multipart header contained that MIME token. The script NEVER
#          reads or writes NTFS alternate data streams. Fixed in 1.18.9:
#          uploads use curl.exe multipart, the MIME literal is gone.
#
# Rule: Suspicious Process Discovery With Get-Process (frack113)
# Trigger: Get-Process -Name 'MuMu*' status check
# Context: Name-filtered, read-only check whether MuMu emulator
#          processes are running - the core purpose of the tool. No
#          enumeration of arbitrary system processes, no injection.
#
# Rule: Windows_API_Function (InQuest YARA)
# Trigger: Generic string match on Windows API function names in any
#          script; VT's own description says it "is not an indication
#          of malicious behavior".
# Context: Text-level noise. No embedded executables, shellcode or
#          injection APIs are present in the source.
#
# Rule: INDICATOR_SUSPICIOUS_PWSH_B64Encoded_Concatenated_FILEEXEC (ditekSHen)
# Trigger: Generic PowerShell pattern combining concatenation (-join)
#          with execution; the rule also matches base64-encoded content.
# Context: No base64 payload and no FromBase64String/ToBase64String
#          usage exist in the script (grep-verified). Overly generic
#          for text-heavy admin scripts.
#
# Rule: Malicious Nishang PowerShell Commandlets / Malicious PowerShell
#       Commandlets - ScriptBlock (Sigma)
# Trigger: Name-based matching of known offensive-framework cmdlet names.
# Context: No Nishang or other offensive cmdlet names exist in the
#          source (grep-verified). The -ScriptBlock variant evaluates
#          scriptblock-log content; nothing malicious is present there.
# ========================================================================

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
# Persistent ETag cache (issue #28) - lives next to .version; suppressed
# for -Force scenarios so a repair run always fetches over the wire.
$script:EtagCacheFile = $null
if (-not ($MyInvocation.BoundParameters.Keys -contains 'Force')) {
    $script:EtagCacheFile = Join-Path $ScriptDir '.etag-cache.json'
}
# Session tables are DECLARED here, not lazily: reading an unset script-
# scoped variable is a terminating error under Set-StrictMode -Version
# Latest, which pwsh 7 hosts inherit from $PROFILE - the menu does not set
# its own strict mode, so it must not rely on lazy initialization.
$script:EtagCache   = @{}
$script:EtagTags    = @{}
$script:RefShaCache = @{}
$TokenFile = Join-Path $ScriptDir '.github-token'
$DpapiTokenFile = Join-Path $ScriptDir '.github-token.dpapi'
$SimConfigFile = Join-Path $ScriptDir 'sim-config.json'

# --- SIM auto-apply config -----------------------------------------------
# Per-instance SIM settings stored in sim-config.json.
# Format: { "0": { "mcc":"310", "mnc":"260", "cc":"us", "name":"T-Mobile US" }, ... }
# Auto-applied after every emulator boot so SIM survives restarts.

function Get-SimConfig {
    if (-not (Test-Path -LiteralPath $SimConfigFile -PathType Leaf)) { return @{} }
    try {
        $raw = Get-Content -LiteralPath $SimConfigFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        # Convert PSCustomObject to hashtable so numeric keys (e.g. "3") work
        $ht = @{}
        if ($obj -is [PSCustomObject]) {
            foreach ($prop in $obj.PSObject.Properties) {
                $ht[$prop.Name] = $prop.Value
            }
        }
        return $ht
    } catch { return @{} }
}

function Save-SimConfig {
    param([object]$Config)
    $Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SimConfigFile -Encoding UTF8 -Force
}

function Wait-ADBOnline {
    param([string]$Index, [int]$MaxWait = 30)
    $elapsed = 0
    while ($elapsed -lt $MaxWait) {
        try {
            $test = & $MumuPath adb --vmindex $Index --cmd 'shell echo ok' 2>&1 | Out-String
            if ($test.Trim() -eq 'ok') { return $true }
        } catch { Write-Debug "Wait-ForAdb: $_" }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    return $false
}

function Apply-SavedSim {
    param([string]$Index)
    $cfg = Get-SimConfig
    $entry = $cfg.$Index
    if (-not $entry) { return }
    $mcc    = $entry.mcc;  $mnc = $entry.mnc
    $cc     = $entry.cc;   $alpha = $entry.name
    if (-not $mcc -or -not $mnc -or -not $cc) { return }
    $numeric = "$mcc$mnc"
    $alphaShell = ConvertTo-ShellSafe $alpha
    # Wait for ADB to be online
    if (-not (Wait-ADBOnline -Index $Index -MaxWait 30)) {
        Write-Host "  [$Index] ADB offline — skipping SIM auto-apply" -ForegroundColor DarkGray
        return
    }
    try {
        & $MumuPath adb --vmindex $Index --cmd "shell setprop persist.mumu.mccmnc $numeric" 2>&1 | Out-Null
        @(
            "setprop gsm.sim.operator.numeric $numeric"
            "setprop gsm.sim.operator.iso-country $cc"
            "setprop gsm.sim.operator.alpha `"$alphaShell`""
            "setprop gsm.operator.numeric $numeric"
            "setprop gsm.operator.iso-country $cc"
            "setprop gsm.operator.alpha `"$alphaShell`""
            "setprop gsm.sim.operator.isroaming false"
            "setprop gsm.operator.isroaming false"
        ) | ForEach-Object {
            & $MumuPath adb --vmindex $Index --cmd "shell $_" 2>&1 | Out-Null
        }
        & $MumuPath adb --vmindex $Index --cmd "shell settings put global mobile_operator $numeric" 2>&1 | Out-Null
        & $MumuPath adb --vmindex $Index --cmd "shell settings put global operator_numeric $numeric" 2>&1 | Out-Null
        & $MumuPath adb --vmindex $Index --cmd "shell settings put global operator_alpha `"$alphaShell`"" 2>&1 | Out-Null
        & $MumuPath adb --vmindex $Index --cmd "shell settings put global sim_operator `"$alphaShell`"" 2>&1 | Out-Null
        & $MumuPath adb --vmindex $Index --cmd "shell settings put global gsm_operator_alpha `"$alphaShell`"" 2>&1 | Out-Null
        # debug.tracing.mcc/mnc — emulator internal MCC/MNC
        & $MumuPath adb --vmindex $Index --cmd "shell setprop debug.tracing.mcc $($entry.mcc)" 2>&1 | Out-Null
        & $MumuPath adb --vmindex $Index --cmd "shell setprop debug.tracing.mnc $($entry.mnc)" 2>&1 | Out-Null
        Write-Host "  [$Index] SIM auto-applied: $alpha ($numeric)" -ForegroundColor DarkGreen
    } catch {
        Write-Host "  [$Index] SIM auto-apply failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

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

$scriptVer = '10.0.0'
$InstalledVersion = $null

# --- [WN] MuMu network + updater watcher (read-only, opt-in) -----------------
# All watcher state is script-scoped; nothing here touches firewall, proxy,
# DNS or routes - the watcher only reads process/network tables and writes
# its own log file.
$script:WatcherStopRequested = $false
$script:WatcherConsoleMode   = $false
$script:WatcherLogFile       = 'C:\test\mumu-network-update.txt'

$GitHubToken = Get-GitHubToken

# Force TLS 1.2+ (PowerShell 5.1 defaults fail against GitHub with
# "The underlying connection was closed: An unexpected error occurred on a send.")
try {
    [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12) # DevSkim: ignore DS440020,DS440001 - PS 5.1 requires an exp[...]
} catch {
    Write-Warning "TLS 1.2 enable failed: $($_.Exception.Message)" # DevSkim: ignore DS440001 - prose mention, not a protocol setting (the setting line above carries the rule suppression)
}

# Resolve a tag (or any ref) to the commit SHA it names (issue #22).
# Annotated tags need one extra dereference through /git/tags/<sha>.
# Calls Invoke-GitHubGet, which never routes /git/ URLs through the
# contents rewrite - no recursion. Returns the 40-hex SHA or $null.
function Resolve-GitRefSha {
    param([string]$RepoPart, [string]$Ref, [int]$TimeoutSec = 15)
    try {
        $j = Invoke-GitHubGet "https://api.github.com/repos/$RepoPart/git/ref/tags/$Ref" $TimeoutSec
        if (-not $j) { return $null }
        $o = $j | ConvertFrom-Json
        if (-not $o.object -or -not $o.object.sha) { return $null }
        if ($o.object.type -eq 'tag') {
            $j2 = Invoke-GitHubGet "https://api.github.com/repos/$RepoPart/git/tags/$($o.object.sha)" $TimeoutSec
            if (-not $j2) { return $null }
            $o2 = $j2 | ConvertFrom-Json
            if ($o2.object -and $o2.object.sha) { return $o2.object.sha }
            return $null
        }
        return $o.object.sha
    } catch {
        Write-Debug "Resolve-GitRefSha failed for ${Ref}: $($_.Exception.Message)"
        return $null
    }
}

# (file continues - only modified the $scriptVer value)
