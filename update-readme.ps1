# Sync README.md with mumu-menu.ps1 (menu block + script version)
# Usage: ./update-readme.ps1
# Used by .github/workflows/sync-readme.yml and locally before commits.

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$menuScript = Join-Path $root 'mumu-menu.ps1'
$readmePath = Join-Path $root 'README.md'

$utf8 = [System.Text.UTF8Encoding]::new($false)
$script = [System.IO.File]::ReadAllText($menuScript)
$readme = [System.IO.File]::ReadAllText($readmePath)
$newline = if ($readme -match "`r`n") { "`r`n" } else { "`n" }

# 1. Extract version
$verMatch = [regex]::Match($script, 'Script version:\s*([\d\.]+)')
if (-not $verMatch.Success) { throw 'Cannot find "Script version" in mumu-menu.ps1' }
$version = $verMatch.Groups[1].Value

# 2. Extract menu lines from Show-Menu body
$startIdx = $script.IndexOf('function Show-Menu')
$endIdx = $script.IndexOf('function Get-InstanceIndex')
if ($startIdx -lt 0 -or $endIdx -lt 0) { throw 'Cannot locate Show-Menu function boundaries' }
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

$menuText = ($lines -join $newline)
$block = '```' + $newline + $menuText + $newline + '```'
$menuStart = '<!-- MENU:AUTO:START -->'
$menuEnd = '<!-- MENU:AUTO:END -->'

$pattern = '(?s)' + [regex]::Escape($menuStart) + '.*?' + [regex]::Escape($menuEnd)
$replacement = $menuStart + $newline + $block + $newline + $menuEnd
$updated = [regex]::Replace($readme, $pattern, $replacement)

# 3. Sync version in examples
$updated = [regex]::Replace($updated, '(Script version:\s*)[\d\.]+', ('${1}' + $version))

# 4. Write only if changed (idempotent)
if ($updated -ne $readme) {
    [System.IO.File]::WriteAllText($readmePath, $updated, $utf8)
    Write-Host "README.md updated (version $version)" -ForegroundColor Green
    exit 0
}
Write-Host "README.md already up to date (version $version)" -ForegroundColor DarkGray
