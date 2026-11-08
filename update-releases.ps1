# Sync RELEASES.md with git tags and published GitHub releases.
# Usage: ./update-releases.ps1 [-Path RELEASES.md] [-RepoSlug owner/name] [-Token <pat>]
# Used by the docs-index job in .github/workflows/release.yml and locally.
#
# Security scope:
#   - Read-only on the network: one paginated GET of /repos/<slug>/releases.
#     No writes to GitHub, no downloads, no executed command output.
#   - Touches exactly one file: rewrites RELEASES.md between the
#     RELEASES:AUTO markers. Everything outside them is hand-written prose.
#   - Fail-closed: ambiguous markers, no tags, a bad API answer or a release
#     with no usable date throws instead of writing a wrong index.

[CmdletBinding()]
param(
    # Document to rewrite, relative to the repository root.
    [string]$Path = 'RELEASES.md',

    # Repository whose releases are indexed.
    [string]$RepoSlug = 'genrihx2/MuMuManager-CLI-Menu',

    # GitHub token; anonymous works but is rate-limited hard on shared runners.
    [string]$Token = $env:GITHUB_TOKEN,

    # Offline fixture: read the releases payload from this JSON file (or
    # directory of page-1.json, page-2.json, ...) instead of the API. Only for
    # local dry runs; the Release workflow never passes it.
    [string]$ReleasesJson = ''
)

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$docPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $root $Path }
if (-not (Test-Path -LiteralPath $docPath -PathType Leaf)) {
    throw "RELEASES document not found: $docPath"
}

# Same convention as update-readme.ps1: .md files stay UTF-8 without BOM, and
# the existing line endings are preserved so a Windows checkout (CRLF) and the
# ubuntu runner (LF) agree byte for byte.
$utf8 = [System.Text.UTF8Encoding]::new($false)
$doc = [System.IO.File]::ReadAllText($docPath)
$nl = if ($doc -match "`r`n") { "`r`n" } else { "`n" }

# --- 1. Tags from git -------------------------------------------------------
# Creatordate: the tagger date for annotated tags, the commit date otherwise.
# Normalised to UTC so the runner's timezone can never shift a published date.
$tagLines = @(& git -C $root for-each-ref refs/tags --format='%(refname:short)|%(creatordate:iso-strict)')
if ($LASTEXITCODE -ne 0) { throw 'git for-each-ref refs/tags failed' }

$tags = New-Object System.Collections.ArrayList
foreach ($line in $tagLines) {
    $line = "$line".Trim()
    if (-not $line) { continue }
    $parts = $line -split '\|', 2
    if ($parts.Count -ne 2 -or -not $parts[0]) { throw "Unparseable tag record: '$line'" }

    $tagName = $parts[0]
    $stamp = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($parts[1], [ref]$stamp)) {
        throw "Tag '$tagName' has no parseable creatordate ('$($parts[1])')"
    }

    # Sort key: numeric version when the name carries one, so v10.10.0 does not
    # land above v10.9.0 the way a plain string compare would put it.
    $version = New-Object System.Version(0, 0)
    [void][System.Version]::TryParse(($tagName -replace '^[vV]', ''), [ref]$version)

    [void]$tags.Add([pscustomobject]@{
        Tag     = $tagName
        Date    = $stamp.UtcDateTime.ToString('yyyy-MM-dd')
        Version = $version
    })
}
if ($tags.Count -eq 0) { throw 'No tags found - refusing to write an empty index' }

# --- 2. Published releases from the GitHub API ------------------------------
# Windows PowerShell 5.1 defaults to SSL3/TLS1.0 on some hosts.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 # DevSkim: ignore DS440020,DS440001 - Windows PowerShell 5.1 needs the explicit TLS 1.2 opt-in for the releases API
}

$headers = @{
    'User-Agent' = 'mumu-releases-index'
    'Accept'     = 'application/vnd.github+json'
}
if ($Token) { $headers['Authorization'] = "Bearer $Token" }

# Payload: the offline fixture when given, otherwise the live API, page by page.
$payload = New-Object System.Collections.ArrayList
if ($ReleasesJson) {
    $fixture = if ([System.IO.Path]::IsPathRooted($ReleasesJson)) { $ReleasesJson } else { Join-Path $root $ReleasesJson }
    if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
        throw "Releases fixture not found: $fixture"
    }
    $parsed = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($fixture, [System.Text.Encoding]::UTF8))
    foreach ($item in @($parsed)) { [void]$payload.Add($item) }
}
else {
    $page = 1
    while ($page -le 20) {
        $uri = "https://api.github.com/repos/$RepoSlug/releases?per_page=100&page=$page"
        try {
            # Bind first: @(Invoke-RestMethod ...) does not enumerate the returned
            # JSON array, it wraps the whole array as ONE item.
            $fetched = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        }
        catch {
            throw "GitHub releases request failed (page $page): $($_.Exception.Message)"
        }
        $batch = @($fetched)
        if ($batch.Count -eq 0) { break }
        foreach ($item in $batch) { [void]$payload.Add($item) }
        if ($batch.Count -lt 100) { break }
        $page++
    }
}

$releases = @{}
$published = 0
foreach ($r in $payload) {
    if (-not $r) { continue }
    if ($r.draft) { continue }
    if (-not $r.tag_name) { throw "Release $($r.id) has no tag_name" }
    if (-not $r.published_at) { throw "Release '$($r.tag_name)' has no published_at" }

    $zip = @($r.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
    $sha = '—'
    if ($zip -and $zip.digest) { $sha = ("$($zip.digest)" -replace '^sha256:', '') }

    $releases["$($r.tag_name)"] = [pscustomobject]@{
        Date = ([datetimeoffset]$r.published_at).UtcDateTime.ToString('yyyy-MM-dd')
        Sha  = $sha
    }
}

# --- 3. Render the table ----------------------------------------------------
$ordered = @($tags | Sort-Object -Property @{ Expression = { $_.Version }; Descending = $true },
                                                @{ Expression = { $_.Date }; Descending = $true },
                                                @{ Expression = { $_.Tag }; Descending = $true })

$rows = New-Object System.Collections.ArrayList
foreach ($t in $ordered) {
    $rel = $releases[$t.Tag]
    if ($rel) {
        $published++
        $tagCell = '[' + $t.Tag + '](https://github.com/' + $RepoSlug + '/releases/tag/' + $t.Tag + ')'
        [void]$rows.Add('| ' + $tagCell + ' | ' + $t.Date + ' | ' + $rel.Date + ' | `' + $rel.Sha + '` |')
    }
    else {
        Write-Host ("  [note] {0} has no published release" -f $t.Tag) -ForegroundColor DarkGray
        [void]$rows.Add('| ' + $t.Tag + ' | ' + $t.Date + ' | — | — |')
    }
}

$summary = "Итого: $($ordered.Count) тегов, $published опубликованных релизов."
$blockLines = @('| Тег | Дата тега | Опубликован | SHA-256 ZIP |', '|---|---|---|---|')
$blockLines += @($rows)
$blockLines += @('', $summary)
$block = ($blockLines -join $nl)

# --- 4. Replace the managed block -------------------------------------------
$startMarker = '<!-- RELEASES:AUTO:START -->'
$endMarker = '<!-- RELEASES:AUTO:END -->'
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker)
$found = [regex]::Matches($doc, $pattern)
if ($found.Count -ne 1) {
    throw "Expected exactly one RELEASES:AUTO block in '$docPath', found $($found.Count)"
}

$replacement = $startMarker + $nl + $block + $nl + $endMarker
$updated = [regex]::Replace($doc, $pattern, $replacement)

# --- 5. Write only if changed (idempotent) ----------------------------------
$relative = [System.IO.Path]::GetFileName($docPath)
if ($updated -ne $doc) {
    [System.IO.File]::WriteAllText($docPath, $updated, $utf8)
    Write-Host "$relative updated ($($ordered.Count) tags, $published released)" -ForegroundColor Green
    exit 0
}
Write-Host "$relative already up to date ($($ordered.Count) tags, $published released)" -ForegroundColor DarkGray
