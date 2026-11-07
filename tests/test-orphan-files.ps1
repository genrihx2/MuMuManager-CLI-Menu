# Static check: every tracked ROOT-LEVEL script must be referenced somewhere -
# the pipeline, the tests, the docs, a manifest, another script - or be
# declared a shipped file in release-files.txt.
#
# Why: the root kept collecting one-off helpers (run-tests.ps1,
# check-functions.ps1, rl-check.ps1) that nothing called, that drifted out of
# date and that still read like part of the product. This turns "wire it up or
# ship it" into a check that runs on every push and pull request.
#
# Scope: root-level files only. tests/ and .github/ are wired by construction,
# and cmd/ and archil/ carry their own manifest + README that explain them.
# Data files are out of scope on purpose - this gate is about code that looks
# runnable but nothing runs.
#
# The checker excludes ITSELF from both the candidate list and the reference
# search, so an allowlist entry here can never make a file look referenced.
#
# Run: pwsh -NoProfile -File tests/test-orphan-files.ps1
# Exit 0 = every tracked root-level script is referenced or ships.

#requires -Version 5.1

$ErrorActionPreference = 'Stop'

$scriptExtensions = @('.ps1', '.psm1', '.mjs', '.cjs', '.js', '.cmd', '.bat', '.sh')
$self = 'tests/test-orphan-files.ps1'

# Deliberately unreferenced files. Every entry needs a reason, and the reason
# is printed with the result so the next reader can judge it.
$allow = @{}

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $tracked = @(& git ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed - run this inside a git checkout' }

    $shipped = @()
    if (Test-Path -LiteralPath 'release-files.txt') {
        # release-files.txt is the single source of truth for what reaches a
        # user's install, exactly as the Release workflow reads it.
        $shipped = @(Get-Content -LiteralPath 'release-files.txt' -Encoding UTF8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') })
    }

    $candidates = @($tracked | Where-Object {
            $_ -ne $self -and
            $_ -notmatch '/' -and
            $scriptExtensions -contains [IO.Path]::GetExtension($_)
        })

    $orphans = @()
    foreach ($rel in $candidates) {
        if ($shipped -contains $rel) {
            Write-Host ("  [OK]   {0}  (ships via release-files.txt)" -f $rel)
            continue
        }
        if ($allow.ContainsKey($rel)) {
            Write-Host ("  [OK]   {0}  (allowlisted: {1})" -f $rel, $allow[$rel])
            continue
        }
        # -F: the name is a literal, not a pattern. The two pathspec excludes
        # keep the file's own text and this checker's allowlist out of the
        # evidence - otherwise every file would "reference" itself.
        $hits = @(& git grep -l -F -e $rel -- . ":(exclude)$rel" ":(exclude)$self")
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
            throw ("git grep failed for {0} (exit {1})" -f $rel, $LASTEXITCODE)
        }
        $refs = @($hits | Where-Object { $_ })
        if ($refs.Count -eq 0) {
            Write-Host ("  [FAIL] {0}  - nothing references it" -f $rel) -ForegroundColor Red
            $orphans += $rel
        } else {
            $more = ''
            if ($refs.Count -gt 1) { $more = (" (+{0} more)" -f ($refs.Count - 1)) }
            Write-Host ("  [OK]   {0}  <- {1}{2}" -f $rel, $refs[0], $more)
        }
    }

    Write-Host ''
    if ($orphans.Count -gt 0) {
        Write-Host ("Orphan root-level script(s): {0}" -f ($orphans -join ', ')) -ForegroundColor Red
        Write-Host 'Wire each one into the pipeline, the tests or the docs; add it to release-files.txt if it ships;' -ForegroundColor Red
        Write-Host 'or delete it. A one-off helper belongs under tests/ and goes away with its job.' -ForegroundColor Red
        exit 1
    }
    Write-Host ("All {0} tracked root-level script(s) are referenced or shipped." -f $candidates.Count) -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}
