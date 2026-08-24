# Sync README.md with mumu-menu.ps1 (menu block + script version)
# Usage: ./update-readme.ps1
# Used by .github/workflows/sync-readme.yml and locally before commits.
#
# Security scope:
#   - LOCAL ONLY: no network access, no downloads, no command execution.
#   - Touches exactly two files in this folder: reads mumu-menu.ps1,
#     rewrites README.md between the MENU:AUTO markers.
#   - Fail-closed: every extraction below is validated; on any anomaly
#     the script throws instead of writing a malformed README.

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$menuScript = Join-Path $root 'mumu-menu.ps1'
$readmePath = Join-Path $root 'README.md'

foreach ($f in @($menuScript, $readmePath)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Required file not found: $f" }
}

$utf8 = [System.Text.UTF8Encoding]::new($true)
$script = [System.IO.File]::ReadAllText($menuScript)
$readme = [System.IO.File]::ReadAllText($readmePath)
$newline = if ($readme -match "`r`n") { "`r`n" } else { "`n" }

# 1. Extract version (strictly numeric, dotted)
$verMatch = [regex]::Match($script, '(?m)^\s*Write-Host ''Script version:\s*(\d+(?:\.\d+){1,3})''')
if (-not $verMatch.Success) { throw 'Cannot find a valid numeric "Script version" line in mumu-menu.ps1' }
$version = $verMatch.Groups[1].Value

# 2. Extract menu lines from Show-Menu body (function boundaries must be unique)
$startIdx = $script.IndexOf('function Show-Menu')
$endIdx = $script.IndexOf('function Get-InstanceIndex')
if ($startIdx -lt 0 -or $endIdx -lt 0 -or $endIdx -le $startIdx) { throw 'Cannot locate Show-Menu function boundaries' }
$body = $script.Substring($startIdx, $endIdx - $startIdx)

$lines = foreach ($m in [regex]::Matches($body, "Write-Host '([^']*)'")) {
    $text = $m.Groups[1].Value -replace "''", "'"
    if ($text -match '^\s*---\s*.+\s*---\s*$') {
        ''
        $text
    } elseif ($text.TrimStart().StartsWith('[') -or $text -match '^=+$' -or $text -match '^\s*MuMuManager CLI Menu\s*$') {
        $text
    }
}
if (-not $lines -or @($lines).Count -lt 5) { throw 'Menu extraction produced too few lines; aborting' }

$menuText = ($lines -join $newline)
$block = '```' + $newline + $menuText + $newline + '```'
$menuStart = '<!-- MENU:AUTO:START -->'
$menuEnd = '<!-- MENU:AUTO:END -->'

# Markers must exist exactly once each - refuse ambiguous/malformed README
$pattern = '(?s)' + [regex]::Escape($menuStart) + '.*?' + [regex]::Escape($menuEnd)
$found = [regex]::Matches($readme, $pattern)
if ($found.Count -ne 1) { throw "Expected exactly one MENU:AUTO block in README.md, found $($found.Count)" }

$replacement = $menuStart + $newline + $block + $newline + $menuEnd
$updated = [regex]::Replace($readme, $pattern, $replacement)

# 3. Sync version in examples (digits-only replacement value)
$updated = [regex]::Replace($updated, '(Script version:\s*)[\d\.]+', ('${1}' + $version))

# 4. Write only if changed (idempotent)
if ($updated -ne $readme) {
    [System.IO.File]::WriteAllText($readmePath, $updated, $utf8)
    Write-Host "README.md updated (version $version)" -ForegroundColor Green
    exit 0
}
Write-Host "README.md already up to date (version $version)" -ForegroundColor DarkGray
