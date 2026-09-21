# Static check: every DevSkim inline suppression in the repo must name a
# real DevSkim rule id (DSxxxxxx). Keeps suppressions honest - a typo in a
# rule id silently leaves the alert open, and a copy-pasted wrong id
# suppresses the wrong thing on a future edit.
#
# Run: pwsh -NoProfile -File tests/test-devskim-suppressions.ps1
# Exit 0 = all suppression comments reference known rule ids.

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

$files = @('mumu-menu.ps1', 'bootstrap-update.ps1', 'tests/run-pester.ps1',
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
if ($bad -gt 0) { exit 1 }
exit 0
