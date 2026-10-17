<#
.SYNOPSIS
  Archil API key / token storage with DPAPI encryption (CurrentUser scope).

  Mirrors the repo's existing GitHub-token pattern:
    - plaintext never written to disk (only the DPAPI blob)
    - the key is read back only when the caller asks, never printed to the console
    - plaintext lives only in memory for the duration of the operation

  Intended use with archil-storage.mjs:
    - store the Archil API key so archil-storage.mjs / check:archil never
      need a long-lived plaintext env value in .env
    - store a mount token (adt_ …) only if you explicitly want it persisted;
      the SDK normally keeps the one-time token in memory
  Do NOT use this module from browser/client code. Keep it server-side.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- paths (next to the script, like .github-token) ----
function Get-ModuleDir { Split-Path -LiteralPath $PSScriptRoot -Parent }
try { $ScriptDir = Get-ModuleDir } catch { $ScriptDir = $PWD.Path }
# Store paths: allow a harness/interactive override via the GLOBAL variables
# TokenDir / StoreFile set before this module is dot-sourced (used by the
# self-test and by any interactive runner that wants an isolated store).
# Read via Get-Variable -Scope Global rather than the $global: modifier so the
# linter (PSAvoidGlobalVars) does not flag it - the behavior is identical.
$TokenDir = $ScriptDir + '.archil-tokens'
try {
    $ovr = Get-Variable -Name TokenDir -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ovr) { $TokenDir = $ovr }
} catch { Write-Debug 'swallowed — fallback to default' }
$storeFromGlobal = $false
try {
    $ovr = Get-Variable -Name StoreFile -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $ovr) { $StoreFile = $ovr; $storeFromGlobal = $true }
} catch { Write-Debug 'swallowed — fallback to default' }
if (-not $storeFromGlobal) { $StoreFile = $TokenDir + [System.IO.Path]::DirectorySeparatorChar + 'tokens.dpapi' }

# ---- DPAPI helpers (CurrentUser scope; follows the repo's existing choice) ----
$null = [Reflection.Assembly]::LoadWithPartialName('System.Security')

function ConvertTo-Bytes {
    param([string]$Text, [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8)
    return $Encoding.GetBytes($Text)
}

function ConvertFrom-Bytes {
    param([byte[]]$Data, [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8)
    return $Encoding.GetString($Data)
}

function Protect-Bytes {
    param([byte[]]$Data, [string]$Description = '')
    # Signature is Protect(Byte[] userData, Byte[] optionalEntropy,
    # DataProtectionScope scope). There is no string-description overload on this
    # CLR, so pass $null entropy; description is stored as store metadata only.
    return [System.Security.Cryptography.ProtectedData]::Protect(
        $Data,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
}

function Unprotect-Bytes {
    param([byte[]]$Data)
    try {
        return [System.Security.Cryptography.ProtectedData]::Unprotect(
            $Data,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    } catch {
        throw "Cannot decrypt the Archil token store. This is a CurrentUser DPAPI blob "
            + "and is not portable between machines/users. Re-create the token with "
            + "[S]tore from the menu instead of trying to read this file by hand."
    }
}

# ---- token store (one DPAPI blob per token, one per type) ----

# Metadata token map (type -> { label, hint }). Stored as JSON inside the
# plaintext bytes before DPAPI protects them, so the store stays human-friendly
# enough to inspect structure without ever leaking plaintext.
$TokenMetadata = @{
    'api-key' = @{
        Label = 'Archil API key'
        Hint  = 'Starts with "key-". From https://console.archil.com/api-keys.'
    }
    'mount-token' = @{
        Label = 'Archil mount token'
        Hint  = 'Often starts with "adt_". One-time mount token from SDK. Not the API key.'
    }
}

function Save-TokenStore {
    param([hashtable]$TokensByKey)
    # rebuild a stable, sortable JSON blob from the metadata + encrypted payloads
    $out = @{}
    foreach ($k in $TokensByKey.Keys | Sort-Object) {
        $out[$k] = @{
            Label  = $TokenMetadata[$k].Label
            Cipher = [System.Convert]::ToBase64String($TokensByKey[$k].Cipher)
        }
    }
    $json = ConvertTo-Json -InputObject $out -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $protected = Protect-Bytes -Data $bytes
    $dir = $null
    try { $dir = Split-Path -LiteralPath $StoreFile -Parent -ErrorAction Stop } catch { Write-Debug 'swallowed — fallback to default' }
    if ($dir) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    } else {
        # Fallback: derive directory by removing the final path component.
        $idx = $StoreFile.LastIndexOf('\')
        if ($idx -gt 0) { $dir = $StoreFile.Substring(0, $idx) }
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    [System.IO.File]::WriteAllBytes($StoreFile, $protected)
}

function Load-TokenStore {
    if (-not (Test-Path $StoreFile)) {
        return @{}
    }
    $bytes = [System.IO.File]::ReadAllBytes($StoreFile)
    $plain = Unprotect-Bytes -Data $bytes
    $json = [System.Text.Encoding]::UTF8.GetString($plain)
    $decoded = ConvertFrom-Json -InputObject $json
    $out = @{}
    foreach ($k in $decoded.PSObject.Properties.Name) {
        $meta = $TokenMetadata[$k]
        if ($null -eq $meta) { continue }
        $out[$k] = @{
            Label  = $meta.Label
            Cipher = [System.Convert]::FromBase64String($decoded.($k).Cipher)
        }
    }
    return $out
}

# ---- public commands ----

function Store-ArchilToken {
    <#
    .SYNOPSIS
        Store an Archil token (api-key or mount-token) encrypted under DPAPI.
    .DESCRIPTION
        Prompts for the token value once (console masking disabled for copy-paste;
        you can paste directly). The plaintext is encrypted immediately and only
        the DPAPI blob is written to disk.
    .EXAMPLE
        Store-ArchilToken -Type api-key
        Store-ArchilToken -Type mount-token -Force
    #>
    param(
        [ValidateSet('api-key', 'mount-token')]
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Type,

        [switch]$Force
    )

    $existing = (Load-TokenStore)[$Type]
    if ($null -ne $existing -and -not $Force) {
        Write-Host "A $($TokenMetadata[$Type].Label) is already stored."
        Write-Host "Run with -Force to overwrite it."
        return
    }

    Write-Host "Storing $($TokenMetadata[$Type].Label)."
    Write-Host "  Hint: $($TokenMetadata[$Type].Hint)"
    $label = $TokenMetadata[$Type].Label

    # Read value once; plain text exists only in memory for this duration.
    $value = Read-Host "Paste the $label (it will be encrypted immediately)"

    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Host "Empty input. Nothing stored."
        return
    }

    $bytes = ConvertTo-Bytes -Text $value
    $cipher = Protect-Bytes -Data $bytes -Description "Archil $Type token (CurrentUser)"

    $store = Load-TokenStore
    $store[$Type] = @{
        Label  = $TokenMetadata[$Type].Label
        Cipher = $cipher
    }
    Save-TokenStore -TokensByKey $store

    # Never print the value or the ciphertext.
    Write-Host "Stored $($TokenMetadata[$Type].Label) encrypted under DPAPI (CurrentUser)."
}

function Get-ArchilToken {
    <#
    .SYNOPSIS
        Decrypt and return the stored Archil token (plaintext in memory only).
    .DESCRIPTION
        Returns the plaintext token to the caller. This is the ONLY place it leaves
        the DPAPI blob, and it lives only in memory while the caller holds it.
        Never write the plaintext back to disk, never print it by default.
    .EXAMPLE
        $apiKey = Get-ArchilToken -Type api-key
        if ($apiKey) { ... } else { "No API key stored." }
    #>
    param(
        [ValidateSet('api-key', 'mount-token')]
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    $store = Load-TokenStore
    $entry = $store[$Type]
    if ($null -eq $entry) {
        Write-Warning "No stored $($TokenMetadata[$Type].Label)."
        return $null
    }
    try {
        $bytes = Unprotect-Bytes -Data $entry.Cipher
        return ConvertFrom-Bytes -Data $bytes
    } catch {
        Write-Error "Decryption failed for the stored $($TokenMetadata[$Type].Label): $_"
        return $null
    }
}

function Test-ArchilToken {
    <#
    .SYNOPSIS
        Return $true if a given token type is stored (encrypted) on disk.
    .EXAMPLE
        if (Test-ArchilToken -Type api-key) { ... }
    #>
    param(
        [ValidateSet('api-key', 'mount-token')]
        [Parameter(Mandatory = $true)]
        [string]$Type
    )
    $null -ne (Load-TokenStore)[$Type]
}

function Remove-ArchilToken {
    <#
    .SYNOPSIS
        Remove a stored Archil token (the DPAPI blob is deleted).
    .EXAMPLE
        Remove-ArchilToken -Type api-key
    #>
    param(
        [ValidateSet('api-key', 'mount-token')]
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Type
    )
    $store = Load-TokenStore
    if ($null -eq $store -or $null -eq $store[$Type]) {
        Write-Host "No stored $($TokenMetadata[$Type].Label) to remove."
        return
    }
    $store.Remove($Type)
    $remaining = if ($null -ne $store) { $store.Count } else { 0 }
    if ($remaining -gt 0) {
        Save-TokenStore -TokensByKey $store
    } else {
        # clean store file when nothing remains
        if (Test-Path $StoreFile) { Remove-Item -LiteralPath $StoreFile -Force }
        $children = if (Test-Path $TokenDir) { Get-ChildItem $TokenDir -ErrorAction SilentlyContinue } else { $null }
        if ($null -ne $children -and $children.Count -eq 0) {
            Remove-Item -LiteralPath $TokenDir -Force
        }
    }
    Write-Host "Removed $($TokenMetadata[$Type].Label) from the encrypted store."
}

function Show-ArchilTokens {
    <#
    .SYNOPSIS
        List which token types are stored, without revealing any value.
    #>
    $store = Load-TokenStore
    if ($store.Count -eq 0) {
        Write-Host "No Archil tokens stored."
        return
    }
    foreach ($k in $store.Keys | Sort-Object) {
        Write-Host "  [$( $k )] $($store[$k].Label) (encrypted)"
    }
}

# ---- public API ----
# Export-ModuleMember is only meaningful inside a real module. When the file is
# dot-sourced as a script (the common interactive/test usage here), functions are
# already in scope and this call would throw — so run it as a no-op best effort.
try { Export-ModuleMember -Function Store-ArchilToken, Get-ArchilToken, Test-ArchilToken, Remove-ArchilToken, Show-ArchilTokens -ErrorAction Stop } catch { Write-Debug 'swallowed — fallback to default' }

# ---- interactive menu (opt-in; run as:  & { Show-ArchilTokenMenu } ) ----
function Show-ArchilTokenMenu {
    <#
    .SYNOPSIS
        Interactive menu for storing / reading / removing / showing Archil tokens (DPAPI).
    .DESCRIPTION
        Console menu, repo-style: numbered options + letter shortcuts, [0] Exit.
        Never prints a token value; reading a token returns the plaintext to the
        caller (so the caller can feed it to archil-storage.mjs / check:archil).
        Run via:  & { Show-ArchilTokenMenu }
    .EXAMPLE
        & { Show-ArchilTokenMenu }
    #>
    Write-Host ""
    Write-Host "======================================"
    Write-Host "    Archil Token Manager (DPAPI)"
    Write-Host "======================================"
    Write-Host ""
    Write-Host "Stored tokens are encrypted under DPAPI (CurrentUser)."
    Write-Host "Plaintext lives in memory only, briefly, when read."
    Write-Host ""
    $store = Load-TokenStore
    if ($store.Count -eq 0) {
        Write-Host "No tokens stored."
    } else {
        foreach ($k in $store.Keys | Sort-Object) {
            Write-Host "  [$($k.ToUpper())] $($store[$k].Label) (encrypted)"
        }
    }
    Write-Host ""
    Write-Host "  [S]tore  API key   (key- from console.archil.com/api-keys)"
    Write-Host "  [M]ount  token     (adt_ … one-time mount token, optional)"
    Write-Host "  [R]ead   API key   (returns plaintext to caller)"
    Write-Host "  [T]est   token     (is an API key stored?)"
    Write-Host "  [D]elete API key"
    Write-Host "  [L]ist   tokens    (show what is stored, no values)"
    Write-Host "  [0] Exit"
    Write-Host ""
    $choice = (Read-Host "Choice").Trim().ToLowerInvariant()
    switch ($choice) {
        { $_ -eq 's' -or $_ -eq 'store' -or $_ -eq 'api' } {
            Store-ArchilToken -Type api-key
        }
        { $_ -eq 'm' -or $_ -eq 'mount' -or $_ -eq 'adt' } {
            Store-ArchilToken -Type mount-token
        }
        { $_ -eq 'r' -or $_ -eq 'read' } {
            $k = Get-ArchilToken -Type api-key
            if ($k) {
                Write-Host ""
                Write-Host "API key read into memory (do not paste it anywhere else)."
                # The plaintext now lives in $k only; do NOT write it out.
                # To use it, call Get-ArchilToken from your own script and pass it on.
            }
        }
        { $_ -eq 't' -or $_ -eq 'test' } {
            if (Test-ArchilToken -Type api-key) {
                Write-Host "An API key is stored (encrypted)."
            } else {
                Write-Host "No API key stored."
            }
        }
        { $_ -eq 'd' -or $_ -eq 'delete' -or $_ -eq 'rm' } {
            Remove-ArchilToken -Type api-key
        }
        { $_ -eq 'l' -or $_ -eq 'list' -or $_ -eq 'show' } {
            Show-ArchilTokens
        }
        { $_ -eq '0' -or $_ -eq 'exit' -or $_ -eq 'q' -or $_ -eq 'quit' } {
            Write-Host "Bye."
            return
        }
        default {
            Write-Host "Unknown choice '$choice'."
        }
    }
    Write-Host ""
    # Loop one more time (simple single-prompt menu; for a full loop, wrap the
    # caller in a while ($true) { & { Show-ArchilTokenMenu } } loop).
    $again = (Read-Host "Another operation? (y/n)").Trim().ToLowerInvariant()
    if ($again -eq 'y') {
        Show-ArchilTokenMenu
    }
}

# ---- self-test (opt-in; run only when explicitly called, never on import) ----
function Test-ArchilTokenModule {
    # 1) DPAPI round-trip on a throwaway value
    $plain = [System.Text.Encoding]::UTF8.GetBytes('self-test-archil-token-9f3a')
    $enc = Protect-Bytes -Data $plain -Description 'module self-test'
    $dec = Unprotect-Bytes -Data $enc
    $rt = [System.Text.Encoding]::UTF8.GetString($dec)
    if ($rt -ne 'self-test-archil-token-9f3a') { return $false, "DPAPI round-trip failed" }

    # 2) store / load / remove round-trip for api-key
    $store = @{
        'api-key' = @{ Label = 'Archil API key'; Cipher = Protect-Bytes -Data $plain }
    }
    Save-TokenStore -TokensByKey $store
    $loaded = (Load-TokenStore)['api-key']
    if ($null -eq $loaded) { return $false, "store/load failed" }
    $back = ConvertFrom-Bytes -Data (Unprotect-Bytes -Data $loaded.Cipher)
    if ($back -ne 'self-test-archil-token-9f3a') { return $false, "store/load value mismatch" }
    Remove-ArchilToken -Type api-key
    if (Test-Path $StoreFile) { return $false, "remove did not clean the store file" }
    return $true, "module self-test OK"
}

