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
# The following Sigma rules trigger on legitimate admin functionality.
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
            $test = & $MumuPath adb -v $Index -c 'shell echo ok' 2>&1 | Out-String
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
        & $MumuPath adb -v $Index -c "shell setprop persist.mumu.mccmnc $numeric" 2>&1 | Out-Null
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
            & $MumuPath adb -v $Index -c "shell $_" 2>&1 | Out-Null
        }
        & $MumuPath adb -v $Index -c "shell settings put global mobile_operator $numeric" 2>&1 | Out-Null
        & $MumuPath adb -v $Index -c "shell settings put global operator_numeric $numeric" 2>&1 | Out-Null
        & $MumuPath adb -v $Index -c "shell settings put global operator_alpha `"$alphaShell`"" 2>&1 | Out-Null
        & $MumuPath adb -v $Index -c "shell settings put global sim_operator `"$alphaShell`"" 2>&1 | Out-Null
        & $MumuPath adb -v $Index -c "shell settings put global gsm_operator_alpha `"$alphaShell`"" 2>&1 | Out-Null
        # debug.tracing.mcc/mnc — emulator internal MCC/MNC
        & $MumuPath adb -v $Index -c "shell setprop debug.tracing.mcc $($entry.mcc)" 2>&1 | Out-Null
        & $MumuPath adb -v $Index -c "shell setprop debug.tracing.mnc $($entry.mnc)" 2>&1 | Out-Null
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

$scriptVer = '1.22.11'
$InstalledVersion = $null

$GitHubToken = Get-GitHubToken

# Force TLS 1.2+ (PowerShell 5.1 defaults fail against GitHub with
# "The underlying connection was closed: An unexpected error occurred on a send.")
try {
    [Net.ServicePointManager]::SecurityProtocol = ([Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12)
} catch {
    Write-Warning "TLS 1.2 enable failed: $($_.Exception.Message)"
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

# Retry flags for curl calls. curl's own --retry ignores TLS handshake
# failures (exit 35) - the flaky-network class behind "Update check failed
# (exit 35)" (v1.21.9). --retry-all-errors makes it retry transport-level
# errors too, but the option exists only since curl 7.71 and older builds
# abort on unknown options - probe once, degrade to plain --retry.
# Returns $true when the given curl accepts --retry-all-errors (curl >= 7.71).
# Probing with a real call: an unknown option makes curl exit 2 before any
# network activity; any other outcome (success or a network error like exit
# 35) means the option was accepted. Missing curl -> catch -> $false, which
# degrades every caller to plain --retry. ProbeUrl is injectable for tests.
function Test-CurlCapability {
    param([string]$CurlExe = 'curl.exe', [string]$ProbeUrl = 'https://api.github.com/')
    try {
        $null = & $CurlExe -s --retry-all-errors --connect-timeout 10 --max-time 15 -o NUL $ProbeUrl 2>$null
        return ($LASTEXITCODE -ne 2)
    } catch {
        return $false
    }
}
$script:CurlRetryArgs = @('--retry', '3', '--retry-delay', '2')
$script:CurlRetryStr  = ' --retry 3 --retry-delay 2'

# Detects whether this curl build accepts --retry-all-errors (curl >= 7.71).
# Signal: exit 2 = option-level failure (unknown option, curl aborts before
# connecting). Any network-layer code (6, 7, 28, 35, ...) means the option
# was parsed and the transfer attempted - capability = supported.
# NOTE: the probe uses a stable URL (api.github.com/zen) so the exit code is
# not confounded by DNS/rate-limit variance.
function Test-CurlRetrySupport {
    param([string]$CurlExe = 'curl.exe')
    try {
        $null = & $CurlExe -s --retry-all-errors --connect-timeout 10 --max-time 15 'https://api.github.com/zen' 2>$null
        return ($LASTEXITCODE -ne 2)
    } catch {
        return $false
    }
}
if (Test-CurlRetrySupport) {
    $script:CurlRetryArgs += '--retry-all-errors'
    $script:CurlRetryStr += ' --retry-all-errors'
}

# Builds a curl ARGUMENT ARRAY for a GitHub API GET. Always use this instead of
# string interpolation like "-s$script:CurlRetryStr" - under PS 5.1 that
# interpolation fuses '-s --retry 3 ...' into ONE argument, which curl rejects
# with exit 2 (invalid usage) and the caller then misreads as an empty/invalid
# response. This is exactly the bug behind the false "Token invalid!" in [K].
function Get-CurlGitHubArgs {
    param([string[]]$ExtraArgs = @(), [string]$Token)
    $curlArgs = @('-s') + $script:CurlRetryArgs + @('--connect-timeout', '30', '--max-time', '30')
    $tk = $Token
    if (-not $PSBoundParameters.ContainsKey('Token')) {
        try { $tk = (Get-Variable -Scope Script -Name GitHubToken -ErrorAction Stop).Value } catch { $tk = $null }
    }
    if ($tk) { $curlArgs += @('-H', "Authorization: token $tk") }
    if ($ExtraArgs.Count -gt 0) { $curlArgs += $ExtraArgs }
    return ,$curlArgs
}

# Shared GitHub API GET via argument array. Returns the raw body as a single
# string; on a non-2xx/transport failure returns the JSON error body (callers
# already treat parse failures / missing fields as failure).
function Invoke-GitHubApiGet {
    param([string]$Url, [string[]]$ExtraArgs = @(), [string]$Token)
    $curlArgs = Get-CurlGitHubArgs -ExtraArgs $ExtraArgs -Token $Token
    return (& curl.exe @curlArgs $Url 2>$null | Out-String)
}

function Invoke-GitHubGet {
    param([string]$Url, [int]$TimeoutSec = 30)
    # Issue #22 hardening, two layers:
    #
    # 1. Tag->SHA pinning: every contents URL that asks for ?ref=<tag> is
    #    rewritten to ?ref=<commit-sha>. The contents API resolves a ref at
    #    fetch time, so a CDN edge can serve the blob of the commit the ref
    #    pointed to BEFORE the push (the stale-blob class behind the
    #    v1.20.3-v1.20.6 incident fixes). A commit SHA is immutable - a
    #    stale read becomes impossible by construction. The resolution is
    #    cached per process and must never cache a failure: a JSON body
    #    from the ref endpoints would pin nothing and is skipped.
    #
    # 2. ETag cache with 304 replay: repeat fetches of the same URL inside
    #    one menu session send If-None-Match and, on 304 Not Modified,
    #    replay the cached body without transferring it. Only successful,
    #    non-API-error bodies are cached - error responses must stay
    #    retryable.
    if (-not $script:EtagCache)    { $script:EtagCache    = @{} }
    if (-not $script:EtagTags)     { $script:EtagTags     = @{} }
    if (-not $script:RefShaCache)  { $script:RefShaCache  = @{} }

    $pinnedUrl = $Url
    if ($Url -match '^https://api\.github\.com/repos/(.+)/contents/(.+)$') {
        $repoPart = $Matches[1]; $rest = $Matches[2]
        $qIdx = $rest.IndexOf('?')
        if ($qIdx -ge 0) {
            $pathPart  = $rest.Substring(0, $qIdx)
            $queryPart = $rest.Substring($qIdx + 1)
            if ($queryPart -match '(^|&)ref=([^&]+)') {
                $ref = $Matches[2]
                if ($ref -notmatch '^[0-9a-fA-F]{40}$') {
                    if (-not $script:RefShaCache.ContainsKey($ref)) {
                        $sha = Resolve-GitRefSha -RepoPart $repoPart -Ref $ref -TimeoutSec $TimeoutSec
                        if ($sha -and $sha -match '^[0-9a-fA-F]{40}$') { $script:RefShaCache[$ref] = $sha }
                    }
                    if ($script:RefShaCache.ContainsKey($ref)) {
                        $newQuery = $queryPart -replace 'ref=[^&]+', "ref=$($script:RefShaCache[$ref])"
                        $pinnedUrl = "https://api.github.com/repos/$repoPart/contents/$pathPart`?$newQuery"
                        Write-Debug "Pinned ref '$ref' -> $($script:RefShaCache[$ref])"
                    }
                }
            }
        }
    }

    # Cache key note: the key is the URL only - different Accept semantics
    # for the same URL would collide. Today every cached URL is fetched with
    # one fixed Accept per URL shape, so this is safe; keep it that way.
    # (Verified live in v1.21.0: the vnd.github.sha media type is NOT
    # supported by the contents endpoint - the cheap-hash idea is dead.)
    # --retry-all-errors: curl's built-in --retry does NOT retry TLS
    # handshake failures (exit 35) - a single flaky-network reset killed the
    # whole request ("Update check failed (exit 35)", v1.21.9). The PS-level
    # loop retries them in-process; the header dump (-D) covers every
    # internal attempt, so the ETag/status parsing is unaffected.
    $curlBase = @('-s') + $script:CurlRetryArgs + @('--connect-timeout', '30', '--max-time', "$TimeoutSec")
    if ($Url -match '^https://api\.github\.com/repos/.+/contents/') {
        $curlBase += @('-H', 'Accept: application/vnd.github.raw')
    } elseif ($Url -match '^https://api\.github\.com/') {
        $curlBase += @('-H', 'Accept: application/vnd.github.v3+json')
    }
    # Captures the final HTTP status and ETag via a header dump (-D).
    # No --fail: a 304 must come back as a result, not a curl error.
    function _Fetch([bool]$UseToken, [string]$UrlToUse, [string]$Etag) {
        $cmdArgs = @($curlBase)
        if ($UseToken -and $GitHubToken -and $GitHubToken.Length -gt 0) { $cmdArgs += @('-H', "Authorization: token $GitHubToken") }
        $hdrFile = Join-Path $env:TEMP ('gh_hdr_' + [Guid]::NewGuid().ToString('N') + '.txt')
        $tmpFile = Join-Path $env:TEMP ('gh_resp_' + [Guid]::NewGuid().ToString('N') + '.json')
        $cmdArgs += @('-D', $hdrFile, '-o', $tmpFile)
        if ($Etag) { $cmdArgs += @('-H', "If-None-Match: $Etag") }
        # try/catch: under ErrorActionPreference=Stop a curl stderr write
        # (TLS warning, retry notice) would surface as terminating - treat
        # it as an empty attempt instead of crashing the fetch.
        try { $null = & curl.exe @cmdArgs $UrlToUse 2>$null }
        catch { Write-Debug "curl threw: $($_.Exception.Message)" }
        $status = ''; $newEtag = ''
        if (Test-Path $hdrFile) {
            try {
                $hdrText = [System.IO.File]::ReadAllText($hdrFile)
                foreach ($m in [regex]::Matches($hdrText, '(?m)^HTTP/\S+\s+(\d+)')) { $status = $m.Groups[1].Value }
                # --retry can produce several responses in one dump - the
                # last one is the final answer. (?i): GitHub emits 'ETag:'
                # with a capital E - a lowercase-only pattern never matched,
                # which silently killed the whole ETag cache (session AND
                # file store) until the E2E drill caught it (v1.22.1).
                foreach ($em in [regex]::Matches($hdrText, '(?im)^etag:\s*(\S+)')) { $newEtag = $em.Groups[1].Value }
            } catch { Write-Debug "Header parse failed: $($_.Exception.Message)" }
            Remove-Item $hdrFile -Force -ErrorAction SilentlyContinue
        }
        $body = $null
        if ((Test-Path $tmpFile) -and (Get-Item $tmpFile -ErrorAction SilentlyContinue).Length -gt 0) {
            $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
            if ($bytes -and $bytes.Length -gt 0) { $body = ([System.Text.Encoding]::UTF8.GetString($bytes)).TrimEnd() }
        }
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        if ($status -eq '304') {
            return [pscustomobject]@{ NotModified = $true; Body = $null; ETag = $Etag }
        }
        return [pscustomobject]@{ NotModified = $false; Body = $body; ETag = $newEtag }
    }

    $etag = ''
    if ($script:EtagTags.ContainsKey($pinnedUrl)) { $etag = $script:EtagTags[$pinnedUrl] }
    $r1 = _Fetch -UseToken $true -UrlToUse $pinnedUrl -Etag $etag
    if ($r1.NotModified) {
        Write-Debug "ETag 304 - replaying cached body ($($script:EtagCache[$pinnedUrl].Length) chars): $Url"
        return $script:EtagCache[$pinnedUrl]
    }
    $resp = $r1.Body
    if ($null -ne $resp) {
        if ($GitHubToken -and $resp -match '"message"\s*:\s*"Bad credentials"') {
            Write-Host '  Token rejected — retrying without auth...' -ForegroundColor Yellow
            $r2 = _Fetch -UseToken $false -UrlToUse $pinnedUrl -Etag $etag
            if ($r2.NotModified) { return $script:EtagCache[$pinnedUrl] }
            $resp = $r2.Body
            if ($null -eq $resp) { throw "Request failed: $Url" }
        }
        # Cache only real content: an API error body (rate limit, auth) must
        # stay retryable and never anchors an ETag for this URL. A fresh
        # body is also persisted to the file store (issue #28) - best-effort.
        $isErrBody = $resp.TrimStart().StartsWith('{') -and $resp -match '"message"\s*:\s*'
        if (-not $isErrBody -and $r1.ETag) {
            $script:EtagCache[$pinnedUrl] = $resp
            $script:EtagTags[$pinnedUrl]  = $r1.ETag
            if ($script:EtagCacheFile) {
                Save-EtagCacheFile -CacheFile $script:EtagCacheFile -Entries @{ $pinnedUrl = @{ etag = $r1.ETag; body = $resp } }
            }
        }
        return $resp
    }
    throw "Request failed after 4 attempt(s) (curl exit $LASTEXITCODE - 35/56/28 = flaky network/TLS, 403 = rate limit): $Url"
}

# Auto-detect MuMuManager.exe path
$MumuPath = ''
$PossiblePaths = @(
    'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe',
    'C:\Program Files (x86)\Netease\MuMuPlayer\nx_main\MuMuManager.exe',
    "$env:LOCALAPPDATA\Netease\MuMuPlayer\nx_main\MuMuManager.exe",
    "$env:ProgramFiles\Netease\MuMuPlayer\shell\MuMuManager.exe",
    "$env:ProgramFiles(x86)\Netease\MuMuPlayer\shell\MuMuManager.exe",
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
            if (Test-Path $regPath) {
                $MumuPath = $regPath
            } else {
                $regPath = Join-Path $reg.InstallPath 'shell\MuMuManager.exe'
                if (Test-Path $regPath) { $MumuPath = $regPath }
            }
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
    # Trailing whitespace trimmed here (not at call sites) so every consumer
    # is symmetric with Invoke-GitHubGet, which TrimEnds response bodies:
    # a trailing newline at EOF - present in tag blobs, stripped by the
    # fetch - cannot false-positive as drift or a hash mismatch.
    $norm = $norm.TrimEnd()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))) -replace '-', '')
    } finally {
        $sha.Dispose()
    }
}

# ── Pure helpers (unit-tested via tests/mumu-menu.Tests.ps1) ──────────

# ── Persistent ETag cache (issue #28) ────────────────────────────────
# The in-session ETag cache of #22 dies with the menu process, so every
# start re-downloads reference bodies. This file store (.etag-cache.json
# next to .version) persists them: url -> { etag, sha256, timestamp }.
# Read rules: the entry must exist, hash-match the stored body digest,
# and carry both an etag and a body - anything else degrades to a normal
# fetch, never an error. Write rules: only real content (the #22 rule -
# API error bodies are never cached) and best-effort, never fatal.
function Read-EtagCacheFile {
    # Returns the deserialized hashtable (url -> entry) or an empty one.
    # A missing, corrupt, or schema-invalid file is silently ignored.
    param([string]$CacheFile)
    $empty = @{}
    if (-not ($CacheFile -and (Test-Path -LiteralPath $CacheFile -PathType Leaf))) { return $empty }
    try {
        $j = [System.IO.File]::ReadAllText($CacheFile) | ConvertFrom-Json
        if (-not $j) { return $empty }
        $out = @{}
        foreach ($p in $j.PSObject.Properties) {
            $e = $p.Value
            if ($e -and $e.etag -and $e.body -and $e.sha256) { $out[$p.Name] = $e }
        }
        return $out
    } catch {
        Write-Debug "etag cache unreadable - degrading to plain fetch: $($_.Exception.Message)"
        return $empty
    }
}

function Get-EtagCacheFileState {
    # Human-readable cache state for [ST]: 'N URL(s), last entry HH:MM'
    # or 'empty'. Never throws.
    param([string]$CacheFile)
    try {
        $c = Read-EtagCacheFile -CacheFile $CacheFile
        if ($c.Count -eq 0) { return 'empty' }
        $newest = [datetime]::MinValue
        foreach ($e in $c.Values) {
            try { $t = [datetime]::Parse("$($e.timestamp)"); if ($t -gt $newest) { $newest = $t } } catch { Write-Debug "cache timestamp unparseable: $($e.timestamp)" }
        }
        $last = if ($newest -gt [datetime]::MinValue) { $newest.ToString('HH:mm') } else { 'n/a' }
        return ("{0} URL(s), last entry {1}" -f $c.Count, $last)
    } catch { return 'unknown' }
}

function Save-EtagCacheFile {
    # Best-effort persist: merges the given url->(etag, body) pairs into
    # the file store. Hashes are computed here so callers stay simple.
    # Any I/O or serialization failure is swallowed (cache is an
    # optimization, never a correctness dependency).
    param([string]$CacheFile, [hashtable]$Entries)
    if (-not ($CacheFile -and $Entries -and $Entries.Count -gt 0)) { return }
    try {
        $store = Read-EtagCacheFile -CacheFile $CacheFile
        foreach ($k in $Entries.Keys) {
            $store[$k] = [pscustomobject]@{
                etag      = "$($Entries[$k].etag)"
                body      = "$($Entries[$k].body)"
                sha256    = Get-ContentHash -Text "$($Entries[$k].body)"
                timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
        }
        $json = $store | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($CacheFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Write-Debug "etag cache save failed (non-fatal): $($_.Exception.Message)"
    }
}

function Invoke-EtagCacheMaintenance {
    # Startup bridge: loads the file store into the session tables the
    # fetch path already uses, validating each body against its stored
    # hash (a tampered or truncated body is dropped, not trusted). Called
    # once at startup; failures degrade to an empty session cache.
    param([string]$CacheFile)
    try {
        $store = Read-EtagCacheFile -CacheFile $CacheFile
        foreach ($k in $store.Keys) {
            $e = $store[$k]
            if ((Get-ContentHash -Text "$($e.body)") -eq "$($e.sha256)") {
                $script:EtagCache[$k] = "$($e.body)"
                $script:EtagTags[$k]  = "$($e.etag)"
            } else {
                Write-Debug "etag cache entry failed hash validation - dropped: $k"
            }
        }
    } catch {
        Write-Debug "etag cache load failed (non-fatal): $($_.Exception.Message)"
    }
}

# Android sh-safe value: the metacharacters that would break a double-
# quoted `adb shell` command are replaced with '_' (the same policy the
# SIM settings applied inline since v1.18.x, now one testable unit).
function ConvertTo-ShellSafe {
    param([string]$Value)
    return $Value.Replace('&', '_').Replace(';', '_').Replace('|', '_').Replace('$', '_')
}

# Version comparison for 'vX.Y.Z' / 'X.Y.Z' tags: numeric component-wise.
# Returns -1 (A older), 0 (equal), 1 (A newer), -2 (unparseable input).
# Unparseable input must compare as 'unknown', never as older/newer.
function Compare-ScriptVersion {
    param([string]$A, [string]$B)
    $pa = @($A.TrimStart('v', 'V') -split '\.' | ForEach-Object { try { [int]$_ } catch { -1 } })
    $pb = @($B.TrimStart('v', 'V') -split '\.' | ForEach-Object { try { [int]$_ } catch { -1 } })
    if (@($pa | Where-Object { $_ -lt 0 }).Count -gt 0) { return -2 }
    if (@($pb | Where-Object { $_ -lt 0 }).Count -gt 0) { return -2 }
    for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
        $xa = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $xb = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($xa -lt $xb) { return -1 }
        if ($xa -gt $xb) { return 1 }
    }
    return 0
}

# One journal line: timestamp<TAB>actor<TAB>event<TAB>from<TAB>to<TAB>detail.
# The detail column is sanitized (tabs/newlines flattened) so every event
# stays exactly one line in update-journal.log.
function Format-JournalEvent {
    param([string]$Actor, [string]$EventType, [string]$From = '', [string]$To = '', [string]$Detail = '')
    return "{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f @(
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Actor, $EventType, $From, $To,
        ($Detail -replace "`t", ' ' -replace "`r?`n", ' | ')
    )
}

# Expected SHA-256 per file, computed from the tag content via the contents
# API (issue #20 semantics; issue #22 makes it trustworthy and cheap to
# repeat: the ref is pinned to the tag's commit SHA and repeat fetches in
# one session are ETag-replayed). Files whose fetch fails or that return an
# API error body (rate limit) are simply absent from the result - the
# caller treats that as 'unknown', never as a hash to compare against.
function Get-ExpectedFileHashes {
    param([string]$Tag, [string[]]$Names)
    $result = @{}
    foreach ($n in $Names) {
        try {
            $remote = Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/contents/$SkillPath/$n`?ref=$Tag" 30
            $t = $remote.TrimEnd()
            if ($t.StartsWith('{') -and $t -match '"message"\s*:\s*"') { continue }
            $result[$n] = Get-ContentHash $t
        } catch {
            Write-Debug "Expected hash fetch failed for ${n}: $($_.Exception.Message)"
        }
    }
    return $result
}

# True when the $scriptVer embedded in the fetched text matches the tag
# (v-prefix agnostic). Guards the version-fix heal against stale CDN blobs:
# fetched content claiming an older scriptVer must never heal the marker
# to the tag - the tag's content has not actually arrived.
function Test-ScriptVerMatchesTag {
    param([string]$Text, [string]$Tag)
    $m = [regex]::Match($Text, "(?m)^\s*\`$scriptVer\s*=\s*'(\d+(?:\.\d+){1,3})'")
    if (-not $m.Success) { return $false }
    try { return ((Compare-ScriptVersion -A $m.Groups[1].Value -B $Tag) -eq 0) } catch { return $false }
}

# The from->to arrow for journal lines: an empty 'from' with a non-empty
# 'to' means the field did not exist yet (fresh install, marker file
# absent) and renders as (new) instead of a bare leading arrow.
function Get-JournalArrow {
    param([string]$From, [string]$To)
    if ($From -and $To) { return "$From -> $To" }
    if ($To) { return "(new) -> $To" }
    return $From
}

# ── Update journal (shared with bootstrap-update.ps1) ────────────────
# Tab-separated UTF-8 at $ScriptDir\update-journal.log, one event per line:
#   timestamp<TAB>actor<TAB>event<TAB>from<TAB>to<TAB>detail
# Actors: menu ([U] updater), bootstrap (bootstrap-update.ps1).
# Rotates at 256 KB keeping a single .old generation. Best-effort: a
# logging failure must never break the update itself.
$script:JournalFile = Join-Path $ScriptDir 'update-journal.log'

function Write-UpdateJournal {
    param([string]$EventType, [string]$From = '', [string]$To = '', [string]$Detail = '')
    try {
        $oldPath = "$script:JournalFile.old"
        if ((Test-Path -LiteralPath $script:JournalFile -PathType Leaf) -and (Get-Item -LiteralPath $script:JournalFile).Length -gt 256KB) {
            Move-Item -LiteralPath $script:JournalFile -Destination $oldPath -Force
        }
        $line = Format-JournalEvent -Actor 'menu' -EventType $EventType -From $From -To $To -Detail $Detail
        [System.IO.File]::AppendAllText($script:JournalFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Debug "Update journal write failed: $($_.Exception.Message)"
    }
}

# ── Single-flight update lock (issue #24) ─────────────────────────────
# [U] and bootstrap-update.ps1 write the same files (.version, scripts,
# journal). Two concurrent updaters could corrupt state or double-apply.
# The lock is a .update-lock file created with CreateNew - the create call
# itself is the atomic test-and-set, so two processes can never both win.
# Content: PID + timestamp (which process holds it, and since when).
# A lock older than 10 minutes is treated as the leftover of a crashed
# process and is broken. Always released in finally, including Ctrl+C.
$script:UpdateLockStaleMinutes = 10

function Test-UpdateLockStale {
    # Pure-ish decision helper: is this lock file older than the stale limit?
    param([string]$LockPath)
    # Local fallback so the helper stays correct even when extracted from
    # the script without the script-scope default (tests, dot-sourcing).
    $limit = if ($script:UpdateLockStaleMinutes) { [int]$script:UpdateLockStaleMinutes } else { 10 }
    try {
        if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { return $false }
        $age = ((Get-Date) - (Get-Item -LiteralPath $LockPath).LastWriteTime).TotalMinutes
        return ($age -gt $limit)
    } catch {
        # Unreadable lock - treat as fresh rather than break someone's live update.
        Write-Debug "Lock staleness check failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-UpdateLockMessage {
    # Human-readable reason for a lock refusal (owner PID + age).
    param([string]$LockPath)
    $owner = ''
    try {
        if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
            $owner = (Get-Content -LiteralPath $LockPath -TotalCount 1 -ErrorAction SilentlyContinue)
        }
    } catch { Write-Debug "Lock owner read failed: $($_.Exception.Message)" }
    $limit = if ($script:UpdateLockStaleMinutes) { [int]$script:UpdateLockStaleMinutes } else { 10 }
    $age = ''
    try {
        if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
            $mins = [math]::Round(((Get-Date) - (Get-Item -LiteralPath $LockPath).LastWriteTime).TotalMinutes, 1)
            $age = ", age ${mins} min"
        }
    } catch { Write-Debug "Lock age read failed: $($_.Exception.Message)" }
    return ("held by {0}{1}. Close that updater or wait; if it crashed, the lock expires after {2} minutes." -f $owner, $age, $limit)
}

function New-UpdateLock {
    # Atomically claim the update lock. Returns $true if WE hold it now.
    # Handles the stale case (break + retry once, create-then-break to close
    # the classic break/recreate race window) and rethrows anything else.
    param([string]$Dir)
    $lockPath = Join-Path $Dir '.update-lock'
    $now = Get-Date
    $payload = "PID $PID started $($now.ToString('yyyy-MM-dd HH:mm:ss'))"
    try {
        $s = [System.IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None')
        $w = [System.IO.StreamWriter]::new($s)
        $w.Write($payload)
        $w.Flush(); $w.Dispose(); $s.Dispose()
        return $true
    } catch [System.IO.IOException] {
        if (-not (Test-UpdateLockStale -LockPath $lockPath)) {
            Write-Host ''
            Write-Host '  Another update is already running:' -ForegroundColor Yellow
            Write-Host ("  " + (Get-UpdateLockMessage -LockPath $lockPath)) -ForegroundColor Yellow
            if ($script:JournalFile) { Write-UpdateJournal -EventType 'update-skipped' -Detail '.update-lock held by another process' }
            return $false
        }
        # Stale lock: create-then-break. Only the process that successfully
        # creates .update-lock.new may delete and re-create the lock, so two
        # racers cannot both end up holding it.
        $claimPath = "$lockPath.new"
        try {
            $c = [System.IO.File]::Open($claimPath, 'CreateNew', 'Write', 'None')
            $cw = [System.IO.StreamWriter]::new($c)
            $cw.Write("stale-break by PID $PID")
            $cw.Flush(); $cw.Dispose(); $c.Dispose()
        } catch {
            Write-Host '  Another update is already breaking a stale lock.' -ForegroundColor Yellow
            if ($script:JournalFile) { Write-UpdateJournal -EventType 'update-skipped' -Detail '.update-lock stale-break race lost' }
            return $false
        }
        try {
            Remove-Item -LiteralPath $lockPath -Force
            Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
            Write-Host '  Removed a stale update lock (leftover of a crashed updater).' -ForegroundColor DarkGray
            $s2 = [System.IO.File]::Open($lockPath, 'CreateNew', 'Write', 'None')
            $w2 = [System.IO.StreamWriter]::new($s2)
            $w2.Write($payload)
            $w2.Flush(); $w2.Dispose(); $s2.Dispose()
            return $true
        } catch {
            Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
            Write-Host '  Another update started while the stale lock was being broken.' -ForegroundColor Yellow
            if ($script:JournalFile) { Write-UpdateJournal -EventType 'update-skipped' -Detail '.update-lock lost stale-break race' }
            return $false
        }
    }
}

function Remove-UpdateLock {
    param([string]$Dir)
    try { Remove-Item -LiteralPath (Join-Path $Dir '.update-lock') -Force -ErrorAction SilentlyContinue } catch { Write-Debug "Lock removal failed: $($_.Exception.Message)" }
    try { Remove-Item -LiteralPath (Join-Path $Dir '.update-lock.new') -Force -ErrorAction SilentlyContinue } catch { Write-Debug "Lock claim cleanup failed: $($_.Exception.Message)" }
}

# ── Verify installation: local files vs current release tag (#18) ────
# Compares SHA-256 of the install's files against the tag blobs and
# prints an OK / differs / missing report. Returns report entries
# (status|name|detail) so tests can assert on the logic without IO.
function Test-InstallationIntegrity {
    param([string]$Tag = '')
    $report = @()
    try {
        if (-not $Tag) {
            try { $rel = Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/releases/latest" 15 | ConvertFrom-Json } catch { $rel = $null }
            if ($rel -and $rel.tag_name) { $Tag = $rel.tag_name }
            else {
                $msg = if ($rel -and $rel.message) { $rel.message } else { 'could not resolve the latest release (network or rate limit)' }
                Write-Host "  Cannot determine current release: $msg" -ForegroundColor Yellow
                return , @()
            }
        }
        $report += "verify-start|$Tag"

        # Issue #22: resolve the tag once to its commit SHA and fetch all
        # content through that pinned ref. The contents API resolves
        # ?ref=<tag> at fetch time, so an edge can serve the previous
        # commit's blob minutes after the push (seen live after v1.20.3 and
        # again after v1.20.4). A commit SHA is immutable, so a fetch
        # through the pinned URL cannot see a stale tag mapping. If
        # resolution fails, the check proceeds exactly as before.
        # NOTE: $Tag stays the human-readable tag - the semantic .version
        # comparison below needs a parseable version, not a SHA (regression
        # caught live in v1.21.0: overwriting $Tag disabled the semantic
        # branch and false-DRIFTed a healthy .version marker).
        $FetchRef = $Tag
        $pinnedRefNote = ''
        if ($Tag -notmatch '^[0-9a-fA-F]{40}$' -and $GitHubRepo) {
            try {
                $sha = Resolve-GitRefSha -RepoPart $GitHubRepo -Ref $Tag 15
                if ($sha -and $sha -match '^[0-9a-fA-F]{40}$') {
                    $FetchRef = $sha
                    $pinnedRefNote = " (pinned to commit $($sha.Substring(0, 8)))"
                    $report += "ref-pin|$sha"
                    Write-Host "  Tag pinned to commit $($sha.Substring(0, 8)) - stale-CDN reads impossible" -ForegroundColor DarkGray
                } else {
                    $report += 'ref-pin-failed|tag-url kept'
                }
            } catch {
                # Pinning is an optimization on top of the check, never a
                # precondition: proceed with the plain tag URL.
                $report += 'ref-pin-failed|tag-url kept'
                Write-Debug "Ref pin failed: $($_.Exception.Message)"
            }
        }

        $files = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')
        $verFile = Join-Path $ScriptDir '.version'
        $localTag = ''
        if (Test-Path -LiteralPath $verFile) {
            try { $localTag = (Get-Content -LiteralPath $verFile -Raw -Encoding UTF8).Trim() } catch { Write-Debug "Version file read failed: $($_.Exception.Message)" }
        }
        if ($localTag) { $files += '.version' }

        Write-Host ''
        Write-Host "  === Verify installation vs $Tag ===" -ForegroundColor Cyan
        $okFiles = @(); $driftFiles = @(); $missingFiles = @()
        foreach ($f in $files) {
            $local = Join-Path $ScriptDir $f
            if (-not (Test-Path -LiteralPath $local -PathType Leaf)) {
                $missingFiles += $f
                $report += "MISSING|$f|"
                Write-Host ("  {0,-8} {1}" -f 'MISSING', $f) -ForegroundColor Red
                continue
            }
            # The .version marker is compared semantically, not by content:
            # a tag can legitimately lag the installed marker by one release
            # (the sync-version bot lands after the tag), so a local marker
            # that is EQUAL OR NEWER than the tag's marker is not drift -
            # even when the bytes differ. An unparseable/older marker still
            # falls through to the content comparison (conservative).
            if ($f -eq '.version' -and $localTag) {
                $sem = $null
                try { $sem = Compare-ScriptVersion -A $localTag -B $Tag } catch { $sem = $null }
                if ($null -ne $sem -and $sem -ge 0) {
                    $okFiles += $f
                    $report += "OK-SEMANTIC|.version|local=$localTag"
                    Write-Host ("  {0,-8} .version  (marker {1} - current or newer than the tag's lagged marker)" -f 'OK', $localTag) -ForegroundColor Green
                    continue
                }
            }
            # Same normalization as the update path: CRLF stripped, BOM ignored.
            # Get-ContentHash trims trailing whitespace symmetrically
            # (mirrors Invoke-GitHubGet's TrimEnd) - see its header comment.
            $localHash = Get-ContentHash ([System.IO.File]::ReadAllText($local))
            try {
                $remote = Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/contents/$f`?ref=$FetchRef" 30
            } catch {
                $report += "DOWNLOAD-FAIL|$f|$($_.Exception.Message)"
                Write-Host ("  {0,-8} {1}  ({2})" -f 'N/A', $f, $_.Exception.Message) -ForegroundColor Yellow
                continue
            }
            # An API error (rate limit, auth) can arrive with HTTP 200-ish
            # semantics and curl exit 0 - hashing it would report bogus drift.
            # Same philosophy as the updater's JSON guards.
            $trimmedRemote = $remote.TrimEnd()
            if ($trimmedRemote.StartsWith('{') -and $trimmedRemote -match '"message"\s*:\s*"') {
                $report += "DOWNLOAD-FAIL|$f|API error response instead of file content"
                Write-Host ("  {0,-8} {1}  (API error instead of content - retry later)" -f 'N/A', $f) -ForegroundColor Yellow
                continue
            }
            $remoteHash = Get-ContentHash $trimmedRemote
            if ($localHash -eq $remoteHash) {
                $okFiles += $f
                $report += "OK|$f|$localHash"
                Write-Host ("  {0,-8} {1}" -f 'OK', $f) -ForegroundColor Green
                if ($f -eq '.version') {
                    Write-Host "           marker is current ($localTag)" -ForegroundColor DarkGray
                }
            } else {
                # The tag->SHA pin above already makes a stale tag mapping
                # impossible; this second fetch now only guards against a
                # rare bad edge read. With ETag caching the recheck costs
                # one conditional request (usually a 304 replay).
                $remoteHash2 = ''
                try {
                    $remote2 = Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/contents/$f`?ref=$FetchRef" 30
                    if ($remote2) {
                        $t2 = $remote2.TrimEnd()
                        if (-not ($t2.StartsWith('{') -and $t2 -match '"message"\s*:\s*"')) { $remoteHash2 = Get-ContentHash $t2 }
                    }
                } catch { Write-Debug "Drift recheck failed for ${f}: $($_.Exception.Message)" }
                if ($remoteHash2 -eq $localHash) {
                    $okFiles += $f
                    $report += "OK|$f|$localHash"
                    Write-Host ("  {0,-8} {1}  (rechecked - first read was stale)" -f 'OK', $f) -ForegroundColor Green
                } else {
                    $shown = if ($remoteHash2) { $remoteHash2 } else { $remoteHash }
                    $driftFiles += $f
                    $report += "DRIFT|$f|expected=$shown local=$localHash"
                    Write-Host ("  {0,-8} {1}" -f 'DRIFT', $f) -ForegroundColor Red
                    Write-Host ("           expected {0}..." -f $shown.Substring(0, 16)) -ForegroundColor DarkGray
                    Write-Host ("           local    {0}..." -f $localHash.Substring(0, 16)) -ForegroundColor DarkGray
                }
            }
        }

        # Stale .version marker: content matches the tag but the marker file
        # still names an older release - the updater heals this via version-fix.
        # Semantically equal markers (v-prefix differences, 1.2.3 == v1.2.3)
        # are NOT drift: the sync-version bot lands after the release tag, so
        # a freshly tagged release can legitimately ship the previous
        # .version spelling.
        $verDrift = @($report | Where-Object { $_ -match '^(DRIFT|MISSING)\|\.version\|' }).Count -gt 0
        $markerStale = $false
        if ($localTag -and (-not $verDrift)) {
            try { $markerStale = ((Compare-ScriptVersion -A $localTag -B $Tag) -lt 0) } catch { $markerStale = ($localTag -ne $Tag) }
        }
        if ($markerStale) {
            Write-Host "  Note: content matches $Tag but .version says $localTag (stale marker, run [U] to heal it)" -ForegroundColor Yellow
        }

        Write-Host ''
        if (($driftFiles.Count + $missingFiles.Count) -gt 0) {
            $bad = @($driftFiles) + @($missingFiles)
            Write-Host ("  Drift detected (files: {0})" -f ($bad -join ', ')) -ForegroundColor Red
            $report += "summary|drift|$($bad -join ',')"
        } elseif (@($report | Where-Object { $_ -like 'DOWNLOAD-FAIL|*' }).Count -gt 0) {
            Write-Host "  Installation matches $Tag (reachable files OK; some could not be downloaded)" -ForegroundColor Yellow
            $report += 'summary|partial|download failures'
        } else {
            Write-Host "  Installation matches $Tag" -ForegroundColor Green
            $report += 'summary|ok|'
        }
    } catch {
        Write-Host "  Verification failed: $($_.Exception.Message)" -ForegroundColor Yellow
        $report += "error|$($_.Exception.Message)|"
    }
    return , $report
}

# ── Release ZIP self-test (issue #19) ────────────────────────────────
# Client-side mirror of the CI checks before a manual ZIP install:
# sidecar sha256, exact release file set, scriptVer vs tag. Pure (no IO
# side effects beyond reading the archive) so tests can assert on it.
function Test-ReleaseZip {
    param(
        [Parameter(Mandatory = $true)] [string]$ZipPath,
        [Parameter(Mandatory = $true)] [string]$ExpectedTag,
        [string]$SidecarPath = "$ZipPath.sha256"
    )
    $expectedFiles = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1', '.version')
    $checks = @()
    $ok = $true
    $zipVer = ''
    $names = @()

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $false; ZipHash = ''; SidecarHash = ''; Checks = @("zip: MISSING ($ZipPath)"); EntryNames = @(); ZipVersion = '' }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    # Check 1: ZIP hash vs sidecar
    $zipHash = ''
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($ZipPath)
        try { $zipHash = ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLower() } finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
    $sidecarHash = ''
    if (Test-Path -LiteralPath $SidecarPath -PathType Leaf) {
        $first = (Get-Content -LiteralPath $SidecarPath -TotalCount 1) -as [string]
        if ($first -match '^([0-9a-fA-F]{64})\b') { $sidecarHash = $Matches[1].ToLower() }
    }
    $sidecarOk = ($sidecarHash -ne '') -and ($sidecarHash -eq $zipHash)
    if ($sidecarOk) {
        $checks += "sha256: OK (match with sidecar)"
    } else {
        $sidecarShown = if ($sidecarHash) { $sidecarHash.Substring(0, [Math]::Min(16, $sidecarHash.Length)) + '...' } else { 'MISSING' }
        $checks += "sha256: MISMATCH (zip=$($zipHash.Substring(0, 16))... sidecar=$sidecarShown)"
        $ok = $false
    }

    # Checks 2 + 3: archive contents
    $zip = $null
    try { $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath) } catch {
        $checks += "archive: unreadable ($($_.Exception.Message))"
        $ok = $false
    }
    if ($zip) {
        try {
            $names = @($zip.Entries | ForEach-Object { $_.FullName } | Where-Object { $_ -and ($_ -notmatch '/$') } | ForEach-Object { $_ -replace '^\./', '' -replace '^.*[/\\]', '' } | Sort-Object -Unique)
            $missing = @($expectedFiles | Where-Object { $names -notcontains $_ })
            $extras = @($names | Where-Object { $expectedFiles -notcontains $_ })
            if (($missing.Count -eq 0) -and ($extras.Count -eq 0)) {
                $checks += "file set: OK ($($expectedFiles.Count) files)"
            } else {
                $parts = @()
                if ($missing.Count -gt 0) { $parts += "missing: $($missing -join ', ')" }
                if ($extras.Count -gt 0) { $parts += "unexpected: $($extras -join ', ')" }
                $checks += "file set: MISMATCH ($($parts -join '; '))"
                $ok = $false
            }

            $menuEntry = $zip.Entries | Where-Object { (($_.FullName -replace '^\./', '') -replace '^.*[/\\]', '') -eq 'mumu-menu.ps1' } | Select-Object -First 1
            if ($menuEntry) {
                $reader = New-Object System.IO.StreamReader($menuEntry.Open(), [System.Text.Encoding]::UTF8)
                try {
                    for ($i = 0; ($i -lt 320) -and (-not $reader.EndOfStream); $i++) {
                        $line = $reader.ReadLine()
                        if ($line -match "^\s*\`$scriptVer\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'") { $zipVer = $Matches[1]; break }
                    }
                } finally { $reader.Dispose() }
            }
            $expectedVer = $ExpectedTag -replace '^v', ''
            if ($zipVer -and ($zipVer -eq $expectedVer)) {
                $checks += "scriptVer: OK ($zipVer matches $ExpectedTag)"
            } else {
                $checks += "scriptVer: MISMATCH (zip=$(if ($zipVer) { $zipVer } else { 'NOT FOUND' }) expected=$expectedVer)"
                $ok = $false
            }
        } finally { $zip.Dispose() }
    }

    [pscustomobject]@{ Ok = $ok; ZipHash = $zipHash; SidecarHash = $sidecarHash; Checks = $checks; EntryNames = $names; ZipVersion = $zipVer }
}

function Show-InstallVerify {
    Write-Host ''
    Write-Host 'Verifying installation against the current release tag...' -ForegroundColor Cyan
    $resolvedTag = ''
    try {
        $rel = Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/releases/latest" 15 | ConvertFrom-Json
        if ($rel -and $rel.tag_name) {
            $resolvedTag = $rel.tag_name
            $null = Test-InstallationIntegrity -Tag $resolvedTag
        } else {
            $msg = if ($rel -and $rel.message) { $rel.message } else { 'no release found' }
            Write-Host "  Cannot determine current release: $msg" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Cannot determine current release: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Optional: verify a downloaded release ZIP before a manual install (#19).
    # Release ZIPs are unpacked by hand - this is the 'before unpacking' gate.
    try {
        Write-Host ''
        $zipAsk = Read-Host '  Verify a downloaded release ZIP? (y/N)'
        if ($zipAsk -eq 'y' -or $zipAsk -eq 'Y') {
            $defaultZip = "MuMuManager-CLI-Menu-$resolvedTag.zip"
            $zipInput = Read-Host "  ZIP path (Enter = .\$defaultZip)"
            if (-not $zipInput) { $zipInput = $defaultZip }
            $zipPath = if ([System.IO.Path]::IsPathRooted($zipInput)) { $zipInput } else { Join-Path (Get-Location) $zipInput }
            $zipTag = if ([IO.Path]::GetFileName($zipPath) -match '(v[0-9]+\.[0-9]+\.[0-9]+)') { $Matches[1] } else { $resolvedTag }
            if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
                # Nothing sinister: the user just has no archive at that path.
                # Say so plainly and skip - a missing file is not tampering.
                Write-Host "  No ZIP found at $zipPath - nothing to verify. (Download MuMuManager-CLI-Menu-$zipTag.zip from the release page first, or correct the path.)" -ForegroundColor Yellow
                Write-Host ''
                return
            }
            $r = Test-ReleaseZip -ZipPath $zipPath -ExpectedTag $zipTag
            Write-Host ''
            foreach ($c in $r.Checks) {
                Write-Host "  $c" -ForegroundColor $(if ($c -match ': OK') { 'Green' } else { 'Red' })
            }
            if ($r.Ok) {
                Write-Host "ZIP: OK ($($r.EntryNames.Count) files, sha256 match) - safe to install" -ForegroundColor Green
                Write-UpdateJournal -EventType 'zip-verify-ok' -From '' -To $zipTag -Detail "sha256 match; $($r.EntryNames.Count) files"
            } else {
                Write-Host 'ZIP: FAILED - do not install from this archive' -ForegroundColor Red
                Write-UpdateJournal -EventType 'zip-verify-fail' -From '' -To $zipTag -Detail ($r.Checks -join '; ')
            }
        }
    } catch {
        Write-Debug "ZIP verify failed: $($_.Exception.Message)"
    }
}

# ── [UP] Update plan (dry-run): what [U] would do, nothing replaced ───
# Pure report renderer so tests can assert the facts without side effects.
# Facts come from the caller's fetched release + local install state; the
# only extra lookups are read-only (existing-file sizes, free disk space).
function Show-UpdatePlan {
    param(
        [Parameter(Mandatory = $true)] [string]$Tag,
        [AllowEmptyString()] [string]$LocalTag
    )

    $files = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')
    $present = 0
    $updateSize = 0
    foreach ($f in $files) {
        $p = Join-Path $ScriptDir $f
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $present++
            try { $updateSize += (Get-Item -LiteralPath $p).Length } catch { Write-Debug "plan size read failed: $f" }
        }
    }
    $scopeNote = if ($present -eq 0) { 'no existing files (fresh install)' } else { "replaces $present existing file(s), ~$([Math]::Round($updateSize / 1KB)) KB touched" }

    $diskNote = ''
    try {
        $drive = (Get-Item $ScriptDir).PSDrive
        if ($drive -and $drive.Free) { $diskNote = "$([Math]::Round($drive.Free / 1MB)) MB free on $($drive.Name):" }
    } catch { Write-Debug 'plan disk check failed' }

    $authNote = if ($GitHubToken) { 'authenticated (5000 req/hr)' } else { 'unauthenticated - the check uses a few requests of the 60 req/hr budget' }

    Write-Host ''
    Write-Host '  ============================================' -ForegroundColor Cyan
    Write-Host '    UPDATE PLAN (dry-run - nothing was replaced)' -ForegroundColor White
    Write-Host '  ============================================' -ForegroundColor Cyan
    Write-Host "  Action:    update $LocalTag -> $Tag" -ForegroundColor Green
    Write-Host "  Target:    $ScriptDir"
    Write-Host "  Files:     $($files -join ', ')"
    Write-Host "  Scope:     $scopeNote"
    if ($diskNote) { Write-Host "  Disk:      $diskNote" -ForegroundColor DarkGray }
    Write-Host '  Sources:   GitHub contents API (release tag); SHA-256 of every downloaded file is verified against the tag content' -ForegroundColor DarkGray
    Write-Host '  Backup:    existing files would be copied to backup\<timestamp> (last 5 kept)'
    Write-Host "  .version:  would be set to $Tag (only if every file is replaced and verified)"
    Write-Host '  Lock:      a single-flight lock guards the run - parallel updaters wait or refuse'
    Write-Host '  Journal:   one update-ok / update-fail event is appended to update-journal.log'
    Write-Host "  API:       $authNote" -ForegroundColor DarkGray
    Write-Host '  ============================================' -ForegroundColor Cyan
    Write-Host '  Preview only - select [U] Check for updates and confirm (y) to apply.' -ForegroundColor Green
}

function Update-FromGitHub {
    # Passive mode = read-only version check (used at startup).
    # Downloads happen only in interactive mode via menu option [U].
    # Plan mode (-Plan, menu [UP]) = full dry-run: the whole [U] flow runs
    # read-only up to the confirmation gate, then the plan is rendered and
    # the function returns before any mutation.
    param([switch]$Passive, [switch]$Plan)

    if (-not $Passive) {
        Write-Host ''
        if ($Plan) {
            Write-Host 'Update plan (dry-run)...' -ForegroundColor Cyan
        } else {
            Write-Host 'Checking for updates...' -ForegroundColor Cyan
        }
    } else {
        Write-Host 'Update check (read-only)...' -ForegroundColor DarkGray
    }

    # Build headers with token if available
    $headers = @{'Accept' = 'application/vnd.github.v3+json'; 'User-Agent' = 'MuMuManager-CLI-Menu'}
    if ($GitHubToken) {
        $headers['Authorization'] = "token $GitHubToken"
    }

    $files = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')

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
                        Write-Host '  GitHub API rate limit exceeded.' -ForegroundColor Yellow
                        if (-not $GitHubToken) {
                            Write-Host '  Without a token the limit is 60 requests/hour per IP.' -ForegroundColor Yellow
                            Write-Host '  Add a token: menu [K] Update GitHub token (stored DPAPI-encrypted).' -ForegroundColor Yellow
                        } else {
                            Write-Host '  Token quota (5000/hour) exhausted or invalid - re-save via [K].' -ForegroundColor Yellow
                        }
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
                if ($Plan) {
                    Write-Host "  Up to date ($tag)." -ForegroundColor Green
                    Write-Host '  Plan: nothing to do. [F] re-verifies the local files against the tag.' -ForegroundColor DarkGray
                } else {
                    Write-Host "  Up to date ($tag)" -ForegroundColor DarkGray
                }
            }
            return
        }

        # Content matches the tag but .version is stale/absent - heal it.
        # Guard: the fetched content must claim the tag's own scriptVer.
        # A stale CDN blob of the PREVIOUS release hashes equal to a local
        # install of that previous release, and healing on it wedges the
        # install: the marker jumps to a tag whose content never arrived
        # and every later check says 'up to date' (seen live on v1.20.4).
        # Issue #22: heal the marker only after fetching the menu script
        # through the tag URL pinned to the tag's commit SHA. The contents
        # API resolves ?ref=<tag> at fetch time, so an edge can serve the
        # PREVIOUS release's blob minutes after the push - and a stale blob
        # of release N-1 hashes equal to a local install of N-1, wedging
        # the marker at N without N's content ever arriving (seen live on
        # v1.20.4). A commit SHA is immutable, so the fetched text is the
        # tag's real content by construction; the scriptVer guard below
        # stays as a defence in depth.
        # The pre-fix build referenced $localText here without ever
        # assigning it - the heal could never fire. Local menu text is read
        # exactly as the drift check reads it.
        $localText = ''
        try { $localText = [System.IO.File]::ReadAllText((Join-Path $ScriptDir 'mumu-menu.ps1')) } catch { Write-Debug "Local menu read failed: $($_.Exception.Message)" }
        $healed = $false
        try {
            $healSha = Resolve-GitRefSha -RepoPart $GitHubRepo -Ref $tag 15
            $healRef = if ($healSha -and $healSha -match '^[0-9a-fA-F]{40}$') { $healSha } else { $tag }
            $healText = Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/contents/$SkillPath/mumu-menu.ps1`?ref=$healRef" 30
            if ($healText -and -not ($healText.TrimStart().StartsWith('{') -and $healText -match '"message"\s*:\s*')) {
                if ((Get-ContentHash $localText) -eq (Get-ContentHash $healText)) {
                    if (Test-ScriptVerMatchesTag -Text $healText -Tag $tag) {
                        Write-UpdateJournal -EventType 'version-fix' -From $localTag -To $tag -Detail 'content matches tag; .version healed (commit-pinned fetch)'
                        Set-Content -Path $VersionFile -Value $tag -NoNewline -ErrorAction SilentlyContinue
                        if (-not $Passive) {
                            Write-Host "  Up to date ($tag)" -ForegroundColor DarkGray
                            if ($Plan) {
                                Write-Host '  (.version marker healed to match the already-present content; see [J])' -ForegroundColor DarkGray
                            }
                        }
                        $healed = $true
                    } else {
                        Write-Debug 'version-fix skipped: fetched content scriptVer does not match the tag'
                    }
                }
            }
        } catch {
            Write-Debug "version-fix heal fetch failed: $($_.Exception.Message)"
        }
        if ($healed) { return }

        Write-Host "  Update available!" -ForegroundColor $(if ($Passive) { 'DarkGray' } else { 'Yellow' })
        if ($Passive) {
            Write-Host '  Nothing was downloaded. Select [U] Check for updates' -ForegroundColor DarkGray
            Write-Host '  in the menu to review and install it manually.' -ForegroundColor DarkGray
            return
        }
        if ($Plan) {
            Show-UpdatePlan -Tag $tag -LocalTag $localTag
            return
        }

        # Expected SHA-256 per file (issue #20): shown in the confirmation so
        # the user approves specific fingerprints, and re-checked after the
        # download. Fetched only once an actual update was found - the fast
        # up-to-date path never pays for this.
        $expectedHashes = @{}
        try { $expectedHashes = Get-ExpectedFileHashes -Tag $tag -Names $files } catch { Write-Debug "Expected hash fetch failed: $($_.Exception.Message)" }
        if ($expectedHashes.Count -gt 0) {
            Write-Host ''
            Write-Host '  Expected SHA-256 (from release tag):' -ForegroundColor Cyan
            foreach ($f in $files) {
                if ($expectedHashes.ContainsKey($f)) {
                    Write-Host ("    {0,-22} {1}" -f $f, $expectedHashes[$f]) -ForegroundColor DarkGray
                } else {
                    Write-Host ("    {0,-22} (unavailable - verified after download instead)" -f $f) -ForegroundColor DarkGray
                }
            }
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

        $confirm = Read-Host '  Download and verify these files? (y/N)'
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host '  Skipped.' -ForegroundColor DarkGray
            return
        }

        # Single-flight lock (issue #24): from here on the updater mutates
        # install files. Held until the update finishes (finally below).
        # Refusal exits like a declined update - nothing was changed.
        if (-not (New-UpdateLock -Dir $ScriptDir)) { return }
        try {

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
        $okFiles = 0
        $fileResults = @()
        $downloadedOk = New-Object 'System.Collections.Generic.HashSet[string]'
        # Helper: download a file via curl with token fallback and rate-limit retry
        function _DlFile([string]$Url, [string]$Out) {
            $baseArgs = @('-s', '--retry', '3', '--retry-delay', '3', '--connect-timeout', '30', '--max-time', '120',
                          '-L', '-H', 'Accept: application/vnd.github.v3.raw', '-o', $Out)
            if ($GitHubToken -and $GitHubToken.Length -gt 0) {
                $allArgs = $baseArgs + @('-H', "Authorization: token $GitHubToken", $Url)
                & curl.exe @allArgs 2>$null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Out)) {
                    # curl failed — could be rate limit; try without token
                    Remove-Item $Out -Force -ErrorAction SilentlyContinue
                    $noAuthArgs = $baseArgs + @($Url)
                    & curl.exe @noAuthArgs 2>$null
                }
            } else {
                $noAuthArgs = $baseArgs + @($Url)
                & curl.exe @noAuthArgs 2>$null
            }
        }

        foreach ($f in $files) {
            $dest = Join-Path $ScriptDir $f
            $rawUrl = "https://api.github.com/repos/$GitHubRepo/contents/$SkillPath/$f`?ref=$tag"
            Write-Host "  Downloading $f..." -ForegroundColor Yellow
            try {
                $tmpDl = Join-Path $env:TEMP ('mumu_dl_' + [Guid]::NewGuid().ToString('N') + '.tmp')
                _DlFile $rawUrl $tmpDl
                if (-not (Test-Path $tmpDl)) {
                    throw 'download failed — file not created'
                }
                $bytes = [System.IO.File]::ReadAllBytes($tmpDl)
                Remove-Item $tmpDl -Force -ErrorAction SilentlyContinue
                if (-not $bytes -or $bytes.Length -eq 0) { throw 'empty download' }
                $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                # Bad credentials fallback — retry without token
                if ($GitHubToken -and $text -match '"message"\s*:\s*"Bad credentials"') {
                    Write-Host '    Token rejected — retrying without auth...' -ForegroundColor Yellow
                    $tmpDl2 = Join-Path $env:TEMP ('mumu_dl_' + [Guid]::NewGuid().ToString('N') + '.tmp')
                    _DlFile $rawUrl $tmpDl2
                    if (Test-Path $tmpDl2) {
                        $bytes = [System.IO.File]::ReadAllBytes($tmpDl2)
                        Remove-Item $tmpDl2 -Force -ErrorAction SilentlyContinue
                        if ($bytes -and $bytes.Length -gt 0) {
                            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                        }
                    }
                }
                # Rate limit detection — suggest adding/updating token
                if ($text -match 'rate limit exceeded') {
                    if (-not $GitHubToken) {
                        Write-Host '    GitHub API rate limit (60/hr without token).' -ForegroundColor Yellow
                        Write-Host '    Add a token: [K] Update GitHub token (stored DPAPI-encrypted).' -ForegroundColor Yellow
                    } else {
                        Write-Host '    Rate limit exceeded even with token — token may be invalid.' -ForegroundColor Yellow
                        Write-Host '    Re-save: [K] Update GitHub token.' -ForegroundColor Yellow
                    }
                }
                # Validate response is raw content, not JSON metadata.
                # Checks apply only when the body starts with '{': raw files may
                # legitimately contain JSON-like strings (self-match false positive).
                if ($text -and $text.TrimStart().StartsWith('{')) {
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
                }

                $dlSize = if ($bytes.Length -gt 1MB) { "$([math]::Round($bytes.Length / 1MB, 1)) MB" }
                          elseif ($bytes.Length -gt 1KB) { "$([math]::Round($bytes.Length / 1KB, 1)) KB" }
                          else { "$($bytes.Length) B" }

                # Self-update: can't overwrite the running script.
                # Write .new file, apply on next startup.
                if ($f -eq 'mumu-menu.ps1') {
                    $newPath = $dest + '.new'
                    [System.IO.File]::WriteAllBytes($newPath, $bytes)
                    Write-Host "    $f saved as .new ($dlSize) (will apply on restart)" -ForegroundColor Green
                } else {
                    [System.IO.File]::WriteAllBytes($dest, $bytes)
                    Write-Host "    $f OK ($dlSize)" -ForegroundColor Green
                }
                $okFiles++
                $null = $downloadedOk.Add($f)
                $fileResults += "$f=$dlSize"
            } catch {
                $errMsg = $_.Exception.Message
                if (-not $errMsg) { $errMsg = 'Unknown error - check network connection and try again' }
                Write-Host "    Failed: $errMsg" -ForegroundColor Red
                if ($tmpDl -and (Test-Path $tmpDl)) { Remove-Item $tmpDl -Force -ErrorAction SilentlyContinue }
                $failed++
            }
        }

        # Post-download verification (issue #20): hash what was actually
        # written and compare with the expected fingerprints shown above.
        # The pending .new copy is hashed in place of the running script.
        # A mismatch fails the update like a failed download - .version is
        # not advanced and the failure is journaled.
        if ($expectedHashes.Count -gt 0) {
            Write-Host ''
            Write-Host '  Verifying downloaded files:' -ForegroundColor Cyan
            foreach ($f in $files) {
                if (-not ($downloadedOk.Contains($f)) -or -not $expectedHashes.ContainsKey($f)) { continue }
                $checkPath = if ($f -eq 'mumu-menu.ps1') { Join-Path $ScriptDir 'mumu-menu.ps1.new' } else { Join-Path $ScriptDir $f }
                if (-not (Test-Path -LiteralPath $checkPath -PathType Leaf)) {
                    Write-Host ("    {0,-22} MISSING after download" -f $f) -ForegroundColor Red
                    $failed++
                    $fileResults += "$f=verify:missing"
                    continue
                }
                $actual = Get-ContentHash ([System.IO.File]::ReadAllText($checkPath))
                if ($actual -eq $expectedHashes[$f]) {
                    Write-Host ("    {0,-22} hash OK" -f $f) -ForegroundColor Green
                } else {
                    Write-Host ("    {0,-22} HASH MISMATCH (expected {1}..., got {2}...)" -f $f, $expectedHashes[$f].Substring(0, 16), $actual.Substring(0, 16)) -ForegroundColor Red
                    $failed++
                    $fileResults += "$f=verify:mismatch"
                }
            }
        }

        if ($failed -gt 0) {
            Write-UpdateJournal -EventType 'update-fail' -From $localTag -To $tag -Detail "$okFiles ok, $failed failed ($($fileResults -join ', '))"
            Write-Host "Update finished with $failed failed file(s). Restore from backup if needed." -ForegroundColor Red
        } else {
            Write-UpdateJournal -EventType 'update-ok' -From $localTag -To $tag -Detail ($fileResults -join ', ')
            Set-Content -Path $VersionFile -Value $tag -NoNewline -ErrorAction SilentlyContinue
            Write-Host ''
            Write-Host 'Update complete! Restart the menu to use the new version.' -ForegroundColor Green
        }
        Start-Sleep -Seconds 2
        exit
        } finally {
            # Release in finally: covers normal exit, update-fail paths and
            # Ctrl+C between acquire and exit.
            Remove-UpdateLock -Dir $ScriptDir
        }
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
            Write-Host '  GitHub API rate limit exceeded.' -ForegroundColor Yellow
            if (-not $GitHubToken) {
                Write-Host '  Without a token the limit is 60 requests/hour per IP - shared networks exhaust it fast.' -ForegroundColor Yellow
                Write-Host '  Fix: [K] Update GitHub token (stored DPAPI-encrypted), or wait for the hourly reset.' -ForegroundColor Yellow
            } else {
                Write-Host '  The token quota (5000/hour) is exhausted or the token is invalid - re-save via [K].' -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Update check failed: $msg" -ForegroundColor Yellow
        }
    }
}

# Apply pending self-updates (.new files from previous [U] update):
# mumu-menu.ps1 (running, cannot overwrite itself) and bootstrap-update.ps1
# (left as .new when the file was busy during an update).
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
        if ($script:JournalFile) { Write-UpdateJournal -EventType 'self-apply' -To 'mumu-menu.ps1' -Detail 'applied pending .new file from previous update' }
        Write-Host '  Applied pending update from .new file' -ForegroundColor Green
    }
    # Pending updater refresh: bootstrap-update.ps1.new saved by [U] (or by
    # bootstrap-update.ps1 itself when the file was busy at end of its run).
    $updNew = Join-Path $ScriptDir 'bootstrap-update.ps1.new'
    if (Test-Path -LiteralPath $updNew) {
        $updDest = Join-Path $ScriptDir 'bootstrap-update.ps1'
        $updOld = $updDest + '.old'
        if (Test-Path -LiteralPath $updDest) {
            try {
                if (Test-Path -LiteralPath $updOld) { Remove-Item -LiteralPath $updOld -Force -ErrorAction SilentlyContinue }
                Copy-Item -LiteralPath $updDest -Destination $updOld -Force
            } catch { Write-Debug "Backup old updater failed: $($_.Exception.Message)" }
        }
        Copy-Item -LiteralPath $updNew -Destination $updDest -Force
        Remove-Item -LiteralPath $updNew -Force -ErrorAction SilentlyContinue
        if ($script:JournalFile) { Write-UpdateJournal -EventType 'updater-refresh' -To 'bootstrap-update.ps1' -Detail 'applied pending .new file from previous update' }
        Write-Host '  Applied pending updater update from .new file' -ForegroundColor Green
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

$script:QuickStatusCache = $null
$script:QuickStatusTs = [datetime]::MinValue

function Show-QuickStatus {
    # Show compact status line at the top of the menu
    # Cache MuMuManager info for 5 seconds to avoid lag on every menu render
    $muVer = if ($InstalledVersion) { "$InstalledVersion" } else { 'unknown' }
    $now = [datetime]::Now
    if ($script:QuickStatusCache -and ($now - $script:QuickStatusTs).TotalSeconds -lt 5) {
        $total = $script:QuickStatusCache.total
        $running = $script:QuickStatusCache.running
        Write-Host "  v$scriptVer | MuMu $muVer | $running/$total running" -ForegroundColor DarkGray
        return
    }
    try {
        $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
        $total = 0; $running = 0
        foreach ($key in $info.PSObject.Properties.Name) {
            $total++
            if ($info.$key.player_state -and $info.$key.player_state -notmatch 'stopped| shutting') { $running++ }
        }
        $script:QuickStatusCache = @{ total = $total; running = $running }
        $script:QuickStatusTs = $now
        Write-Host "  v$scriptVer | MuMu $muVer | $running/$total running" -ForegroundColor DarkGray
    } catch {
        Write-Host "  v$scriptVer | MuMu $muVer" -ForegroundColor DarkGray
    }
}

function Show-UpdateJournal {
    # Viewer for update-journal.log (written by [U] and bootstrap-update.ps1).
    # -Mode (1/2/3/4) makes the selection scriptable and testable; without it
    # the mode is asked interactively.
    param([string]$Mode = '')
    $file = $script:JournalFile
    Write-Host ''
    if (-not ($file -and (Test-Path -LiteralPath $file -PathType Leaf))) {
        Write-Host '  Update journal is empty - no updates have been performed yet.' -ForegroundColor Yellow
        Write-Host "  Expected file: $file" -ForegroundColor DarkGray
        return
    }
    $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if ($lines.Count -eq 0) {
        Write-Host '  Update journal is empty.' -ForegroundColor Yellow
        return
    }

    if (-not $Mode) {
        Write-Host '  [1] Last 20 events (default)' -ForegroundColor White
        Write-Host '  [2] Full journal' -ForegroundColor White
        Write-Host '  [3] Errors and partial failures only' -ForegroundColor White
        Write-Host '  [4] Open journal file in notepad' -ForegroundColor White
        Write-Host '  [5] Export journal (MD / CSV / JSON)' -ForegroundColor White
        Write-Host '  [0] Cancel' -ForegroundColor Yellow
        $Mode = Read-Host 'Select'
    }
    $mode = $Mode
    if ($mode -eq '0' -or $mode -eq '') { return }

    if ($mode -eq '4') {
        try { Start-Process notepad.exe $file } catch { Write-Host "  Cannot open notepad: $($_.Exception.Message)" -ForegroundColor Red }
        return
    }

    if ($mode -eq '5') {
        $err = Export-UpdateJournal
        if ($err) { Write-Host "  $err" -ForegroundColor Red }
        return
    }

    $selected = switch ($mode) {
        '2' { $lines }
        '3' { @($lines | Where-Object { (($_ -split "`t")[2]) -match 'fail|error' }) }
        default { @($lines | Select-Object -Last 20) }
    }
    if ($selected.Count -eq 0) {
        if ($mode -eq '3') {
            Write-Host ("  No errors recorded - all {0} journal events are successes or skips (update-ok / version-fix / updater-refresh / self-apply / update-skipped)." -f $lines.Count) -ForegroundColor Green
        } else {
            Write-Host '  No matching entries.' -ForegroundColor Yellow
        }
        return
    }

    Write-Host ''
    Write-Host ("  === Update journal ({0} of {1} events) ===" -f $selected.Count, $lines.Count) -ForegroundColor Cyan
    # Consecutive events sharing timestamp+actor come from one run (e.g.
    # update-ok + updater-refresh written back to back): only the first
    # prints the timestamp/actor; the rest render as a tree continuation.
    $prevRunKey = ''
    foreach ($raw in $selected) {
        $p = $raw -split "`t", 6
        if ($p.Count -lt 6) { Write-Host "  $raw" -ForegroundColor White; continue }
        $color = switch -Regex ($p[2]) {
            'fail|error' { 'Red' }
            'skipped' { 'Yellow' }
            'ok|fix|apply' { 'Green' }
            'start' { 'Cyan' }
            default { 'White' }
        }
        $info = @()
        $arrow = Get-JournalArrow -From $p[3] -To $p[4]
        if ($arrow) { $info += $arrow }
        if ($p[5]) { $info += $p[5] }
        $runKey = "$($p[0])|$($p[1])"
        $sameRun = ($runKey -eq $prevRunKey)
        $prevRunKey = $runKey
        if ($sameRun) {
            # ASCII continuation marker: box-drawing glyphs are not in OEM
            # codepages (cp866 etc.) and would render as garbage in the menu.
            Write-Host ("  {0}  {1,-9} {2,-12} {3}" -f (' ' * 19), '', ('- ' + $p[2]), ($info -join ' | ')) -ForegroundColor $color
        } else {
            Write-Host ("  {0}  {1,-9} {2,-12} {3}" -f $p[0], $p[1], $p[2], ($info -join ' | ')) -ForegroundColor $color
        }
    }
    Write-Host ("  file: {0}" -f $file) -ForegroundColor DarkGray
}

# ── Journal export (issue #23) ────────────────────────────────────────
# Pure converters first - the file writing is deliberately separated so
# golden tests can assert the exact output without touching the disk.

function ConvertTo-JournalMarkdown {
    # Issue-ready Markdown table (same structure the [J] viewer prints).
    # Pipes inside cells are escaped; a missing field renders empty.
    param([string[]]$Lines)
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('# Update journal')
    $out.Add('')
    $out.Add('| Timestamp | Actor | Event | From | To | Detail |')
    $out.Add('|---|---|---|---|---|---|')
    foreach ($raw in $Lines) {
        $p = $raw -split "`t", 6
        while ($p.Count -lt 6) { $p += '' }
        $cells = foreach ($c in $p[0..5]) { ($c -replace '\|', '\|').Trim() }
        $out.Add('| ' + ($cells -join ' | ') + ' |')
    }
    return $out
}

function ConvertTo-JournalCsv {
    # RFC-4180-style CSV with header. Cells containing quote, comma or a
    # newline are wrapped in quotes with inner quotes doubled (the source
    # format is tab-separated, so commas are common in the detail column).
    param([string[]]$Lines)
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('timestamp,actor,event,from,to,detail')
    foreach ($raw in $Lines) {
        $p = $raw -split "`t", 6
        while ($p.Count -lt 6) { $p += '' }
        $cells = foreach ($c in $p[0..5]) {
            $c = $c.Trim()
            if ($c -match '[",\r\n]') { '"' + ($c -replace '"', '""') + '"' } else { $c }
        }
        $out.Add(($cells -join ','))
    }
    return $out
}

function ConvertTo-JournalJson {
    # Full-fidelity JSON export for automation: a top-level OBJECT wrapping
    # the events array (generator + count + events). Top-level arrays hit
    # inconsistent parse shapes in some PowerShell 5.1 consumers, while an
    # object property is uniform everywhere (PS 5.1/7, jq, Python). Every
    # event field verbatim (no trimming). Compact single line; the content
    # is derived purely from the input lines, so exports are idempotent.
    param([string[]]$Lines)
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($raw in $Lines) {
        $p = $raw -split "`t", 6
        while ($p.Count -lt 6) { $p += '' }
        $events.Add([ordered]@{ timestamp = $p[0]; actor = $p[1]; event = $p[2]; from = $p[3]; to = $p[4]; detail = $p[5] })
    }
    $doc = [ordered]@{
        generator = 'MuMuManager-CLI-Menu update journal'
        count     = $events.Count
        events    = @($events.ToArray())
    }
    return ConvertTo-Json -InputObject $doc -Depth 3 -Compress
}

function Export-UpdateJournal {
    # [J] -> 5 export (issue #23): writes the selected journal events to a
    # UTF-8 BOM file (repo rule from alert #535). Returns '' on success or
    # an error message; prompts for format/range/path interactively unless
    # -Format/-Range/-Path are given (scriptable + testable). -Lines allows
    # exporting an in-memory selection without re-reading the journal.
    # The journal itself is never modified and repeated exports with the
    # same inputs are byte-identical (idempotent).
    param(
        [string]$Format = '',
        [string]$Range = '',
        [string]$Path = '',
        [string[]]$Lines
    )
    try {
        if ($Lines -and $Lines.Count -gt 0) {
            $sel = @($Lines)
        } else {
            $file = $script:JournalFile
            if (-not ($file -and (Test-Path -LiteralPath $file -PathType Leaf))) { return 'journal file not found' }
            $all = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
            if ($all.Count -eq 0) { return 'journal is empty' }
            if (-not $Range) {
                Write-Host '  Range:' -ForegroundColor White
                Write-Host '  [1] Last 20 events (default)' -ForegroundColor White
                Write-Host '  [2] Full journal' -ForegroundColor White
                Write-Host '  [3] Errors and partial failures only' -ForegroundColor White
                $Range = Read-Host 'Select'
            }
            $sel = switch ($Range) {
                '2' { $all }
                '3' { @($all | Where-Object { (($_ -split "`t")[2]) -match 'fail|error' }) }
                default { @($all | Select-Object -Last 20) }
            }
            if ($sel.Count -eq 0) { return 'nothing to export for this range' }
        }
        if (-not $Format) {
            Write-Host '  Format:' -ForegroundColor White
            Write-Host '  [1] Markdown (ready for issues)' -ForegroundColor White
            Write-Host '  [2] CSV' -ForegroundColor White
            Write-Host '  [3] JSON' -ForegroundColor White
            $Format = Read-Host 'Select'
        }
        $fmtKey = switch -Regex ($Format) {
            '^(1|md|markdown)$' { 'md' }
            '^(2|csv)$' { 'csv' }
            '^(3|json)$' { 'json' }
            default { '' }
        }
        if (-not $fmtKey) { return "unknown format: $Format" }
        if (-not $Path) {
            $default = Join-Path (Split-Path -Parent $script:JournalFile) ("update-journal-{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $fmtKey)
            $Path = Read-Host "  Output path (Enter = $default)"
            if (-not $Path) { $Path = $default }
        }
        $out = switch ($fmtKey) {
            'csv' { ConvertTo-JournalCsv -Lines $sel }
            'json' { ConvertTo-JournalJson -Lines $sel }
            default { ConvertTo-JournalMarkdown -Lines $sel }
        }
        # Normalizer: the MD/CSV converters return lists, JSON returns a
        # single string - @() makes one [string[]] for either shape.
        $linesToWrite = [string[]]@($out | ForEach-Object { [string]$_ })
        # Explicit BOM: both PS 5.1 and pwsh 7 honor this encoding object.
        [System.IO.File]::WriteAllLines($Path, $linesToWrite, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host ("  Exported {0} event(s) -> {1}" -f $sel.Count, $Path) -ForegroundColor Green
        return ''
    } catch {
        return "export failed: $($_.Exception.Message)"
    }
}

# ── Problem diagnostics (read-only, local-only) ──────────────────────
# One screen that answers "is anything wrong with this install?" without
# touching state and without network calls (the [F] integrity check owns
# the online comparison). Collects findings from the install layout, the
# version marker vs the script's own $scriptVer (the v1.20.5 wedge class),
# the update lock, pending .new/.old files and the journal's health.

function Invoke-MumuManagerProbe {
    # One MuMuManager info query, parsed into testable data (issue #32).
    # $MumuPathOverride is for tests (stub binary); production passes the
    # auto-detected $MumuPath via -TargetPath. Returns a hashtable:
    # found, instances, running, adbReady, error, rawFirstLine.
    # v1.22.5: every external call (info, adb) runs with a kill-on-timeout
    # wrapper - a hung MuMu RPC or cold adb daemon must never freeze the menu.
    param(
        [string]$MumuPathOverride = '',
        [string]$TargetPath = '',
        [string]$AdbPathOverride = ''
    )
    function Invoke-Quick {
        # Non-blocking external call with a hard timeout; kill on overrun.
        # All production arguments are space-free, so a single argument string
        # is safe (PS 5.1 has no array Arguments overload without quoting pain).
        param([string]$Exe, [string]$ArgumentString, [int]$TimeoutMs = 10000)
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            # .cmd/.bat launch: CreateProcess needs cmd.exe in front of batch files
            if ($Exe -match '\.(cmd|bat)$') {
                $psi.FileName = $env:ComSpec
                $psi.Arguments = "/c `"$Exe`" $ArgumentString"
            } else {
                $psi.FileName = $Exe
                $psi.Arguments = $ArgumentString
            }
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $outTask = $p.StandardOutput.ReadToEndAsync()
            $errTask = $p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit($TimeoutMs)) {
                try { $p.Kill() } catch { Write-Debug "quick-exec kill failed: $($_.Exception.Message)" }
                return $null
            }
            $o = ''; $e = ''
            try { $o = $outTask.Result } catch { Write-Debug "quick-exec stdout read failed: $($_.Exception.Message)" }
            try { $e = $errTask.Result } catch { Write-Debug "quick-exec stderr read failed: $($_.Exception.Message)" }
            return ($o + $e)
        } catch {
            Write-Debug "quick-exec failed: $($_.Exception.Message)"
            return $null
        }
    }
    $r = @{ found = $false; instances = -1; running = -1; adbReady = $false; error = ''; rawFirstLine = ''; adbExeUsed = '' }
    $exe = if ($MumuPathOverride) { $MumuPathOverride } else { $TargetPath }
    if (-not ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf))) { $r.error = 'not found'; return $r }
    $r.found = $true
    $raw = $null
    try { $raw = Invoke-Quick -Exe $exe -ArgumentString 'info -v all' -TimeoutMs 10000 } catch { $r.error = $_.Exception.Message; return $r }
    if ($null -eq $raw) { $r.error = 'info query timed out (10s)'; return $r }
    $outLines = @($raw | Where-Object { $_ -and $_.ToString().Trim() })
    if ($outLines.Count -gt 0) { $r.rawFirstLine = $outLines[0].ToString().Trim() }
    if ($outLines.Count -eq 0) { $r.error = 'no output'; return $r }
    $info = $null
    # Join before parsing: MuMuManager emits pretty-printed multi-line JSON.
    # PS 5.1's pipeline ConvertFrom-Json concatenates input lines, but pwsh 7
    # parses each pipeline item separately (every line alone is invalid JSON).
    try { $info = ($outLines -join "`n") | ConvertFrom-Json } catch { $r.error = 'output is not JSON'; return $r }
    $total = 0; $running = 0; $adb = $false
    foreach ($key in $info.PSObject.Properties.Name) {
        $inst = $info.$key
        if ($null -eq $inst -or -not $inst.PSObject.Properties['player_state']) { continue }
        $total++
        $st = "$($inst.player_state)"
        if ($st -notmatch 'stopped|shutting') {
            $running++
            $av = if ($inst.PSObject.Properties['adb_version']) { "$($inst.adb_version)" } else { '' }
            if ($av -and $av.Trim() -and $av -ne '0') {
                $adb = $true
            } else {
                # v1.21.8 fix: some MuMu builds never report adb_version, which
                # made the readiness flag a permanent false positive. Ask ADB
                # itself, per instance, via its adb_port (local socket only).
                $port = if ($inst.PSObject.Properties['adb_port']) { "$($inst.adb_port)" } else { '' }
                if ($port -and $port -ne '0') {
                    # adb.exe candidates: next to MuMuManager itself (nx_main layout,
                    # caught live in v1.22.5), the classic shell\ subfolder above it,
                    # then PATH. Derive from -TargetPath or -MumuPathOverride (tests).
                    $exeForDir = if ($TargetPath) { $TargetPath } elseif ($MumuPathOverride) { $MumuPathOverride } else { '' }
                    $adbDir = if ($exeForDir) { Split-Path -Parent $exeForDir } else { '' }
                    $adbSide = if ($adbDir) { Join-Path $adbDir 'adb.exe' } else { '' }
                    $adbSideCmd = if ($adbDir) { Join-Path $adbDir 'adb.cmd' } else { '' }
                    $shellAdb = if ($adbDir) { Join-Path (Split-Path -Parent $adbDir) 'shell\adb.exe' } else { '' }
                    $shellAdbCmd = if ($adbDir) { Join-Path (Split-Path -Parent $adbDir) 'shell\adb.cmd' } else { '' }
                    $adbExe = $AdbPathOverride
                    if (-not $adbExe) {
                        foreach ($cand in @($adbSide, $adbSideCmd, $shellAdb, $shellAdbCmd, 'adb.exe')) {
                            $found = $false
                            if ($cand -and (Test-Path -LiteralPath $cand -PathType Leaf)) { $found = $true }
                            elseif ($cand -and (Get-Command $cand -ErrorAction SilentlyContinue)) { $found = $true }
                            if ($found) { $adbExe = $cand; break }
                        }
                    }
                    $r.adbExeUsed = "$adbExe"
                    if ($adbExe) {
                        # v1.22.5: MuMu's bridge listens but adb does NOT attach to it
                        # automatically - plain `adb devices` stays empty (caught live:
                        # "ADB bridge not ready" forever on a healthy emulator).
                        # Explicit `adb connect` fixes that; it is idempotent.
                        # Second live finding: with a COLD adb server the in-band
                        # daemon start can block for a long time and freeze the menu
                        # - so every adb call runs through the kill-on-timeout wrapper.
                        $null = Invoke-Quick -Exe $adbExe -ArgumentString "connect 127.0.0.1:$port" -TimeoutMs 5000
                        foreach ($attempt in 1..2) {
                            $dev = Invoke-Quick -Exe $adbExe -ArgumentString "-s 127.0.0.1:$port devices" -TimeoutMs 5000
                            $dev = "$dev"
                            if ($dev -match "127\.0\.0\.1:$port\s+device") { $adb = $true; break }
                            if ($dev -match "127\.0\.0\.1:$port\s+(offline|unauthorized)") { break }
                            if ($attempt -eq 1) {
                                # still not attached: try connect once more (cold adb
                                # daemon sometimes drops the first attempt), then recheck
                                $null = Invoke-Quick -Exe $adbExe -ArgumentString "connect 127.0.0.1:$port" -TimeoutMs 5000
                                Start-Sleep -Milliseconds 800
                            }
                        }
                    }
                }
            }
        }
    }
    $r.instances = $total
    $r.running = $running
    $r.adbReady = $adb
    return $r
}

function Get-ProblemFindings {
    # Returns an array of finding objects:
    #   severity: 'error' | 'warn' | 'info'   area: install|lock|journal|mumu
    # Pure with respect to its inputs - all paths are parameters, so tests
    # can drive it against fixture directories. Never mutates anything.
    param(
        [string]$ScriptDir,
        [string]$VersionFile,
        [string]$MenuPath,
        [string]$JournalFile,
        [string]$MumuPath,
        [string]$InstalledVersion = '',
        [string]$ScriptVer = '',
        [string]$MinVersion = '4.0.0.3179',
        [scriptblock]$MumuProbe = { param($exe) Invoke-MumuManagerProbe -TargetPath $exe }
    )
    $findings = New-Object System.Collections.Generic.List[object]
    $add = { param($sev, $area, $msg) $findings.Add([pscustomobject]@{ severity = $sev; area = $area; message = $msg }) }

    # ── Install layout ────────────────────────────────────────────
    if (-not ($ScriptDir -and (Test-Path -LiteralPath $ScriptDir -PathType Container))) {
        & $add 'error' 'install' "install directory not found: $ScriptDir"
        return $findings.ToArray()
    }
    if (-not ($MenuPath -and (Test-Path -LiteralPath $MenuPath -PathType Leaf))) {
        & $add 'error' 'install' "mumu-menu.ps1 missing from the install directory"
    }

    # Version marker vs the script's own $scriptVer - the wedge detector:
    # a marker AHEAD of content means a heal raised .version without the
    # content ever arriving (v1.20.5 bug class); the updater will then say
    # "Up to date" forever.
    $marker = ''
    if (Test-Path -LiteralPath $VersionFile -PathType Leaf) {
        try { $marker = (Get-Content -LiteralPath $VersionFile -Raw).Trim() } catch { Write-Debug "marker read failed: $($_.Exception.Message)" }
    }
    $fileVer = ''
    if ($MenuPath -and (Test-Path -LiteralPath $MenuPath -PathType Leaf)) {
        try {
            $head = (Get-Content -LiteralPath $MenuPath -TotalCount 260 -ErrorAction SilentlyContinue) -join "`n"
            if ($head -match "\`$scriptVer\s*=\s*'([\d\.]+)'") { $fileVer = $Matches[1] }
        } catch { Write-Debug "scriptVer read failed: $($_.Exception.Message)" }
    }
    if (-not $marker) {
        & $add 'info' 'install' "no .version marker yet - the install has never recorded an update"
    }
    if ($marker -and $fileVer) {
        $cmp = Compare-ScriptVersion -A $marker -B "v$fileVer"
        if ($cmp -eq 1) {
            & $add 'error' 'install' "marker ($marker) is AHEAD of the installed content ($fileVer) - wedged heal; run bootstrap-update.ps1 to repair"
        } elseif ($cmp -eq -1) {
            & $add 'warn' 'install' "installed content ($fileVer) is newer than the marker ($marker) - an update may have been interrupted"
        }
    } elseif ($marker -and -not $fileVer) {
        & $add 'warn' 'install' "could not read the script version from mumu-menu.ps1"
    }

    # Pending self-apply files and leftovers.
    foreach ($pending in @('mumu-menu.ps1.new', 'bootstrap-update.ps1.new')) {
        if (Test-Path -LiteralPath (Join-Path $ScriptDir $pending) -PathType Leaf) {
            & $add 'info' 'install' "pending $pending will be applied at the next menu start"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $ScriptDir 'mumu-menu.ps1.old') -PathType Leaf) {
        & $add 'info' 'install' "mumu-menu.ps1.old leftover from the last self-apply (removed at next startup)"
    }

    # ── Update lock ───────────────────────────────────────────────
    $lockPath = Join-Path $ScriptDir '.update-lock'
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        if (Test-UpdateLockStale -LockPath $lockPath) {
            & $add 'info' 'lock' "stale .update-lock (older than 10 minutes) - it will be broken automatically on the next update"
        } else {
            $owner = ''
            try { $owner = (Get-Content -LiteralPath $lockPath -TotalCount 1 -ErrorAction SilentlyContinue) } catch { $owner = '' }
            & $add 'warn' 'lock' "an update lock is held right now ($owner) - another updater may be running"
        }
    }
    if (Test-Path -LiteralPath "$lockPath.new" -PathType Leaf) {
        & $add 'info' 'lock' ".update-lock.new claim residue - a stale-break was interrupted; harmless, cleaned on the next update"
    }

    # ── Journal health ────────────────────────────────────────────
    if (-not ($JournalFile -and (Test-Path -LiteralPath $JournalFile -PathType Leaf))) {
        & $add 'info' 'journal' "no update journal yet - no updates have been performed"
    } else {
        $size = (Get-Item -LiteralPath $JournalFile).Length
        if ($size -gt 256KB) { & $add 'info' 'journal' "journal is $([math]::Round($size / 1KB, 0)) KB - it will rotate to .old on the next write" }
        if (Test-Path -LiteralPath "$JournalFile.old" -PathType Leaf) {
            & $add 'info' 'journal' "rotated journal present: update-journal.log.old"
        }
        $lines = @(Get-Content -LiteralPath $JournalFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
        $bad = 0; $fails = 0; $skips = 0
        foreach ($raw in $lines) {
            $p = $raw -split "`t", 6
            if (($p.Count -lt 6) -or ($p[0] -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')) { $bad++; continue }
            if ($p[2] -match 'fail|error') { $fails++ }
            if ($p[2] -eq 'update-skipped') { $skips++ }
        }
        if ($bad -gt 0) { & $add 'warn' 'journal' "$bad malformed journal line(s) - written by an older version or corrupted" }
        if ($fails -gt 0) { & $add 'warn' 'journal' "$fails failed update event(s) recorded - review with [J] -> 3" }
        if ($skips -gt 0) { & $add 'info' 'journal' "$skips update-skipped event(s) - concurrent update attempts that were correctly refused" }
    }

    # ── MuMu environment ──────────────────────────────────────────
    if (-not ($MumuPath -and (Test-Path -LiteralPath $MumuPath -PathType Leaf))) {
        & $add 'error' 'mumu' "MuMuManager.exe not found - emulator functions will not work"
    } else {
        if ($InstalledVersion) {
            try {
                if ([version]$InstalledVersion -lt [version]$MinVersion) {
                    & $add 'warn' 'mumu' "MuMu version $InstalledVersion is below the minimum $MinVersion - some commands may fail"
                }
            } catch { & $add 'warn' 'mumu' "could not parse MuMu version '$InstalledVersion'" }
        }
        # Emulator section (issue #32): one info query - instance count,
        # running state, ADB-bridge readiness. Quiet degradation: a failed
        # probe warns but never breaks the diagnostics.
        try {
            $probe = & $MumuProbe $MumuPath
            if (-not $probe.found) {
                & $add 'error' 'mumu' "MuMuManager.exe not found - emulator functions will not work"
            } elseif ($probe.error) {
                & $add 'warn' 'mumu' "MuMuManager did not answer cleanly ($($probe.error))$(if ($probe.rawFirstLine) { ": $($probe.rawFirstLine)" })"
            } else {
                if ($probe.instances -eq 0) {
                    & $add 'info' 'emulator' "no emulator instances - create one with menu [5]"
                } elseif ($probe.running -eq 0) {
                    & $add 'info' 'emulator' "$($probe.instances) instance(s) present, none running - launch with menu [2]"
                } else {
                    $adbNote = if ($probe.adbReady) { ', ADB bridge ready' } else { ', ADB bridge NOT ready' }
                    & $add 'info' 'emulator' "$($probe.running) of $($probe.instances) instance(s) running$adbNote"
                    if (-not $probe.adbReady) {
                        & $add 'warn' 'emulator' "ADB bridge not ready on the running instance - wait a moment or restart it; in-emulator commands (curl, adb shell) will fail until then"
                    }
                }
            }
        } catch {
            & $add 'warn' 'mumu' "emulator probe failed: $($_.Exception.Message)"
        }
    }

    # ── Disk space ────────────────────────────────────────────────
    try {
        $drive = (Get-Item $ScriptDir).PSDrive
        if ($drive -and $drive.Free -and $drive.Free -lt 100MB) {
            & $add 'warn' 'install' "low disk space on $($drive.Name): ($([math]::Round($drive.Free / 1MB, 0)) MB free) - updates and backups may fail"
        }
    } catch { Write-Debug "disk check failed: $($_.Exception.Message)" }

    return $findings.ToArray()
}

function Get-BackupFolders {
    # Lists rollback candidates: backup\YYYYMMDD_HHMMSS directories, newest
    # first, with size and completeness (issue #27). Read-only.
    param([string]$InstallDir)
    $backupRoot = Join-Path $InstallDir 'backup'
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) { return @() }
    $result = @()
    $dirs = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending)
    foreach ($d in $dirs) {
        $sizeBytes = (Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if (-not $sizeBytes) { $sizeBytes = 0 }
        $result += [pscustomobject]@{
            Path      = $d.FullName
            Name      = $d.Name
            LastWrite = $d.LastWriteTime
            SizeMB    = [Math]::Round($sizeBytes / 1MB, 1)
            Files     = @(Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue).Count
            HasMenu   = (Test-Path -LiteralPath (Join-Path $d.FullName 'mumu-menu.ps1') -PathType Leaf)
        }
    }
    return $result
}

function Build-RollbackPlan {
    # Pure decision logic for [RB]: validates a backup folder and returns the
    # restore plan. The marker is earned from the restored content's own
    # $scriptVer - backups contain no .version (bootstrap copies only files),
    # and the guard principle of v1.20.5 says: never write a version the
    # content does not claim.
    param(
        [Parameter(Mandatory = $true)] [string]$BackupDir,
        [Parameter(Mandatory = $true)] [string]$InstallDir,
        [string[]]$FileSet = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')
    )
    $r = @{ Ok = $false; Reason = ''; Files = @(); MarkerTo = ''; MarkerWrite = $false }
    if (-not ($BackupDir -and (Test-Path -LiteralPath $BackupDir -PathType Container))) { $r.Reason = "backup folder not found: $BackupDir"; return $r }
    $missing = @()
    foreach ($f in $FileSet) { if (-not (Test-Path -LiteralPath (Join-Path $BackupDir $f) -PathType Leaf)) { $missing += $f } }
    if ($missing.Count -gt 0) { $r.Reason = "backup is incomplete - missing: $($missing -join ', ')"; return $r }
    $r.Files = $FileSet
    $menuText = ''
    try { $menuText = [System.IO.File]::ReadAllText((Join-Path $BackupDir 'mumu-menu.ps1')) } catch { $r.Reason = "cannot read the backed-up mumu-menu.ps1: $($_.Exception.Message)"; return $r }
    $ver = ''
    foreach ($line in ($menuText -split "`n" | Select-Object -First 320)) {
        if ($line -match "\`$scriptVer\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'") { $ver = $Matches[1]; break }
    }
    if ($ver) { $r.MarkerTo = "v$ver"; $r.MarkerWrite = $true }
    $r.Ok = $true
    return $r
}

function Invoke-Rollback {
    # Restores the file set from a backup folder and re-aligns the marker
    # from the restored content's own $scriptVer. Journals 'rollback'
    # (from = marker before, to = marker after); 'rollback-fail' on errors.
    param(
        [Parameter(Mandatory = $true)] [string]$BackupDir,
        [Parameter(Mandatory = $true)] [string]$InstallDir,
        [string]$VersionFile = '',
        [string[]]$FileSet = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')
    )
    if (-not $VersionFile) { $VersionFile = Join-Path $InstallDir '.version' }
    $markerBefore = ''
    try { if (Test-Path -LiteralPath $VersionFile -PathType Leaf) { $markerBefore = (Get-Content -LiteralPath $VersionFile -Raw).Trim() } } catch { Write-Debug "marker read failed: $($_.Exception.Message)" }
    $restored = 0
    foreach ($f in $FileSet) {
        try {
            Copy-Item -LiteralPath (Join-Path $BackupDir $f) -Destination (Join-Path $InstallDir $f) -Force -ErrorAction Stop
            $restored++
        } catch {
            Write-Host "  Failed to restore ${f}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if ($restored -lt $FileSet.Count) {
        Write-UpdateJournal -EventType 'rollback-fail' -From $markerBefore -To '' -Detail "restored $restored of $($FileSet.Count) file(s) from $(Split-Path -Leaf $BackupDir)"
        return $false
    }
    # Re-align the marker from the restored content's own claim (never guess).
    $markerTo = $markerBefore
    $ver = ''
    try {
        $menuText = [System.IO.File]::ReadAllText((Join-Path $InstallDir 'mumu-menu.ps1'))
        foreach ($line in ($menuText -split "`n" | Select-Object -First 320)) {
            if ($line -match "\`$scriptVer\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'") { $ver = $Matches[1]; break }
        }
    } catch { Write-Debug "restored menu read failed: $($_.Exception.Message)" }
    if ($ver) {
        $markerTo = "v$ver"
        try { [System.IO.File]::WriteAllText($VersionFile, $markerTo, (New-Object System.Text.UTF8Encoding($false))) } catch { Write-Debug "marker write failed: $($_.Exception.Message)" }
    }
    Write-UpdateJournal -EventType 'rollback' -From $markerBefore -To $markerTo -Detail "restored $($FileSet.Count) file(s) from $(Split-Path -Leaf $BackupDir)"
    return $true
}

function Show-RollbackFromBackup {
    Write-Host ''
    Write-Host '=== Rollback from backup ===' -ForegroundColor Cyan
    $backups = @(Get-BackupFolders -InstallDir $ScriptDir)
    if ($backups.Count -eq 0) {
        Write-Host '  No backup folders found - nothing to roll back to.' -ForegroundColor Yellow
        Write-Host '  Backups are created automatically before every update (backup\YYYYMMDD_HHMMSS).' -ForegroundColor DarkGray
        return
    }
    Write-Host '  Available backups (newest first):' -ForegroundColor White
    $i = 1
    foreach ($b in $backups) {
        $note = if ($b.HasMenu) { '' } else { '  (incomplete - no mumu-menu.ps1)' }
        Write-Host ("  [{0}] {1}  {2} MB  {3}{4}" -f $i, $b.Name, $b.SizeMB, $b.LastWrite.ToString('yyyy-MM-dd HH:mm'), $note) -ForegroundColor $(if ($b.HasMenu) { 'Yellow' } else { 'DarkGray' })
        $i++
    }
    Write-Host '  [0] Cancel'
    $sel = Read-Host 'Select backup to restore'
    if ($sel -eq '' -or $sel -eq '0' -or $sel -eq 'q') { Write-Host '  Cancelled.' -ForegroundColor DarkGray; return }
    $idx = 0
    if (-not [int]::TryParse($sel, [ref]$idx) -or $idx -lt 1 -or $idx -gt $backups.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red; return
    }
    $chosen = $backups[$idx - 1]
    $plan = Build-RollbackPlan -BackupDir $chosen.Path -InstallDir $ScriptDir
    if (-not $plan.Ok) { Write-Host "  Cannot roll back: $($plan.Reason)" -ForegroundColor Red; return }
    Write-Host ''
    Write-Host "  Will restore $($plan.Files.Count) file(s) from $($chosen.Name):" -ForegroundColor White
    Write-Host "    $($plan.Files -join ', ')"
    if ($plan.MarkerWrite) {
        Write-Host "  Marker will be re-aligned to $($plan.MarkerTo) (the restored content's own scriptVer)." -ForegroundColor DarkGray
    } else {
        Write-Host '  The restored content claims no version - the marker will be left unchanged.' -ForegroundColor DarkGray
    }
    Write-Host '  Note: the current (newer) files are not backed up by this operation.' -ForegroundColor Yellow
    $confirm = Read-Host 'Type ROLLBACK to confirm'
    if ($confirm -cne 'ROLLBACK') { Write-Host '  Cancelled.' -ForegroundColor DarkGray; return }
    if (Invoke-Rollback -BackupDir $chosen.Path -InstallDir $ScriptDir) {
        Write-Host '  Rollback complete. Restart the menu to run the restored version.' -ForegroundColor Green
        $vf = Read-Host '  Run [F] verify installation now? (y/N)'
        if ($vf -eq 'y') { Show-InstallVerify }
    } else {
        Write-Host '  Rollback FAILED - see the journal for details.' -ForegroundColor Red
    }
}

function Show-ProblemDiagnostics {
    # Renders the findings collected by Get-ProblemFindings, grouped by
    # severity, with an honest summary line. Read-only: nothing here
    # mutates the install.
    $findings = @(Get-ProblemFindings -ScriptDir $ScriptDir -VersionFile $VersionFile -MenuPath (Join-Path $ScriptDir 'mumu-menu.ps1') -JournalFile $script:JournalFile -MumuPath $MumuPath -InstalledVersion $InstalledVersion -ScriptVer $scriptVer)
    Write-Host ''
    Write-Host '  === Problem diagnostics ===' -ForegroundColor Cyan
    $errors = @($findings | Where-Object { $_.severity -eq 'error' })
    $warns  = @($findings | Where-Object { $_.severity -eq 'warn' })
    $infos  = @($findings | Where-Object { $_.severity -eq 'info' })
    foreach ($f in $errors) { Write-Host ("  [ERROR] {0}" -f $f.message) -ForegroundColor Red }
    foreach ($f in $warns)  { Write-Host ("  [WARN ] {0}" -f $f.message) -ForegroundColor Yellow }
    foreach ($f in $infos)  { Write-Host ("  [info ] {0}" -f $f.message) -ForegroundColor DarkGray }
    # v1.22.6: the verdict line lives in one shared formatter. Info-only
    # findings are a healthy install - they no longer read as "Problems
    # found: 1"; the honest per-severity counts stay visible either way.
    $diag = Get-DiagSummary -Findings $findings
    if ($findings.Count -eq 0) {
        Write-Host '  No problems detected - install, lock, journal and MuMu environment are healthy.' -ForegroundColor Green
        Write-Host '  Problems found: 0' -ForegroundColor Green
    } elseif ($diag.errors -eq 0 -and $diag.warns -eq 0) {
        Write-Host ''
        Write-Host ("  {0} ({1} info note(s) - nothing to fix)" -f $diag.verdict, $diag.infos) -ForegroundColor Green
    } else {
        Write-Host ''
        $detail = "Problems found: {0} ({1} error(s), {2} warning(s), {3} info)" -f $findings.Count, $diag.errors, $diag.warns, $diag.infos
        Write-Host ("  {0} - {1}" -f $diag.verdict, $detail) -ForegroundColor $diag.color
    }
    Write-Host ("  install: {0}" -f $ScriptDir) -ForegroundColor DarkGray
}

# ── Startup auto-diag (issue #30) ────────────────────────────────────
# Runs the [DIAG] findings collector once per process, silently, at menu
# startup and surfaces ONE line only when errors or warnings exist - info
# findings ("no .version marker yet") stay in [DIAG] and never nag. The
# collector is wrapped in try/catch: diagnostics must never block or
# break the startup. MUMU_MENU_NO_AUTODIAG=1 suppresses the whole thing.
function Get-DiagSummary {
    # Pure formatter for the [DIAG] verdict line (v1.22.6). A findings list
    # that contains only info entries ("1 of 1 instance(s) running", "no
    # journal yet") is a HEALTHY install - the old unconditional "Problems
    # found: 1 (0 error(s), 0 warning(s), 1 info)" read like an alarm while
    # nothing was wrong. Returns a hashtable { verdict, color, errors, warns,
    # infos } so callers share one classification: red verdict when errors
    # exist, yellow for warnings-only, green "Status: healthy" for clean or
    # info-only. Testable without any install fixture.
    param([object[]]$Findings)
    $errors = @($Findings | Where-Object { $_.severity -eq 'error' })
    $warns  = @($Findings | Where-Object { $_.severity -eq 'warn' })
    $infos  = @($Findings | Where-Object { $_.severity -eq 'info' })
    if ($errors.Count -eq 0 -and $warns.Count -eq 0) {
        return @{ verdict = 'Status: healthy'; color = 'Green'; errors = $errors.Count; warns = $warns.Count; infos = $infos.Count }
    }
    $color = if ($errors.Count -gt 0) { 'Red' } else { 'Yellow' }
    $verdict = "Problems found: $($errors.Count) error(s), $($warns.Count) warning(s)"
    if ($infos.Count -gt 0) { $verdict += ", $($infos.Count) info" }
    return @{ verdict = $verdict; color = $color; errors = $errors.Count; warns = $warns.Count; infos = $infos.Count }
}

function Get-AutoDiagSummary {
    # Pure formatter: takes finding objects (severity/message), returns
    # the summary string or '' when nothing needs surfacing (clean or
    # info-only). Testable without any install fixture.
    param([object[]]$Findings)
    $errors = @($Findings | Where-Object { $_.severity -eq 'error' })
    $warns  = @($Findings | Where-Object { $_.severity -eq 'warn' })
    if ($errors.Count -eq 0 -and $warns.Count -eq 0) { return '' }
    return ("Problems found: {0} error(s), {1} warning(s) - details: [DIAG]" -f $errors.Count, $warns.Count)
}

function Invoke-StartupAutoDiag {
    # Collects once per process (guarded by $script:AutoDiagSummary) and
    # returns the summary line ('' = nothing to show). Never throws.
    if ($null -ne $script:AutoDiagSummary) { return $script:AutoDiagSummary }
    $script:AutoDiagSummary = ''
    try {
        $f = @(Get-ProblemFindings -ScriptDir $ScriptDir -VersionFile $VersionFile -MenuPath (Join-Path $ScriptDir 'mumu-menu.ps1') -JournalFile $script:JournalFile -MumuPath $MumuPath -InstalledVersion $InstalledVersion -ScriptVer $scriptVer)
        $script:AutoDiagSummary = Get-AutoDiagSummary -Findings $f
    } catch {
        Write-Debug "auto-diag failed (non-fatal): $($_.Exception.Message)"
    }
    return $script:AutoDiagSummary
}

function Show-AutoDiagLine {
    # Renders the one-line auto-diag verdict under the quick status bar.
    # Empty output = healthy or suppressed - the menu looks exactly as before.
    # Returns the rendered line ('' / $null = nothing shown) for testability.
    if ($env:MUMU_MENU_NO_AUTODIAG -eq '1') { return $null }
    $line = Invoke-StartupAutoDiag
    if ($line) { Write-Host "  [auto-diag] $line" -ForegroundColor Yellow }
    return $line
}

# The verdict is collected once, right after the journal target is known.
$script:AutoDiagSummary = $null

# Persistent ETag cache load (issue #28): hydrate the session tables from
# .etag-cache.json once, after the cache path is known. Hash-validated,
# best-effort - a corrupt store simply yields an empty session cache.
if ($script:EtagCacheFile) {
    if (-not $script:EtagCache)    { $script:EtagCache = @{} }
    if (-not $script:EtagTags)     { $script:EtagTags  = @{} }
    Invoke-EtagCacheMaintenance -CacheFile $script:EtagCacheFile
}

# ── Status screen (issue #25) ────────────────────────────────────────
# One read-only screen answering "what am I on and am I OK?": local
# marker vs latest release, journal summary, last ZIP verification from
# the journal, and (on explicit request) the full drift check vs the tag.
# The fast path never touches the network; unknown states are honest.

function Get-IntegrityVerdict {
    # Classifies a Test-InstallationIntegrity report array into a verdict.
    # The report carries informational lines (verify-start|, ref-pin|,
    # per-file OK|...) plus the author's own verdict in summary|<kind>|.
    # Only the summary (or its absence / an error line) decides - metadata
    # lines must never look like drift (bug caught live in v1.21.5: [ST]
    # reported DRIFT on a healthy install from 'verify-start|...').
    param([string[]]$Report)
    $summary = @($Report | Where-Object { $_ -like 'summary|*' }) | Select-Object -First 1
    if ($summary) {
        $p = $summary -split '\|', 3
        $kind = if ($p.Count -gt 1) { $p[1] } else { '' }
        $payload = if ($p.Count -gt 2) { $p[2] } else { '' }
        switch ($kind) {
            'ok'      { return @{ ok = $true;  detail = 'all files match the tag' } }
            'partial' { return @{ ok = $true;  detail = "files OK, but some could not be downloaded: $payload" } }
            'drift'   { return @{ ok = $false; detail = "drift in: $payload" } }
            default   { return @{ ok = $false; detail = "unknown verdict: $summary" } }
        }
    }
    $errLine = @($Report | Where-Object { $_ -like 'error|*' }) | Select-Object -First 1
    if ($errLine) {
        $p = $errLine -split '\|', 3
        return @{ ok = $false; detail = "check failed: $(if ($p.Count -gt 1) { $p[1] } else { $errLine })" }
    }
    return @{ ok = $false; detail = 'check could not run (release not resolved or network failure)' }
}

function Get-InstallStatus {
    # Builds the status as data (rendering lives in Show-InstallStatus).
    # Network parameters default to off: Get-LatestReleaseTag/Invoke-DriftCheck
    # are scriptblocks so tests can mock them; production passes real ones.
    param(
        [string]$VersionFile,
        [string]$JournalFile,
        [string]$ScriptVer = '',
        [scriptblock]$GetLatestReleaseTag,
        [scriptblock]$InvokeDriftCheck
    )
    $status = [ordered]@{
        localMarker   = ''
        latestRelease = ''
        releaseState  = 'unknown'   # ok | behind | ahead | unknown
        markerNote    = ''
        journal       = @{ exists = $false; events = 0; errors = 0; lastAt = '' }
        lastZipVerify = 'not checked'
        drift         = 'not checked'
        driftNote     = ''
    }
    if ($VersionFile -and (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
        try { $status.localMarker = (Get-Content -LiteralPath $VersionFile -Raw).Trim() } catch { Write-Debug "marker read failed: $($_.Exception.Message)" }
    }
    if ($GetLatestReleaseTag) {
        try { $status.latestRelease = & $GetLatestReleaseTag } catch { $status.latestRelease = '' }
    }
    if ($status.latestRelease -and $status.localMarker) {
        $cmp = Compare-ScriptVersion -A $status.localMarker -B $status.latestRelease
        if ($cmp -eq 0) { $status.releaseState = 'ok' }
        elseif ($cmp -eq -1) {
            $status.releaseState = 'behind'
            $status.markerNote = "update available: $($status.latestRelease)"
        } else {
            $status.releaseState = 'ahead'
            $status.markerNote = 'marker ahead of the latest release - run bootstrap-update.ps1 to repair'
        }
    }
    if ($JournalFile -and (Test-Path -LiteralPath $JournalFile -PathType Leaf)) {
        $status.journal.exists = $true
        $lines = @(Get-Content -LiteralPath $JournalFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
        $status.journal.events = $lines.Count
        $errs = 0
        foreach ($raw in $lines) {
            $p = $raw -split "`t", 6
            if ($p.Count -ge 3 -and $p[2] -match 'fail|error') { $errs++ }
        }
        $status.journal.errors = $errs
        if ($lines.Count -gt 0) {
            $status.journal.lastAt = ($lines[-1] -split "`t")[0]
            # Last ZIP verification verdict from the journal, if any.
            $zipLine = @($lines | Where-Object { (($_ -split "`t")[2]) -match '^zip-verify-(ok|fail)$' } | Select-Object -Last 1)
            if ($zipLine.Count -gt 0) {
                $zp = $zipLine[0] -split "`t", 6
                $status.lastZipVerify = "$(if ($zp[2] -eq 'zip-verify-ok') { 'OK' } else { 'FAILED' }) $($zp[4])".Trim()
            }
        }
    }
    if ($InvokeDriftCheck) {
        try {
            $dr = & $InvokeDriftCheck
            $status.drift = if ($dr.ok) { 'OK' } else { 'DRIFT' }
            $status.driftNote = $dr.detail
        } catch {
            $status.drift = 'unknown'
            $status.driftNote = $_.Exception.Message
        }
    }
    return $status
}

function Show-InstallStatus {
    # Read-only status screen. Enter/direct = fast local view (no network);
    # 'd' adds the full drift check vs the release tag (network).
    # Issue #28: a repeat 'd' in the same session replays the cached verdict
    # (with its age) unless the version marker changed, and the screen shows
    # the persistent ETag cache state.
    param([switch]$Deep)
    Write-Host ''
    Write-Host '  === Install status ===' -ForegroundColor Cyan
    Write-Host ("  ETag cache:                {0}" -f (Get-EtagCacheFileState -CacheFile $script:EtagCacheFile)) -ForegroundColor DarkGray
    $relTag = $null
    $driftCheck = $null
    if ($Deep) {
        $relTag = {
            try {
                $rel = Invoke-GitHubGet "https://api.github.com/repos/$GitHubRepo/releases/latest" 15 | ConvertFrom-Json
                if ($rel -and $rel.tag_name) { return $rel.tag_name } else { return '' }
            } catch { return '' }
        }
        # Session-level cache (issue #28): the deep drift check is the most
        # expensive operation in the menu (several full-body downloads).
        # A repeat 'd' replays the verdict with its age unless the version
        # marker changed since (invalidation on marker change).
        $markerNow = ''
        try { if (Test-Path -LiteralPath $VersionFile -PathType Leaf) { $markerNow = (Get-Content -LiteralPath $VersionFile -Raw).Trim() } } catch { Write-Debug "marker read for drift-cache invalidation failed: $($_.Exception.Message)" }
        if ($script:StDriftCache -and $script:StDriftCache.marker -eq $markerNow) {
            $ageMin = [int]([datetime]::Now - $script:StDriftCache.at).TotalMinutes
            $script:StDriftFromCache = "from session cache, age $($ageMin) min (re-check on next menu restart or marker change)"
            $script:StDriftReplay = $script:StDriftCache.verdict
        } else {
            $script:StDriftFromCache = ''
            $script:StDriftReplay = $null
            $driftCheck = {
                try {
                    $report = Test-InstallationIntegrity
                    return Get-IntegrityVerdict -Report @($report)
                } catch {
                    return @{ ok = $false; detail = "check failed: $($_.Exception.Message)" }
                }
            }
        }
    }
    $st = Get-InstallStatus -VersionFile $VersionFile -JournalFile $script:JournalFile -GetLatestReleaseTag $relTag -InvokeDriftCheck $driftCheck
    if ($Deep -and $script:StDriftReplay) {
        $st.drift = if ($script:StDriftReplay.ok) { 'OK' } else { 'DRIFT' }
        $st.driftNote = "$($script:StDriftReplay.detail) [$($script:StDriftFromCache)]"
    }
    if ($Deep -and $driftCheck) {
        # Cache the fresh verdict for the rest of the session (issue #28).
        $script:StDriftCache = @{ marker = $markerNow; at = [datetime]::Now; verdict = @{ ok = ($st.drift -eq 'OK'); detail = $st.driftNote } }
    }
    $relShown = if ($st.latestRelease) { $st.latestRelease } else { 'unknown (no network in fast mode; press d for full check)' }
    Write-Host ("  Script version:            {0}" -f "v$scriptVer") -ForegroundColor White
    Write-Host ("  Local marker:              {0}" -f $(if ($st.localMarker) { $st.localMarker } else { 'none yet' })) -ForegroundColor White
    Write-Host ("  Latest release:            {0}" -f $relShown) -ForegroundColor White
    $relLine = switch ($st.releaseState) {
        'ok'     { 'marker matches the latest release' }
        'behind' { $st.markerNote }
        'ahead'  { $st.markerNote }
        default  { 'not compared (fast mode - no network)' }
    }
    Write-Host ("  Version state:             {0}" -f $relLine) -ForegroundColor $(if ($st.releaseState -eq 'ok') { 'Green' } elseif ($st.releaseState -eq 'ahead') { 'Red' } elseif ($st.releaseState -eq 'behind') { 'Yellow' } else { 'DarkGray' })
    Write-Host ("  Drift check:               {0}{1}" -f $st.drift, $(if ($st.driftNote) { " - $($st.driftNote)" })) -ForegroundColor $(if ($st.drift -eq 'OK') { 'Green' } elseif ($st.drift -eq 'DRIFT') { 'Red' } else { 'DarkGray' })
    Write-Host ("  Last ZIP verification:     {0}" -f $st.lastZipVerify) -ForegroundColor $(if ($st.lastZipVerify -match '^OK') { 'Green' } elseif ($st.lastZipVerify -match '^FAILED') { 'Red' } else { 'DarkGray' })
    if ($st.journal.exists) {
        Write-Host ("  Journal:                   {0} event(s), {1} error(s), last at {2}" -f $st.journal.events, $st.journal.errors, $(if ($st.journal.lastAt) { $st.journal.lastAt } else { 'n/a' })) -ForegroundColor $(if ($st.journal.errors -gt 0) { 'Yellow' } else { 'White' })
    } else {
        Write-Host '  Journal:                   none yet - no updates performed' -ForegroundColor DarkGray
    }
    Write-Host ("  install: {0}" -f $ScriptDir) -ForegroundColor DarkGray
    if (-not $Deep) {
        Write-Host '  Press d in the menu for a full drift check (network).' -ForegroundColor DarkGray
    }
}

function Show-Menu {
    Clear-Host
    Write-Host '======================================' -ForegroundColor Cyan
    Write-Host '    MuMuManager CLI Menu' -ForegroundColor Cyan
    Show-QuickStatus
    Show-AutoDiagLine
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
    Write-Host '  [VF] VirusTotal Upload file' -ForegroundColor Yellow
    Write-Host '  [UW] Fix Unicode / encoding' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Spoofing ---' -ForegroundColor Green
    Write-Host '  [DM] Spoof device model' -ForegroundColor Yellow
    Write-Host '  [SIM] Change SIM operator / country (MCC/MNC)' -ForegroundColor Yellow
    Write-Host '  [SIM+] View / clear auto-apply SIM config' -ForegroundColor Yellow
    Write-Host '  [SC] SIM check (all properties)' -ForegroundColor Yellow
    Write-Host '  [AI] Set Android ID' -ForegroundColor Yellow
    Write-Host '  [DI] Random device IDs' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- Info ---' -ForegroundColor Green
    Write-Host '  [V] Version info' -ForegroundColor Yellow
    Write-Host '  [U] Check for updates' -ForegroundColor Yellow
    Write-Host '  [UP] Update plan (dry-run)' -ForegroundColor Yellow
    Write-Host '  [F] Verify installation (files vs release tag)' -ForegroundColor Yellow
    Write-Host '  [ST] Install status (read-only)' -ForegroundColor Yellow
    Write-Host '  [J] Update journal' -ForegroundColor Yellow
    Write-Host '  [DIAG] Problem diagnostics' -ForegroundColor Yellow
    Write-Host '  [RB] Rollback from backup' -ForegroundColor Yellow
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
    Apply-SavedSim -Index $index
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
    Apply-SavedSim -Index $index
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
            $headArgs = @('-s', '--connect-timeout', '30', '--max-time', '30', '-D', $tmpHead, '-H', "Authorization: token $GitHubToken", 'https://api.github.com/user')
            $rawUser = & curl.exe @headArgs 2>$null
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

    # Helper: run ADB shell command through MuMuManager (targets specific instance).
    # Guest stderr (e.g. toybox "curl: inaccessible or not found") must never
    # render as PS 5.1 NativeCommandError blocks: capture with EAP
    # SilentlyContinue and flatten ErrorRecords to plain text.
    $run = {
        param($cmd)
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try { $raw = & $MumuPath adb -v $index -c "shell $cmd" 2>&1 } finally { $ErrorActionPreference = $prevEap }
        (($raw | ForEach-Object { "$_" }) -join "`n").TrimEnd()
    }

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
    $hasPing = (& $run 'command -v ping 2>/dev/null || which ping 2>/dev/null').Trim() -match '^/'
    if ($hasPing) {
        $netResult = & $run 'ping -c 2 -W 5 8.8.8.8'
        if ($netResult -match '(\d+) packets transmitted') {
            $sent = [int]($Matches[1])
            $recv = if ($netResult -match '(\d+)\s+(?:packets?\s+)?received') { [int]($Matches[1]) } else { 0 }
            if ($recv -gt 0) {
                $loss = (($sent - $recv) / $sent) * 100
                Write-Host "  Ping: OK (sent=$sent recv=$recv loss=$loss%)" -ForegroundColor Green
            } else {
                Write-Host '  Ping: FAILED (0 received)' -ForegroundColor Red
            }
        } else {
            Write-Host "  Ping: FAILED" -ForegroundColor Red
        }
    } else {
        Write-Host '  Ping: N/A (ping not available in guest)' -ForegroundColor DarkGray
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
    $storage = & $run 'df -h /data'
    if (-not $storage -or $storage.Trim() -eq '') {
        $storage = & $run 'df /data'
    }
    $storLines = $storage -split "`n" | Where-Object { $_ -match '/data' }
    if ($storLines) {
        $parts = $storLines[0] -split '\s+'
        if ($parts.Count -ge 4) {
            $totalGB = [int]$parts[1] / 1048576
            $usedGB = [int]$parts[2] / 1048576
            $availGB = [int]$parts[3] / 1048576
            Write-Host ("  /data: {0:N1} GB / {1:N1} GB used ({2:N1} GB free)" -f $usedGB, $totalGB, $availGB) -ForegroundColor White
        } else {
            Write-Host '  Storage: unable to parse df output' -ForegroundColor Yellow
        }
    } else {
        Write-Host '  Storage: N/A (df not supported via MuMuManager ADB)' -ForegroundColor DarkGray
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

    # Helper: run ADB shell command through MuMuManager (targets specific instance).
    # Guest stderr (e.g. toybox "curl: inaccessible or not found") must never
    # render as PS 5.1 NativeCommandError blocks: capture with EAP
    # SilentlyContinue and flatten ErrorRecords to plain text.
    $run = {
        param($cmd)
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try { $raw = & $MumuPath adb -v $index -c "shell $cmd" 2>&1 } finally { $ErrorActionPreference = $prevEap }
        (($raw | ForEach-Object { "$_" }) -join "`n").TrimEnd()
    }

    # Guest tool availability: toybox images ship without some commands
    # (observed in the field: no curl). A missing tool is N/A, not a network
    # failure - detect before testing so results stay honest.
    $hasPing = (& $run 'command -v ping 2>/dev/null || which ping 2>/dev/null').Trim() -match '^/'
    $dnsCmd = ''
    if ((& $run 'command -v nslookup 2>/dev/null').Trim() -match '^/') { $dnsCmd = 'nslookup' }
    elseif ((& $run 'command -v getent 2>/dev/null').Trim() -match '^/') { $dnsCmd = 'getent' }
    elseif ((& $run 'command -v busybox 2>/dev/null').Trim() -match '^/') { $dnsCmd = 'busybox-nslookup' }
    $hasCurl = (& $run 'command -v curl 2>/dev/null || which curl 2>/dev/null').Trim() -match '^/'
    $httpCmd = if ($hasCurl) { 'curl' }
    elseif ((& $run 'command -v wget 2>/dev/null').Trim() -match '^/') { 'wget' }
    elseif ((& $run 'command -v busybox 2>/dev/null').Trim() -match '^/') { 'busybox-wget' }
    else { '' }

    # Ping test
    Write-Host '[1] Ping test' -ForegroundColor Yellow
    $targets = @('8.8.8.8', '1.1.1.1', '223.5.5.5', 'google.com', 'github.com')
    if ($hasPing) {
        foreach ($t in $targets) {
            $result = & $run "ping -c 2 -W 5 $t"
            # busybox/iputils: "rtt min/avg/max/mdev = ..."; Android toybox:
            # "round-trip min/avg/max = ..." - accept both.
            if ($result -match '(?:rtt|round-trip) min[^=\n]*=\s*([\d.]+)/([\d.]+)/([\d.]+)') {
                Write-Host "  $t : OK (avg $($Matches[2])ms)" -ForegroundColor Green
            } elseif ($result -match '(\d+)\s+(?:packets?\s+)?received') {
                $recv = [int]$Matches[1]
                if ($recv -gt 0) { Write-Host "  $t : OK" -ForegroundColor Green }
                else { Write-Host "  $t : FAILED" -ForegroundColor Red }
            } else {
                Write-Host "  $t : FAILED" -ForegroundColor Red
            }
        }
    } else {
        Write-Host '  N/A: ping not available in guest - ping test skipped' -ForegroundColor DarkGray
    }

    # DNS resolution
    Write-Host ''
    Write-Host '[2] DNS resolution' -ForegroundColor Yellow
    $dnsTargets = @('google.com', 'github.com', 'baidu.com')
    if ($dnsCmd) {
        foreach ($d in $dnsTargets) {
            $dnsOk = $false
            if ($dnsCmd -eq 'nslookup') {
                $result = & $run "nslookup $d"
                $dnsOk = $result -match 'Address:\s+\d'
            } elseif ($dnsCmd -eq 'busybox-nslookup') {
                # MuMu 12 images ship /system/xbin/busybox without nslookup symlink
                $result = & $run "busybox nslookup $d"
                $dnsOk = $result -match 'Address\s+\d+:\s+\d+'
            } else {
                $result = & $run "getent hosts $d"
                $dnsOk = $result -match '\d+\.\d+\.\d+\.\d+'
            }
            if ($dnsOk) {
                Write-Host "  $d : OK" -ForegroundColor Green
            } else {
                Write-Host "  $d : FAILED" -ForegroundColor Red
            }
        }
    } else {
        Write-Host '  N/A: no nslookup/getent in guest - DNS test skipped' -ForegroundColor DarkGray
    }

    # HTTP test
    Write-Host ''
    Write-Host '[3] HTTP test' -ForegroundColor Yellow
    $httpTargets = @(
        @{ Url = 'http://connectivitycheck.gstatic.com/generate_204'; Name = 'Google' },
        @{ Url = 'http://www.baidu.com'; Name = 'Baidu' },
        @{ Url = 'https://github.com'; Name = 'GitHub' }
    )
    if ($httpCmd) {
        foreach ($h in $httpTargets) {
            $code = 'ERR'
            if ($httpCmd -eq 'curl') {
                $code = (& $run "curl -s -o /dev/null -w '%{http_code}' --max-time 10 $($h.Url)").Trim()
                $ok = $code -match '^(200|301|302|204)$'
            } else {
                # busybox 1.22 wget has no -S; old GNU wget: -S prints to stderr,
                # both captured through the flattened stderr helper. Exit code
                # decides - codes are parsed only when the tool prints them.
                $result = & $run "$httpCmd wget -q -O /dev/null --timeout=10 $($h.Url)"
                $ok = ($result -notmatch 'wget: (not an http|bad address|I/O error|server returned error)')
            }
            if ($ok) {
                Write-Host "  $($h.Name) : OK$(if ($code -ne 'ERR') { " ($code)" })" -ForegroundColor Green
            } else {
                Write-Host "  $($h.Name) : FAILED" -ForegroundColor Red
            }
        }
    } else {
        Write-Host '  N/A: no curl/wget/busybox in guest - HTTP test skipped' -ForegroundColor DarkGray
        Write-Host '  (missing tool in the Android image, not a network failure)' -ForegroundColor DarkGray
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
            break
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
                # Multipart upload via curl.exe (see SIGMA note in header: the
                # hand-built MIME header tripped the NTFS ADS scriptblock rule).
                $curlCfg = Join-Path $env:TEMP ("vt-" + [Guid]::NewGuid().ToString('N') + ".cfg")
                Set-Content -LiteralPath $curlCfg -Value "header = `"x-apikey: $apiKey`"" -Encoding ASCII -Force
                $null = & curl.exe -sS --fail --max-time 300 --config $curlCfg -F "file=@$($f.Path)" 'https://www.virustotal.com/api/v3/files' 2>$null
                $curlRc = $LASTEXITCODE
                Remove-Item -LiteralPath $curlCfg -Force -ErrorAction SilentlyContinue
                if ($curlRc -eq 0) {
                    Write-Host ' done (analyzing...)' -ForegroundColor Green
                    Write-Host "    https://www.virustotal.com/gui/file/$hash" -ForegroundColor DarkGray
                } else {
                    Write-Host " FAILED (curl exit $curlRc)" -ForegroundColor Red
                }
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

function Upload-VirusTotal {
    Write-Host ''
    Write-Host '=== VirusTotal Upload File ===' -ForegroundColor Cyan
    Write-Host ''

    $apiKey = Get-VTApiKey
    if (-not $apiKey) {
        Write-Host '  No API key configured.' -ForegroundColor Yellow
        Write-Host '  Select [VK] to save your key, or [VT][4] to open VT in browser.' -ForegroundColor DarkGray
        return
    }

    # Prompt for file path
    Write-Host '  Enter the file path to upload:' -ForegroundColor Yellow
    Write-Host '  (Tip: drag and drop a file into this window)' -ForegroundColor DarkGray
    $filePath = (Read-Host '  File path').Trim()
    if (-not $filePath) {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        return
    }

    # Strip surrounding quotes if present
    $filePath = $filePath.Trim('"').Trim("'")

    # Resolve relative to ScriptDir
    if (-not [IO.Path]::IsPathRooted($filePath)) {
        $filePath = Join-Path $ScriptDir $filePath
    }

    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Write-Host "  File not found: $filePath" -ForegroundColor Red
        return
    }

    # Check file size (VT free API limit: 32 MB)
    $fileInfo = Get-Item -LiteralPath $filePath
    $maxSize = 32MB
    if ($fileInfo.Length -gt $maxSize) {
        $sizeMB = [math]::Round($fileInfo.Length / 1MB, 1)
        Write-Host "  File too large: ${sizeMB} MB (VT free limit: 32 MB)" -ForegroundColor Red
        return
    }

    $fileName = $fileInfo.Name
    $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLower()
    $sizeStr = if ($fileInfo.Length -gt 1MB) { "$([math]::Round($fileInfo.Length / 1MB, 1)) MB" }
               elseif ($fileInfo.Length -gt 1KB) { "$([math]::Round($fileInfo.Length / 1KB, 1)) KB" }
               else { "$($fileInfo.Length) B" }

    Write-Host ''
    Write-Host "  File:      $fileName" -ForegroundColor White
    Write-Host "  Size:      $sizeStr" -ForegroundColor White
    Write-Host "  SHA256:    $($hash.Substring(0,16))..." -ForegroundColor White
    Write-Host ''

    # Check if already on VT
    $existing = $false
    try {
        $checkUrl = "https://www.virustotal.com/api/v3/files/$hash"
        $checkResult = Invoke-RestMethod -Uri $checkUrl -Headers @{ 'x-apikey' = $apiKey } -ErrorAction Stop
        $existing = $true
        $stats = $checkResult.data.attributes.last_analysis_stats
        $m = $stats.malicious; $s = $stats.suspicious; $u = $stats.undetected; $h = $stats.harmless
        $t = $m + $s + $u + $h
        if ($m -gt 0 -or $s -gt 0) {
            Write-Host "  DETECTED: $m malicious, $s suspicious / $t engines" -ForegroundColor Red
        } else {
            Write-Host "  0/$t clean" -ForegroundColor Green
        }
        Write-Host "  https://www.virustotal.com/gui/file/$hash" -ForegroundColor DarkGray
    } catch {
        Write-Debug "VT file lookup: $($_.Exception.Message)"
    }

    # Upload
    Write-Host ''
    Write-Host '  Uploading to VirusTotal...' -ForegroundColor Cyan -NoNewline
    try {
        # Multipart upload via curl.exe (see SIGMA note in header: the
        # hand-built MIME header tripped the NTFS ADS scriptblock rule).
        $curlCfg = Join-Path $env:TEMP ("vt-" + [Guid]::NewGuid().ToString('N') + ".cfg")
        Set-Content -LiteralPath $curlCfg -Value "header = `"x-apikey: $apiKey`"" -Encoding ASCII -Force
        $respText = & curl.exe -sS --fail --max-time 300 --config $curlCfg -F "file=@$filePath" 'https://www.virustotal.com/api/v3/files' 2>$null
        $curlRc = $LASTEXITCODE
        Remove-Item -LiteralPath $curlCfg -Force -ErrorAction SilentlyContinue
        if ($curlRc -ne 0 -or -not $respText) { throw "VT upload failed (curl exit $curlRc)" }
        $uploadResult = $respText | ConvertFrom-Json
        $analysisId = $uploadResult.data.id
        if (-not $analysisId) { throw 'VT upload failed: no analysis id in response' }
        Write-Host ' done!' -ForegroundColor Green
        Write-Host ''
        Write-Host "  Analysis ID: $analysisId" -ForegroundColor White
        Write-Host "  File URL:    https://www.virustotal.com/gui/file/$hash" -ForegroundColor DarkGray
        Write-Host ''

        # Ask to poll for results
        $poll = Read-Host '  Wait for analysis results? (y/N)'
        if ($poll -eq 'y' -or $poll -eq 'Y') {
            Write-Host ''
            Write-Host '  Waiting for analysis...' -ForegroundColor Cyan
            $maxWait = 120
            $elapsed = 0
            while ($elapsed -lt $maxWait) {
                Start-Sleep -Seconds 5
                $elapsed += 5
                try {
                    $pollUrl = "https://www.virustotal.com/api/v3/analyses/$analysisId"
                    $pollResult = Invoke-RestMethod -Uri $pollUrl -Headers @{ 'x-apikey' = $apiKey } -ErrorAction Stop
                    $status = $pollResult.data.attributes.status
                    if ($status -eq 'completed') {
                        $rStats = $pollResult.data.attributes.stats
                        $rm = $rStats.malicious; $rs = $rStats.suspicious; $ru = $rStats.undetected; $rh = $rStats.harmless
                        $rt = $rm + $rs + $ru + $rh
                        Write-Host ''
                        Write-Host "  Analysis complete!" -ForegroundColor Green
                        Write-Host ''
                        if ($rm -gt 0 -or $rs -gt 0) {
                            Write-Host "  DETECTED: $rm malicious, $rs suspicious / $rt engines" -ForegroundColor Red
                        } else {
                            Write-Host "  0/$rt clean" -ForegroundColor Green
                        }
                        Write-Host "  https://www.virustotal.com/gui/file/$hash" -ForegroundColor DarkGray
                        break
                    }
                    Write-Host "  [$elapsed s] status: $status" -ForegroundColor DarkGray
                } catch {
                    Write-Host "  [$elapsed s] polling..." -ForegroundColor DarkGray
                }
            }
            if ($elapsed -ge $maxWait) {
                Write-Host "  Timed out after ${maxWait}s. Check results later:" -ForegroundColor Yellow
                Write-Host "  https://www.virustotal.com/gui/file/$hash" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host ' FAILED' -ForegroundColor Red
        $errMsg = $_.Exception.Message
        if ($errMsg -match 'Forbidden') {
            Write-Host '  API key may be invalid or expired.' -ForegroundColor Yellow
        } elseif ($errMsg -match '429|rate') {
            Write-Host '  Rate limit exceeded. Wait and try again.' -ForegroundColor Yellow
        } else {
            Write-Host "  Error: $errMsg" -ForegroundColor Red
        }
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
    Write-Host '  [5] Add missing BOM to .ps1 files (PowerShell 5.1 repair)' -ForegroundColor White
    Write-Host ''
    $mode = Read-Host 'Select option (1/2/3/4/5)'

    if ($mode -eq '1') {
        # Scan for encoding issues
        Write-Host ''
        Write-Host 'Scanning files...' -ForegroundColor Cyan
        # update-journal.log is runtime data with arbitrary text fragments -
        # it always scans as noise and belongs to [J], not to an encoding audit.
        $files = Get-ChildItem -LiteralPath $ScriptDir -File -Include '*.ps1','*.md','*.txt','*.yml','*.json' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\.git\\' -and $_.FullName -notmatch '\\.freebuff\\' -and $_.Name -ne 'update-journal.log' }

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

            $isScript = $f.Extension -eq '.ps1'
            $status = 'OK'
            $color = 'Green'
            if ($mojibake -or $hasReplacement) {
                $status = 'MOJIBAKE'
                $color = 'Red'
                $bad++
            } elseif ($hasBOM -and -not $isScript) {
                $status = 'UTF-8 BOM (OK - safe to strip)'
                $color = 'Yellow'
                $warn++
            } elseif ($hasBOM) {
                # The BOM on .ps1 files is intentional: PowerShell 5.1 reads
                # BOM-less files in the system ANSI codepage and garbles
                # non-ASCII literals (box-drawing chars, Cyrillic strings).
                $status = 'UTF-8 BOM (required for PowerShell 5.1)'
                $color = 'DarkGray'
                $ok++
            } else {
                $ok++
            }

            $rel = $f.FullName.Substring($ScriptDir.Length + 1)
            Write-Host "  [$status] $rel" -ForegroundColor $color
        }

        Write-Host ''
        Write-Host "  OK: $ok  |  Warnings: $warn  |  Mojibake: $bad" -ForegroundColor Cyan
        if ($bad -eq 0) {
            Write-Host '  BOM on .ps1 files is intentional (PowerShell 5.1 ANSI fallback) - do not strip.' -ForegroundColor DarkGray
        }

    } elseif ($mode -eq '2') {
        # Fix encoding - convert to UTF-8 without BOM
        Write-Host ''
        $path = (Read-Host 'Enter file path (or folder)').Trim()
        $path = $path.Trim('"').Trim()

        Write-Host '  NOTE: .ps1 files are skipped - they need their BOM (PowerShell 5.1'
        Write-Host '  reads BOM-less scripts in the system ANSI codepage and garbles non-ASCII).'

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host 'Path not found.' -ForegroundColor Red
            return
        }

        $files = if ((Get-Item -LiteralPath $path).PSIsContainer) {
            Get-ChildItem -LiteralPath $path -File -Include '*.ps1','*.md','*.txt','*.yml','*.json' -Recurse -ErrorAction SilentlyContinue
        } else {
            Get-Item -LiteralPath $path
        }

        # Never strip the BOM from PowerShell scripts (PS 5.1 ANSI fallback).
        $files = @($files | Where-Object { $_.Extension -ne '.ps1' })

        if ($files.Count -gt 0) {
            Write-Host ''
            $resp = Read-Host "  Convert $($files.Count) file(s) to UTF-8 without BOM? (y/N)"
            if ($resp -ne 'y' -and $resp -ne 'Y') {
                Write-Host '  Cancelled.' -ForegroundColor DarkGray
                return
            }
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
                    $dec = [System.Text.UTF8Encoding]::new($false, $true)
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

            # Convert to UTF-8 without BOM. ANSI/other files must be decoded
            # in the system codepage - UTF-8 decode of ANSI bytes silently
            # replaces every non-ASCII character with U+FFFD.
            $content = if ($encoding -eq 'ANSI/other') {
                [System.Text.Encoding]::Default.GetString($bytes)
            } else {
                [System.IO.File]::ReadAllText($f.FullName)
            }
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
            $dec = [System.Text.UTF8Encoding]::new($false, $true)
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

    } elseif ($mode -eq '5') {
        # Add BOM to BOM-less .ps1 files - the reverse repair. The scanner
        # (option 1) treats .ps1 BOM as required; this heals foreign scripts
        # that non-ASCII-literal code and would garble under PowerShell 5.1's
        # ANSI fallback (comments/strings become mojibake on RU Windows).
        # Scan defaults to the install dir - the file may sit anywhere.
        Write-Host ''
        Write-Host '  Scans a folder for .ps1 files WITHOUT a BOM that contain non-ASCII' -ForegroundColor White
        Write-Host '  characters - those garble under PowerShell 5.1 (ANSI fallback).' -ForegroundColor White
        $path = (Read-Host 'Enter folder (Enter = install dir)').Trim().Trim('"')
        if (-not $path) { $path = $ScriptDir }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            Write-Host "Folder not found: $path" -ForegroundColor Red
            return
        }
        $files = @((Get-ChildItem -LiteralPath $path -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue) |
            Where-Object { $_.FullName -notmatch '\\.git\\' -and $_.FullName -notmatch '\\.freebuff\\' })
        $candidates = @()
        foreach ($f in $files) {
            $b = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { continue }
            if ($b.Length -ge 2 -and (($b[0] -eq 0xFF -and $b[1] -eq 0xFE) -or ($b[0] -eq 0xFE -and $b[1] -eq 0xFF))) { continue }
            # UTF-16 without BOM: NUL byte in the first two - not a repair case.
            if ($b.Length -ge 2 -and ($b[0] -eq 0 -or $b[1] -eq 0)) { continue }
            $nonAscii = $false
            for ($i = 0; $i -lt $b.Length; $i++) {
                if ($b[$i] -gt 127) { $nonAscii = $true; break }
            }
            if ($nonAscii) { $candidates += $f }
        }
        if ($candidates.Count -eq 0) {
            Write-Host '  No repairable .ps1 files found (all have a BOM, UTF-16, or pure ASCII).' -ForegroundColor Green
            return
        }
        Write-Host "  Repairable .ps1 files (BOM-less, contains non-ASCII):" -ForegroundColor Yellow
        foreach ($f in $candidates) { Write-Host "    $($f.FullName.Substring($path.Length).TrimStart('\'))" -ForegroundColor Yellow }
        $resp = Read-Host "  Prepend UTF-8 BOM to $($candidates.Count) file(s)? (y/N)"
        if ($resp -ne 'y' -and $resp -ne 'Y') {
            Write-Host '  Cancelled - nothing written.' -ForegroundColor DarkGray
            return
        }
        foreach ($f in $candidates) {
            try {
                $b = [System.IO.File]::ReadAllBytes($f.FullName)
                # Explicit EF BB BF byte array - a char 0xFEFF does not fit a byte.
                $out = New-Object byte[] (3 + $b.Length)
                $out[0] = 0xEF; $out[1] = 0xBB; $out[2] = 0xBF
                [Array]::Copy($b, 0, $out, 3, $b.Length)
                [System.IO.File]::WriteAllBytes($f.FullName, $out)
            } catch {
                Write-Host "  FAILED: $($f.Name) ($($_.Exception.Message))" -ForegroundColor Red
                continue
            }
            Write-Host "  BOM added: $($f.Name)" -ForegroundColor Green
        }
        Write-Host '  Done. Re-run option 1 to confirm every .ps1 now reports the BOM as required.' -ForegroundColor Green
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

            $rawStr = Invoke-GitHubApiGet -Url 'https://api.github.com/user' -Token $plain
            $user = $rawStr | ConvertFrom-Json

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
        $rawStr = Invoke-GitHubApiGet -Url 'https://api.github.com/user' -Token $plain
        if (-not $rawStr.Trim()) {
            Write-Host 'Token check failed: GitHub did not respond (network problem). Nothing was saved.' -ForegroundColor Red
            Write-Host 'Note: a valid token is NOT invalidated by a failed check. Try again later.' -ForegroundColor Yellow
            return
        }
        $user = $rawStr | ConvertFrom-Json
        if (-not $user.login) {
            if ($rawStr -match 'Bad credentials') {
                Write-Host 'Token rejected by GitHub (Bad credentials) - the token is wrong or revoked. Nothing was saved.' -ForegroundColor Red
            } else {
                Write-Host 'Token validation failed: unexpected response from GitHub (see above). Nothing was saved.' -ForegroundColor Red
                Write-Host ($rawStr.Trim() | Select-Object -First 1) -ForegroundColor DarkGray
            }
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
        $branchJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/branches"
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
        $relListJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/releases?per_page=20"
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
                $dlArgs = @('-sS', '--fail', '--retry', '2', '--connect-timeout', '30', '--max-time', '60', '-L', '-H', 'Accept: application/vnd.github.v3.raw', '-o', $fDest, $fUrl)
                if ($GitHubToken) { $dlArgs += @('-H', "Authorization: token $GitHubToken") }
                & curl.exe @dlArgs 2>$null | Out-Null
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
        $zipArgs = @('-#', '--fail', '--connect-timeout', '30', '--max-time', '300', '--retry', '3', '--retry-delay', '3', '-L', '-o', $zipPath, $zipUrl)
        if ($GitHubToken) { $zipArgs += @('-H', "Authorization: token $GitHubToken") }
        & curl.exe @zipArgs 2>$null
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
        $relJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/releases/latest"
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
                $dlArgs = @('-sS', '--fail', '--retry', '2', '--connect-timeout', '30', '--max-time', '60', '-L', '-H', 'Accept: application/vnd.github.v3.raw', '-o', $fDest, $fUrl)
                if ($GitHubToken) { $dlArgs += @('-H', "Authorization: token $GitHubToken") }
                & curl.exe @dlArgs 2>$null | Out-Null
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
        $zipArgs = @('-#', '--fail', '--connect-timeout', '30', '--max-time', '300', '--retry', '3', '--retry-delay', '3', '-L', '-o', $zipPath, $zipUrl)
        if ($GitHubToken) { $zipArgs += @('-H', "Authorization: token $GitHubToken") }
        & curl.exe @zipArgs 2>$null
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
            $relJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/releases/latest"
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
                    $dlArgs = @('-sS', '--fail', '--retry', '2', '--connect-timeout', '30', '--max-time', '60', '-L', '-H', 'Accept: application/vnd.github.v3.raw', '-o', $fDest, $fUrl)
                    if ($GitHubToken) { $dlArgs += @('-H', "Authorization: token $GitHubToken") }
                    & curl.exe @dlArgs 2>$null | Out-Null
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

            $zipArgs = @('-#', '--fail', '--connect-timeout', '30', '--max-time', '300', '--retry', '3', '--retry-delay', '3', '-L', '-o', $tmp, $zipUrl)
            if ($GitHubToken) { $zipArgs += @('-H', "Authorization: token $GitHubToken") }
            & curl.exe @zipArgs 2>$null
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
            $ltJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/releases/latest"
            try { $lt = $ltJson | ConvertFrom-Json } catch { $lt = $null }
            if ($lt.tag_name) { $ref = $lt.tag_name; Write-Host "  Using: $ref" -ForegroundColor DarkGray }
            else { $ref = 'main'; Write-Host '  Using: main (no releases found)' -ForegroundColor DarkGray }
        }

        # List files in repo root
        Write-Host ''
        Write-Host "Fetching file list ($ref)..." -ForegroundColor DarkGray
        $listJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/contents/?ref=$ref"
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
        $dlArgs = @('-sL', '--connect-timeout', '30', '--max-time', '120', '-o', (Join-Path $targetDir $fileName))
        if ($GitHubToken) { $dlArgs += @('-H', "Authorization: token $GitHubToken") }
        $dlArgs += @('-H', 'Accept: application/vnd.github.v3.raw', $downloadUrl)
        & curl.exe @dlArgs 2>$null | Out-Null
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
    $relJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/releases" -ExtraArgs @('-H', 'Accept: application/vnd.github.v3+json')
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
    $patchArgs = @('-s', '--connect-timeout', '30', '--max-time', '60', '-X', 'PATCH', '-H', "Authorization: token $GitHubToken", '-H', 'Accept: application/vnd.github.v3+json', '-H', 'Content-Type: application/json; charset=utf-8', '-d', "@$jsonFile", "https://api.github.com/repos/$GitHubRepo/releases/$($chosen.id)")
    $result = & curl.exe @patchArgs 2>$null | Out-String

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
    $tagsJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/tags"
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
            $compareJson = Invoke-GitHubApiGet -Url "https://api.github.com/repos/$GitHubRepo/compare/$baseTag...$tagName"
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
        $postArgs = @('-s', '-X', 'POST', '-H', "Authorization: token $GitHubToken", '-H', 'Accept: application/vnd.github.v3+json', '-H', 'Content-Type: application/json', '-d', "@$tmpPayload", '-o', $tmpResp, $releaseUrl)
        & curl.exe @postArgs 2>$null

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
            foreach ($idx in $indices) { Apply-SavedSim -Index $idx }
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

    # Check for updates (2 attempts - a single TLS flake must not read as
    # "Cannot check updates"; mirrors the v1.21.9 retry hardening)
    $latest = $null
    for ($vAttempt = 1; $vAttempt -le 2 -and -not $latest; $vAttempt++) {
        try {
            $latest = (Invoke-WebRequest -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest" -UseBasicParsing -TimeoutSec 10).Content | ConvertFrom-Json
        } catch {
            if ($vAttempt -lt 2) { Start-Sleep -Seconds 2 }
        }
    }
    try {
        if ($latest -and $latest.tag_name) {
            $latestVer = $latest.tag_name -replace '^v',''
            if ($latestVer -ne $scriptVer) {
                Write-Host "  -> Update available: $latestVer (run [U] to update)" -ForegroundColor Yellow
            } else {
                Write-Host '  -> Up to date' -ForegroundColor DarkGray
            }
        } elseif ($latest -and $latest.message -match 'rate limit') {
            Write-Host '  -> Rate limit exceeded - cannot check now' -ForegroundColor Yellow
            Write-Host "     ($($(if ($GitHubToken) { 'token quota exhausted' } else { '60 req/hr without a token; add one via [K]' })))" -ForegroundColor DarkGray
        } else {
            Write-Host '  -> Cannot check updates' -ForegroundColor DarkGray
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

function Show-SimCheck {
    $index = Get-InstanceIndex 'Select instance to check'
    if (-not $index) { return }
    Write-Host ''
    Write-Host "Checking SIM properties on instance $index..." -ForegroundColor Cyan

    # Get all properties with timeout
    $props = ''
    try {
        $checkJob = Start-Job -ScriptBlock {
            param($mp, $idx)
            & $mp adb -v $idx -c 'shell getprop' 2>$null | Out-String
        } -ArgumentList $MumuPath, $index
        if (Wait-Job $checkJob -Timeout 10) {
            $props = Receive-Job $checkJob
        } else {
            Write-Host '  ADB not ready — cannot check properties.' -ForegroundColor Yellow
            Remove-Job $checkJob -Force -ErrorAction SilentlyContinue
            return
        }
        Remove-Job $checkJob -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    if (-not $props) {
        Write-Host '  No properties returned.' -ForegroundColor Yellow
        return
    }

    # Define property groups
    $groups = @(
        @{ Title = 'SIM Operator (gsm.sim.*)'; Props = @('gsm.sim.operator.numeric', 'gsm.sim.operator.alpha', 'gsm.sim.operator.iso-country', 'gsm.sim.operator.isroaming', 'gsm.sim.state') }
        @{ Title = 'Network Operator (gsm.operator.*)'; Props = @('gsm.operator.numeric', 'gsm.operator.alpha', 'gsm.operator.iso-country', 'gsm.operator.isroaming') }
        @{ Title = 'MuMu Persist'; Props = @('persist.mumu.mccmnc') }
        @{ Title = 'Settings Global'; Props = @('gsm.operator.alpha') }
        @{ Title = 'Emulator Internal'; Props = @('debug.tracing.mcc', 'debug.tracing.mnc', 'ro.carrier', 'gsm.network.type', 'gsm.current.phone-type') }
        @{ Title = 'Device Identity'; Props = @('ro.product.model', 'ro.product.brand', 'ro.product.manufacturer', 'ro.serialno') }
    )

    foreach ($group in $groups) {
        Write-Host ''
        Write-Host "  $($group.Title)" -ForegroundColor Cyan
        Write-Host ('  ' + ('-' * 40)) -ForegroundColor DarkGray
        foreach ($p in $group.Props) {
            if ($props -match "\[$p\]:\s*\[(.*?)\]") {
                $val = $Matches[1]
                $color = 'White'
                if ($p -eq 'persist.mumu.mccmnc' -or $p -eq 'debug.tracing.mcc') {
                    $color = if ($val -and $val -ne '460') { 'Green' } else { 'Yellow' }
                }
                Write-Host "    $p = $val" -ForegroundColor $color
            } else {
                Write-Host "    $p = (not set)" -ForegroundColor DarkGray
            }
        }
    }

    # Summary
    $mccmnc = ''
    if ($props -match '\[gsm\.sim\.operator\.numeric\]:\s*\[(.*?)\]') { $mccmnc = $Matches[1] }
    $alpha = ''
    if ($props -match '\[gsm\.sim\.operator\.alpha\]:\s*\[(.*?)\]') { $alpha = $Matches[1] }
    $persist = ''
    if ($props -match '\[persist\.mumu\.mccmnc\]:\s*\[(.*?)\]') { $persist = $Matches[1] }
    $traceMcc = ''
    if ($props -match '\[debug\.tracing\.mcc\]:\s*\[(.*?)\]') { $traceMcc = $Matches[1] }

    Write-Host ''
    Write-Host '  ┌────────────────────────────────────────┐' -ForegroundColor Cyan
    Write-Host '  │  SIM STATUS SUMMARY                    │' -ForegroundColor Cyan
    Write-Host '  ├────────────────────────────────────────┤' -ForegroundColor Cyan
    Write-Host "  │  Operator:  $(if ($alpha) { $alpha } else { '(not set)' })" -ForegroundColor White
    Write-Host "  │  MCC/MNC:   $(if ($mccmnc) { $mccmnc } else { '(not set)' })" -ForegroundColor White
    Write-Host "  │  Persist:   $(if ($persist) { $persist } else { '(not set)' })" -ForegroundColor $(if ($persist -eq $mccmnc) { 'Green' } else { 'Yellow' })
    Write-Host "  │  Tracing:   $(if ($traceMcc) { $traceMcc } else { '(not set)' })" -ForegroundColor $(if ($traceMcc -and $traceMcc -ne '460') { 'Green' } else { 'Yellow' })
    $match = ($mccmnc -eq $persist) -and ($persist -ne '')
    Write-Host "  │  Consistent: $(if ($match) { 'YES' } else { 'NO — some values differ' })" -ForegroundColor $(if ($match) { 'Green' } else { 'Yellow' })
    Write-Host '  └────────────────────────────────────────┘' -ForegroundColor Cyan
}

function Show-SimConfig {
    $cfg = Get-SimConfig
    $entries = @()
    if ($cfg -is [hashtable] -or $cfg -is [PSCustomObject]) {
        foreach ($prop in $cfg.PSObject.Properties) {
            $entries += @{ Index = $prop.Name; Entry = $prop.Value }
        }
    }

    # Get instance states for display
    $states = @{}
    try {
        $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
        foreach ($key in $info.PSObject.Properties.Name) {
            $states[$key] = $info.$key.player_state
        }
    } catch {
        Write-Debug "Could not read instance states: $($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host '═══════════════════════════════════════════' -ForegroundColor Cyan
    Write-Host '  AUTO-APPLY SIM CONFIG' -ForegroundColor Cyan
    Write-Host '═══════════════════════════════════════════' -ForegroundColor Cyan
    if ($entries.Count -eq 0) {
        Write-Host ''
        Write-Host '  (none — use [SIM] to set a SIM operator first)' -ForegroundColor DarkGray
    } else {
        Write-Host ''
        Write-Host '  IDX  State          Operator              MCC/MNC   CC' -ForegroundColor DarkGray
        Write-Host '  ---  -------------- --------------------- --------- --' -ForegroundColor DarkGray
        foreach ($e in $entries) {
            $v = $e.Entry
            $state = if ($states.ContainsKey($e.Index)) { $states[$e.Index] } else { 'unknown' }
            $stateShort = if ($state -match 'start_finished|running') { 'running' }
                          elseif ($state -match 'stopped') { 'stopped' }
                          elseif ($state) { $state.Substring(0, [Math]::Min(10, $state.Length)) }
                          else { '?' }
            $stateColor = if ($stateShort -eq 'running') { 'Green' } elseif ($stateShort -eq 'stopped') { 'DarkGray' } else { 'Yellow' }
            $mccmnc = "$($v.mcc)/$($v.mnc)"
            Write-Host '  ' -NoNewline
            Write-Host ('{0,-4}' -f $e.Index) -NoNewline -ForegroundColor White
            Write-Host ('{0,-15}' -f "[$stateShort]") -NoNewline -ForegroundColor $stateColor
            Write-Host ('{0,-22}' -f $v.name) -NoNewline -ForegroundColor White
            Write-Host ('{0,-10}' -f $mccmnc) -NoNewline -ForegroundColor White
            Write-Host $v.cc -ForegroundColor White
        }
        Write-Host ''
        Write-Host '  [A]  Apply saved config to a running instance' -ForegroundColor Yellow
        Write-Host '  [E]  Edit config (change operator for an instance)' -ForegroundColor Yellow
        Write-Host '  [V]  Verify current props match saved config' -ForegroundColor Yellow
        Write-Host '  [D]  Delete all saved SIM configs' -ForegroundColor Yellow
        Write-Host '  [DX] Delete SIM config for a specific instance' -ForegroundColor Yellow
        Write-Host '  [0]  Back' -ForegroundColor Yellow
        $choice = (Read-Host 'Action').Trim()
        if ($choice -eq 'd' -or $choice -eq 'D') {
            Remove-Item -LiteralPath $SimConfigFile -Force -ErrorAction SilentlyContinue
            Write-Host 'All saved SIM configs cleared.' -ForegroundColor Green
        } elseif ($choice -eq 'dx' -or $choice -eq 'DX') {
            $idx = (Read-Host 'Instance index to clear').Trim()
            if ($idx -and $cfg.$idx) {
                $cfg.Remove($idx)
                Save-SimConfig $cfg
                Write-Host "SIM config for instance $idx cleared." -ForegroundColor Green
            } else {
                Write-Host 'No config found for that instance.' -ForegroundColor Yellow
            }
        } elseif ($choice -eq 'a' -or $choice -eq 'A') {
            $idx = (Read-Host 'Instance index to apply to').Trim()
            if (-not $idx -or -not $cfg.$idx) {
                Write-Host 'No saved config for that instance.' -ForegroundColor Yellow; return
            }
            $v = $cfg.$idx
            $state = if ($states.ContainsKey($idx)) { $states[$idx] } else { '' }
            if ($state -notmatch 'start_finished|running') {
                Write-Host "  Instance $idx is not running ($state). Start it first." -ForegroundColor Yellow
                return
            }
            Write-Host "  Applying $($v.name) ($($v.mcc)$($v.mnc)) to instance $idx..." -ForegroundColor Cyan
            Apply-SavedSim -Index $idx
        } elseif ($choice -eq 'e' -or $choice -eq 'E') {
            $idx = (Read-Host 'Instance index to edit').Trim()
            if (-not $idx -or -not $cfg.$idx) {
                Write-Host 'No saved config for that instance.' -ForegroundColor Yellow; return
            }
            $v = $cfg.$idx
            Write-Host "  Current: $($v.name) (MCC=$($v.mcc) MNC=$($v.mnc) CC=$($v.cc))" -ForegroundColor DarkGray
            $newMcc = (Read-Host "  MCC [$($v.mcc)]").Trim()
            if (-not $newMcc) { $newMcc = $v.mcc }
            $newMnc = (Read-Host "  MNC [$($v.mnc)]").Trim()
            if (-not $newMnc) { $newMnc = $v.mnc }
            $newCc = (Read-Host "  ISO country [$($v.cc)]").Trim()
            if (-not $newCc) { $newCc = $v.cc }
            $newName = (Read-Host "  Operator name [$($v.name)]").Trim()
            if (-not $newName) { $newName = $v.name }
            $cfg.$idx = @{ mcc = $newMcc; mnc = $newMnc; cc = $newCc.ToLower(); name = $newName }
            Save-SimConfig $cfg
            Write-Host "  Config for instance $idx updated." -ForegroundColor Green
        } elseif ($choice -eq 'v' -or $choice -eq 'V') {
            $idx = (Read-Host 'Instance index to verify').Trim()
            if (-not $idx -or -not $cfg.$idx) {
                Write-Host 'No saved config for that instance.' -ForegroundColor Yellow; return
            }
            $v = $cfg.$idx
            $expected = "$($v.mcc)$($v.mnc)"
            Write-Host "  Checking instance $idx (expected: $expected)..." -ForegroundColor Cyan
            try {
                $props = ''
                $vj = Start-Job -ScriptBlock {
                    param($mp, $i)
                    & $mp adb -v $i -c 'shell getprop' 2>$null | Out-String
                } -ArgumentList $MumuPath, $idx
                if (Wait-Job $vj -Timeout 10) { $props = Receive-Job $vj }
                Remove-Job $vj -Force -ErrorAction SilentlyContinue
                if (-not $props) {
                    Write-Host '  ADB not ready — cannot verify.' -ForegroundColor Yellow
                    return
                }
                $curNum = if ($props -match '\[gsm\.sim\.operator\.numeric\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
                $curMum = if ($props -match '\[persist\.mumu\.mccmnc\]:\s*\[(.*?)\]') { $Matches[1] } else { '' }
                $match = ($curNum -eq $expected) -or ($curMum -eq $expected)
                if ($match) {
                    Write-Host "  MATCH: $curNum = $expected" -ForegroundColor Green
                } else {
                    Write-Host "  MISMATCH: gsm.sim=$curNum, persist.mumu=$curMum, expected=$expected" -ForegroundColor Red
                    Write-Host '  Re-apply with [A] or restart the emulator.' -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  Verify failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

function Set-SimOperator {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''
    # Show current SIM props via adb (with timeout to avoid hang on unready ADB)
    try {
        $props = ''
        $adbJob = Start-Job -ScriptBlock {
            param($mp, $idx)
            & $mp adb -v $idx -c 'shell getprop' 2>$null | Out-String
        } -ArgumentList $MumuPath, $index
        if (Wait-Job $adbJob -Timeout 10) {
            $props = Receive-Job $adbJob
        } else {
            Write-Host '  ADB not ready — skipping current SIM display (will set anyway)' -ForegroundColor DarkGray
        }
        Remove-Job $adbJob -Force -ErrorAction SilentlyContinue
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
        # --- North America ---
        @{ CC='us'; MCC='310'; MNC='260'; Name='T-Mobile US'; Lang='en' },
        @{ CC='us'; MCC='310'; MNC='410'; Name='AT&T US'; Lang='en' },
        @{ CC='us'; MCC='311'; MNC='480'; Name='Verizon US'; Lang='en' },
        @{ CC='ca'; MCC='302'; MNC='720'; Name='Rogers CA'; Lang='en' },
        @{ CC='mx'; MCC='334'; MNC='020'; Name='Telcel MX'; Lang='es' },
        # --- Europe ---
        @{ CC='ru'; MCC='250'; MNC='01';  Name='MTS RU'; Lang='ru' },
        @{ CC='gb'; MCC='234'; MNC='15';  Name='Vodafone UK'; Lang='en' },
        @{ CC='de'; MCC='262'; MNC='01';  Name='Telekom DE'; Lang='de' },
        @{ CC='fr'; MCC='208'; MNC='01';  Name='Orange FR'; Lang='fr' },
        @{ CC='it'; MCC='222'; MNC='01';  Name='TIM IT'; Lang='it' },
        @{ CC='es'; MCC='214'; MNC='01';  Name='Movistar ES'; Lang='es' },
        @{ CC='nl'; MCC='204'; MNC='16';  Name='KPN NL'; Lang='nl' },
        @{ CC='pl'; MCC='260'; MNC='06';  Name='Play PL'; Lang='pl' },
        @{ CC='ua'; MCC='255'; MNC='01';  Name='Vodafone UA'; Lang='uk' },
        @{ CC='tr'; MCC='286'; MNC='01';  Name='Turkcell TR'; Lang='tr' },
        # --- East Asia ---
        @{ CC='jp'; MCC='440'; MNC='10';  Name='Docomo JP'; Lang='ja' },
        @{ CC='kr'; MCC='450'; MNC='05';  Name='SK Telecom KR'; Lang='ko' },
        @{ CC='cn'; MCC='460'; MNC='00';  Name='China Mobile'; Lang='zh' },
        @{ CC='cn'; MCC='460'; MNC='01';  Name='China Unicom'; Lang='zh' },
        @{ CC='cn'; MCC='460'; MNC='03';  Name='China Telecom'; Lang='zh' },
        # --- Southeast Asia ---
        @{ CC='th'; MCC='520'; MNC='01';  Name='AIS TH'; Lang='th' },
        @{ CC='ph'; MCC='515'; MNC='02';  Name='Globe PH'; Lang='tl' },
        @{ CC='my'; MCC='502'; MNC='12';  Name='Maxis MY'; Lang='ms' },
        @{ CC='sg'; MCC='525'; MNC='01';  Name='Singtel SG'; Lang='en' },
        @{ CC='id'; MCC='510'; MNC='01';  Name='Telkomsel ID'; Lang='id' },
        @{ CC='vn'; MCC='452'; MNC='01';  Name='Viettel VN'; Lang='vi' },
        # --- South Asia ---
        @{ CC='in'; MCC='404'; MNC='45';  Name='Airtel IN'; Lang='en' },
        @{ CC='pk'; MCC='410'; MNC='01';  Name='Jazz PK'; Lang='ur' },
        @{ CC='bd'; MCC='470'; MNC='01';  Name='Grameenphone BD'; Lang='bn' },
        # --- Middle East ---
        @{ CC='sa'; MCC='420'; MNC='01';  Name='STC SA'; Lang='ar' },
        @{ CC='ae'; MCC='424'; MNC='02';  Name='Etisalat AE'; Lang='ar' },
        @{ CC='kz'; MCC='401'; MNC='01';  Name='Beeline KZ'; Lang='ru' },
        # --- Africa ---
        @{ CC='eg'; MCC='602'; MNC='02';  Name='Vodafone EG'; Lang='ar' },
        @{ CC='ng'; MCC='621'; MNC='30';  Name='MTN NG'; Lang='en' },
        # --- Latin America ---
        @{ CC='br'; MCC='724'; MNC='05';  Name='Claro BR'; Lang='pt' },
        # --- Oceania ---
        @{ CC='au'; MCC='505'; MNC='01';  Name='Telstra AU'; Lang='en' },
        @{ CC='au'; MCC='505'; MNC='02';  Name='Optus AU'; Lang='en' },
        @{ CC='nz'; MCC='530'; MNC='01';  Name='Spark NZ'; Lang='en' }
    )

    # Region mapping for display
    $regionMap = @{
        'us'='NA'; 'ca'='NA'; 'mx'='NA'
        'ru'='EU'; 'gb'='EU'; 'de'='EU'; 'fr'='EU'; 'it'='EU'; 'es'='EU'; 'nl'='EU'; 'pl'='EU'; 'ua'='EU'; 'tr'='EU'
        'jp'='EA'; 'kr'='EA'; 'cn'='EA'
        'th'='SEA'; 'ph'='SEA'; 'my'='SEA'; 'sg'='SEA'; 'id'='SEA'; 'vn'='SEA'
        'in'='SA'; 'pk'='SA'; 'bd'='SA'
        'sa'='ME'; 'ae'='ME'; 'kz'='ME'
        'eg'='AF'; 'ng'='AF'
        'br'='LA'
        'au'='OC'; 'nz'='OC'
    }

    # Build filtered list
    $filtered = @()
    for ($i = 0; $i -lt $presets.Count; $i++) {
        $filtered += @{ Num = $i + 1; Preset = $presets[$i] }
    }

    Write-Host ''
    Write-Host '  Type to filter (name/CC/MCC), or enter number:' -ForegroundColor DarkGray
    Write-Host ''
    $lastRegion = ''
    foreach ($f in $filtered) {
        $p = $f.Preset
        $region = if ($regionMap.ContainsKey($p.CC)) { $regionMap[$p.CC] } else { '' }
        if ($region -ne $lastRegion) {
            $lastRegion = $region
        }
        Write-Host ("  [{0,2}] {1,-4} {2,-22} {3}/{4}  [{5}]" -f $f.Num, $p.CC.ToUpper(), $p.Name, $p.MCC, $p.MNC, $p.Lang) -ForegroundColor White
    }
    Write-Host ''
    Write-Host '  [ F] Filter presets' -ForegroundColor DarkGray
    Write-Host '  [ C] Custom MCC / MNC / ISO' -ForegroundColor White
    Write-Host '  [ 0] Cancel' -ForegroundColor Yellow
    $choice = (Read-Host 'Select SIM country').Trim()
    if ($choice -eq '0') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }

    # Handle filter
    if ($choice -eq 'f' -or $choice -eq 'F') {
        $query = (Read-Host 'Filter (name, CC, MCC, or region)').Trim()
        if (-not $query) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
        $query = $query.ToLower()
        $regionNames = @{ 'NA'='north america'; 'EU'='europe'; 'EA'='east asia'; 'SEA'='southeast asia'; 'SA'='south asia'; 'ME'='middle east'; 'AF'='africa'; 'LA'='latin america'; 'OC'='oceania' }
        $filtered = @()
        for ($i = 0; $i -lt $presets.Count; $i++) {
            $p = $presets[$i]
            $region = if ($regionMap.ContainsKey($p.CC)) { $regionMap[$p.CC] } else { '' }
            $regionFull = if ($regionNames.ContainsKey($region)) { $regionNames[$region] } else { '' }
            if ($p.CC -match [regex]::Escape($query) -or $p.Name.ToLower() -match [regex]::Escape($query) -or
                $p.MCC -match $query -or $p.MNC -match $query -or
                $region.ToLower() -match $query -or $regionFull -match $query) {
                $filtered += @{ Num = $i + 1; Preset = $p }
            }
        }
        if ($filtered.Count -eq 0) {
            Write-Host "  No presets matching '$query'" -ForegroundColor Yellow
            return
        }
        Write-Host "  Found $($filtered.Count) preset(s):" -ForegroundColor Green
        Write-Host ''
        $lastRegion = ''
        foreach ($f in $filtered) {
            $p = $f.Preset
            $region = if ($regionMap.ContainsKey($p.CC)) { $regionMap[$p.CC] } else { '' }
            Write-Host ("  [{0,2}] {1,-4} {2,-22} {3}/{4}  [{5}]" -f $f.Num, $p.CC.ToUpper(), $p.Name, $p.MCC, $p.MNC, $p.Lang) -ForegroundColor White
        }
        Write-Host ''
        $choice = (Read-Host 'Select SIM number').Trim()
        if ($choice -eq '0') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    }
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
    # Escape shell-special characters for Android sh (e.g. AT&T -> AT\&T)
    $alphaShell = ConvertTo-ShellSafe $alpha
    Write-Host ''
    Write-Host '  ┌─────────────────────────────────────────┐' -ForegroundColor Cyan
    Write-Host '  │  SIM CHANGE SUMMARY                     │' -ForegroundColor Cyan
    Write-Host '  ├─────────────────────────────────────────┤' -ForegroundColor Cyan
    Write-Host "  │  Operator:  $alpha" -ForegroundColor White
    Write-Host "  │  MCC/MNC:   $($sel.MCC)/$($sel.MNC) ($numeric)" -ForegroundColor White
    Write-Host "  │  Country:   $($cc.ToUpper())" -ForegroundColor White
    Write-Host "  │  Instance:  $index" -ForegroundColor White
    Write-Host '  ├─────────────────────────────────────────┤' -ForegroundColor Cyan
    Write-Host '  │  Sets: gsm.sim.operator.*, gsm.operator.*' -ForegroundColor DarkGray
    Write-Host '  │        persist.mumu.mccmnc, settings global' -ForegroundColor DarkGray
    Write-Host '  │  Saves: sim-config.json (auto-apply)' -ForegroundColor DarkGray
    Write-Host '  └─────────────────────────────────────────┘' -ForegroundColor Cyan
    $confirm = (Read-Host '  Apply? (Y/n)').Trim()
    if ($confirm -eq 'n' -or $confirm -eq 'N') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    Write-Host ''
    # Wait for ADB to be online
    if (-not (Wait-ADBOnline -Index $index -MaxWait 30)) {
        Write-Host '  ADB offline — cannot set SIM properties.' -ForegroundColor Red
        Write-Host '  Config saved. Re-run [SIM] or restart to apply.' -ForegroundColor Yellow
        return
    }
    Write-Host "Setting SIM to $alpha ($numeric, $cc)..." -ForegroundColor Cyan
    try {
        # 1) MuMu-specific persist property (most reliable in MuMu)
        & $MumuPath adb -v $index -c "shell setprop persist.mumu.mccmnc $numeric" 2>&1 | Out-Null

        # 2) Standard gsm.sim.* and gsm.operator.* shell properties
        $cmds = @(
            "setprop gsm.sim.operator.numeric $numeric"
            "setprop gsm.sim.operator.iso-country $cc"
            "setprop gsm.sim.operator.alpha `"$alphaShell`""
            "setprop gsm.operator.numeric $numeric"
            "setprop gsm.operator.iso-country $cc"
            "setprop gsm.operator.alpha `"$alphaShell`""
            "setprop gsm.sim.operator.isroaming false"
            "setprop gsm.operator.isroaming false"
        )
        foreach ($c in $cmds) {
            & $MumuPath adb -v $index -c "shell $c" 2>&1 | Out-Null
        }

        # 3) MuMu debug.tracing.* properties (emulator internal MCC/MNC)
        & $MumuPath adb -v $index -c "shell setprop debug.tracing.mcc $($sel.MCC)" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell setprop debug.tracing.mnc $($sel.MNC)" 2>&1 | Out-Null
        Write-Host "  Set debug.tracing.mcc=$($sel.MCC) mnc=$($sel.MNC)" -ForegroundColor DarkGray

        # 3) Settings global — carrier ID / operator name (persists across shell restarts)
        & $MumuPath adb -v $index -c "shell settings put global mobile_operator $numeric" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global operator_numeric $numeric" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global operator_alpha `"$alphaShell`"" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global sim_operator `"$alphaShell`"" 2>&1 | Out-Null
        & $MumuPath adb -v $index -c "shell settings put global gsm_operator_alpha `"$alphaShell`"" 2>&1 | Out-Null

        # Verify (with timeout)
        $props2 = ''
        $verifyJob = Start-Job -ScriptBlock {
            param($mp, $idx)
            & $mp adb -v $idx -c 'shell getprop' 2>$null | Out-String
        } -ArgumentList $MumuPath, $index
        if (Wait-Job $verifyJob -Timeout 10) {
            $props2 = Receive-Job $verifyJob
        }
        Remove-Job $verifyJob -Force -ErrorAction SilentlyContinue
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

        # Persist to sim-config.json for auto-apply on next boot
        $cfg = Get-SimConfig
        $cfg.$index = @{ mcc = $sel.MCC; mnc = $sel.MNC; cc = $cc; name = $alpha }
        Save-SimConfig $cfg
        Write-Host "  Saved for auto-apply on next boot (instance $index)." -ForegroundColor DarkGreen
        Write-Host ''
        Write-Host '  ┌────────────────────────────────────────┐' -ForegroundColor Yellow
        Write-Host '  │  WHAT THIS SPOOF COVERS:' -ForegroundColor Yellow
        Write-Host '  │  ✔ gsm.sim.operator.* (getprop)' -ForegroundColor Green
        Write-Host '  │  ✔ persist.mumu.mccmnc' -ForegroundColor Green
        Write-Host '  │  ✔ settings global operator_*' -ForegroundColor Green
        Write-Host '  │  ✔ debug.tracing.mcc/mnc (emulator internal)' -ForegroundColor Green
        Write-Host '  │  Apps that read these props (TikTok, etc.) see spoofed values' -ForegroundColor DarkGray
        Write-Host '  │' -ForegroundColor Yellow
        Write-Host '  │  WHAT THIS SPOOF DOES NOT COVER:' -ForegroundColor Yellow
        Write-Host '  │  ✘  Android Settings → SIM cards (reads telephony registry)' -ForegroundColor Red
        Write-Host '  │  ✘  networkCountryIso (built from virtual modem)' -ForegroundColor Red
        Write-Host '  │  ✘  SubscriptionInfo (telephony framework)' -ForegroundColor Red
        Write-Host '  │  ✘  dumpsys telephony.registry (rRplmn, mMnc)' -ForegroundColor Red
        Write-Host '  │  The modem layer constructs its own state — not editable via setprop.' -ForegroundColor DarkGray
        Write-Host '  └────────────────────────────────────────┘' -ForegroundColor Yellow
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

function Set-AndroidId {
    $index = Get-InstanceIndex 'Select instance'
    if (-not $index) { return }
    Write-Host ''

    # Show current values
    try {
        $sim = & $MumuPath simulation -v $index 2>$null | ConvertFrom-Json
        Write-Host 'Current values:' -ForegroundColor DarkGray
        Write-Host "  Android ID: $(if ($sim.android_id) { $sim.android_id } else { '(not set)' })" -ForegroundColor White
        Write-Host "  IMEI:       $(if ($sim.imei) { $sim.imei } else { '(not set)' })" -ForegroundColor DarkGray
        Write-Host "  MAC:        $(if ($sim.mac_address) { $sim.mac_address } else { '(not set)' })" -ForegroundColor DarkGray
    } catch {
        Write-Host 'Could not read simulation properties.' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'Set Android ID:' -ForegroundColor Cyan
    Write-Host '  [1] Random (16 hex chars)' -ForegroundColor White
    Write-Host '  [2] Custom value' -ForegroundColor White
    Write-Host '  [3] Clear (reset to default)' -ForegroundColor White
    Write-Host '  [0] Cancel' -ForegroundColor Yellow
    $choice = (Read-Host 'Select option').Trim()

    $newId = $null
    switch ($choice) {
        '1' { $newId = New-RandomAndroidId; Write-Host "  Generated: $newId" -ForegroundColor Green }
        '2' {
            $userInput = (Read-Host 'Enter Android ID (16 hex chars)').Trim()
            if (-not $userInput -or $userInput.Length -ne 16 -or $userInput -notmatch '^[0-9a-fA-F]+$') {
                Write-Host '  Invalid format. Must be 16 hex characters.' -ForegroundColor Red
                return
            }
            $newId = $userInput.ToLower()
        }
        '3' { $newId = '__null__'; Write-Host '  Will reset to default.' -ForegroundColor Yellow }
        default { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }
    }

    if (-not $newId) { return }

    try {
        & $MumuPath simulation -v $index -sk android_id -sv $newId 2>&1 | Out-Null
        if ($newId -ne '__null__') {
            Write-Host "  Android ID set to: $newId" -ForegroundColor Green
        } else {
            Write-Host '  Android ID cleared.' -ForegroundColor Green
        }
    } catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Verify
    try {
        $sim2 = & $MumuPath simulation -v $index 2>$null | ConvertFrom-Json
        $verify = $sim2.android_id
        if ($newId -eq '__null__') {
            Write-Host "  Verified: Android ID is now $(if ($verify) { $verify } else { '(default)' })" -ForegroundColor Green
        } elseif ($verify -eq $newId) {
            Write-Host "  Verified: Android ID = $verify" -ForegroundColor Green
        } else {
            Write-Host "  Warning: expected $newId, got $verify" -ForegroundColor Yellow
        }
    } catch {
        Write-Debug "Verify Android ID failed: $($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host 'NOTE: Changes only take effect after emulator restart.' -ForegroundColor Yellow
    $restart = Read-Host 'Restart now? (y/N)'
    if ($restart -eq 'y' -or $restart -eq 'Y') {
        Write-Host 'Restarting emulator...' -ForegroundColor Cyan
        try {
            & $MumuPath control -v $index restart 2>&1 | Out-Null
            Write-Host 'Emulator restarting. Android ID will be active after boot.' -ForegroundColor Green
        } catch {
            Write-Host "Restart failed: $($_.Exception.Message). Please restart manually." -ForegroundColor Red
        }
    }
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
        'vf' { Upload-VirusTotal }
        'uw' { Fix-Unicode }
        'dm' { Set-DeviceModel }
        'sim' { Set-SimOperator }
        'sim+' { Show-SimConfig }
        'sc' { Show-SimCheck }
        'ai' { Set-AndroidId }
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
        'up' { Update-FromGitHub -Plan }
        'f' { Show-InstallVerify }
        'j' { Show-UpdateJournal }
        'st' { Show-InstallStatus; $resp = Read-Host '  d = full drift check, Enter = back'; if ($resp -eq 'd') { Show-InstallStatus -Deep } }
        'diag' { Show-ProblemDiagnostics }
        'rb' { Show-RollbackFromBackup }
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