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

# UTF-8 WITHOUT BOM: non-script files must stay BOM-less (the [UW] scanner
# flags BOM on .md/.json/.yml as 'safe to strip'), and a BOM here would come
# back on every CI sync run. A BOM-less UTF-8 file is safe for GitHub,
# PowerShell 5.1 (it only reads .ps1 files here) and every editor.
$utf8 = [System.Text.UTF8Encoding]::new($false)
$script = [System.IO.File]::ReadAllText($menuScript)
$readme = [System.IO.File]::ReadAllText($readmePath)
$newline = if ($readme -match "`r`n") { "`r`n" } else { "`n" }

# 1. Extract version (strictly numeric, dotted)
# Match: $scriptVer = 'X.Y.Z' OR Write-Host 'Script version: X.Y.Z'
$verMatch = [regex]::Match($script, "(?m)^\s*\`$scriptVer\s*=\s*'(\d+(?:\.\d+){1,3})'|Write-Host\s+['""]Script version:\s*(\d+(?:\.\d+){1,3})")
if (-not $verMatch.Success) { throw 'Cannot find a valid numeric "Script version" in mumu-menu.ps1' }
$version = if ($verMatch.Groups[1].Success) { $verMatch.Groups[1].Value } else { $verMatch.Groups[2].Value }

# 1b. Offline-installer line: README advertises [OI] only when the script
#     actually implements Show-MumuOfflineInstallers.
$oiInScript = $script -match 'function\s+Show-MumuOfflineInstallers\s*\{'
$oiReadmeLine = "- 📥 Offline-инсталляторы: пункт `[OI]` показывает все текущие официальные сборки (Windows .exe, macOS .dmg, Android APK) прямо из CDN NetEase — с именем файла, размером и бейджем целостности, когда заголовки его отдают. Без скачивания, только список. Источник: https://www.mumuplayer.com/ "

# 2. Extract the menu from Show-Menu's $groups array (function boundaries must
#    be unique). The menu is no longer a flat list of Write-Host '[N] ...'
#    calls - it is a $groups array of hashtables (Title + Items) rendered by
#    Write-MenuGroup/Write-MenuItem - so we parse the array literal directly.
$startIdx = $script.IndexOf('function Show-Menu')
$endIdx = $script.IndexOf('function Get-InstanceIndex')
if ($startIdx -lt 0 -or $endIdx -lt 0 -or $endIdx -le $startIdx) { throw 'Cannot locate Show-Menu function boundaries' }
$body = $script.Substring($startIdx, $endIdx - $startIdx)

# The array literal runs from '$groups = @(' up to the sizing comment that
# immediately follows it - slice exactly that so unrelated code is never parsed.
$gStart = $body.IndexOf('$groups = @(')
$sizingAnchor = $body.IndexOf('# Size the frame')
if ($gStart -lt 0 -or $sizingAnchor -lt 0 -or $sizingAnchor -le $gStart) { throw 'Cannot locate the $groups array literal in Show-Menu' }
$gSlice = $body.Substring($gStart, $sizingAnchor - $gStart)

# Titles and items in source order; items are single-quoted strings on their
# own line starting with '[' (the '[KEY] description' menu entries). Capture
# group 1 is the text WITHOUT the surrounding quotes.
$titleMatches = [regex]::Matches($gSlice, "(?m)Title\s*=\s*'([^']*)'")
$itemMatches  = [regex]::Matches($gSlice, "(?m)^\s*'\[([^\]]+\][^']*)'\s*$")
if ($titleMatches.Count -lt 1)               { throw 'No group titles found in $groups' }
if (@($itemMatches).Count -lt 5)             { throw "Menu extraction produced too few lines (@(@($itemMatches).Count)); aborting" }

# Rebuild the documented block: 38-column '=' rule, 4-space title, then each
# group as '  --- Title ---' with '  [K] desc' items, a blank line before every
# group header, and a closing rule (this mirrors the previous hand-written
# block, so a correct run is a no-op on an up-to-date README).
$rule = '=' * 38
$lines = @($rule, '    MuMuManager CLI Menu', $rule)
$titles = @()
foreach ($t in $titleMatches) { $titles += [pscustomobject]@{ Title = $t.Groups[1].Value; Pos = $t.Index } }
for ($i = 0; $i -lt $titles.Count; $i++) {
    $tStart = $titles[$i].Pos
    $tEnd   = if ($i + 1 -lt $titles.Count) { $titles[$i + 1].Pos } else { $gSlice.Length }
    $lines += ''
    $lines += ('  --- ' + $titles[$i].Title + ' ---')
    foreach ($im in $itemMatches) {
        if ($im.Index -ge $tStart -and $im.Index -lt $tEnd) {
            $lines += ('  [' + ($im.Groups[1].Value -replace "''", "'"))
        }
    }
}
$lines += $rule

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

# 3. Sync the [OI] offline-installer blurb: insert before the '## Требования'
# first heading if the script implements Show-MumuOfflineInstallers, otherwise
# remove any existing blurb line so documentation tracks the code.
$reqAnchor = '## Требования'
$oiPat = '(?m)^\s*' + [regex]::Escape($oiReadmeLine) + '\s*$'
if ($oiInScript) {
    $updated = $updated -replace $oiPat, $oiReadmeLine
    if ($updated -notmatch '(?m)^\s*' + [regex]::Escape($oiReadmeLine) + '\s*$') {
        # Not yet present - insert just before the requirements heading.
        $updated = $updated -replace '(?s)((' + [regex]::Escape($reqAnchor) + '))', ($oiReadmeLine + $newline + '$1')
    }
} else {
    $updated = [regex]::Replace($updated, $oiPat, '')
}

# 4. Sync version in examples (digits-only replacement value)
$updated = [regex]::Replace($updated, '(Script version:\s*)[\d\.]+', ('${1}' + $version))

# 5. Write only if changed (idempotent)
if ($updated -ne $readme) {
    [System.IO.File]::WriteAllText($readmePath, $updated, $utf8)
    Write-Host "README.md updated (version $version)" -ForegroundColor Green
    exit 0
}
Write-Host "README.md already up to date (version $version)" -ForegroundColor DarkGray
