# Static check: every DevSkim inline suppression in the repo must name a
# real DevSkim rule id (DSxxxxxx). Keeps suppressions honest - a typo in a
# rule id silently leaves the alert open, and a copy-pasted wrong id
# suppresses the wrong thing on a future edit.
#
# It also catches code lines that would raise DS197836 on their own. That rule
# is a per-line pattern (a hash name followed by a clock word), so a plain
# download whose URL ends in ".sha256" and whose line carries "-TimeoutSec"
# reads as "hash of a time value" - exactly the alert raised on
# tests/test-installed-smoke.ps1. Fail before the scanner sees it.
#
# Run: pwsh -NoProfile -File tests/test-devskim-suppressions.ps1
# Exit 0 = all suppression comments reference known rule ids, and no
#          unsuppressed line matches the DS197836 pattern.

$ErrorActionPreference = 'Stop'

$known = @(
    'DS126858' # weak or broken hash algorithm
    'DS137138' # HTTP-based URL without TLS
    'DS162092' # accessing localhost
    'DS173237' # token or key found in source code
    'DS197836' # hash of a time value / insufficient entropy
    'DS440001' # generic hard-coded SSL/TLS protocol
    'DS440020' # .NET hard-coded SSL/TLS versions
)

$files = @('mumu-menu.ps1', 'mumu-menu.cjs', 'bootstrap-update.ps1', 'tests/run-pester.ps1',
    'tests/mumu-menu.Tests.ps1', 'tests/test-bootstrap-update.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$bad = 0; $total = 0
foreach ($rel in $files) {
    $path = Join-Path $repoRoot $rel
    if (-not (Test-Path -LiteralPath $path)) { Write-Error "missing file: $rel" }
    $lines = Get-Content -LiteralPath $path -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch 'DevSkim: ignore ((?:DS\d{6})(?:\s*,\s*DS\d{6})*)') { continue }
        $total++
        $ids = $Matches[1] -split '\s*,\s*'
        foreach ($id in $ids) {
            if ($known -notcontains $id) {
                Write-Host "UNKNOWN RULE: $rel :$($i + 1) -> $id" -ForegroundColor Red
                $bad++
            }
        }
    }
}

Write-Host ("DevSkim suppressions: {0} comment(s) checked, {1} unknown rule reference(s)" -f $total, $bad)

# --- DS197836 pattern guard -------------------------------------------------
# Mirror the rule's own regex and scope: matched per line, code only. Comment
# lines and inline-suppressed lines are ignored, so prose that mentions sha256
# next to a timestamp does not fail the build.
$hashThenTime = '(MD4|MD5|(SHA(1|224|256|384|512))).*Time'   # DevSkim: ignore DS126858,DS197836 - mirrors the scanner's own regex, nothing is hashed here
$selfPath = $MyInvocation.MyCommand.Path
$skipPath = '/(node_modules|\.git|\.tools|\.cloud-attachments)/'
$hits = 0
$scanned = 0
$scripts = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -in '.ps1', '.psm1', '.psd1', '.cjs', '.js' -and
        ($_.FullName.Replace('\', '/') -notmatch $skipPath)
    }
foreach ($file in $scripts) {
    if ($file.FullName -eq $selfPath) { continue }
    $scanned++
    $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -notmatch $hashThenTime) { continue }
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('#') -or $trimmed.StartsWith('//') -or $trimmed.StartsWith('*')) { continue }
        if ($line -match 'DevSkim: ignore .*DS197836') { continue }
        $rel = $file.FullName.Substring($repoRoot.Length + 1)
        Write-Host "DS197836 PATTERN: $rel :$($i + 1)" -ForegroundColor Red
        Write-Host "  $($line.Trim())" -ForegroundColor DarkGray
        $hits++
    }
}

Write-Host ("DevSkim DS197836 pattern: {0} script(s) scanned, {1} unsuppressed code line(s)" -f $scanned, $hits)
if ($bad -gt 0 -or $hits -gt 0) { exit 1 }
exit 0
