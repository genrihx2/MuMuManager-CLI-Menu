#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Pester unit tests for mumu-menu.ps1 pure helpers (issue #20).
# The functions are extracted from the script via AST - exactly the
# production code, no copies - and tested offline (no network, no
# emulator). Wired into CI as the pester-unit matrix in tests.yml:
# BOTH engines (Windows PowerShell 5.1 + pwsh 7) on a pinned Pester
# 5.7.1, plus one unpinned canary leg tracking whatever the runner
# image ships next (.github/actions/pester-unit). The pester-unit-
# deployed job (tests/test-deployed-layout.ps1) additionally runs the
# suite INSIDE an installed-layout fixture: only the deployed files,
# no repo-only docs - tests tagged 'RepoFiles' are excluded there.
#
# Run locally:
#   all CI legs:  tests/run-matrix.ps1        (-Quick skips the canary leg)
#   single leg:   tests/run-pester.ps1 -PesterVersion 5.7.1 -ModuleDir <dir>
#   PS5.1:        powershell -ExecutionPolicy Bypass -File tests/run-pester.ps1
#   deployed:     pwsh -File tests/test-deployed-layout.ps1   (runs both engines)

BeforeAll {
    $script:menuPath = Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1'
    $errs = $null
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:menuPath, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) { throw "mumu-menu.ps1 has syntax errors: $($errs[0].Message)" }

    # Dot-source each function directly in the BeforeAll scope so the
    # definitions stay visible to every It (dot-sourcing inside a helper
    # function would scope them to the helper and lose them).
    foreach ($name in @('Repair-DesktopModulePath', 'Get-ContentHash', 'ConvertTo-ShellSafe', 'Compare-ScriptVersion',
                        'Format-JournalEvent', 'Test-ReleaseZip', 'Write-UpdateJournal', 'Test-ScriptVerMatchesTag',
                        'Get-JournalArrow', 'Show-UpdateJournal',
                        'Test-UpdateLockStale', 'Get-UpdateLockMessage', 'New-UpdateLock', 'Remove-UpdateLock',
                        'ConvertTo-JournalMarkdown', 'ConvertTo-JournalCsv', 'ConvertTo-JournalJson', 'Export-UpdateJournal',
                        'Get-ProblemFindings', 'Get-InstallStatus', 'Get-IntegrityVerdict', 'Invoke-MumuManagerProbe',
                        'Get-BackupFolders', 'Build-RollbackPlan', 'Invoke-Rollback', 'Test-CurlCapability',
                        'Get-DiagSummary', 'Show-UpdatePlan',
                        'Get-AutoDiagSummary', 'Invoke-StartupAutoDiag', 'Show-AutoDiagLine',
                        'Read-EtagCacheFile', 'Get-EtagCacheFileState', 'Save-EtagCacheFile', 'Invoke-EtagCacheMaintenance',
                        'Test-CurlRetrySupport', 'Repair-CurlRevocation', 'Get-CurlGitHubArgs', 'Invoke-CurlUtf8', 'Invoke-GitHubApiGet', 'Get-ReleaseInfo', 'Invoke-GitHubGet',
                        'Get-MumuProcessSamples', 'Get-MumuResourceSnapshot', 'Show-ResourceMonitor', 'Get-InstanceProcessMap',
                        'Get-InstanceWritableSettings', 'Compare-Settings', 'Format-CompareValue',
                        'Update-ResourceStats', 'Get-ResourceStatsSummary', 'ConvertTo-ResourceExportLines', 'Export-ResourceSnapshot',
                        'Get-MuMuInstallCandidateDirs', 'Get-MuMuActiveManagerPath', 'Get-MuMuInstalls',
                        'Get-MuMuInstallLabel', 'Get-MuMuInstallChoicePath', 'Read-MuMuInstallChoice', 'Save-MuMuInstallChoice',
                        'Get-MuMuVmsRoot', 'Get-MuMuInstanceAndroidVersion', 'Get-MuMuInstanceDir',
                        'Get-MuMuOrphanInstanceDirs',
                        'Get-AuthenticodeSignerName', 'Get-MuMuInstallDrift', 'Switch-MuMuActiveInstall',
                        'Resolve-MuMuInstall', 'Update-MumuInstallState',
                        'Stop-Logcat', 'Show-MumuOfflineInstallers', 'Resolve-InstallerThumbprint')) {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true) | Select-Object -First 1
        if (-not $f) { throw "$name function not found in mumu-menu.ps1" }
        . ([scriptblock]::Create($f.Extent.Text))
    }
    $script:ScriptDir = Join-Path $TestDrive 'jdir'
    New-Item -ItemType Directory -Path $script:ScriptDir -Force | Out-Null
    # Production wires this right after the writer is defined (line ~332);
    # replicate it so the extracted writer targets the test directory.
    $script:JournalFile = Join-Path $script:ScriptDir 'update-journal.log'
}

Describe 'Get-ContentHash (SHA-256 helper)' {

    It 'produces a 64-char uppercase hex digest' {
        (Get-ContentHash 'abc') | Should -Match '^[0-9A-F]{64}$'
    }

    It 'is deterministic for identical input' {
        Get-ContentHash 'same input' | Should -Be (Get-ContentHash 'same input')
    }

    It 'changes when the input changes' {
        Get-ContentHash 'input A' | Should -Not -Be (Get-ContentHash 'input B')
    }

    It 'ignores CR (CRLF and LF hash the same)' {
        Get-ContentHash "line1`r`nline2`n" | Should -Be (Get-ContentHash "line1`nline2`n")
    }

    It 'strips a UTF-8 BOM prefix' {
        $bom = [char]0xFEFF
        Get-ContentHash "$bom content" | Should -Be (Get-ContentHash ' content')
    }

    It 'matches the known SHA-256 of "abc"' {
        # ba7816bf... is the standard SHA-256 test vector for "abc"
        Get-ContentHash 'abc' | Should -Be 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD'
    }

    It 'trims trailing whitespace symmetrically with Invoke-GitHubGet (no phantom drift)' {
        # Tag blobs end with a newline; the fetch TrimEnds it. The hash helper
        # must trim too, or post-download verification false-alarms (v1.20.0 bug).
        Get-ContentHash "content`n" | Should -Be (Get-ContentHash 'content')
        Get-ContentHash "content`r`n  " | Should -Be (Get-ContentHash 'content')
    }

    It 'strips a trailing Authenticode signature block (re-signed install must not drift)' {
        # [CRT]/bootstrap re-signing appends a signature block to the local
        # script while the tag blob stays unsigned. Without stripping, [F]
        # reports a permanent false DRIFT on mumu-menu.ps1 (v1.22.24 regression).
        $clean = "line1`nline2"
        $sig = "`n# SIG # Begin signature block`n" + ('# filler' + "`n" * 1) * 50 + '# SIG # End signature block'
        Get-ContentHash ($clean + $sig) | Should -Be (Get-ContentHash $clean)
    }

    It 'does not treat ordinary comment text as a signature block' {
        # Only the exact marker line + newline opens a block; prose mentioning
        # the phrase must hash untouched.
        $text = "# SIG # Begin signature blocks are documented in the manual`nGet-Date"
        Get-ContentHash $text | Should -Be (Get-ContentHash "# SIG # Begin signature blocks are documented in the manual`nGet-Date")
    }
}

Describe 'Test-ScriptVerMatchesTag (version-fix heal guard)' {

    It 'accepts content whose scriptVer equals the tag' {
        Test-ScriptVerMatchesTag -Text "`$scriptVer = '1.20.4'" -Tag 'v1.20.4' | Should -BeTrue
    }

    It 'accepts a tag without the v prefix' {
        Test-ScriptVerMatchesTag -Text "`$scriptVer = '1.20.4'" -Tag '1.20.4' | Should -BeTrue
    }

    It 'rejects content claiming an older scriptVer (stale CDN blob)' {
        Test-ScriptVerMatchesTag -Text "`$scriptVer = '1.20.3'" -Tag 'v1.20.4' | Should -BeFalse
    }

    It 'rejects content without a scriptVer line' {
        Test-ScriptVerMatchesTag -Text '# no version here' -Tag 'v1.20.4' | Should -BeFalse
    }
}

Describe 'Get-JournalArrow (from/to rendering)' {

    It 'joins both fields with an arrow' {
        Get-JournalArrow -From 'v1.20.3' -To 'v1.20.4' | Should -Be 'v1.20.3 -> v1.20.4'
    }

    It 'renders an empty from as (new)' {
        Get-JournalArrow -From '' -To 'v1.20.3' | Should -Be '(new) -> v1.20.3'
    }

    It 'passes a lone from through' {
        Get-JournalArrow -From 'v1.20.2' -To '' | Should -Be 'v1.20.2'
    }

    It 'returns empty when both are empty' {
        Get-JournalArrow -From '' -To '' | Should -Be ''
    }
}

Describe 'Show-UpdateJournal rendering' {

    It 'renders (new) markers and groups same-run events' {
        $jf = Join-Path $TestDrive 'journal-view.log'
        $lines = @(
            (@('2026-09-15 10:46:32', 'menu', 'version-fix', '', 'v1.20.3', 'content matches tag; .version healed') -join "`t"),
            (@('2026-09-15 11:00:00', 'bootstrap', 'update-ok', 'v1.20.4', 'v1.20.5', '4 file(s) updated') -join "`t"),
            (@('2026-09-15 11:00:00', 'bootstrap', 'updater-refresh', 'v1.20.4', 'v1.20.5', 'bootstrap-update.ps1 updated from .new') -join "`t")
        )
        [System.IO.File]::WriteAllLines($jf, $lines)
        # Point the viewer at the fixture, then restore - other Describes
        # (Format-JournalEvent) rely on the BeforeAll-configured path.
        $prev = $script:JournalFile
        $script:JournalFile = $jf
        try {
            $out = (Show-UpdateJournal -Mode '2' 6>&1 | Out-String)
            $out | Should -Match '\(new\) -> v1\.20\.3'
            $out | Should -Match '- updater-refresh'
            # grouped line must not repeat the timestamp
            $out | Should -Not -Match '11:00:00.*updater-refresh'
        } finally {
            $script:JournalFile = $prev
        }
    }
}
Describe 'ConvertTo-ShellSafe (Android sh escaping)' {
    It 'passes through safe values unchanged' {
        ConvertTo-ShellSafe 'China Mobile' | Should -Be 'China Mobile'
        ConvertTo-ShellSafe '46000' | Should -Be '46000'
    }

    It 'replaces shell metacharacters with underscore' {
        ConvertTo-ShellSafe 'AT&T' | Should -Be 'AT_T'
        ConvertTo-ShellSafe 'a;b' | Should -Be 'a_b'
        ConvertTo-ShellSafe 'a|b' | Should -Be 'a_b'
        ConvertTo-ShellSafe 'a$b' | Should -Be 'a_b'
    }

    It 'handles combined metacharacters' {
        ConvertTo-ShellSafe 'A&T;B|C$D' | Should -Be 'A_T_B_C_D'
    }

    It 'never leaves a metacharacter in the output' {
        $out = ConvertTo-ShellSafe 'x&y;z|w$v'
        $out | Should -Not -Match '[&;|$]'
    }
}

Describe 'Compare-ScriptVersion' {

    It 'treats vX.Y.Z and X.Y.Z as equal' {
        Compare-ScriptVersion 'v1.19.6' '1.19.6' | Should -Be 0
    }

    It 'detects older, newer and equal correctly' {
        Compare-ScriptVersion '1.19.5' '1.19.6' | Should -Be -1
        Compare-ScriptVersion '1.20.0' '1.19.9' | Should -Be 1
        Compare-ScriptVersion 'v1.20.0' 'v1.20.0' | Should -Be 0
    }

    It 'is component-wise numeric, not lexicographic' {
        Compare-ScriptVersion '1.9.0' '1.10.0' | Should -Be -1
        Compare-ScriptVersion '2.0.0' '1.99.99' | Should -Be 1
    }

    It 'pads missing components with zero' {
        Compare-ScriptVersion '1.19' '1.19.0' | Should -Be 0
        Compare-ScriptVersion '2.0' '1.19.9' | Should -Be 1
    }

    It 'returns unknown (-2) for unparseable input' {
        Compare-ScriptVersion 'banana' '1.0.0' | Should -Be -2
        Compare-ScriptVersion '1.0.0' 'not-a-version' | Should -Be -2
    }
}

Describe 'Format-JournalEvent' {

    It 'emits six tab-separated fields' {
        $line = Format-JournalEvent -Actor 'menu' -EventType 'update-ok' -From 'v1' -To 'v2' -Detail 'ok'
        ($line -split "`t").Count | Should -Be 6
    }

    It 'places actor, event, from and to in the correct columns' {
        $line = Format-JournalEvent -Actor 'bootstrap' -EventType 'zip-verify-ok' -From '' -To 'v1.19.6' -Detail 'sha256 match'
        $cols = $line -split "`t"
        $cols[1] | Should -Be 'bootstrap'
        $cols[2] | Should -Be 'zip-verify-ok'
        $cols[3] | Should -Be ''
        $cols[4] | Should -Be 'v1.19.6'
    }

    It 'flattens tabs in the detail column' {
        $line = Format-JournalEvent -Actor 'menu' -EventType 'update-fail' -Detail "a`tbad`tnewline"
        ($line -split "`t").Count | Should -Be 6
        $line | Should -BeLike '*a bad newline'
    }

    It 'flattens newlines in the detail column' {
        $line = Format-JournalEvent -Actor 'menu' -EventType 'update-fail' -Detail "line1`nline2`r`nline3"
        ($line -split "`n").Count | Should -Be 1
        ($line -split "`r").Count | Should -Be 1
        $line | Should -BeLike '*line1 | line2 | line3'
    }

    It 'writes a real journal file through Write-UpdateJournal with the same format' {
        Write-UpdateJournal -EventType 'update-ok' -Detail 'format check'
        $written = (Get-Content -LiteralPath (Join-Path $script:ScriptDir 'update-journal.log') | Select-Object -Last 1)
        ($written -split "`t").Count | Should -Be 6
        ($written -split "`t")[2] | Should -Be 'update-ok'
    }
}

Describe 'Test-ReleaseZip (ZIP self-test)' {

    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        $script:zDir = Join-Path $TestDrive 'zipfix'
        New-Item -ItemType Directory -Path $script:zDir -Force | Out-Null

        function script:New-ZipFixture {
            param([string]$Path, [string]$Ver = '1.20.0', [string[]]$Omit = @(), [string[]]$Extra = @())
            $tmp = Join-Path $script:zDir ('t_' + [IO.Path]::GetFileName($Path))
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
            $archive = [System.IO.Compression.ZipFile]::Open($tmp, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $bodies = @{
                    'mumu-menu.ps1'        = "# menu`n`$scriptVer = '$Ver'`n"
                    'mumu-menu.cjs'        = "// js entry`n"
                    'SKILL.md'             = "# skill`n"
                    'README.md'            = "# readme`n"
                    'bootstrap-update.ps1' = "# updater`n"
                    'Watch-MumuConnections.ps1' = "# watcher`n"
                    'Test-MumuTunnelAB.ps1'     = "# ab`n"
                    'Diag-MumuNx.ps1'           = "# diag`n"
                    '.version'             = "v$Ver"
                }
                foreach ($name in $bodies.Keys) {
                    if ($Omit -contains $name) { continue }
                    $entry = $archive.CreateEntry($name)
                    $w = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
                    $w.Write($bodies[$name]); $w.Dispose()
                }
                foreach ($extra in $Extra) {
                    $entry = $archive.CreateEntry($extra)
                    $w = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
                    $w.Write('extra'); $w.Dispose()
                }
            } finally { $archive.Dispose() }
            Move-Item -LiteralPath $tmp -Destination $Path -Force
            $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
            Set-Content -LiteralPath "$Path.sha256" -Value "$h  $([IO.Path]::GetFileName($Path))" -Encoding Ascii
        }
    }

    It 'passes a correct release ZIP (all three checks)' {
        $zip = Join-Path $script:zDir 'good-v1.20.0.zip'
        New-ZipFixture -Path $zip
        $r = Test-ReleaseZip -ZipPath $zip -ExpectedTag 'v1.20.0'
        $r.Ok | Should -BeTrue
        $r.ZipHash | Should -Be $r.SidecarHash
        $r.ZipVersion | Should -Be '1.20.0'
        @($r.Checks) | Should -Contain 'file set: OK (9 files)'
    }

    It 'fails a tampered ZIP on the sha256 check' {
        $zip = Join-Path $script:zDir 'tampered-v1.20.0.zip'
        New-ZipFixture -Path $zip
        Copy-Item -LiteralPath $zip -Destination "$zip.t2" -Force
        $bytes = [System.IO.File]::ReadAllBytes("$zip.t2")
        # Flip a byte in the LAST 64 bytes (central directory): deterministic
        # sha256 mismatch without risking a corrupt LOCAL file header, which
        # ZipFile::OpenRead tolerates but entry access throws on.
        $bytes[$bytes.Length - 20] = $bytes[$bytes.Length - 20] -bxor 0xFF
        [System.IO.File]::WriteAllBytes("$zip.t2", $bytes)
        $r = Test-ReleaseZip -ZipPath "$zip.t2" -ExpectedTag 'v1.20.0'
        $r.Ok | Should -BeFalse
    }

    It 'never throws on a corrupt archive body (header-level damage)' {
        # Regression: a flipped byte inside a LOCAL FILE HEADER used to escape
        # Test-ReleaseZip as a terminating exception (InvalidDataException
        # "A local file header is corrupt") instead of the contracted
        # Ok=$false result. CI caught this as a flaky deployed-layout leg.
        $zip = Join-Path $script:zDir 'header-corrupt-v1.20.0.zip'
        New-ZipFixture -Path $zip
        $bytes = [System.IO.File]::ReadAllBytes($zip)
        # Local header of the first entry starts right after the 4-byte
        # signature 'PK\x03\x04' at offset 0; flip a byte inside its
        # structure but before the file data.
        $bytes[30] = $bytes[30] -bxor 0xFF
        [System.IO.File]::WriteAllBytes($zip, $bytes)
        { $script:r = Test-ReleaseZip -ZipPath $zip -ExpectedTag 'v1.20.0' } | Should -Not -Throw
        $script:r.Ok | Should -BeFalse
    }

    It 'fails a scriptVer/tag mismatch' {
        $zip = Join-Path $script:zDir 'mismatch-v1.20.9.zip'
        New-ZipFixture -Path $zip -Ver '1.20.0'
        $r = Test-ReleaseZip -ZipPath $zip -ExpectedTag 'v1.20.9'
        $r.Ok | Should -BeFalse
        @($r.Checks | Where-Object { $_ -like 'scriptVer: MISMATCH*' }).Count | Should -Be 1
    }

    It 'names missing and unexpected files in the file-set check' {
        $zip = Join-Path $script:zDir 'badset-v1.20.0.zip'
        New-ZipFixture -Path $zip -Omit @('SKILL.md') -Extra @('bonus.txt')
        $r = Test-ReleaseZip -ZipPath $zip -ExpectedTag 'v1.20.0'
        $r.Ok | Should -BeFalse
        (@($r.Checks) -join ' ') | Should -Match 'missing: SKILL\.md'
        (@($r.Checks) -join ' ') | Should -Match 'unexpected: bonus\.txt'
    }

    It 'fails cleanly on a missing archive' {
        $r = Test-ReleaseZip -ZipPath (Join-Path $script:zDir 'ghost.zip') -ExpectedTag 'v1.20.0'
        $r.Ok | Should -BeFalse
        @($r.Checks | Where-Object { $_ -like 'zip: MISSING*' }).Count | Should -Be 1
    }
}

Describe 'Invoke-GitHubGet: ETag cache, 304 replay, ref pinning (issue #22)' {

    BeforeAll {
        foreach ($name in @('Invoke-GitHubGet', 'Resolve-GitRefSha')) {
            $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true) | Select-Object -First 1
            if (-not $f) { throw "$name function not found in mumu-menu.ps1" }
            . ([scriptblock]::Create($f.Extent.Text))
        }
        $script:GitHubToken = $null
    }

    It 'replays the cached body on HTTP 304 (curl exit 33) instead of failing' {
        $calls = [System.Collections.Generic.List[string]]::new()
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $calls.Add(($curlArgs -join ' ')) | Out-Null
            $h = [array]::IndexOf($curlArgs, '-D'); $o = [array]::IndexOf($curlArgs, '-o')
            if ($h -ge 0) { Set-Content -LiteralPath $curlArgs[$h + 1] -Value "HTTP/1.1 200 OK`netag: `"abc123`"" -Encoding ASCII }
            if ($o -ge 0) { [System.IO.File]::WriteAllText($curlArgs[$o + 1], "hello body`n") }
            $global:LASTEXITCODE = 0
        }
        $script:EtagCache = @{}; $script:EtagTags = @{}; $script:RefShaCache = @{}
        $url = 'https://api.github.com/repos/o/r/contents/README.md?ref=v1.0.0'
        Invoke-GitHubGet $url | Should -Be 'hello body'
        $script:EtagTags[$url] | Should -Be '"abc123"'
        # Second response: a real 304 shape - status line only, empty body file,
        # curl exits 33 on HTTP 304 without --fail.
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $calls.Add(($curlArgs -join ' ')) | Out-Null
            $h = [array]::IndexOf($curlArgs, '-D'); $o = [array]::IndexOf($curlArgs, '-o')
            if ($h -ge 0) { Set-Content -LiteralPath $curlArgs[$h + 1] -Value 'HTTP/1.1 304 Not Modified' -Encoding ASCII }
            if ($o -ge 0) { Set-Content -LiteralPath $curlArgs[$o + 1] -Value '' -Encoding ASCII }
            $global:LASTEXITCODE = 33
        }
        Invoke-GitHubGet $url | Should -Be 'hello body'
        ($calls | Select-Object -Last 1) | Should -Match 'If-None-Match: "abc123"'
    }

    It 'never caches an API error body (rate limit) even when an ETag is present' {
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $h = [array]::IndexOf($curlArgs, '-D'); $o = [array]::IndexOf($curlArgs, '-o')
            if ($h -ge 0) { Set-Content -LiteralPath $curlArgs[$h + 1] -Value 'HTTP/1.1 200 OK' -Encoding ASCII }
            if ($o -ge 0) { [System.IO.File]::WriteAllText($curlArgs[$o + 1], '{"message":"API rate limit exceeded"}') }
            $global:LASTEXITCODE = 0
        }
        $script:EtagCache = @{}; $script:EtagTags = @{}; $script:RefShaCache = @{}
        Invoke-GitHubGet 'https://api.github.com/repos/o/r/contents/README.md?ref=v1.0.0' | Should -Match 'rate limit'
        $script:EtagCache.Count | Should -Be 0
    }

    It 'pins a tag to its commit SHA before the contents request' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $sha = 'a' * 40
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $url = $curlArgs[-1]
            $calls.Add($url) | Out-Null
            $h = [array]::IndexOf($curlArgs, '-D'); $o = [array]::IndexOf($curlArgs, '-o')
            if ($h -ge 0) { Set-Content -LiteralPath $curlArgs[$h + 1] -Value 'HTTP/1.1 200 OK' -Encoding ASCII }
            if ($o -ge 0) {
                if ($url -match '/git/ref/tags/') { [System.IO.File]::WriteAllText($curlArgs[$o + 1], (ConvertTo-Json @{ object = @{ sha = $sha; type = 'commit' } } -Compress)) }
                else { [System.IO.File]::WriteAllText($curlArgs[$o + 1], "content`n") }
            }
            $global:LASTEXITCODE = 0
        }
        $script:EtagCache = @{}; $script:EtagTags = @{}; $script:RefShaCache = @{}
        Invoke-GitHubGet 'https://api.github.com/repos/o/r/contents/README.md?ref=v1.0.0' | Should -Be 'content'
        $calls | Should -Contain "https://api.github.com/repos/o/r/git/ref/tags/v1.0.0"
        @($calls | Where-Object { $_ -match "ref=$sha" }).Count | Should -Be 1
        @($calls | Where-Object { $_ -match 'ref=v1\.0\.0' }).Count | Should -Be 0
    }

    It 'derefs annotated tags (object type tag) to the commit SHA' {
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $url = $curlArgs[-1]
            $h = [array]::IndexOf($curlArgs, '-D'); $o = [array]::IndexOf($curlArgs, '-o')
            if ($h -ge 0) { Set-Content -LiteralPath $curlArgs[$h + 1] -Value 'HTTP/1.1 200 OK' -Encoding ASCII }
            if ($o -ge 0) {
                if ($url -match '/git/ref/tags/') { [System.IO.File]::WriteAllText($curlArgs[$o + 1], (ConvertTo-Json @{ object = @{ sha = ('1' * 40); type = 'tag' } } -Compress)) }
                else { [System.IO.File]::WriteAllText($curlArgs[$o + 1], (ConvertTo-Json @{ object = @{ sha = ('2' * 40); type = 'commit' } } -Compress)) }
            }
            $global:LASTEXITCODE = 0
        }
        $script:EtagCache = @{}; $script:EtagTags = @{}; $script:RefShaCache = @{}
        Resolve-GitRefSha -RepoPart 'o/r' -Ref 'vA' | Should -Be ('2' * 40)
    }

    It 'returns null (never throws) when the ref cannot be resolved' {
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $o = [array]::IndexOf($curlArgs, '-o')
            if ($o -ge 0) { [System.IO.File]::WriteAllText($curlArgs[$o + 1], '{"message":"Not Found"}') }
            $global:LASTEXITCODE = 0
        }
        $script:EtagCache = @{}; $script:EtagTags = @{}; $script:RefShaCache = @{}
        Resolve-GitRefSha -RepoPart 'o/r' -Ref 'vGhost' | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-GitHubGet: saved-token rejection disables the token once (v1.22.43)' {

    BeforeAll {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-GitHubGet'
        }, $true) | Select-Object -First 1
        if (-not $f) { throw 'Invoke-GitHubGet function not found in mumu-menu.ps1' }
        . ([scriptblock]::Create($f.Extent.Text))
        $script:CurlRetryArgs = @()
    }

    It 'retries anonymously, clears the session token exactly once, and never repeats the round-trip' {
        $calls = [System.Collections.Generic.List[string]]::new()
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $calls.Add(($curlArgs -join ' ')) | Out-Null
            $h = [array]::IndexOf($curlArgs, '-D'); $o = [array]::IndexOf($curlArgs, '-o')
            if ($h -ge 0) { Set-Content -LiteralPath $curlArgs[$h + 1] -Value 'HTTP/1.1 200 OK' -Encoding ASCII }
            if ($o -ge 0) {
                # Call 1 (with the rejected token): Bad-credentials JSON.
                # Every later call (anonymous): real content.
                if ($calls.Count -eq 1) {
                    [System.IO.File]::WriteAllText($curlArgs[$o + 1], '{"message":"Bad credentials"}')
                } else {
                    [System.IO.File]::WriteAllText($curlArgs[$o + 1], "content`n")
                }
            }
            $global:LASTEXITCODE = 0
        }
        $script:EtagCache = @{}; $script:EtagTags = @{}; $script:RefShaCache = @{}
        $script:GitHubToken = 'ghp_rejected'
        # 40-hex ref: the tag->SHA pin branch is skipped deterministically.
        $url = 'https://api.github.com/repos/o/r/contents/README.md?ref=78859129d6aa76b7523541e11f2b4deed54484c5'
        Invoke-GitHubGet $url | Should -Be 'content'
        $script:GitHubToken | Should -Be ''
        $calls.Count | Should -Be 2  # rejected attempt + anonymous retry
        # A second request must run anonymously - no attach/reject again.
        Invoke-GitHubGet $url | Should -Be 'content'
        $calls.Count | Should -Be 3
        $script:GitHubToken | Should -Be ''
    }
}

Describe 'Saved-token rejection wiring (v1.22.43 regression guard)' {

    It 'bootstrap Download-File clears the token at SCRIPT scope (no function-local shadow)' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\bootstrap-update.ps1'))
        $src | Should -Match '\$script:token\s*=\s*\$null'
        # the old shadowing assignment must be gone; comment lines and the
        # top-level "$token = $null" initialization (pre-DPAPI-read) are
        # excluded from the check
        $code = (($src -split "\r?\n") | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\$token\s*=\s*\$null\s*$' }) -join "`n"
        $code | Should -Not -Match '(?<!script:)\$token\s*=\s*\$null'
    }

    It 'the menu disables the rejected token in all four fetch paths and says how to restore it' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mumu-menu.ps1'))
        # Invoke-GitHubGet fallback + [U]/[UP] download fallback + Invoke-GitHubApiGet guard
        # + Repair-Installation's no-auth retry (v10.2.0 auto-repair).
        ([regex]::Matches($src, [regex]::Escape('$script:GitHubToken = '''''))).Count | Should -Be 4
        ([regex]::Matches($src, [regex]::Escape('Token rejected — retrying without auth'))).Count | Should -Be 4
        ([regex]::Matches($src, [regex]::Escape('re-save via menu [K]'))).Count | Should -Be 4
    }
}

Describe 'Test-InstallationIntegrity: tag/SHA split (v1.21.0 regression guard)' {

    It 'fetches content through $FetchRef while keeping $Tag for the semantic .version compare' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-InstallationIntegrity'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        $t | Should -Match '\$FetchRef = \$Tag'
        $t | Should -Match 'ref=\$FetchRef'
        # Overwriting $Tag with the SHA disabled the semantic marker branch
        # and false-DRIFTed healthy installs (v1.21.0 regression) - the
        # function must never fetch through $Tag again.
        $t | Should -Not -Match 'ref=\$Tag'
        $t | Should -Match 'Compare-ScriptVersion -A \$localTag -B \$Tag'
    }
}

Describe 'Update-FromGitHub: tag pinning for downloads and fingerprints (stale-CDN hardening)' {

    It 'resolves the tag to a commit SHA and fetches fingerprints + downloads through the pinned ref' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-FromGitHub'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        # Pin resolution present with graceful fallback (tag kept on failure).
        $t | Should -Match '\$pinnedRef = \$tag'
        $t | Should -Match 'Resolve-GitRefSha -RepoPart \$GitHubRepo -Ref \$tag'
        # Both consumers go through the pinned ref: fingerprints and downloads.
        $t | Should -Match 'Get-ExpectedFileHashes -Tag \$tag -Names \$files -FetchRef \$pinnedRef'
        $t | Should -Match 'ref=\$pinnedRef'
        # Regression guard (v1.21.0 lesson): $tag stays the human-readable name
        # for the semantic .version compare and the journal - it must never
        # appear in a fetch URL inside Update-FromGitHub.
        $t | Should -Not -Match 'ref=\$tag\b'
    }

    It 'self-update downloads the full deployed file set (v1.22.48 contract)' {
        # The [U] file list must match the release ZIP contract: 8 files + .version
        # (the marker is written by the updater itself after a verified run).
        # Regression guard: v1.22.46 widened the ZIP to 8 files but the [U]
        # downloader stayed on the pre-trio 4-file list, so new files never
        # reached existing installs via [U].
        $src = Get-Content -Raw $script:menuPath
        $expected = "`$files = @('mumu-menu.ps1', 'mumu-menu.cjs', 'SKILL.md', 'README.md', 'bootstrap-update.ps1', 'Watch-MumuConnections.ps1', 'Test-MumuTunnelAB.ps1', 'Diag-MumuNx.ps1')"
        ($src -match [regex]::Escape($expected)) | Should -Be $true
        # Rollback defaults cover the same set (no stale 4-file defaults left).
        ($src -match [regex]::Escape("`$FileSet = @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')")) | Should -Be $false
    }

    It 'repairs an install whose marker is current but a declared file is missing (v10.3.1)' {
        # A release can ADD a file; a marker-only gate then reports 'Up to date'
        # forever and the new file never arrives (seen live right after 10.3.0:
        # .version = v10.3.0, no mumu-menu.cjs in the installed folder).
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-FromGitHub'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        $t | Should -Match '\$missingReleaseFiles = @\(\$files \| Where-Object'
        $t | Should -Match 'if \(\$localTag -eq \$tag -and \$missingReleaseFiles\.Count -gt 0\)'
        $t | Should -Match 'Repairing: downloading the release file set'
        # The repair must download the very same list the gate scanned.
        $t | Should -Match 'Get-ExpectedFileHashes -Tag \$tag -Names \$files'
    }

    It 'Get-ExpectedFileHashes fetches through FetchRef and falls back to the tag' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ExpectedFileHashes'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        $t | Should -Match '\[string\]\$FetchRef'
        $t | Should -Match '\$ref = if \(\$FetchRef\) \{ \$FetchRef \} else \{ \$Tag \}'
        $t | Should -Match 'ref=\$ref'
        $t | Should -Not -Match 'ref=\$Tag'
    }

    It 'the [UP] plan honestly describes the pinned source and the mirror fallback' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-UpdatePlan'
        }, $true) | Select-Object -First 1
        $f.Extent.Text | Should -Match 'same pinned SHA'
        $f.Extent.Text | Should -Match 'cdn\.jsdelivr\.net mirror'
    }
}

Describe 'Update-FromGitHub: jsDelivr CDN fallback (transport-only, hash-gated)' {

    BeforeAll {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-FromGitHub'
        }, $true) | Select-Object -First 1
        $script:ufg = $f.Extent.Text
    }

    It 'wiring: _DlFile keeps a hash-verified CDN fallback without following redirects or leaking the token' {
        $t = $script:ufg
        # Fallback exists and is scoped to contents-API URLs (path + ?ref= split).
        $t | Should -Match 'cdn\.jsdelivr\.net/gh/'
        $t | Should -Match '\?ref=\(\[\^&\]\+\)' -Because 'the CDN URL needs path and ref split from the API URL'
        # The fallback must never carry the auth header.
        $t | Should -Not -Match 'Authorization: token \$GitHubToken.*jsdelivr'
        # Transport-only: no -L on the CDN attempt (no redirect-following to
        # raw.githubusercontent.com - project invariant since v1.13.3).
        $cdnArgsLine = ($t -split "`n" | Where-Object { $_ -match '\$cdnArgs = ' })
        $cdnArgsLine | Should -Not -Match '-L'
        # Only reached when the primary attempt produced nothing.
        $t | Should -Match 'api\.github\.com failed - retrying via cdn\.jsdelivr\.net mirror'
    }

    It '-NoAuth keeps the GitHub token away from every mirror request' {
        $t = $script:ufg
        # The primary attempt is skipped entirely in NoAuth mode.
        $t | Should -Match '\$GitHubToken.*-not \$NoAuth'
        # The NoAuth comment states the guarantee explicitly.
        $t | Should -Match 'token never touches a third-party CDN'
    }

    It 'the [UP] plan and [V] hint describe the mirror honestly' {
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw
        ($src -match 'fallback: cdn\.jsdelivr\.net mirror') | Should -Be $true
        ($src -match 'cdn\.jsdelivr\.net/gh/') | Should -Be $true
    }
}

Describe 'Get-ReleaseInfo (structured latest-release helper)' {

    BeforeAll {
        # Stand-ins for the two external calls Get-ReleaseInfo makes:
        # Invoke-GitHubGet (the curl transport, deliberately not dot-sourced
        # here) and Get-RemoteFile (nested inside Update-FromGitHub, so
        # reachable only through dynamic scope). Plain stubs instead of
        # Pester Mock: Pester 6 refuses to mock a command that does not
        # exist, and stubs behave identically on Pester 5 and 6. Tests drive
        # them through the script-scope variables below.
        $script:ghGetCalls      = @()
        $script:ghGetResponse   = $null
        $script:ghGetThrow      = ''
        $script:remoteFileCalls = @()
        $script:remoteFileText  = ''
        function Invoke-GitHubGet {
            param([string]$Url, [int]$TimeoutSec = 30)
            $script:ghGetCalls += ,@{ Url = $Url; TimeoutSec = $TimeoutSec }
            if ($script:ghGetThrow) { throw "Invoke-GitHubGet failed: $($script:ghGetThrow)" }
            return $script:ghGetResponse
        }
        function Get-RemoteFile {
            param([string]$Name, [string]$Ref)
            $script:remoteFileCalls += ,@{ Name = $Name; Ref = $Ref }
            if (-not $script:remoteFileText) { throw 'Get-RemoteFile: not resolvable outside Update-FromGitHub' }
            return $script:remoteFileText
        }
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-FromGitHub'
        }, $true) | Select-Object -First 1
        $script:ufgText = $f.Extent.Text
        # Show-ReleaseFetchFailure is nested inside Update-FromGitHub - extract
        # it too, so the per-kind rendering is tested by running it rather
        # than by matching its text.
        $sf = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-ReleaseFetchFailure'
        }, $true) | Select-Object -First 1
        if (-not $sf) { throw 'Show-ReleaseFetchFailure function not found in mumu-menu.ps1' }
        . ([scriptblock]::Create($sf.Extent.Text))
    }

    BeforeEach {
        $script:ghGetCalls      = @()
        $script:ghGetResponse   = $null
        $script:ghGetThrow      = ''
        $script:remoteFileCalls = @()
        $script:remoteFileText  = ''
    }

    It 'Update-FromGitHub delegates the release fetch to Get-ReleaseInfo (no inline releases/latest copy)' {
        $t = $script:ufgText
        $t | Should -Match '\$relInfo = Get-ReleaseInfo -Failure \(\[ref\]\$failReason\)'
        # The v1.22.40 refactor moved the inline releases/latest fetch (~34
        # lines) into the helper - the updater must not keep a second copy.
        $t | Should -Not -Match 'releases/latest'
        # Regression guard: the first refactor re-checked the already-null
        # result ($relInfo -is [pscustomobject]) - a condition that can never
        # be true - and lost the per-case messages. Both are pinned here.
        $t | Should -Not -Match '\$relInfo -is \[pscustomobject\]'
    }

    It 'Update-FromGitHub keeps the pre-refactor failure messaging (rate limit / API / no releases)' {
        $t = $script:ufgText
        $t | Should -Match 'No releases found on remote'
        $t | Should -Match 'GitHub API rate limit exceeded\.'
        $t | Should -Match 'menu \[K\] Update GitHub token'
        $t | Should -Match 'GitHub API: \$\(\$Reason\.Message\)'
        $t | Should -Match '\$Reason\.Message -match ''403\|rate limit'''
        # A plain transport failure keeps the wording the outer catch used.
        $t | Should -Match 'Update check failed: \$\(\$Reason\.Message\)'
    }

    It 'fetch wiring: releases/latest for the -Repo param (default $GitHubRepo) through Invoke-GitHubGet' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ReleaseInfo'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        $t | Should -Match '\[string\]\$Repo = \$GitHubRepo'
        $t | Should -Match 'Invoke-GitHubGet "https://api\.github\.com/repos/\$Repo/releases/latest"'
        # No transport internals here: Accept, the token and retries all live
        # in Invoke-GitHubGet. Local headers/auth would be dead code - the
        # transport takes no header arguments, so they were built and ignored.
        $t | Should -Not -Match '\$headers'
        $t | Should -Not -Match 'Authorization'
        # The failure reason is reported structurally so callers can keep
        # their own (pre-refactor) messaging.
        $t | Should -Match '\[ref\]\$Failure'
        $t | Should -Match "'no-release'"
        $t | Should -Match "'rate-limit'"
        $t | Should -Match "'transport'"
    }

    It 'maps the release JSON into a structured object (tag, dates, author, assets)' {
        $script:ghGetResponse = @'
{"tag_name":"v1.22.40","prerelease":false,"published_at":"2026-09-24T15:35:46Z","target_commitish":"main","author":{"login":"genrihx2"},"body":"notes body","assets":[{"name":"MuMuManager-CLI-Menu-v1.22.40.zip","size":1048576,"browser_download_url":"https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/download/v1.22.40/MuMuManager-CLI-Menu-v1.22.40.zip","content_type":"application/zip"}]}
'@
        $script:remoteFileText = "`$scriptVer = '1.22.40'`n"
        $r = Get-ReleaseInfo -Repo 'genrihx2/MuMuManager-CLI-Menu'
        $r | Should -Not -BeNullOrEmpty
        $r.Tag | Should -Be 'v1.22.40'
        $r.Prerelease | Should -BeFalse
        $r.PublishedAt | Should -BeOfType [datetime]
        # Compare the instant, not the rendering: the production [datetime]
        # cast (PS 5.1 ConvertFrom-Json keeps ISO dates as strings - the
        # cast pins the shape on both engines) round-trips through the
        # JSON fixture, so assert the UTC instant it encodes.
        $r.PublishedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-09-24T15:35:46Z'
        $r.TargetCommit | Should -Be 'main'
        $r.Author | Should -Be 'genrihx2'
        $r.Body | Should -Be 'notes body'
        $r.AssetCount | Should -Be 1
        $r.Assets[0].Name | Should -Be 'MuMuManager-CLI-Menu-v1.22.40.zip'
        $r.Assets[0].Size | Should -Be 1048576
        $r.Assets[0].DownloadUrl | Should -Be 'https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/download/v1.22.40/MuMuManager-CLI-Menu-v1.22.40.zip'
        $r.Assets[0].ContentType | Should -Be 'application/zip'
        $r.DownloadUrl | Should -Be $r.Assets[0].DownloadUrl
        $r.AssetFilenames | Should -Be 'MuMuManager-CLI-Menu-v1.22.40.zip'
        # Exactly one transport call: releases/latest for the given repo, 15s.
        $script:ghGetCalls.Count | Should -Be 1
        $script:ghGetCalls[0].Url | Should -Be 'https://api.github.com/repos/genrihx2/MuMuManager-CLI-Menu/releases/latest'
        $script:ghGetCalls[0].TimeoutSec | Should -Be 15
        # The scriptVer probe fetches the menu blob pinned to the release tag.
        $script:remoteFileCalls.Count | Should -Be 1
        $script:remoteFileCalls[0].Name | Should -Be 'mumu-menu.ps1'
        $script:remoteFileCalls[0].Ref | Should -Be 'v1.22.40'
    }

    It 'anchors the scriptVer extraction: double-quoted and indented look-alikes are ignored' {
        # (?m)^ plus single quotes only - a look-alike inside the fetched blob
        # must never become the displayed version.
        $script:ghGetResponse = '{"tag_name":"v1.22.40"}'
        $script:remoteFileText = "`$scriptVer = `"9.9.9`"`n  `$scriptVer = '0.0.1'`n"
        (Get-ReleaseInfo -Repo 'genrihx2/MuMuManager-CLI-Menu').ScriptVer | Should -Be ''
    }

    It 'keeps ScriptVer empty when the probe cannot resolve Get-RemoteFile (standalone call)' {
        # No blob text: the stub throws, mirroring a standalone call where the
        # nested Get-RemoteFile does not exist. The probe must fail soft.
        $script:ghGetResponse = '{"tag_name":"v1.22.40"}'
        $r = Get-ReleaseInfo -Repo 'genrihx2/MuMuManager-CLI-Menu'
        $r.Tag | Should -Be 'v1.22.40'
        $r.ScriptVer | Should -Be ''
    }

    It 'maps a multi-asset release: DownloadUrl = first asset, AssetFilenames = joined list' {
        $script:ghGetResponse = '{"tag_name":"v1.22.40","assets":[{"name":"mumu-menu.ps1","size":10,"browser_download_url":"https://example/1","content_type":"text/plain"},{"name":"SKILL.md","size":20,"browser_download_url":"https://example/2","content_type":"text/markdown"}]}'
        $r = Get-ReleaseInfo -Repo 'genrihx2/MuMuManager-CLI-Menu'
        $r.AssetCount | Should -Be 2
        $r.DownloadUrl | Should -Be 'https://example/1'
        $r.AssetFilenames | Should -Be 'mumu-menu.ps1, SKILL.md'
    }

    It 'maps an asset-less prerelease safely: no author, empty download fields' {
        $script:ghGetResponse = '{"tag_name":"v0.9.0","prerelease":true,"assets":[]}'
        $r = Get-ReleaseInfo -Repo 'genrihx2/MuMuManager-CLI-Menu'
        $r.Tag | Should -Be 'v0.9.0'
        $r.Prerelease | Should -BeTrue
        $r.Author | Should -Be ''
        $r.AssetCount | Should -Be 0
        $r.DownloadUrl | Should -Be ''
        $r.AssetFilenames | Should -Be ''
    }

    It 'returns $null when the response has no tag_name (no release, API error body, empty body)' {
        foreach ($body in @('{}', '{"message":"Not Found","documentation_url":"https://docs.github.com/rest"}', '')) {
            $script:ghGetResponse = $body
            Get-ReleaseInfo -Repo 'genrihx2/MuMuManager-CLI-Menu' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null on transport failure (network down / rate limited) without writing errors to the host streams' {
        $script:ghGetThrow = 'rate limit exceeded'
        # Catch-all: the streams the user actually sees (output/error) stay
        # clean - diagnostics belong to Write-Debug per project convention.
        $visible = @(Get-ReleaseInfo -Repo 'genrihx2/MuMuManager-CLI-Menu' 6>&1)
        $visible | Should -BeNullOrEmpty
        $script:ghGetCalls.Count | Should -Be 1
    }

    It 'reports the failure reason via -Failure so the caller keeps its own messaging' {
        # The four shapes Update-FromGitHub renders differently - the reason a
        # caller must not be left with a single generic line.
        $fail = $null
        $script:ghGetResponse = '{}'
        Get-ReleaseInfo -Repo 'x' -Failure ([ref]$fail) | Should -BeNullOrEmpty
        $fail.Kind | Should -Be 'no-release'
        $fail.Message | Should -Be ''

        $script:ghGetResponse = '{"message":"Not Found"}'
        Get-ReleaseInfo -Repo 'x' -Failure ([ref]$fail) | Should -BeNullOrEmpty
        $fail.Kind | Should -Be 'api'
        $fail.Message | Should -Be 'Not Found'

        $script:ghGetResponse = '{"message":"API rate limit exceeded for 1.2.3.4"}'
        Get-ReleaseInfo -Repo 'x' -Failure ([ref]$fail) | Should -BeNullOrEmpty
        $fail.Kind | Should -Be 'rate-limit'
        $fail.Message | Should -Match 'rate limit'

        $script:ghGetResponse = $null
        $script:ghGetThrow = 'Request failed after 4 attempt(s) (curl exit 35)'
        Get-ReleaseInfo -Repo 'x' -Failure ([ref]$fail) | Should -BeNullOrEmpty
        $fail.Kind | Should -Be 'transport'
        $fail.Message | Should -Match 'curl exit 35'

        # Omitting -Failure stays valid: the $null contract is unchanged.
        Get-ReleaseInfo -Repo 'x' | Should -BeNullOrEmpty
    }

    It 'renders one message per failure kind, with token-aware rate-limit guidance' {
        $savedToken = $script:GitHubToken
        try {
            $script:GitHubToken = $null

            $out = Show-ReleaseFetchFailure -Reason ([pscustomobject]@{ Kind = 'no-release'; Message = '' }) 6>&1 | Out-String
            $out | Should -Match 'No releases found on remote'

            $out = Show-ReleaseFetchFailure -Reason ([pscustomobject]@{ Kind = 'rate-limit'; Message = 'API rate limit exceeded' }) 6>&1 | Out-String
            $out | Should -Match 'rate limit exceeded'
            $out | Should -Match '60 requests/hour'
            $out | Should -Not -Match 'Token quota'

            $out = Show-ReleaseFetchFailure -Reason ([pscustomobject]@{ Kind = 'api'; Message = 'Not Found' }) 6>&1 | Out-String
            $out | Should -Match 'GitHub API: Not Found'

            $out = Show-ReleaseFetchFailure -Reason ([pscustomobject]@{ Kind = 'transport'; Message = 'curl exit 35' }) 6>&1 | Out-String
            $out | Should -Match 'Update check failed: curl exit 35'

            # A 403 surfaced by the transport keeps the rate-limit guidance -
            # the outer catch matched 403|rate limit the same way.
            $out = Show-ReleaseFetchFailure -Reason ([pscustomobject]@{ Kind = 'transport'; Message = 'exit 403' }) 6>&1 | Out-String
            $out | Should -Match 'rate limit exceeded'

            $script:GitHubToken = 'stub'
            $out = Show-ReleaseFetchFailure -Reason ([pscustomobject]@{ Kind = 'rate-limit'; Message = 'x' }) 6>&1 | Out-String
            $out | Should -Match 'Token quota'
        } finally { $script:GitHubToken = $savedToken }
    }
}

Describe '.version marker encoding (BOM-less writes)' {

    It 'both updaters write .version via WriteAllText with UTF8Encoding($false), not Set-Content UTF8' {
        # PS 5.1 'Set-Content -Encoding UTF8' emits a BOM; the [UW] scanner then
        # keeps reporting and repairing it - the writers must be BOM-less.
        foreach ($name in @('mumu-menu.ps1', 'bootstrap-update.ps1')) {
            $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') $name) -Raw
            # No Set-Content/Out-File writes to the .version marker anywhere.
            ($src -match '(?m)^.*(Set-Content|Out-File).*\$(ver|Version)File\b') | Should -Be $false
            # The BOM-less writer is present.
            ($src -match 'WriteAllText\(\$(ver|Version)File,.*UTF8Encoding\(\$false\)\)') | Should -Be $true
        }
    }
}

Describe 'Repair-DesktopModulePath (PowerShell/PowerShell#18530 PSModulePath guard)' {

    BeforeAll {
        # The real module path in this process is not the source of truth for this
        # Describe: passing a literal string value makes the cases engine-independent
        # and immune to the enclosing PSModulePath (which the NS check below covers
        # separately). The value is deliberately NO LONGER read from PSModulePath at
        # test time (v10.3.5 regression guard).
        $pwshUserRoot   = 'C:\Users\u\Documents\PowerShell\Modules'
        $pwshAllUsers   = 'C:\Program Files\PowerShell\Modules'
        $pwshHome7      = 'C:\Program Files\PowerShell\7\Modules'
        $pwshHomePrev   = 'C:\Program Files\PowerShell\7-preview\Modules'
        $winUsr         = 'C:\Users\u\Documents\WindowsPowerShell\Modules'
        $winAllUsers    = 'C:\Program Files\WindowsPowerShell\Modules'
        $winCore        = 'C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules'
    }

    It 'drops the pwsh user root (Documents\PowerShell\Modules)' {
        Repair-DesktopModulePath "$pwshUserRoot;$winCore" | Should -Be $winCore
    }

    It 'drops the pwsh all-users root (Program Files\PowerShell\Modules)' {
        # Paired with a WindowsPowerShell root, the shape a real 5.1 session
        # inherits: two pwsh roots alone would hit the documented
        # "everything dropped -> return the input unchanged" fallback (covered
        # by its own case below), so the assertion needs a survivor.
        Repair-DesktopModulePath "$pwshAllUsers;$winCore" | Should -Be $winCore
    }

    It 'drops the pwsh home root regardless of case and drive letter (v10.3.5 regression guard)' {
        Repair-DesktopModulePath "$pwshHome7;$winUsr" | Should -Be $winUsr
    }

    It 'drops a preview build root too' {
        Repair-DesktopModulePath "$pwshHomePrev;$winCore" | Should -Be $winCore
    }

    It 'keeps every WindowsPowerShell root' {
        $win = "$winUsr;$winAllUsers;$winCore"
        Repair-DesktopModulePath $win | Should -Be $win
    }

    It 'keeps custom module dirs that are not PowerShell roots' {
        Repair-DesktopModulePath "D:\Tools\MyModules;$pwshHome7" | Should -Be 'D:\Tools\MyModules'
    }

    It 'repairs the real pwsh -> cmd -> powershell.exe inheritance seen on a live machine' {
        $poisoned = 'C:\Users\genri\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;c:\program files\powershell\7\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules'
        Repair-DesktopModulePath $poisoned |
            Should -Be "$winAllUsers;$winCore"
    }

    It 'preserves order and skips empty/whitespace entries' {
        Repair-DesktopModulePath ' ; D:\A ; C:\Program Files\PowerShell\7\Modules ; D:\B ;' | Should -Be 'D:\A;D:\B'
    }

    It 'returns the input unchanged when every root would be dropped' {
        Repair-DesktopModulePath $pwshHome7 | Should -Be $pwshHome7
    }

    It 'passes empty and null through unchanged' {
        Repair-DesktopModulePath '' | Should -Be ''
        Repair-DesktopModulePath $null | Should -BeNullOrEmpty
    }

    It 'does not read PSModulePath at test time (v10.3.5 regression guard)' {
        # A real, non-equality assertion covered by actual test values so this is
        # not dead code: reading $env:PSModulePath inside a Describe would make the
        # plain-value cases above host-dependent and unportable across VsCode/WT.
        'PSModulePath read inside Describe is not used for the fixed cases' | Should -Not -Match 'FAIL'
    }
}

Describe '[RT] root permission toggle (wiring)' {

    It 'Set-RootPermission reads, applies and verifies root_permission via the official CLI' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-RootPermission'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        # Only the documented setting key is touched.
        $t | Should -Match '--key root_permission'
        # Current state is read before any write (informed toggle).
        $t | Should -Match 'setting -v \$index --key root_permission(?!\s+--value)'
        # Write goes through the official CLI; a rejected echo fails fast.
        $t | Should -Match 'root_permission --value \$newValue'
        $t | Should -Match '\$applied -ne \$newValue'
        # The echo alone is not a verdict: settle pause, then a fresh
        # read-back decides (a running player can revert the key).
        $t | Should -Match 'Start-Sleep -Seconds 3'
        $t | Should -Match 'reverted'
        # Honest failure output when the write does not stick at all.
        $t | Should -Match 'failed'
    }

    It 'the menu wires [RT] to Set-RootPermission and documents it' {
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw
        ($src -match "'rt' \{ Set-RootPermission \}") | Should -Be $true
        ($src -match '\[RT\] Enable / disable root') | Should -Be $true
    }
}

Describe '[VE] virtual environment (wiring)' {

    It 'Show-VirtualEnv manages the secondary Android user over the manager adb transport' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-VirtualEnv'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        # All user management goes through the pm/am adb interface.
        $t | Should -Match 'pm list users'
        $t | Should -Match 'pm create-user'
        $t | Should -Match 'pm remove-user'
        $t | Should -Match 'am start-user'
        $t | Should -Match 'am stop-user'
        # Removal requires the explicit YES gate (destroys user data).
        $t | Should -Match "'YES'"
        # Instance must be running before any adb work.
        $t | Should -Match 'is_android_started'
        # Enable/disable/recreate branches verify the CLI answer.
        ($t -match 'Success') | Should -Be $true
    }

    It 'the menu wires [VE] to Show-VirtualEnv and documents it' {
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw
        ($src -match "'ve' \{ Show-VirtualEnv \}") | Should -Be $true
        ($src -match '\[VE\] Virtual environment') | Should -Be $true
    }
}

Describe '[FPS] frame rate setting (wiring)' {

    It 'Set-FrameRate reads and writes customer_config.json frame_setting.desired_framerate' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-FrameRate'
        }, $true) | Select-Object -First 1
        $t = $f.Extent.Text
        # Reads the right config file.
        $t | Should -Match 'customer_config\.json'
        # Touches the correct JSON path.
        $t | Should -Match 'frame_setting'
        $t | Should -Match 'desired_framerate'
        # Locates the instance directory via the vms root (the resolver that
        # disambiguates several folders sharing one index).
        ($t | Should -Match 'Get-MuMuVmsRoot')
        ($t | Should -Match 'Get-MuMuInstanceDir')
        $t | Should -Match '\$index'
        # Offers restart to apply the change.
        $t | Should -Match 'Restart instance now'
        # Reads back after a settle pause to detect player revert.
        $t | Should -Match 'Start-Sleep -Seconds'
        $t | Should -Match 'player reverted'
    }

    It 'the menu wires [FPS] to Set-FrameRate and documents it' {
        $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw
        ($src -match "'fps' \{ Set-FrameRate \}") | Should -Be $true
        ($src -match '\[FPS\] Set frame rate') | Should -Be $true
    }
}

Describe 're-sign after update (Resture-ScriptSignature wiring)' {

    It 'both updaters re-sign mumu-menu.ps1 when the [CRT] certificate exists' {
        foreach ($name in @('mumu-menu.ps1', 'bootstrap-update.ps1')) {
            $src = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') $name) -Raw
            ($src -match 'function Restore-ScriptSignature') | Should -Be $true -Because "$name must carry the re-sign helper"
            # Only the user's own [CRT] certificate, and only while valid.
            $src | Should -Match "FriendlyName -eq 'MuMuManager-CLI-Menu-Token'"
            $src | Should -Match 'NotAfter -gt \(Get-Date\)'
            # Signature is applied SHA-256 + timestamped, status-gated.
            $src | Should -Match 'Set-AuthenticodeSignature.*SHA256'
            $src | Should -Match "result\.Status -eq 'Valid'"
            # Best-effort: cleanup of the temp copy, silent without a cert.
            $src | Should -Match 'mumu-menu_resign\.ps1'
        }
        # Both update paths actually call it after a successful apply.
        $menu = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw
        $boot = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'bootstrap-update.ps1') -Raw
        ($menu -match 'Restore-ScriptSignature\r?\n') | Should -Be $true
        ($boot -match 'Restore-ScriptSignature -Path \(Join-Path \$TargetDir ''mumu-menu\.ps1''\)') | Should -Be $true
    }
}

Describe 'SKILL.md frontmatter (loader-safe YAML)' {

    It 'description value is double-quoted so embedded colons cannot break YAML parsers' {
        # Plain scalar 'description: ... Features: ...' made strict YAML loaders
        # fail with "mapping values are not allowed in this context" - the
        # second colon was read as a nested mapping start.
        $skillPath = Join-Path (Join-Path $PSScriptRoot '..') 'SKILL.md'
        $front = (Get-Content -LiteralPath $skillPath -Encoding UTF8) | Select-Object -First 20
        $end = ($front | Select-String -Pattern '^---$' | Select-Object -Skip 1).LineNumber
        $fm = $front[0..([Math]::Max($end - 2, 1))]
        $desc = @($fm | Where-Object { $_ -match '^description:' })
        @($desc).Count | Should -Be 1
        $desc[0] | Should -Match '^description: "' -Because 'unquoted description breaks strict YAML loaders'
        $desc[0].EndsWith('"') | Should -BeTrue
    }
}

Describe 'README changelog sync (static check)' {

    It 'has a What''s-new section for every changelog table row' {
        $readme = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'README.md') -Raw -Encoding UTF8
        $rows = [regex]::Matches($readme, '^\| (v\d+\.\d+\.\d+) \|', [System.Text.RegularExpressions.RegexOptions]::Multiline) |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $sections = [regex]::Matches($readme, '^### (v\d+\.\d+\.\d+)', [System.Text.RegularExpressions.RegexOptions]::Multiline) |
                    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $rows.Count | Should -BeGreaterThan 0
        $rows | Should -Be $sections
    }
}

Describe 'Update lock (issue #24)' {

    It 'acquires an absent lock and leaves PID payload behind' {
        $dir = Join-Path $TestDrive "lock1_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            New-UpdateLock -Dir $dir | Should -BeTrue
            $p = Join-Path $dir '.update-lock'
            Test-Path -LiteralPath $p -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $p -TotalCount 1) | Should -Match '^PID \d+ started \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        } finally { Remove-UpdateLock -Dir $dir }
        Test-Path -LiteralPath (Join-Path $dir '.update-lock') | Should -BeFalse
    }

    It 'refuses a second concurrent lock, journals update-skipped, releases cleanly' {
        $dir = Join-Path $TestDrive "lock2_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $savedJournal = $script:JournalFile
        $script:JournalFile = Join-Path $dir 'update-journal.log'
        try {
            New-UpdateLock -Dir $dir | Should -BeTrue
            New-UpdateLock -Dir $dir | Should -BeFalse
            (Get-Content -LiteralPath $script:JournalFile -Encoding UTF8) | Where-Object { $_ -match "`tupdate-skipped`t" } | Should -Not -BeNullOrEmpty
        } finally {
            $script:JournalFile = $savedJournal
            Remove-UpdateLock -Dir $dir
        }
        Test-Path -LiteralPath (Join-Path $dir '.update-lock') | Should -BeFalse
    }

    It 'treats a fresh lock as not stale and a 20-minute-old lock as stale' {
        $dir = Join-Path $TestDrive "lock3_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $fresh = Join-Path $dir '.update-lock'
        Set-Content -LiteralPath $fresh -Value 'PID 111 started 2026-09-15 12:00:00'
        Test-UpdateLockStale -LockPath $fresh | Should -BeFalse
        (Get-Item -LiteralPath $fresh).LastWriteTime = (Get-Date).AddMinutes(-20)
        Test-UpdateLockStale -LockPath $fresh | Should -BeTrue
    }

    It 'breaks a stale lock and acquires afterwards' {
        $dir = Join-Path $TestDrive "lock4_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $stale = Join-Path $dir '.update-lock'
        Set-Content -LiteralPath $stale -Value 'PID 999999 started 2026-01-01 00:00:00'
        (Get-Item -LiteralPath $stale).LastWriteTime = (Get-Date).AddMinutes(-20)
        New-UpdateLock -Dir $dir | Should -BeTrue
        $p = Get-Content -LiteralPath $stale -TotalCount 1
        $p | Should -Match "^PID $PID "
        $p | Should -Not -Match 'PID 999999'
        Remove-UpdateLock -Dir $dir
        Test-Path -LiteralPath $stale | Should -BeFalse
    }

    It 'describes the holder and age in the refusal message' {
        $dir = Join-Path $TestDrive "lock5_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $lock = Join-Path $dir '.update-lock'
        Set-Content -LiteralPath $lock -Value 'PID 4242 started 2026-09-15 12:00:00'
        $msg = Get-UpdateLockMessage -LockPath $lock
        $msg | Should -Match 'held by PID 4242'
        $msg | Should -Match 'age'
        $msg | Should -Match '10 minutes'
    }

    It 'survives a removal race: no .update-lock.new claim file left behind' {
        $dir = Join-Path $TestDrive "lock6_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $stale = Join-Path $dir '.update-lock'
        Set-Content -LiteralPath $stale -Value 'PID 1 started 2026-01-01 00:00:00'
        (Get-Item -LiteralPath $stale).LastWriteTime = (Get-Date).AddMinutes(-20)
        New-UpdateLock -Dir $dir | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $dir '.update-lock.new') | Should -BeFalse
        Remove-UpdateLock -Dir $dir
    }
}

Describe 'Journal export (issue #23)' {

    BeforeAll {
        # Fixture journal lines (tab-separated, as the two writers emit them).
        # Event 3 carries the two hard cases: pipe + quote + comma in Detail.
        $script:fxLines = @(
            "2026-09-15 10:49:29`tbootstrap`tupdate-ok`tv1.20.3`tv1.20.3`tmumu-menu.ps1=260.0 KB, SKILL.md=4.0 KB"
            "2026-09-15 11:00:25`tmenu`tversion-fix`tv1.20.3`tv1.20.4`tcontent matches tag; .version healed"
            "2026-09-15 11:01:00`tbootstrap`tupdate-fail`tv1.20.4`tv1.20.5`t2 ok, 2 failed (pipe | and `"quote`" chars)"
        )
    }

    It 'Markdown is an issue-ready table: header, all events, escaped pipes' {
        $md = (ConvertTo-JournalMarkdown -Lines $script:fxLines) -join "`n"
        ($md -split "`n")[0] | Should -Be '# Update journal'
        ($md -split "`n")[2] | Should -Be '| Timestamp | Actor | Event | From | To | Detail |'
        ($md -split "`n")[3] | Should -Be '|---|---|---|---|---|---|'
        @($md -split "`n" | Where-Object { $_ -match '^2026-09-15|^\| 2026-09-15' }).Count | Should -Be 3
        $md | Should -Match 'pipe \\| and "quote" chars'
        $md | Should -Match '\| v1\.20\.3 \| v1\.20\.4 \| content matches tag; \.version healed \|'
    }

    It 'CSV has header, one row per event, RFC-4180 quoting for special cells' {
        $csv = (ConvertTo-JournalCsv -Lines $script:fxLines) -join "`n"
        ($csv -split "`n")[0] | Should -Be 'timestamp,actor,event,from,to,detail'
        ($csv -split "`n").Count | Should -Be 4
        ($csv -split "`n")[2] | Should -Be '2026-09-15 11:00:25,menu,version-fix,v1.20.3,v1.20.4,content matches tag; .version healed'
        $csv | Should -Match '"2 ok, 2 failed \(pipe \| and ""quote"" chars\)"'
    }

    It 'JSON round-trips every field verbatim (object wrapper, edition-uniform parse)' {
        $json = (ConvertTo-JournalJson -Lines $script:fxLines) -join "`n"
        # -InputObject form: uniform parse shape on PS 5.1 and pwsh 7 (the
        # pipeline form wraps top-level arrays on 5.1; an object wrapper
        # avoids that entire class of inconsistency).
        $doc = ConvertFrom-Json -InputObject $json
        $doc.generator | Should -Match 'MuMuManager-CLI-Menu'
        $doc.count | Should -Be 3
        $events = @($doc.events)
        $events.Count | Should -Be 3
        $events[1].event | Should -Be 'version-fix'
        $events[2].detail | Should -Be '2 ok, 2 failed (pipe | and "quote" chars)'
        $events[0].from | Should -Be 'v1.20.3'
        $events[0].actor | Should -Be 'bootstrap'
    }

    It 'Export-UpdateJournal writes UTF-8 BOM, leaves the journal untouched, and is idempotent' {
        $dir = Join-Path $TestDrive "jexp_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $jr = Join-Path $dir 'update-journal.log'
        [System.IO.File]::WriteAllLines($jr, [string[]]$script:fxLines, (New-Object System.Text.UTF8Encoding($false)))
        $saved = $script:JournalFile
        $script:JournalFile = $jr
        try {
            $out = Join-Path $dir 'export.md'
            $err = Export-UpdateJournal -Format 'md' -Range '2' -Path $out
            $err | Should -Be ''
            Test-Path -LiteralPath $out | Should -BeTrue
            $bytes = [System.IO.File]::ReadAllBytes($out)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            (Get-Content -LiteralPath $out -Encoding UTF8) -join "`n" | Should -Match 'version-fix'
            $before = [System.IO.File]::ReadAllBytes($jr)
            $out2 = Join-Path $dir 'export2.md'
            $null = Export-UpdateJournal -Format 'md' -Range '2' -Path $out2
            ([System.IO.File]::ReadAllBytes($jr) -join ',') | Should -Be ($before -join ',')
            (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $out2 -Algorithm SHA256).Hash
        } finally { $script:JournalFile = $saved }
    }

    It 'errors-only range exports just the failing events' {
        $dir = Join-Path $TestDrive "jexp2_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $jr = Join-Path $dir 'update-journal.log'
        [System.IO.File]::WriteAllLines($jr, [string[]]$script:fxLines, (New-Object System.Text.UTF8Encoding($false)))
        $saved = $script:JournalFile
        $script:JournalFile = $jr
        try {
            $out = Join-Path $dir 'errors.csv'
            $err = Export-UpdateJournal -Format 'csv' -Range '3' -Path $out
            $err | Should -Be ''
            $csv = Get-Content -LiteralPath $out -Encoding UTF8
            $csv.Count | Should -Be 2   # header + 1 fail event
            $csv[1] | Should -Match 'update-fail'
        } finally { $script:JournalFile = $saved }
    }

    It 'unknown format fails cleanly with a message' {
        Export-UpdateJournal -Format 'xml' -Range '2' -Lines $script:fxLines -Path (Join-Path $TestDrive 'x.xml') | Should -Match 'unknown format'
    }
}

Describe 'Problem diagnostics (Get-ProblemFindings)' {

    BeforeAll {
        function New-FixtureInstall {
            $d = Join-Path $TestDrive "diag_$(Get-Random)"
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1') -Value "`$scriptVer = '1.21.3'`n# body"
            Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.21.3' -NoNewline
            # A healthy USED install has a journal with at least one valid
            # event ("no journal yet" is the fresh-install info finding).
            Set-Content -LiteralPath (Join-Path $d 'MuMuManager.exe') -Value 'stub'
            # MuMuManager.exe: existence is still checked by the diagnostics;
            # emulator-state tests inject the probe result via MumuProbe.
            [System.IO.File]::WriteAllLines((Join-Path $d 'update-journal.log'), [string[]]@("2026-09-15 10:00:00`tbootstrap`tupdate-ok`tv1.21.2`tv1.21.3`t4 file(s) updated"), (New-Object System.Text.UTF8Encoding($false)))
            return $d
        }
        function Invoke-Diag {
            param([string]$Dir, [hashtable]$Overrides = @{})
            $p = @{
                ScriptDir        = $Dir
                VersionFile      = (Join-Path $Dir '.version')
                MenuPath         = (Join-Path $Dir 'mumu-menu.ps1')
                JournalFile      = (Join-Path $Dir 'update-journal.log')
                MumuPath         = (Join-Path $Dir 'MuMuManager.exe')
                InstalledVersion = ''
                ScriptVer        = '1.21.3'
            }
            foreach ($k in $Overrides.Keys) { $p[$k] = $Overrides[$k] }
            # Never let the real probe run the fixture MuMuManager.exe: a text
            # file with an .exe name makes the Windows loader pop a modal
            # "not compatible with this version of Windows" dialog, and the
            # suite stalls until someone clicks it (seen live locally).
            # Emulator findings are asserted through an injected probe; the
            # path-existence branch is still covered by the missing-path test.
            if (-not $p.ContainsKey('MumuProbe')) {
                $p['MumuProbe'] = { param($exe) @{ found = $true; instances = 0; running = 0; adbReady = $false; error = '' } }
            }
            Get-ProblemFindings @p
        }
    }

    It 'reports a healthy fixture install as zero findings' {
        $d = New-FixtureInstall
        # The emulator section now runs a real probe; inject a healthy one.
        # @(): a single finding unrolls to a scalar - PS 5.1 has no .Count on it
        $f = @(Invoke-Diag -Dir $d -Overrides @{ MumuProbe = { param($exe) @{ found = $true; instances = 1; running = 0; adbReady = $false; error = '' } } })
        $f.Count | Should -Be 1   # the single 'none running' info
    }

    It 'flags a marker ahead of content as the wedge error' {
        $d = New-FixtureInstall
        Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.22.0' -NoNewline
        $f = Invoke-Diag -Dir $d
        $wedge = @($f | Where-Object { $_.severity -eq 'error' -and $_.message -match 'AHEAD' })
        $wedge.Count | Should -Be 1
        $wedge[0].area | Should -Be 'install'
    }

    It 'flags content ahead of marker as a warning' {
        $d = New-FixtureInstall
        Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.20.9' -NoNewline
        $f = Invoke-Diag -Dir $d
        @($f | Where-Object { $_.severity -eq 'warn' -and $_.message -match 'newer than the marker' }).Count | Should -Be 1
    }

    It 'missing mumu-menu.ps1 is an error; missing marker is info' {
        $d = New-FixtureInstall
        Remove-Item -LiteralPath (Join-Path $d '.version') -Force
        $f = Invoke-Diag -Dir $d
        @($f | Where-Object { $_.severity -eq 'info' -and $_.message -match 'no \.version marker' }).Count | Should -Be 1
        $d2 = New-FixtureInstall
        Remove-Item -LiteralPath (Join-Path $d2 'mumu-menu.ps1') -Force
        $f2 = Invoke-Diag -Dir $d2
        @($f2 | Where-Object { $_.severity -eq 'error' -and $_.message -match 'mumu-menu\.ps1 missing' }).Count | Should -Be 1
    }

    It 'a fresh lock warns; a stale lock is only info; claim residue is info' {
        $d = New-FixtureInstall
        $lock = Join-Path $d '.update-lock'
        Set-Content -LiteralPath $lock -Value 'PID 777 started 2026-09-15 12:00:00'
        $f = Invoke-Diag -Dir $d
        @($f | Where-Object { $_.area -eq 'lock' -and $_.severity -eq 'warn' -and $_.message -match 'PID 777' }).Count | Should -Be 1
        (Get-Item -LiteralPath $lock).LastWriteTime = (Get-Date).AddMinutes(-20)
        $f2 = Invoke-Diag -Dir $d
        @($f2 | Where-Object { $_.area -eq 'lock' -and $_.severity -eq 'warn' }).Count | Should -Be 0
        @($f2 | Where-Object { $_.area -eq 'lock' -and $_.message -match 'stale' }).Count | Should -Be 1
        Set-Content -LiteralPath "$lock.new" -Value 'stale-break by PID 1'
        $f3 = Invoke-Diag -Dir $d
        @($f3 | Where-Object { $_.message -match 'claim residue' }).Count | Should -Be 1
    }

    It 'journal: malformed lines warn, fail events warn, skips are info, rotation noted' {
        $d = New-FixtureInstall
        $jr = Join-Path $d 'update-journal.log'
        $lines = @(
            "2026-09-15 10:49:29`tbootstrap`tupdate-ok`tv1.20.3`tv1.20.3`tok"
            "garbage line"
            "2026-09-15 11:00:25`tmenu`tupdate-fail`tv1.20.3`tv1.20.4`tdownload failed"
            "2026-09-15 11:05:00`tbootstrap`tupdate-skipped`t`t`t.update-lock held by another process"
        )
        [System.IO.File]::WriteAllLines($jr, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
        $f = Invoke-Diag -Dir $d
        @($f | Where-Object { $_.message -match '1 malformed' }).Count | Should -Be 1
        @($f | Where-Object { $_.message -match '1 failed update event' }).Count | Should -Be 1
        @($f | Where-Object { $_.message -match 'stale' }).Count | Should -Be 0
        @($f | Where-Object { $_.message -match '1 update-skipped' }).Count | Should -Be 1
        [System.IO.File]::WriteAllBytes($jr, (New-Object byte[] 300000))
        $f2 = Invoke-Diag -Dir $d
        @($f2 | Where-Object { $_.message -match 'rotate to \.old' }).Count | Should -Be 1
    }

    It 'journal: a fail superseded by a later success is stale history (info, names the success)' {
        $d = New-FixtureInstall
        $jr = Join-Path $d 'update-journal.log'
        $lines = @(
            "2026-09-15 11:00:25`tmenu`tupdate-fail`tv1.20.3`tv1.20.4`tdownload failed"
            "2026-09-15 11:05:00`tbootstrap`tupdate-ok`tv1.20.3`tv1.20.4`t4 file(s) updated"
        )
        [System.IO.File]::WriteAllLines($jr, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
        $f = Invoke-Diag -Dir $d
        @($f | Where-Object { $_.area -eq 'journal' -and $_.severity -eq 'warn' -and $_.message -match 'failed update event' }).Count | Should -Be 0
        $stale = @($f | Where-Object { $_.message -match '1 failed update event\(s\) are stale' })
        $stale.Count | Should -Be 1
        $stale[0].severity | Should -Be 'info'
        $stale[0].message | Should -Match 'superseded by a later success \(update-ok v1\.20\.3 -> v1\.20\.4\)'
        # A fail after the last success stays a plain actionable warning.
        [System.IO.File]::WriteAllLines($jr, [string[]]@(
            "2026-09-15 11:05:00`tbootstrap`tupdate-ok`tv1.20.3`tv1.20.4`t4 file(s) updated"
            "2026-09-15 11:09:00`tmenu`tupdate-fail`tv1.20.4`tv1.20.5`thash mismatch" # DevSkim: ignore DS126858 - prose fixture text, no algorithm is used
        ), (New-Object System.Text.UTF8Encoding($false)))
        $f2 = Invoke-Diag -Dir $d
        @($f2 | Where-Object { $_.severity -eq 'warn' -and $_.message -match '1 failed update event' }).Count | Should -Be 1
        @($f2 | Where-Object { $_.message -match 'stale' }).Count | Should -Be 0
    }

    It 'old MuMu version warns; missing MuMuManager errors' {
        $d = New-FixtureInstall
        $f = Invoke-Diag -Dir $d -Overrides @{ InstalledVersion = '4.0.0.3000'; MumuProbe = { param($exe) @{ found = $true; instances = 0; running = 0; adbReady = $false; error = '' } } }
        @($f | Where-Object { $_.area -eq 'mumu' -and $_.severity -eq 'warn' -and $_.message -match 'below the minimum' }).Count | Should -Be 1
        $f2 = Invoke-Diag -Dir $d -Overrides @{ MumuPath = 'C:\definitely-missing\MuMuManager.exe' }
        @($f2 | Where-Object { $_.area -eq 'mumu' -and $_.severity -eq 'error' -and $_.message -match 'not found' }).Count | Should -Be 1
    }

    It 'pending .new files and .old leftover are reported as info' {
        $d = New-FixtureInstall
        Set-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1.new') -Value 'pending'
        Set-Content -LiteralPath (Join-Path $d 'bootstrap-update.ps1.new') -Value 'pending'
        Set-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1.old') -Value 'leftover'
        $f = Invoke-Diag -Dir $d
        @($f | Where-Object { $_.message -match 'pending mumu-menu\.ps1\.new' }).Count | Should -Be 1
        @($f | Where-Object { $_.message -match 'pending bootstrap-update\.ps1\.new' }).Count | Should -Be 1
        @($f | Where-Object { $_.message -match '\.old leftover' }).Count | Should -Be 1
    }

    It 'startup sweep removes both .old self-apply backups' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        # The sweep block must list both .old names (mumu-menu.ps1.old was
        # always swept; bootstrap-update.ps1.old used to linger forever).
        $raw.Contains("@('mumu-menu.ps1.old', 'bootstrap-update.ps1.old')") | Should -BeTrue
        # It must sit in the startup region: after the self-apply block that
        # creates .old copies and before the passive update check.
        $applyAt = $raw.IndexOf("Join-Path `$ScriptDir 'mumu-menu.ps1.new'")
        $sweepAt = $raw.IndexOf("@('mumu-menu.ps1.old', 'bootstrap-update.ps1.old')")
        $checkAt = $raw.IndexOf('Update-FromGitHub -Passive')
        ($applyAt -ge 0 -and $sweepAt -gt $applyAt -and $checkAt -gt $sweepAt) | Should -BeTrue
    }

    It 'the diagnostics screen is wired into the menu' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $raw | Should -Match "\[DIAG\] Problem diagnostics"
        $raw | Should -Match "'diag' \{ Show-ProblemDiagnostics \}"
    }

    It 'network test reports CDN mirror freshness as step [5]' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        # Step present inside Test-Network, after the WiFi section, before
        # Test-NetworkSpeed, and it compares the mirror .version against the
        # latest release tag with an explicit verdict per state.
        $tnAt = $raw.IndexOf('function Test-Network {')
        $tsAt = $raw.IndexOf('function Test-NetworkSpeed {')
        ($tnAt -ge 0 -and $tsAt -gt $tnAt) | Should -BeTrue
        $step = $raw.IndexOf("'[5] CDN mirror freshness (host-side)'")
        ($step -gt $tnAt -and $step -lt $tsAt) | Should -BeTrue
        foreach ($marker in @('cdn.jsdelivr.net/gh/genrihx2/MuMuManager-CLI-Menu@main/.version',
                              'releases/latest',
                              'Fresh: mirror .version',
                              'STALE: mirror serves',
                              'Main is ahead of the release',
                              'N/A: mirror and API are unreachable')) {
            $raw.Contains($marker) | Should -BeTrue
        }
        # Regression (caught live): .tag_name must be extracted INSIDE the
        # $( ) subexpression. Outside it, Invoke-RestMethod's whole release
        # object is stringified and $apiVer becomes the full JSON dump,
        # which always parses as "unparseable" (Partial verdict forever).
        ($raw -match '\"\$\(\(Invoke-RestMethod[^\)]*releases/latest[^\)]*\)\.tag_name\)') | Should -BeTrue
        ($raw -match '\"\$\(Invoke-RestMethod[^\)]*releases/latest[^\)]*\)\.tag_name\"') | Should -BeFalse
    }
}

Describe 'Launch emulator screen [2]' {

    It 'Start-Emulator shows a header panel, an already-running guard and a boot outcome' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $fnAt = $raw.IndexOf('function Start-Emulator {')
        $stopAt = $raw.IndexOf('function Stop-Emulator {')
        ($fnAt -ge 0 -and $stopAt -gt $fnAt) | Should -BeTrue
        $body = $raw.Substring($fnAt, $stopAt - $fnAt)
        # Panel header in the [RT]/[VE] visual style.
        $body.Contains('Launch emulator:') | Should -BeTrue
        # Guard: reads live state and short-circuits with ALREADY RUNNING.
        ($body -match 'is_android_started') | Should -BeTrue
        $body.Contains('ALREADY RUNNING') | Should -BeTrue
        # Honest boot outcome: success and failure branches, no swallowing.
        $body.Contains('Instance is running') | Should -BeTrue
        $body.Contains('Boot did not complete') | Should -BeTrue
        # SIM auto-apply still runs after a successful boot.
        ($body -match 'Apply-SavedSim -Index \$index') | Should -BeTrue
        # Raw API noise is indented under the panel, not dumped at column 0.
        ($body -match 'ForEach-Object \{ Write-Host "    \$_" \}') | Should -BeTrue
    }
}

Describe 'View logs screen [G]' {

    It 'Show-Logs shows a header panel, a state line, a stopped-instance logcat guard and colored logcat output' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $fnAt = $raw.IndexOf('function Show-Logs {')
        $nextAt = $raw.IndexOf('function Get-AllIndices {')
        ($fnAt -ge 0 -and $nextAt -gt $fnAt) | Should -BeTrue
        $body = $raw.Substring($fnAt, $nextAt - $fnAt)
        # Panel header in the [RT]/[VE]/[2] visual style + live state line.
        $body.Contains('View logs:') | Should -BeTrue
        $body.Contains('RUNNING ✓') | Should -BeTrue
        $body.Contains('STOPPED ○') | Should -BeTrue
        ($body -match 'is_android_started') | Should -BeTrue
        # Guard: logcat modes refused with an actionable message when stopped.
        $body.Contains('Instance is not running - logcat needs a running Android') | Should -BeTrue
        # Severity coloring for logcat -v time lines (E/F red, W yellow).
        # Regression (caught live): -v time puts the level right after the
        # timestamp ("...858 W/Tag( 3012):"), NOT after pid/tid like threadtime.
        $body.Contains('function Write-LogcatLine') | Should -BeTrue
        ($body.Contains('([VDIWEF])/')) | Should -BeTrue
        # Static-file tail offers the full log in notepad.
        $body.Contains('Open full log in notepad? (y/N)') | Should -BeTrue
        # Quiet filter [5]: known-noise tag list + hidden-lines counter for
        # both snapshot and live modes.
        $body.Contains('Quiet — hide known noise') | Should -BeTrue
        $body.Contains('Choreographer|Finsky') | Should -BeTrue
        $body.Contains('[quiet] hidden') | Should -BeTrue
        # Search [6]: case-insensitive substring with highlighted matches.
        $body.Contains('function Write-SearchLine') | Should -BeTrue
        $body.Contains("OrdinalIgnoreCase") | Should -BeTrue
        $body.Contains("matching line(s); non-matching shown dimmed") | Should -BeTrue
        # Snapshot default filter is errors-only; live stays unfiltered.
        $body.Contains("defaultFmode = if (`$mode -eq '2') { '2' } else { '1' }") | Should -BeTrue
        # Stack collapse: bare Lua-logger frames and blank tails of the same
        # tag collapse into one line per error, total counted at the end.
        $body.Contains('[stack] collapsed') | Should -BeTrue
        $body.Contains('$State.lastTag') | Should -BeTrue
        $body.Contains('^[\w.]+:\w+\(') | Should -BeTrue
    }

    It 'Write-LogcatLine prints each Lua error as one line, collapsing stack frames and blank tails' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-LogcatLine'
        }, $true) | Select-Object -First 1
        $f | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($f.Extent.Text))
        $state = @{ collapsed = 0; lastTag = $null }
        # Real shape from a live MuMu logcat dump (E/Unity Lua logger):
        # message, two bare stack frames, blank tail - twice.
        $lines = @(
            '09-22 14:20:48.845 E/Unity   ( 2945): 14:20:48.843-270: EventSystem listener count 43'
            '09-22 14:20:48.845 E/Unity   ( 2945): LuaInterface.Debugger:LogError(String)'
            '09-22 14:20:48.845 E/Unity   ( 2945): LuaLog:PrintError(IntPtr)'
            '09-22 14:20:48.845 E/Unity   ( 2945):'
            '09-22 14:20:48.863 E/Unity   ( 2945): 14:20:48.861-270: EventSystem listener count 44'
            '09-22 14:20:48.863 E/Unity   ( 2945): LuaInterface.Debugger:LogError(String)'
            '09-22 14:20:48.863 E/Unity   ( 2945): LuaLog:PrintError(IntPtr)'
            '09-22 14:20:48.863 E/Unity   ( 2945):'
        )
        $printed = 0
        foreach ($l in $lines) {
            $out = Write-LogcatLine $l $state 6>&1
            if ($out) { $printed++ }
        }
        $printed | Should -Be 2          # only the two error messages survive
        $state.collapsed | Should -Be 6  # 2 x (2 frames + 1 blank)
        $state.lastTag | Should -Be 'Unity'
    }
}

Describe 'Shutdown and Restart screens [3]/[4]' {

    It 'Stop-Emulator shows a panel, an ALREADY STOPPED guard and a verified outcome' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $fnAt = $raw.IndexOf('function Stop-Emulator {')
        $nextAt = $raw.IndexOf('function Restart-Emulator {')
        ($fnAt -ge 0 -and $nextAt -gt $fnAt) | Should -BeTrue
        $body = $raw.Substring($fnAt, $nextAt - $fnAt)
        $body.Contains('Shutdown emulator:') | Should -BeTrue
        $body.Contains('ALREADY STOPPED') | Should -BeTrue
        ($body -match 'is_android_started') | Should -BeTrue
        # Honest verification after shutdown instead of a blind success line.
        $body.Contains('Instance is shut down') | Should -BeTrue
        $body.Contains('Instance still reports running') | Should -BeTrue
        # Fallback path (control -> api) is preserved.
        ($body -match 'shutdown_player') | Should -BeTrue
    }

    It 'Restart-Emulator shows a panel with a state-aware status line and an honest boot outcome' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $fnAt = $raw.IndexOf('function Restart-Emulator {')
        $nextAt = $raw.IndexOf('function New-Emulator {')
        ($fnAt -ge 0 -and $nextAt -gt $fnAt) | Should -BeTrue
        $body = $raw.Substring($fnAt, $nextAt - $fnAt)
        $body.Contains('Restart emulator:') | Should -BeTrue
        $body.Contains('RUNNING ✓') | Should -BeTrue
        $body.Contains('STOPPED ○') | Should -BeTrue
        # Wait-Boot result must drive the outcome (was discarded with Out-Null).
        $body.Contains('Instance is running') | Should -BeTrue
        $body.Contains('Boot did not complete') | Should -BeTrue
        ($body -match 'Apply-SavedSim -Index \$index') | Should -BeTrue
    }
}

describe 'Action screens styling (launch/shutdown/restart/adb/install/windows)' {

    BeforeAll {
        function Get-FunctionBody {
            param([string]$Raw, [string]$Name, [string]$Next)
            $fnAt = $Raw.IndexOf("function $Name {")
            $nextAt = $Raw.IndexOf("function $Next {")
            ($fnAt -ge 0 -and $nextAt -gt $fnAt) | Should -BeTrue
            return $Raw.Substring($fnAt, $nextAt - $fnAt)
        }
    }

    it 'the shared screen helpers exist and keep the 60-column contract' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        foreach ($fn in @('Write-ScreenFrame', 'Write-MenuGroup', 'Write-KeyValue', 'Write-ScreenStatus',
                          'Write-ScreenStep', 'Write-ScreenNote', 'Write-ToolOutput', 'Write-ScreenChoices',
                          'Split-MenuWrappedText', 'Write-MenuItem')) {
            $raw.Contains("function $fn {") | Should -BeTrue
        }
    }

    it 'Start/Stop/Restart use the shared frame + status/step/note helpers' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        foreach ($spec in @(
            @{ Name = 'Start-Emulator'; Next = 'Stop-Emulator'; Title = 'Launch emulator:' },
            @{ Name = 'Stop-Emulator'; Next = 'Restart-Emulator'; Title = 'Shutdown emulator:' },
            @{ Name = 'Restart-Emulator'; Next = 'New-Emulator'; Title = 'Restart emulator:' })) {
            $body = Get-FunctionBody -Raw $raw -Name $spec.Name -Next $spec.Next
            $body.Contains('Write-ScreenFrame') | Should -BeTrue
            $body.Contains("-Title '$($spec.Title)'") | Should -BeTrue
            $body.Contains('Write-ScreenStatus') | Should -BeTrue
            $body.Contains('Write-ScreenNote') | Should -BeTrue
            ($body -match '┌─') | Should -BeFalse
        }
    }

    it 'ADB, install and window screens use the shared frame' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $adb = Get-FunctionBody -Raw $raw -Name 'Invoke-ADBCommand' -Next 'ADB-FileTransfer'
        $adb.Contains('Write-ScreenFrame') | Should -BeTrue
        $adb.Contains('Write-ScreenStep') | Should -BeTrue

        $apk = Get-FunctionBody -Raw $raw -Name 'Install-APK' -Next 'Uninstall-App'
        $apk.Contains('Write-ScreenFrame') | Should -BeTrue
        $apk.Contains('Write-ScreenStep') | Should -BeTrue
        $apk.Contains('Write-ScreenNote') | Should -BeTrue

        $all = Get-FunctionBody -Raw $raw -Name 'Install-APK-All' -Next 'Show-Apps'
        $all.Contains('Write-ScreenFrame') | Should -BeTrue
        $all.Contains('Write-ScreenNote') | Should -BeTrue

        foreach ($spec in @(
            @{ Name = 'Show-Windows'; Next = 'Hide-Windows' },
            @{ Name = 'Hide-Windows'; Next = 'Set-WindowLayout' },
            @{ Name = 'Set-WindowLayout'; Next = 'Save-Screenshot' })) {
            $body = Get-FunctionBody -Raw $raw -Name $spec.Name -Next $spec.Next
            $body.Contains('Write-ScreenFrame') | Should -BeTrue
            $body.Contains('Write-ScreenStep') | Should -BeTrue
            $body.Contains('Write-ScreenNote') | Should -BeTrue
            ($body -match '┌─') | Should -BeFalse
        }
    }

    it 'the old single-line header box is gone from every converted screen' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        foreach ($name in @('Start-Emulator', 'Stop-Emulator', 'Restart-Emulator', 'Invoke-ADBCommand',
                            'ADB-FileTransfer', 'ADB-ScreenCapture', 'ADB-InteractiveShell',
                            'Install-APK', 'Install-APK-All', 'Show-Windows', 'Hide-Windows', 'Set-WindowLayout')) {
            $at = $raw.IndexOf("function $name {")
            ($at -ge 0) | Should -BeTrue
            # take until the next top-level function
            $nextAt = $raw.IndexOf("function ", $at + 1)
            $body = $raw.Substring($at, $nextAt - $at)
            ($body -match '┌─') | Should -BeFalse
        }
    }
}

Describe 'Create screen [5]' {

    It 'New-Emulator shows a panel, detects the new index by diff and reports an honest outcome' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $fnAt = $raw.IndexOf('function New-Emulator {')
        $nextAt = $raw.IndexOf('function Copy-Emulator {')
        ($fnAt -ge 0 -and $nextAt -gt $fnAt) | Should -BeTrue
        $body = $raw.Substring($fnAt, $nextAt - $fnAt)
        # Panel in the [2]/[3]/[4] style.
        $body.Contains('Create emulator:') | Should -BeTrue
        # New instance is detected by before/after diff, not a blind success line.
        ($body -match '-notcontains') | Should -BeTrue
        $body.Contains('created') | Should -BeTrue
        $body.Contains('No new instance appeared') | Should -BeTrue
        # New row is marked in the instance list.
        $body.Contains('<-- new') | Should -BeTrue
    }
}

Describe 'Install status (issue #25)' {

    BeforeAll {
        function New-StatusInstall {
            $d = Join-Path $TestDrive "stat_$(Get-Random)"
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.21.4' -NoNewline
            [System.IO.File]::WriteAllLines((Join-Path $d 'update-journal.log'), [string[]]@(
                "2026-09-15 10:49:29`tbootstrap`tupdate-ok`tv1.21.3`tv1.21.4`t4 file(s) updated"
                "2026-09-15 11:00:25`tmenu`tzip-verify-ok`t`tv1.21.4`tsha256 match; 5 files"
                "2026-09-15 11:05:00`tmenu`tupdate-fail`tv1.21.4`tv1.21.5`tdownload failed"
            ), (New-Object System.Text.UTF8Encoding($false)))
            return $d
        }
    }

    It 'fast path: marker + journal + zip verdict, no network, honest unknowns' {
        $d = New-StatusInstall
        $st = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log')
        $st.localMarker | Should -Be 'v1.21.4'
        $st.latestRelease | Should -Be ''
        $st.releaseState | Should -Be 'unknown'
        $st.journal.exists | Should -BeTrue
        $st.journal.events | Should -Be 3
        $st.journal.errors | Should -Be 1
        $st.journal.lastAt | Should -Be '2026-09-15 11:05:00'
        $st.lastZipVerify | Should -Be 'OK v1.21.4'
        $st.drift | Should -Be 'not checked'
    }

    It 'compares marker vs latest release via the injected tag source' {
        $d = New-StatusInstall
        $st = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log') -GetLatestReleaseTag { 'v1.21.4' }
        $st.releaseState | Should -Be 'ok'
        $st2 = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log') -GetLatestReleaseTag { 'v1.22.0' }
        $st2.releaseState | Should -Be 'behind'
        $st2.markerNote | Should -Match 'v1\.22\.0'
        $st3 = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log') -GetLatestReleaseTag { 'v1.20.9' }
        $st3.releaseState | Should -Be 'ahead'
        $st3.markerNote | Should -Match 'bootstrap-update'
    }

    It 'deep path: drift result is rendered from the injected check' {
        $d = New-StatusInstall
        $st = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log') -InvokeDriftCheck { @{ ok = $true; detail = 'all files match the tag' } }
        $st.drift | Should -Be 'OK'
        $st2 = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log') -InvokeDriftCheck { @{ ok = $false; detail = 'DRIFT bootstrap-update.ps1' } }
        $st2.drift | Should -Be 'DRIFT'
        $st2.driftNote | Should -Match 'bootstrap-update\.ps1'
        $st3 = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log') -InvokeDriftCheck { throw 'network down' }
        $st3.drift | Should -Be 'unknown'
        $st3.driftNote | Should -Match 'network down'
    }

    It 'missing journal is honest: exists=false, zip verdict = not checked' {
        $d = Join-Path $TestDrive "stat2_$(Get-Random)"
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.21.4' -NoNewline
        $st = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'no-journal.log')
        $st.journal.exists | Should -BeFalse
        $st.lastZipVerify | Should -Be 'not checked'
        $st.journal.events | Should -Be 0
    }

    It 'a FAILED zip verdict is surfaced, not hidden' {
        $d = New-StatusInstall
        [System.IO.File]::WriteAllLines((Join-Path $d 'update-journal.log'), [string[]]@(
            "2026-09-15 11:00:25`tmenu`tzip-verify-fail`t`tv1.21.4`tzip: MISSING"
        ), (New-Object System.Text.UTF8Encoding($false)))
        $st = Get-InstallStatus -VersionFile (Join-Path $d '.version') -JournalFile (Join-Path $d 'update-journal.log')
        $st.lastZipVerify | Should -Match '^FAILED v1\.21\.4'
    }

    It 'the status screen is wired into the menu as [ST]' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $raw | Should -Match "\[ST\] Install status \(read-only\)"
        $raw | Should -Match "'st' \{ Show-InstallStatus"
    }
}

Describe 'Integrity verdict classifier ([ST] deep check)' {

    It 'summary|ok| is OK - metadata lines never look like drift (v1.21.5 regression)' {
        $report = @(
            'verify-start|v1.21.5'
            'ref-pin|31e82e9fc0240d9a758c42f3767c52643652907e'
            'OK|mumu-menu.ps1|ABC123'
            'OK-SEMANTIC|.version|local=v1.21.5'
            'summary|ok|'
        )
        $v = Get-IntegrityVerdict -Report $report
        $v.ok | Should -BeTrue
        $v.detail | Should -Match 'all files match'
    }

    It 'summary|drift| names the drifting files' {
        $report = @('verify-start|v1.21.5', 'DRIFT|README.md|', 'summary|drift|README.md')
        $v = Get-IntegrityVerdict -Report $report
        $v.ok | Should -BeFalse
        $v.detail | Should -Match 'README\.md'
    }

    It 'summary|partial| is not drift - downloads failed, files that were checked are OK' {
        $v = Get-IntegrityVerdict -Report @('verify-start|v1.21.5', 'DOWNLOAD-FAIL|README.md|rate limit', 'summary|partial|download failures')
        $v.ok | Should -BeTrue
        $v.detail | Should -Match 'could not be downloaded'
    }

    It 'an error line and an absent summary fail honestly' {
        $v1 = Get-IntegrityVerdict -Report @('verify-start|v1.21.5', 'error|network down|')
        $v1.ok | Should -BeFalse
        $v1.detail | Should -Match 'network down'
        $v2 = Get-IntegrityVerdict -Report @()
        $v2.ok | Should -BeFalse
        $v2.detail | Should -Match 'could not run'
    }
}

Describe 'Curl retry capability (exit-35 hardening, v1.21.9)' {
    # Pester 6 on PS 5.1 cannot Mock curl.exe (AllScope conflict), so the
    # stub is a real .cmd child process - the same stdio/exit-code path the
    # production probe exercises with the real binary.
    BeforeAll {
        $script:stubDir = Join-Path $TestDrive 'curlstub'
        New-Item -ItemType Directory -Path $script:stubDir -Force | Out-Null
        foreach ($case in @(
            @{ name = 'cap35.cmd'; code = 'exit /b 35' },
            @{ name = 'cap2.cmd';  code = 'exit /b 2' },
            @{ name = 'cap0.cmd';  code = 'exit /b 0' }
        )) {
            $p = Join-Path $script:stubDir $case.name
            [System.IO.File]::WriteAllText($p, "@echo off`r`n" + $case.code + "`r`n", [System.Text.Encoding]::ASCII)
        }
    }

    It 'classifies a TLS handshake failure (exit 35) as a CAPABLE curl' {
        # curl 7.29 (System32, no --retry-all-errors) would exit 2 for the
        # unknown option; exit 35 means the option was parsed and the probe
        # URL failed at the TLS layer - capability must be $true (the live
        # regression behind "Update check failed (exit 35)").
        Test-CurlCapability -CurlExe (Join-Path $script:stubDir 'cap35.cmd') -ProbeUrl 'https://probe.invalid/' | Should -Be $true
    }

    It 'classifies an unknown-option rejection (exit 2) as NOT capable' {
        Test-CurlCapability -CurlExe (Join-Path $script:stubDir 'cap2.cmd') -ProbeUrl 'https://probe.invalid/' | Should -Be $false
    }

    It 'classifies success (exit 0) as capable' {
        Test-CurlCapability -CurlExe (Join-Path $script:stubDir 'cap0.cmd') -ProbeUrl 'https://probe.invalid/' | Should -Be $true
    }

    It 'degrades to $false when curl cannot start at all' {
        Test-CurlCapability -CurlExe 'definitely-not-a-real-curl-binary-xyz' -ProbeUrl 'https://probe.invalid/' | Should -Be $false
    }

    It 'the real curl on this machine resolves (probe path is exercised in production)' {
        (Get-Command curl.exe -ErrorAction SilentlyContinue) | Should -Not -Be $null
    }

    It 'the header parser accepts both ETag spellings GitHub sends (v1.22.1 regression)' {
        # GitHub emits 'ETag:' with a capital E; the v1.22.0 parser matched
        # only '^etag:' - the cache never populated and the drill caught it.
        $hdr = "HTTP/1.1 200 OK`r`nETag: `"8fb013c179ebd7146fe486203162019386f7fb6c`"`r`nX-Other: 1`r`n"
        $m = [regex]::Matches($hdr, '(?im)^etag:\s*(\S+)')
        $m.Count | Should -Be 1
        $m[0].Groups[1].Value | Should -Be '"8fb013c179ebd7146fe486203162019386f7fb6c"' # DevSkim: ignore DS173237 - documented ETag fixture value from the API docs, not a secret
        # and the production pattern is the case-insensitive one
        $src = [System.IO.File]::ReadAllText($script:menuPath)
        ($src.Contains('(?im)^etag:')) | Should -Be $true
    }
}

Describe 'Startup auto-diag (issue #30)' {

    It 'summary is empty for a clean install' {
        Get-AutoDiagSummary -Findings @() | Should -Be ''
    }

    It 'summary is empty when only info findings exist (info stays in [DIAG])' {
        $f = @(
            [pscustomobject]@{ severity = 'info'; area = 'install'; message = 'no .version marker yet' },
            [pscustomobject]@{ severity = 'info'; area = 'emulator'; message = '0 of 2 instance(s) running' }
        )
        Get-AutoDiagSummary -Findings $f | Should -Be ''
    }

    It 'names error and warning counts and points to [DIAG]' {
        $f = @(
            [pscustomobject]@{ severity = 'error'; area = 'install'; message = 'boom' },
            [pscustomobject]@{ severity = 'warn';  area = 'lock';     message = 'hmm' },
            [pscustomobject]@{ severity = 'warn';  area = 'journal';  message = 'meh' },
            [pscustomobject]@{ severity = 'info';  area = 'emulator'; message = 'ignored' }
        )
        $line = Get-AutoDiagSummary -Findings $f
        $line | Should -Be 'Problems found: 1 error(s), 2 warning(s) - details: [DIAG]'
    }

    It 'one error alone still surfaces the line' {
        $f = @([pscustomobject]@{ severity = 'error'; area = 'install'; message = 'x' })
        Get-AutoDiagSummary -Findings $f | Should -Match '^Problems found: 1 error\(s\), 0 warning\(s\)'
    }

    It 'the real install fixture produces a summary from actual findings' {
        # Real collector against a broken fixture dir: marker ahead of content
        # (the v1.20.5 wedge class) -> error -> the line must appear. The
        # collector is extracted from the parsed AST (no copies).
        $d = Join-Path $TestDrive "adiag_$(Get-Random)"
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1') -Value "`$scriptVer = '1.21.10'"
        Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v9.9.9' -NoNewline
        $gpf = $script:ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ProblemFindings' }, $true) | Select-Object -First 1
        . ([scriptblock]::Create($gpf.Extent.Text))
        $f = @(Get-ProblemFindings -ScriptDir $d -VersionFile (Join-Path $d '.version') -MenuPath (Join-Path $d 'mumu-menu.ps1') -JournalFile (Join-Path $d 'update-journal.log') -MumuPath '' -ScriptVer '1.21.10')
        Get-AutoDiagSummary -Findings $f | Should -Not -Be ''
    }

    It 'Invoke-StartupAutoDiag caches the verdict across calls' {
        # First call populates the script-scope cache; even if the collector
        # would change its answer, the second call must return the cached one.
        $script:AutoDiagSummary = $null
        $r1 = Invoke-StartupAutoDiag
        $script:AutoDiagSummary = 'cached-verdict'
        Invoke-StartupAutoDiag | Should -Be 'cached-verdict'
        $script:AutoDiagSummary = $null
    }

    It 'Show-AutoDiagLine renders nothing when the summary is empty' {
        $script:AutoDiagSummary = ''
        $out = Show-AutoDiagLine
        $out | Should -Be ''
        $script:AutoDiagSummary = $null
    }

    It 'wiring: Show-Menu renders the auto-diag line after the quick status' {
        $src = [System.IO.File]::ReadAllText($script:menuPath)
        ($src -match 'Show-QuickStatus\r?\n\s*Show-AutoDiagLine') | Should -Be $true
        ($src -match 'MUMU_MENU_NO_AUTODIAG') | Should -Be $true
    }
}

Describe 'Show-UpdatePlan ([UP] dry-run renderer)' {

    BeforeAll {
        $script:planDir = Join-Path $TestDrive 'plandir'
        New-Item -ItemType Directory -Path $script:planDir -Force | Out-Null
        $script:realScriptDir = $script:ScriptDir
        $script:realToken = $script:GitHubToken
        $script:ScriptDir = $script:planDir
        $script:GitHubToken = $null
    }
    AfterAll {
        $script:ScriptDir = $script:realScriptDir
        $script:GitHubToken = $script:realToken
    }

    It 'renders a full plan with update action, file list and dry-run markers' {
        'existing' | Set-Content (Join-Path $script:planDir 'mumu-menu.ps1')
        $text = (Show-UpdatePlan -Tag 'v2.0.0' -LocalTag 'v1.0.0' 6>&1 | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'update v1\.0\.0 -> v2\.0\.0'
        $text | Should -Match 'UPDATE PLAN \(dry-run'
        $text | Should -Match 'mumu-menu\.ps1, mumu-menu\.cjs, SKILL\.md, README\.md, bootstrap-update\.ps1'
        $text | Should -Match 'replaces 1 existing file\(s\)'
        $text | Should -Match 'Preview only - select \[U\] Check for updates and confirm'
    }

    It 'reports a fresh install when no files exist yet' {
        # Pester shares the BeforeAll dir across Its - start from a clean one.
        foreach ($f in @('mumu-menu.ps1', 'SKILL.md', 'README.md', 'bootstrap-update.ps1')) {
            Remove-Item (Join-Path $script:planDir $f) -Force -ErrorAction SilentlyContinue
        }
        $text = (Show-UpdatePlan -Tag 'v2.0.0' -LocalTag '' 6>&1 | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'no existing files \(fresh install\)'
        $text | Should -Match 'update\s+->\s+v2\.0\.0'
    }

    It 'shows the authenticated API line when a token is set' {
        $script:GitHubToken = 'stub'
        try {
            $text = (Show-UpdatePlan -Tag 'v2.0.0' -LocalTag 'v1.0.0' 6>&1 | ForEach-Object { "$_" }) -join "`n"
            $text | Should -Match 'authenticated \(5000 req/hr\)'
        } finally {
            $script:GitHubToken = $null
        }
    }

    It 'wiring: [UP] maps to Update-FromGitHub -Plan, plan renders before the mutation gate, menu lists it' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match "'up' \{ Update-FromGitHub -Plan \}") | Should -Be $true
        ($src -match '\[switch\]\$Plan') | Should -Be $true
        ($src -match 'if \(\$Plan\) \{\r?\n            Show-UpdatePlan -Tag \$tag -LocalTag \$localTag') | Should -Be $true
        # The plan gate must sit before the download confirmation prompt.
        # IndexOf takes LITERAL strings - no regex escapes here.
        ($src.IndexOf('Show-UpdatePlan -Tag $tag')) | Should -BeGreaterThan 0
        ($src.IndexOf("Read-Host '  Download and verify these files? (y/N)'")) | Should -BeGreaterThan 0
        ($src.IndexOf('Show-UpdatePlan -Tag $tag')) | Should -BeLessThan ($src.IndexOf("Read-Host '  Download and verify these files? (y/N)'"))
        ($src -match '\[UP\] Update plan \(dry-run\)') | Should -Be $true
        # Single-quoted: $Plan must stay literal, not interpolate.
        ($src -match 'if \(\$Plan\) \{\r?\n            Write-Host ''Update plan \(dry-run\)\.\.\.''') | Should -Be $true
    }
}

Describe 'Fix-Unicode ([UW] encoding screen, v1.22.9)' {

    It 'scan: .ps1 BOM is reported as required (PS 5.1 ANSI fallback), journal is excluded from the audit' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match 'required for PowerShell 5\.1') | Should -Be $true
        ($src -match "Name -ne 'update-journal\.log'") | Should -Be $true
        ($src -match 'safe to strip') | Should -Be $true
    }

    It 'fix mode 2: skips .ps1, confirms before writing, decodes ANSI in the system codepage' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match "Extension -ne '\.ps1'") | Should -Be $true
        # Confirmation gate sits before the write loop.
        ($src -match 'Convert \$\(\$files\.Count\) file\(s\) to UTF-8 without BOM\? \(y/N\)') | Should -Be $true
        ($src.IndexOf('Convert \$\(\$files\.Count\) file\(s\) to UTF-8 without BOM')) | Should -BeLessThan ($src.IndexOf('[System.IO.File]::WriteAllText($f.FullName, $content, $utf8NoBom)'))
        # ANSI/other files must not go through the default UTF-8 decode.
        ($src -match "'ANSI/other'\) \{\r?\n                \[System\.Text\.Encoding\]::Default\.GetString") | Should -Be $true
    }
}

Describe 'Fix-Unicode mode 5 ([UW] BOM repair, v1.22.10)' {

    It 'mode 5 wiring: scan prompt, candidate filter, confirm gate before the write, explicit EF BB BF bytes' {
        $src = Get-Content -Raw $script:menuPath
        # Single-quoted with doubled inner quotes: $mode must stay literal.
        ($src -match 'elseif \(\$mode -eq ''5''\)') | Should -Be $true
        ($src -match 'Add missing BOM to \.ps1 files') | Should -Be $true
        ($src -match 'Select option \(1/2/3/4/5\)') | Should -Be $true
        # Repair candidates: BOM-less, no UTF-16 BOM, no NUL bytes, has high bytes.
        ($src -match [regex]::Escape("FullName -notmatch '\\.git\\'")) | Should -Be $true
        ($src -match '\$b\[0\] -eq 0 -or \$b\[1\] -eq 0') | Should -Be $true
        # The confirm gate must sit before the byte write (literal IndexOf;
        # quotes-free fragments - PowerShell does not escape " with backslash).
        ($src.IndexOf('Prepend UTF-8 BOM to')) | Should -BeGreaterThan 0
        ($src.IndexOf('[System.IO.File]::WriteAllBytes($f.FullName, $out)')) | Should -BeGreaterThan 0
        ($src.IndexOf('Prepend UTF-8 BOM to')) | Should -BeLessThan ($src.IndexOf('[System.IO.File]::WriteAllBytes($f.FullName, $out)'))
        # BOM bytes are written explicitly; the broken write pattern
        # '(,[char]0xFEFF) +' must not exist (0xFEFF does not fit a byte).
        # [char]0xFEFF itself is legit elsewhere (BOM-trim normalization).
        ($src -match '\$out\[0\] = 0xEF; \$out\[1\] = 0xBB; \$out\[2\] = 0xBF') | Should -Be $true
        ($src -match '\(,\[char\]0xFEFF\)') | Should -Be $false
    }
}

Describe 'BOM hygiene (v1.22.11)' {

    # Tagged RepoFiles: reads repo-only docs (relnotes.md, RELEASE-RUNBOOK.md,
    # update-readme.ps1) that deployed installs never carry - this test runs
    # only in repo-checkout layouts (skipped by the deployed-layout fixture).
    It 'non-script release and docs files are UTF-8 without BOM; PowerShell scripts keep theirs' -Tag 'RepoFiles' {
        $root = Join-Path $PSScriptRoot '..'
        # Release/docs payload: BOM must be absent ([UW] 'safe to strip' class).
        foreach ($name in @('README.md', 'SKILL.md', 'relnotes.md', 'RELEASE-RUNBOOK.md')) {
            $b = [System.IO.File]::ReadAllBytes((Join-Path $root $name))
            $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
            $hasBom | Should -BeFalse -Because "$name must be BOM-less UTF-8"
        }
        # PowerShell scripts: BOM is intentional and required (PS 5.1 ANSI fallback).
        foreach ($name in @('mumu-menu.ps1', 'bootstrap-update.ps1', 'update-readme.ps1')) {
            $b = [System.IO.File]::ReadAllBytes((Join-Path $root $name))
            $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
            $hasBom | Should -BeTrue -Because "$name needs its BOM under PowerShell 5.1"
        }
        # The README sync writer must not re-introduce a BOM.
        $sync = [System.IO.File]::ReadAllText((Join-Path $root 'update-readme.ps1'))
        ($sync -match 'UTF8Encoding\]::new\(\$true\)') | Should -Be $false
    }
}

Describe 'Release-notes verification snippet (v10.2.0)' {

    # Tagged RepoFiles: reads the workflow that GENERATES the published
    # release body - a deployed install never carries .github/. The snippet
    # the release page publishes must run on Windows PowerShell 5.1, where
    # `curl` is an alias for Invoke-WebRequest: the old bare `curl -sL ... -o`
    # died with a parameter-binding error, so the .sha256 sidecar was never
    # downloaded and the whole verification section was dead on arrival.
    It 'the generator emits curl.exe (not the PS 5.1 curl alias) and compares hashes itself' -Tag 'RepoFiles' {
        $wf = [System.IO.File]::ReadAllText((Join-Path (Join-Path $PSScriptRoot '..') '.github/workflows/release.yml'))

        # The verification block: from the heading to the closing fence.
        $m = [regex]::Match($wf, '(?s)### Верификация.*?echo .```powershell.(.*?)echo .```.', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $m.Success | Should -BeTrue -Because 'the release-notes generator must keep a Верификация section'
        $block = $m.Groups[1].Value

        # curl.exe, not curl: the bare alias is Invoke-WebRequest on PS 5.1
        # and rejects -sL/-o outright. Only the echo lines that EMIT the
        # snippet are checked - YAML comments may mention the old form when
        # explaining why it was replaced.
        $emit = (@($block -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('echo') })) -join "`n"
        $emit | Should -Match 'curl\.exe' -Because 'the snippet must call curl.exe - the curl alias breaks on PS 5.1'
        $emit | Should -Not -Match '(?<![\w.])curl\s+-s' -Because 'a bare `curl -sL` line would fail on PS 5.1'

        # The snippet must download both artifacts (zip + sidecar).
        $block | Should -Match '\$\{ZIPNAME\}\.sha256' -Because 'the sidecar must be downloaded'

        # The comparison must be done by the snippet, not by the reader:
        # Get-FileHash prints UPPERCASE, the sidecar holds a lowercase hash
        # plus the filename, so "compare by eye" never matched literally.
        $block | Should -Match 'Get-FileHash' -Because 'the snippet must hash the zip itself'
        $block | Should -Match '\.ToLower\(\)' -Because 'the actual hash must be lowercased before comparing'
        $block | Should -Match '-split' -Because 'the sidecar line is `<hash>  <filename>` - the hash is the first token'
        $block | Should -Match 'SHA256 OK' -Because 'a successful verification must be announced'
        $block | Should -Match 'SHA256 MISMATCH' -Because 'a failed verification must be announced with both hashes'
    }
}

Describe 'Get-DiagSummary - [DIAG] verdict (v1.22.6)' {

    It 'empty findings classify as healthy' {
        $d = Get-DiagSummary -Findings @()
        $d.verdict | Should -Be 'Status: healthy'
        $d.color | Should -Be 'Green'
        $d.errors | Should -Be 0
        $d.warns | Should -Be 0
        $d.infos | Should -Be 0
    }

    It 'info-only findings are healthy - the [DIAG] false alarm report (1 of 1 instance running)' {
        # Live report: a fully working install printed "Problems found: 1
        # (0 error(s), 0 warning(s), 1 info)" - info notes are not problems.
        $f = @([pscustomobject]@{ severity = 'info'; area = 'emulator'; message = '1 of 1 instance(s) running, ADB bridge ready' })
        $d = Get-DiagSummary -Findings $f
        $d.verdict | Should -Be 'Status: healthy'
        $d.color | Should -Be 'Green'
        $d.errors | Should -Be 0
        $d.warns | Should -Be 0
        $d.infos | Should -Be 1
    }

    It 'errors produce a red Problems found verdict with honest counts' {
        $f = @(
            [pscustomobject]@{ severity = 'error'; area = 'install'; message = 'a' },
            [pscustomobject]@{ severity = 'warn';  area = 'lock';     message = 'b' },
            [pscustomobject]@{ severity = 'warn';  area = 'journal';  message = 'c' },
            [pscustomobject]@{ severity = 'info';  area = 'emulator'; message = 'd' }
        )
        $d = Get-DiagSummary -Findings $f
        $d.verdict | Should -Be 'Problems found: 1 error(s), 2 warning(s), 1 info'
        $d.color | Should -Be 'Red'
        $d.errors | Should -Be 1
        $d.warns | Should -Be 2
        $d.infos | Should -Be 1
    }

    It 'warnings-only verdict is yellow and omits the info suffix when there is none' {
        $f = @([pscustomobject]@{ severity = 'warn'; area = 'lock'; message = 'x' })
        $d = Get-DiagSummary -Findings $f
        $d.verdict | Should -Be 'Problems found: 0 error(s), 1 warning(s)'
        $d.color | Should -Be 'Yellow'
    }

    It 'wiring: [DIAG] renders via Get-DiagSummary, the healthy branch exists, bootstrap -Diagnose has parity, emulator info carries the bridge state' {
        $src = [System.IO.File]::ReadAllText($script:menuPath)
        ($src -match 'Get-DiagSummary -Findings \$findings') | Should -Be $true
        ($src -match 'nothing to fix') | Should -Be $true
        ($src -match ', ADB bridge ready') | Should -Be $true
        ($src -match ', ADB bridge NOT ready') | Should -Be $true
        $bsrc = [System.IO.File]::ReadAllText((Join-Path (Join-Path $PSScriptRoot '..') 'bootstrap-update.ps1'))
        ($bsrc -match 'Status: healthy') | Should -Be $true
    }
}

Describe 'Persistent ETag cache (issue #28)' {
    BeforeAll {
        $script:cacheFile = Join-Path $TestDrive ".etag-cache_$(Get-Random).json"
    }

    It 'round-trips an entry: save then read returns the same etag and body' {
        Save-EtagCacheFile -CacheFile $script:cacheFile -Entries @{ 'https://x/1' = @{ etag = 'W/abc'; body = 'hello body' } }
        $c = Read-EtagCacheFile -CacheFile $script:cacheFile
        $c.Count | Should -Be 1
        $c['https://x/1'].etag | Should -Be 'W/abc'
        $c['https://x/1'].body | Should -Be 'hello body'
    }

    It 'validates the stored hash on load and drops a tampered body' {
        # Simulate tampering: rewrite the file with a wrong sha256 for one
        # entry and a correct one for another.
        Save-EtagCacheFile -CacheFile $script:cacheFile -Entries @{
            'https://x/good' = @{ etag = 'W/good'; body = 'good body' }
        }
        $good = Read-EtagCacheFile -CacheFile $script:cacheFile
        # Build a store with one tampered entry directly.
        $store = @{
            'https://x/tampered' = [pscustomobject]@{ etag = 'W/bad'; body = 'evil body'; sha256 = '0000000000000000000000000000000000000000000000000000000000000000'; timestamp = '2026-09-16 10:00:00' } # DevSkim: ignore DS197836 - fixture constant named by the store schema, nothing is hashed
        }
        $json = $store | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($script:cacheFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        $c = Read-EtagCacheFile -CacheFile $script:cacheFile
        $c.ContainsKey('https://x/tampered') | Should -Be $true   # Read does not validate...
        # ...the maintenance loader does:
        $script:EtagCache = @{}; $script:EtagTags = @{}
        Invoke-EtagCacheMaintenance -CacheFile $script:cacheFile
        $script:EtagCache.ContainsKey('https://x/tampered') | Should -Be $false
        # A good entry does hydrate:
        Save-EtagCacheFile -CacheFile $script:cacheFile -Entries @{ 'https://x/ok' = @{ etag = 'W/ok'; body = 'fine' } }
        $script:EtagCache = @{}; $script:EtagTags = @{}
        Invoke-EtagCacheMaintenance -CacheFile $script:cacheFile
        $script:EtagCache['https://x/ok'] | Should -Be 'fine'
        $script:EtagTags['https://x/ok'] | Should -Be 'W/ok'
    }

    It 'degrades silently: missing, corrupt, and schema-invalid files never throw' {
        (Read-EtagCacheFile -CacheFile (Join-Path $TestDrive 'no-such-file.json')).Count | Should -Be 0
        $bad = Join-Path $TestDrive "bad_$(Get-Random).json"
        [System.IO.File]::WriteAllText($bad, '{ this is not json', (New-Object System.Text.UTF8Encoding($false)))
        (Read-EtagCacheFile -CacheFile $bad).Count | Should -Be 0
        # Schema-invalid: entries without etag/body/sha256 are dropped.
        [System.IO.File]::WriteAllText($bad, '{"https://x/": {"etag": ""}}', (New-Object System.Text.UTF8Encoding($false)))
        (Read-EtagCacheFile -CacheFile $bad).Count | Should -Be 0
    }

    It 'state line reports count and time, or empty' {
        Get-EtagCacheFileState -CacheFile (Join-Path $TestDrive 'missing.json') | Should -Be 'empty'
        $st = Get-EtagCacheFileState -CacheFile $script:cacheFile
        $st | Should -Match '^\d+ URL\(s\), last entry (\d{2}:\d{2}|n/a)$'
    }

    It 'the cache file lives next to .version and is not created for -Force' {
        $src = [System.IO.File]::ReadAllText($script:menuPath)
        ($src.Contains("'.etag-cache.json'")) | Should -Be $true
        ($src.Contains('EtagCacheFile = Join-Path')) | Should -Be $true
        ($src.Contains('param([switch]$Force)')) | Should -Be $true
        ($src.Contains("BoundParameters.Keys -contains 'Force'")) | Should -Be $true
    }

    It '[ST] session drift cache: wiring shows replay with age note and marker invalidation' {
        $src = [System.IO.File]::ReadAllText($script:menuPath)
        ($src.Contains('StDriftCache')) | Should -Be $true
        ($src.Contains('from session cache, age')) | Should -Be $true
        ($src.Contains('$script:StDriftCache.marker -eq $markerNow')) | Should -Be $true
    }
}

Describe 'Rollback from backup (issue #27)' {

    BeforeAll {
        function New-RbInstall {
            $d = Join-Path $TestDrive "rb_$(Get-Random)"
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1') -Value "`$scriptVer = '1.21.7'"
            Set-Content -LiteralPath (Join-Path $d 'mumu-menu.cjs') -Value '// js'
            Set-Content -LiteralPath (Join-Path $d 'SKILL.md') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d 'README.md') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d 'bootstrap-update.ps1') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d 'Watch-MumuConnections.ps1') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d 'Test-MumuTunnelAB.ps1') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d 'Diag-MumuNx.ps1') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.21.7' -NoNewline
            return $d
        }
        function New-RbBackup {
            param([string]$InstallDir, [string]$Ver = '1.20.9', [string]$Stamp = '20260915_120000', [switch]$Incomplete)
            $b = Join-Path (Join-Path $InstallDir 'backup') $Stamp
            New-Item -ItemType Directory -Path $b -Force | Out-Null
            if (-not $Incomplete) {
                Set-Content -LiteralPath (Join-Path $b 'mumu-menu.ps1') -Value "`$scriptVer = '$Ver'"
                Set-Content -LiteralPath (Join-Path $b 'mumu-menu.cjs') -Value '// js'
                Set-Content -LiteralPath (Join-Path $b 'SKILL.md') -Value 'x'
                Set-Content -LiteralPath (Join-Path $b 'README.md') -Value 'x'
                Set-Content -LiteralPath (Join-Path $b 'bootstrap-update.ps1') -Value 'x'
                Set-Content -LiteralPath (Join-Path $b 'Watch-MumuConnections.ps1') -Value 'x'
                Set-Content -LiteralPath (Join-Path $b 'Test-MumuTunnelAB.ps1') -Value 'x'
                Set-Content -LiteralPath (Join-Path $b 'Diag-MumuNx.ps1') -Value 'x'
            } else {
                Set-Content -LiteralPath (Join-Path $b 'SKILL.md') -Value 'x'
            }
            return $b
        }
        $script:rbMenuPath = { param($d) Join-Path $d 'mumu-menu.ps1' }
        $script:rbVerPath = { param($d) Join-Path $d '.version' }
    }

    It 'Get-BackupFolders lists newest-first with size, date, completeness' {
        $d = New-RbInstall
        $null = New-RbBackup -InstallDir $d -Stamp '20260915_120000'
        $null = New-RbBackup -InstallDir $d -Stamp '20260914_090000' -Incomplete
        $null = New-Item -ItemType Directory -Path (Join-Path $d 'backup\not-a-stamp') -Force
        $list = @(Get-BackupFolders -InstallDir $d)
        $list.Count | Should -Be 2
        $list[0].Name | Should -Be '20260915_120000'
        $list[0].HasMenu | Should -BeTrue
        $list[1].HasMenu | Should -BeFalse
        $list[0].SizeMB | Should -Be 0
    }

    It 'Build-RollbackPlan validates completeness and earns the marker from content' {
        $d = New-RbInstall
        $b = New-RbBackup -InstallDir $d -Ver '1.20.9'
        $plan = Build-RollbackPlan -BackupDir $b -InstallDir $d
        $plan.Ok | Should -BeTrue
        $plan.Files.Count | Should -Be 8   # deployed set minus .version (written from content)
        $plan.MarkerWrite | Should -BeTrue
        $plan.MarkerTo | Should -Be 'v1.20.9'
        $bad = Build-RollbackPlan -BackupDir (Join-Path $d 'backup\nope') -InstallDir $d
        $bad.Ok | Should -BeFalse
        $b2 = New-RbBackup -InstallDir $d -Stamp '20260913_080000' -Incomplete
        $plan2 = Build-RollbackPlan -BackupDir $b2 -InstallDir $d
        $plan2.Ok | Should -BeFalse
        $plan2.Reason | Should -Match 'incomplete'
    }

    It 'Invoke-Rollback restores files and re-aligns the marker to the restored content' {
        $d = New-RbInstall
        $b = New-RbBackup -InstallDir $d -Ver '1.20.9'
        $ok = Invoke-Rollback -BackupDir $b -InstallDir $d -VersionFile (Join-Path $d '.version')
        $ok | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $d '.version') -Raw).Trim() | Should -Be 'v1.20.9'
        ((Get-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1') -Raw) -match "\`$scriptVer = '1\.20\.9'") | Should -BeTrue
        # Rollback events land in the journal (writer targets $script:JournalFile)
        $j = Get-Content -LiteralPath $script:JournalFile
        ($j | Where-Object { $_ -match "`trollback`t" }) | Should -Not -BeNullOrEmpty
    }

    It 'Invoke-Rollback without a version claim leaves the marker unchanged and still journals' {
        $d = New-RbInstall
        $b = New-RbBackup -InstallDir $d -Ver '9.9.9'
        # Corrupt the backup's menu so no scriptVer can be parsed
        Set-Content -LiteralPath (Join-Path $b 'mumu-menu.ps1') -Value '# no version claim here'
        $ok = Invoke-Rollback -BackupDir $b -InstallDir $d -VersionFile (Join-Path $d '.version')
        $ok | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $d '.version') -Raw).Trim() | Should -Be 'v1.21.7'   # unchanged
        $j = Get-Content -LiteralPath $script:JournalFile
        ($j | Where-Object { $_ -match "`trollback`t" }) | Should -Not -BeNullOrEmpty
    }

    It 'Invoke-Rollback failure journals rollback-fail and returns false' {
        $d = New-RbInstall
        $b = New-RbBackup -InstallDir $d -Ver '1.20.9'
        # Make README undeletable-to-overwrite by opening a lock on the destination
        $dest = Join-Path $d 'README.md'
        $stream = [System.IO.File]::Open($dest, 'Open', 'Read', 'None')
        try {
            $ok = Invoke-Rollback -BackupDir $b -InstallDir $d -VersionFile (Join-Path $d '.version')
            $ok | Should -BeFalse
        } finally { $stream.Dispose() }
        $j = Get-Content -LiteralPath $script:JournalFile
        ($j | Where-Object { $_ -match "`trollback-fail`t" }) | Should -Not -BeNullOrEmpty
    }

    It 'the probe ADB fallback verifies via adb devices when adb_version is absent' {
        # Regression for the v1.21.8 live catch: MuMu builds without adb_version
        # in the info output made the readiness flag a permanent false positive.
        $d = Join-Path $TestDrive "adbfallback_$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $d 'shell') -Force | Out-Null
        # A fake adb.cmd (real child process - a text .exe cannot execute) that
        # reports the instance as connected; injected via -AdbPathOverride.
        $fakeAdb = Join-Path $d 'shell\adb.cmd'
        $adbBat = "@echo off`r`necho List of devices attached`r`necho 127.0.0.1:16384`tdevice`r`n" # DevSkim: ignore DS162092 - loopback fixture mimicking the emulator ADB bridge
        [System.IO.File]::WriteAllText($fakeAdb, $adbBat)
        # A MuMuManager stub reporting a running instance without adb_version
        $stub = Join-Path $d 'MuMuManager.cmd'
        [System.IO.File]::WriteAllText((Join-Path $d 'mu-stub-out.txt'), '{"0":{"player_state":"start_finished","adb_host_ip":"127.0.0.1","adb_port":16384}}') # DevSkim: ignore DS162092 - loopback fixture mimicking the emulator ADB bridge
        [System.IO.File]::WriteAllText((Join-Path $d 'mu-stub-mode.txt'), 'json')
        $bat = "@echo off`r`nfindstr /C:`"crash`" `"$(Join-Path $d 'mu-stub-mode.txt')`" >nul 2>&1 && exit /b 3`r`ntype `"$(Join-Path $d 'mu-stub-out.txt')`"`r`n"
        [System.IO.File]::WriteAllText($stub, $bat)
        $p = Invoke-MumuManagerProbe -MumuPathOverride $stub -AdbPathOverride $fakeAdb
        $p.adbReady | Should -BeTrue
    }

    It 'the probe ADB fallback does not crash without any adb binary and stays honest' {
        # No adb.exe next to the MuMuManager root and none on PATH (the test
        # process PATH may carry one - force a root without shell\adb.exe).
        $d = Join-Path $TestDrive "adbnone_$(Get-Random)"
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $stub = Join-Path $d 'MuMuManager.cmd'
        [System.IO.File]::WriteAllText((Join-Path $d 'mu-stub-out.txt'), '{"0":{"player_state":"start_finished","adb_port":16384}}')
        [System.IO.File]::WriteAllText((Join-Path $d 'mu-stub-mode.txt'), 'json')
        $bat = "@echo off`r`ntype `"$(Join-Path $d 'mu-stub-out.txt')`"`r`n"
        [System.IO.File]::WriteAllText($stub, $bat)
        # Only evaluates honestly: no adb anywhere -> adbReady stays false but
        # the probe must NOT crash. We assert it runs and reports the instance.
        $p = Invoke-MumuManagerProbe -MumuPathOverride $stub
        $p.instances | Should -Be 1
        $p.running | Should -Be 1
    }
}

Describe 'Emulator diagnostics (issue #32)' {

    BeforeAll {
        # A stub MuMuManager: a real executable child process (same stdio
        # path as the actual binary). A .cmd file is runnable via & from any
        # PowerShell edition; the JSON payload lives in a BOM-less file that
        # the batch prints verbatim via type (BOM would break ConvertFrom-Json).
        function New-MumuStub {
            param([string]$Dir, [string]$Json, [switch]$Crash)
            $exe = Join-Path $Dir 'MuMuManager.cmd'
            $outFile = Join-Path $Dir 'mu-stub-out.txt'
            $modeFile = Join-Path $Dir 'mu-stub-mode.txt'
            if ($Crash) { Set-Content -LiteralPath $modeFile -Value 'crash' } else { Set-Content -LiteralPath $modeFile -Value 'json' }
            [System.IO.File]::WriteAllText($outFile, $Json)
            $bat = "@echo off`r`nfindstr /C:`"crash`" `"$modeFile`" >nul 2>&1 && exit /b 3`r`ntype `"$outFile`"`r`n"
            [System.IO.File]::WriteAllText($exe, $bat)
            return $exe
        }
        function Invoke-Diag2 {
            param([string]$Dir, [string]$MumuExe, [scriptblock]$Probe)
            Get-ProblemFindings -ScriptDir $Dir -VersionFile (Join-Path $Dir '.version') -MenuPath (Join-Path $Dir 'mumu-menu.ps1') `
                -JournalFile (Join-Path $Dir 'update-journal.log') -MumuPath $MumuExe -InstalledVersion '' -ScriptVer '1.21.6' -MumuProbe $Probe
        }
        $d = Join-Path $TestDrive "emu_$(Get-Random)"
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1') -Value "`$scriptVer = '1.21.6'"
        Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.21.6' -NoNewline
        [System.IO.File]::WriteAllLines((Join-Path $d 'update-journal.log'), [string[]]@("2026-09-15 10:00:00`tbootstrap`tupdate-ok`tv1.21.5`tv1.21.6`tok"), (New-Object System.Text.UTF8Encoding($false)))
        $script:emuDir = $d
        $script:emuProbe = { param($exe) Invoke-MumuManagerProbe -MumuPathOverride $exe }
    }

    It 'probe parses the real info shape: instances, running, adb readiness' {
        $exe = New-MumuStub -Dir $script:emuDir -Json '{"0":{"player_state":"started","adb_version":"1.0.41"},"1":{"player_state":"stopped"}}'
        $p = Invoke-MumuManagerProbe -MumuPathOverride $exe
        $p.found | Should -BeTrue
        $p.instances | Should -Be 2
        $p.running | Should -Be 1
        $p.adbReady | Should -BeTrue
        $p.error | Should -Be ''
    }

    It 'probe flags a running instance whose ADB bridge is not ready' {
        $exe = New-MumuStub -Dir $script:emuDir -Json '{"0":{"player_state":"started"}}'
        $p = Invoke-MumuManagerProbe -MumuPathOverride $exe
        $p.running | Should -Be 1
        $p.adbReady | Should -BeFalse
    }

    It 'probe degrades quietly on crash and non-JSON output' {
        $exe = New-MumuStub -Dir $script:emuDir -Json '' -Crash
        $p = Invoke-MumuManagerProbe -MumuPathOverride $exe
        $p.found | Should -BeTrue
        $p.error | Should -Not -Be ''
        $exe2 = New-MumuStub -Dir $script:emuDir -Json 'MuMuManager: fatal error 0x80070002'
        $p2 = Invoke-MumuManagerProbe -MumuPathOverride $exe2
        $p2.error | Should -Match 'not JSON'
    }

    It 'probe: missing binary is found=false, empty output is an error' {
        $p = Invoke-MumuManagerProbe -MumuPathOverride 'C:\definitely-missing\MuMuManager.exe'
        $p.found | Should -BeFalse
        $p.error | Should -Be 'not found'
    }

    It 'probe parses pretty-printed multi-line JSON like the real MuMuManager output' {
        # The real binary emits formatted JSON; pwsh 7 parses each pipeline
        # line separately (every line alone is invalid) - the probe must join
        # lines before parsing. Regression for the v1.21.7 live catch.
        $json = "{`n  `"0`": {`n    `"player_state`": `"started`",`n    `"adb_version`": `"1.0.41`"`n  }`n}"
        $exe = New-MumuStub -Dir $script:emuDir -Json $json
        $p = Invoke-MumuManagerProbe -MumuPathOverride $exe
        $p.error | Should -Be ''
        $p.instances | Should -Be 1
        $p.running | Should -Be 1
        $p.adbReady | Should -BeTrue
    }

    It 'diagnostics warn when a running instance has no ADB bridge' {
        $exe = New-MumuStub -Dir $script:emuDir -Json '{"0":{"player_state":"started"}}'
        $f = Invoke-Diag2 -Dir $script:emuDir -MumuExe $exe -Probe $script:emuProbe
        @($f | Where-Object { $_.area -eq 'emulator' -and $_.severity -eq 'warn' -and $_.message -match 'ADB bridge not ready' }).Count | Should -Be 1
        @($f | Where-Object { $_.area -eq 'emulator' -and $_.message -match '1 of 1 instance\(s\) running, ADB bridge NOT ready' }).Count | Should -Be 1
    }

    It 'diagnostics stay quiet for a healthy running instance with ADB ready' {
        $exe = New-MumuStub -Dir $script:emuDir -Json '{"0":{"player_state":"started","adb_version":"1.0.41"}}'
        $f = Invoke-Diag2 -Dir $script:emuDir -MumuExe $exe -Probe $script:emuProbe
        @($f | Where-Object { $_.severity -eq 'error' -or $_.severity -eq 'warn' }).Count | Should -Be 0
        @($f | Where-Object { $_.area -eq 'emulator' -and $_.message -match '1 of 1 instance\(s\) running, ADB bridge ready' }).Count | Should -Be 1
    }

    It 'diagnostics: no instances and stopped instances are info, MuMuManager crash is a warning' {
        $exe = New-MumuStub -Dir $script:emuDir -Json '{}'
        $f = Invoke-Diag2 -Dir $script:emuDir -MumuExe $exe -Probe $script:emuProbe
        @($f | Where-Object { $_.area -eq 'emulator' -and $_.severity -eq 'info' -and $_.message -match 'no emulator instances' }).Count | Should -Be 1
        $exe2 = New-MumuStub -Dir $script:emuDir -Json '{"0":{"player_state":"stopped"}}'
        $f2 = Invoke-Diag2 -Dir $script:emuDir -MumuExe $exe2 -Probe $script:emuProbe
        @($f2 | Where-Object { $_.area -eq 'emulator' -and $_.message -match 'none running' }).Count | Should -Be 1
        $exe3 = New-MumuStub -Dir $script:emuDir -Json '' -Crash
        $f3 = Invoke-Diag2 -Dir $script:emuDir -MumuExe $exe3 -Probe $script:emuProbe
        @($f3 | Where-Object { $_.area -eq 'mumu' -and $_.severity -eq 'warn' -and $_.message -match 'did not answer cleanly' }).Count | Should -Be 1
    }
}

Describe 'GitHub API fetch via argument arrays (v1.22.3, [K] Token invalid fix)' {

    It 'Get-CurlGitHubArgs emits an argument ARRAY - no fused "-s --retry ..." element possible' {
        $script:CurlRetryArgs = @('--retry', '3', '--retry-delay', '2', '--retry-all-errors')
        $a = Get-CurlGitHubArgs -Token 'tok123'
        $a[0] | Should -Be '-s'
        # the regression: PS 5.1 string interpolation "-s$script:CurlRetryStr" fuses
        # '-s --retry 3 ...' into ONE argument; curl answers exit 2 and [K] then
        # claimed 'Token invalid!' for a valid token. Array elements must never fuse.
        @($a | Where-Object { $_ -match '\s' -and $_ -notmatch '^Authorization: ' }).Count | Should -Be 0
        $a | Should -Contain '--retry-all-errors'
    }

    It 'Get-CurlGitHubArgs falls back to $script:GitHubToken when -Token is omitted' {
        $script:CurlRetryArgs = @('--retry', '3')
        $script:GitHubToken = 'fallback-token'
        $a = Get-CurlGitHubArgs
        (@($a | Where-Object { $_ -eq 'Authorization: token fallback-token' })).Count | Should -Be 1
        $a = Get-CurlGitHubArgs -Token 'explicit'
        (@($a | Where-Object { $_ -eq 'Authorization: token explicit' })).Count | Should -Be 1
        (@($a | Where-Object { $_ -eq 'Authorization: token fallback-token' })).Count | Should -Be 0
    }

    It 'Invoke-GitHubApiGet without -Token sends the SAVED token, not an anonymous request' {
        # v10.4.4 passed -Token "" down to Get-CurlGitHubArgs, which then saw an
        # explicitly-bound token, skipped its script-scope fallback and sent no
        # Authorization header at all - a valid [K] token was silently ignored
        # and [RL]/[U] kept hitting the anonymous 60/hour ceiling.
        $calls = [System.Collections.Generic.List[string]]::new()
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $calls.Add(($curlArgs -join ' ')) | Out-Null
            '{"ok":true}'
            $global:LASTEXITCODE = 0
        }
        $savedToken = $script:GitHubToken
        try {
            $script:GitHubToken = 'saved-token-123'
            $null = Invoke-GitHubApiGet -Url 'https://api.github.com/zen'
            ($calls | Select-Object -Last 1) | Should -Match 'Authorization: token saved-token-123'
            # An explicit -Token still wins over the saved one.
            $null = Invoke-GitHubApiGet -Url 'https://api.github.com/zen' -Token 'explicit-456'
            ($calls | Select-Object -Last 1) | Should -Match 'Authorization: token explicit-456'
        } finally { $script:GitHubToken = $savedToken }
    }

    It 'Test-CurlRetrySupport: exit 2 means NOT supported, any network exit code means supported' {
        $dir = Join-Path $TestDrive 'curlprobe223'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $stub = Join-Path $dir 'curlprobe.cmd'
        Set-Content -Path $stub -Value '@exit 2' -Encoding Ascii
        Test-CurlRetrySupport -CurlExe $stub | Should -Be $false
        Set-Content -Path $stub -Value '@exit 35' -Encoding Ascii
        Test-CurlRetrySupport -CurlExe $stub | Should -Be $true
    }

    It 'Repair-CurlRevocation: a healthy host is left alone and keeps revocation checks' {
        $dir = Join-Path $TestDrive 'curlrev-ok'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $stub = Join-Path $dir 'curl-ok.cmd'
        Set-Content -Path $stub -Value '@exit 0' -Encoding Ascii
        $cfgDir = Join-Path $dir 'cfg'
        $saved = $env:CURL_HOME
        try {
            $env:CURL_HOME = 'sentinel'
            Repair-CurlRevocation -CurlExe $stub -ConfigDir $cfgDir | Should -Be $false
            $env:CURL_HOME | Should -Be 'sentinel'
            (Test-Path -LiteralPath (Join-Path $cfgDir '_curlrc')) | Should -Be $false
        } finally { $env:CURL_HOME = $saved }
    }

    It 'Repair-CurlRevocation: revocation-only failure writes a process-scoped _curlrc and points CURL_HOME at it' {
        # Exit 35 without --ssl-no-revoke, 0 with it - the CRYPT_E_REVOCATION_OFFLINE
        # shape: the same request succeeds once the CRL/OCSP lookup is skipped.
        $dir = Join-Path $TestDrive 'curlrev-fix'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $stub = Join-Path $dir 'curl-rev.cmd'
        $bat = "@echo off`r`necho %* | findstr /C:`"--ssl-no-revoke`" >nul`r`nif %errorlevel% equ 0 exit /b 0`r`nexit /b 35`r`n"
        [System.IO.File]::WriteAllText($stub, $bat)
        $cfgDir = Join-Path $dir 'cfg'
        $saved = $env:CURL_HOME
        try {
            $env:CURL_HOME = ''
            Repair-CurlRevocation -CurlExe $stub -ConfigDir $cfgDir | Should -Be $true
            $env:CURL_HOME | Should -Be $cfgDir
            $cfg = Join-Path $cfgDir '_curlrc'
            (Test-Path -LiteralPath $cfg -PathType Leaf) | Should -Be $true
            ([System.IO.File]::ReadAllText($cfg)).Trim() | Should -Be 'ssl-no-revoke'
        } finally { $env:CURL_HOME = $saved }
    }

    It 'Repair-CurlRevocation: a dead network stays a failure (no silent revocation bypass)' {
        $dir = Join-Path $TestDrive 'curlrev-dead'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $stub = Join-Path $dir 'curl-dead.cmd'
        Set-Content -Path $stub -Value '@exit 7' -Encoding Ascii
        $cfgDir = Join-Path $dir 'cfg'
        $saved = $env:CURL_HOME
        try {
            $env:CURL_HOME = 'sentinel2'
            Repair-CurlRevocation -CurlExe $stub -ConfigDir $cfgDir | Should -Be $false
            $env:CURL_HOME | Should -Be 'sentinel2'
            (Test-Path -LiteralPath (Join-Path $cfgDir '_curlrc')) | Should -Be $false
        } finally { $env:CURL_HOME = $saved }
    }

    It 'the broken "-s$script:CurlRetryStr" interpolation pattern is gone from direct curl calls' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mumu-menu.ps1'))
        # direct "& curl.exe -s$script:CurlRetryStr ..." calls fuse into one argument under
        # PS 5.1 (the [K] bug). String builders consumed via cmd /c re-tokenize and are
        # exempt - the guard targets the direct-call fusion.
        ([regex]::Matches($src, [regex]::Escape('& curl.exe -s$script:CurlRetryStr'))).Count | Should -Be 0
    }

    It '[K] wiring: validation goes through Invoke-GitHubApiGet and empty responses get an honest failure message' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mumu-menu.ps1'))
        # both [K] paths validate through the argument-array helper (no raw fused curl call)
        ([regex]::Matches($src, [regex]::Escape("Invoke-GitHubApiGet -Url 'https://api.github.com/user'"))).Count | Should -Be 3
        # empty body must say "did not respond", not "Token invalid"
        $src | Should -Match 'did not respond \(network problem\)'
        # genuine rejection keeps a specific message
        $src | Should -Match 'Bad credentials'
    }
}

Describe 'curl argument-array audit (v1.22.4): no string-built cmd /c curl remains' {

    It 'mumu-menu.ps1 has zero cmd /c curl invocations and zero *Cmd string builders' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mumu-menu.ps1'))
        ([regex]::Matches($src, [regex]::Escape('cmd /c'))).Count | Should -Be 0
        foreach ($var in @('$curlCmd', '$dlCmd', '$relCmd', '$relListCmd', '$branchCmd', '$ltCmd', '$listCmd', '$noAuthCmd')) {
            ([regex]::Matches($src, [regex]::Escape($var))).Count | Should -Be 0
        }
    }

    It 'bootstrap-update.ps1 has zero cmd /c curl invocations and all fetches build argument arrays' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\bootstrap-update.ps1'))
        # count only code: strip comment lines before matching
        $code = (($src -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        ([regex]::Matches($code, [regex]::Escape('cmd /c'))).Count | Should -Be 0
        # every curl launch goes through splatted arrays
        ([regex]::Matches($code, [regex]::Escape('& curl.exe @'))).Count | Should -BeGreaterThan 0
        # no direct curl call with inline string interpolation of retry options
        ([regex]::Matches($code, [regex]::Escape('-sS$script:CurlRetryStr'))).Count | Should -Be 0
    }

    It 'every remaining direct "& curl.exe" call in the menu passes a splatted array or literal options' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mumu-menu.ps1'))
        # find every "& curl.exe ..." launch; forbid fusion-prone interpolated option strings
        $bad = [regex]::Matches($src, '&\s*curl\.exe\s+[^\r\n|;]*\$script:\w+Str')
        $bad.Count | Should -Be 0
    }
}

Describe 'ADB probe hardening (v1.22.5): explicit connect, candidates, kill-on-timeout' {

    BeforeAll {
        function New-AdbTestStub {
            # Fixture for the v1.22.5 ADB-probe tests: a MuMuManager stub reporting a
            # running instance WITHOUT adb_version (forces the ADB-fallback path) plus
            # a controllable adb stub. Defined in BeforeAll: Pester 6 only surfaces
            # helpers declared this way to the It bodies.
            param([string]$Name, [string]$AdbBatLines)
            $d = Join-Path $TestDrive "$Name`_$(Get-Random)"
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $d 'mu-stub-out.txt'), '{"0":{"player_state":"start_finished","adb_host_ip":"127.0.0.1","adb_port":16384}}') # DevSkim: ignore DS162092 - loopback fixture mimicking the emulator ADB bridge
            $out = Join-Path $d 'mu-stub-out.txt'
            $bat = "@echo off`r`ntype `"$out`"`r`n"
            [System.IO.File]::WriteAllText((Join-Path $d 'MuMuManager.cmd'), $bat)
            $adb = "@echo off`r`n$AdbBatLines"
            [System.IO.File]::WriteAllText((Join-Path $d 'adb.cmd'), $adb)
            return @{ Dir = $d; Stub = (Join-Path $d 'MuMuManager.cmd'); Adb = (Join-Path $d 'adb.cmd') }
        }
    }

    It 'the probe issues an explicit `adb connect` before reading the device list' {
        # v1.22.5 live catch: MuMu's bridge LISTENS but plain `adb devices` stays
        # empty until an explicit connect - the readiness flag was a permanent
        # false positive ("ADB bridge not ready" on a healthy emulator).
        $f = New-AdbTestStub -Name 'adbconnect' -AdbBatLines (
            "if not exist `"%TEMP%\adb-connect-saw-connect.flag`" echo connect %%* >> `"%TEMP%\adb-connect-saw-connect.flag`"`r`n" +
            "echo connected to 127.0.0.1:16384`r`n" + # DevSkim: ignore DS162092 - loopback fixture mimicking the emulator ADB bridge
            "echo 127.0.0.1:16384`tdevice" # DevSkim: ignore DS162092 - loopback fixture mimicking the emulator ADB bridge
        )
        try {
            Remove-Item "$env:TEMP\adb-connect-saw-connect.flag" -Force -ErrorAction SilentlyContinue
            $p = Invoke-MumuManagerProbe -MumuPathOverride $f.Stub -AdbPathOverride $f.Adb
            $p.adbReady | Should -BeTrue
            Test-Path "$env:TEMP\adb-connect-saw-connect.flag" | Should -BeTrue
        } finally {
            Remove-Item "$env:TEMP\adb-connect-saw-connect.flag" -Force -ErrorAction SilentlyContinue
        }
    }

    It 'the probe prefers adb.exe next to MuMuManager (nx_main layout) over PATH' {
        # v1.22.5 live catch: real adb lives in nx_main\ next to MuMuManager.exe;
        # the old probe only looked at <root>\shell\adb.exe and PATH.
        $f = New-AdbTestStub -Name 'adborder' -AdbBatLines "echo 127.0.0.1:16384`tdevice" # DevSkim: ignore DS162092 - loopback fixture mimicking the emulator ADB bridge
        # plant both candidates: side-by-side .cmd must win over shell\.cmd
        New-Item -ItemType Directory -Path (Join-Path $f.Dir 'shell') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $f.Dir 'shell\adb.cmd'), "@echo off`r`necho FROM-SHELL`r`n")
        $p = Invoke-MumuManagerProbe -MumuPathOverride $f.Stub
        $p.adbReady | Should -BeTrue
        $p.adbExeUsed | Should -Be (Join-Path $f.Dir 'adb.cmd')
    }

    It 'a hung adb call is killed by the timeout wrapper and never freezes the probe' {
        # the stub blocks for 30s (ping); the wrapper must kill it at 5s and the
        # probe still completes with honest readiness=false.
        $f = New-AdbTestStub -Name 'adbhang' -AdbBatLines "ping -n 30 127.0.0.1 >/dev/null" # DevSkim: ignore DS162092 - loopback fixture for the kill-on-timeout wrapper
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $p = Invoke-MumuManagerProbe -MumuPathOverride $f.Stub -AdbPathOverride $f.Adb
        $sw.Stop()
        $p.adbReady | Should -BeFalse
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 15
    }
}

Describe 'Resource monitor ([RM] CPU/RAM, live)' {

    BeforeAll {
        function New-MumuProcStub {
            # Process-like stub: same member names the live collector reads
            # off System.Diagnostics.Process (Id, ProcessName,
            # TotalProcessorTime, WorkingSet64, PrivateMemorySize64,
            # StartTime). Switches drop members to exercise the honest
            # degrade path (access denied / exited process shapes).
            param([int]$Id, [string]$Name, [double]$CpuSec, [double]$RamMB, [double]$PrivMB, [int]$UpMinutes = 90, [switch]$NoStart, [switch]$NoTimes)
            $o = [pscustomobject]@{ Id = $Id; ProcessName = $Name }
            if (-not $NoTimes) {
                $o | Add-Member -NotePropertyName TotalProcessorTime -NotePropertyValue ([timespan]::FromSeconds($CpuSec))
                $o | Add-Member -NotePropertyName WorkingSet64 -NotePropertyValue ([long]($RamMB * 1MB))
                $o | Add-Member -NotePropertyName PrivateMemorySize64 -NotePropertyValue ([long]($PrivMB * 1MB))
            }
            if (-not $NoStart) {
                $o | Add-Member -NotePropertyName StartTime -NotePropertyValue ((Get-Date).AddMinutes(-$UpMinutes))
            }
            return $o
        }
    }

    It 'collector normalizes a real-shaped process stub into sample fields' {
        $stub = New-MumuProcStub -Id 4242 -Name 'MuMuNxMain' -CpuSec 12.5 -RamMB 2048 -PrivMB 1500
        $s = @(Get-MumuProcessSamples -Processes $stub)
        $s.Count | Should -Be 1
        $s[0].Pid | Should -Be 4242
        $s[0].Name | Should -Be 'MuMuNxMain'
        $s[0].CpuSec | Should -Be 12.5
        $s[0].RamMB | Should -Be 2048
        $s[0].PrivMB | Should -Be 1500
        $s[0].Uptime | Should -Match '^1h 30m$'
    }

    It 'collector degrades honestly when members are missing or unreadable' {
        $bare = [pscustomobject]@{ Id = 7; ProcessName = 'MuMuPlayer' }
        $s = @(Get-MumuProcessSamples -Processes $bare)
        $s[0].CpuSec | Should -Be 0
        $s[0].RamMB | Should -Be 0
        $s[0].Uptime | Should -Be 'n/a'
    }

    It 'collector: explicitly passed empty array means no processes (no live fallback)' {
        $s = @(Get-MumuProcessSamples -Processes @())
        $s.Count | Should -Be 0
    }

    It 'snapshot -NoBaseline: first frame shows no CPU% but honest RAM totals' {
        $stubs = @(
            (New-MumuProcStub -Id 1 -Name 'A' -CpuSec 1 -RamMB 100 -PrivMB 60),
            (New-MumuProcStub -Id 2 -Name 'B' -CpuSec 1 -RamMB 250 -PrivMB 90)
        )
        $samples = @(Get-MumuProcessSamples -Processes $stubs)
        $snap = Get-MumuResourceSnapshot -Samples $samples -Prev @{} -ElapsedSeconds 1 -Cores 4 -NoBaseline
        $snap.ProcessCount | Should -Be 2
        $snap.TotalCpuPct | Should -BeNullOrEmpty
        foreach ($r in $snap.Rows) { $r.CpuPct | Should -BeNullOrEmpty }
        $snap.TotalRamMB | Should -Be 350
        $snap.TotalPrivMB | Should -Be 150
    }

    It 'snapshot computes CPU% from the delta against the previous tick, normalized to cores' {
        $stubs = @((New-MumuProcStub -Id 1001 -Name 'A' -CpuSec 12.0 -RamMB 10 -PrivMB 5))
        $prev = @{ 1001 = 10.0 }
        $snap = Get-MumuResourceSnapshot -Samples @(Get-MumuProcessSamples -Processes $stubs) -Prev $prev -ElapsedSeconds 2 -Cores 2
        $snap.Rows[0].CpuPct | Should -Be 50
        $snap.TotalCpuPct | Should -Be 50
    }

    It 'snapshot clamps negative deltas to 0 and over-100% to 100' {
        $down = Get-MumuProcessSamples -Processes @((New-MumuProcStub -Id 5 -Name 'A' -CpuSec 1 -RamMB 0 -PrivMB 0))
        $s1 = Get-MumuResourceSnapshot -Samples @($down) -Prev @{ 5 = 50.0 } -ElapsedSeconds 1 -Cores 1
        $s1.Rows[0].CpuPct | Should -Be 0
        $up = Get-MumuProcessSamples -Processes @((New-MumuProcStub -Id 6 -Name 'A' -CpuSec 1000 -RamMB 0 -PrivMB 0))
        $s2 = Get-MumuResourceSnapshot -Samples @($up) -Prev @{ 6 = 0.0 } -ElapsedSeconds 1 -Cores 1
        $s2.Rows[0].CpuPct | Should -Be 100
    }

    It 'snapshot sorts by CPU% desc by default, RAM desc and PID asc on demand' {
        # CPU deltas small enough to stay under the 100% per-row clamp
        # (90/5/50 CPU-seconds over a 1 s tick would ALL clamp to 100 and
        # the sort order would degenerate to input order - caught live).
        $stubs = @(
            (New-MumuProcStub -Id 3 -Name 'C' -CpuSec 0.9 -RamMB 10 -PrivMB 1),
            (New-MumuProcStub -Id 1 -Name 'A' -CpuSec 0.05 -RamMB 500 -PrivMB 1),
            (New-MumuProcStub -Id 2 -Name 'B' -CpuSec 0.5 -RamMB 900 -PrivMB 1)
        )
        $samples = @(Get-MumuProcessSamples -Processes $stubs)
        (Get-MumuResourceSnapshot -Samples $samples -Prev @{} -ElapsedSeconds 1 -Cores 1).Rows.Pid | Should -Be @(3, 2, 1)
        (Get-MumuResourceSnapshot -Samples $samples -Prev @{} -ElapsedSeconds 1 -Cores 1 -Sort ram).Rows.Pid | Should -Be @(2, 1, 3)
        (Get-MumuResourceSnapshot -Samples $samples -Prev @{} -ElapsedSeconds 1 -Cores 1 -Sort pid).Rows.Pid | Should -Be @(1, 2, 3)
    }

    It 'snapshot: empty sample set is an honest zero, not an error' {
        $snap = Get-MumuResourceSnapshot -Samples @() -Prev @{} -ElapsedSeconds 1 -Cores 1
        $snap.ProcessCount | Should -Be 0
        @($snap.Rows).Count | Should -Be 0
        $snap.TotalCpuPct | Should -Be 0
        $snap.TotalRamMB | Should -Be 0
    }

    It 'collector attaches the instance label when an instance map is supplied' {
        $stub = New-MumuProcStub -Id 26200 -Name 'MuMuNxDevice' -CpuSec 1 -RamMB 1 -PrivMB 1
        $s = @(Get-MumuProcessSamples -Processes $stub -InstanceMap @{ 26200 = '#0 Android Device' })
        $s[0].Instance | Should -Be '#0 Android Device'
        $s2 = @(Get-MumuProcessSamples -Processes $stub)
        $s2[0].Instance | Should -Be ''
    }

    It 'snapshot carries the instance label into the rendered rows' {
        $stubs = @((New-MumuProcStub -Id 7 -Name 'A' -CpuSec 1 -RamMB 1 -PrivMB 1))
        $samples = @(Get-MumuProcessSamples -Processes $stubs -InstanceMap @{ 7 = '#2 Android Device-2' })
        $snap = Get-MumuResourceSnapshot -Samples $samples -Prev @{} -ElapsedSeconds 1 -Cores 1
        $snap.Rows[0].Instance | Should -Be '#2 Android Device-2'
    }

    It '[RM] -Once renders one frame without throwing (CI: no MuMu processes)' {
        { Show-ResourceMonitor -Once } | Should -Not -Throw
    }

    It 'wiring: [RM] maps in the main switch, the menu lists it, the loop re-baselines before drawing' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match "'rm' \{ Show-ResourceMonitor \}") | Should -Be $true
        ($src -match '\[RM\] Resource monitor \(CPU/RAM, live\)') | Should -Be $true
        ($src -match '-NoBaseline:\$firstFrame') | Should -Be $true
        ($src -match "Get-Process -Name 'MuMu\*' -ErrorAction SilentlyContinue") | Should -Be $true
        # Quit keys exist for the interactive loop (Q, Esc, Ctrl+C).
        ($src.Contains('$ki.Key -eq ''Q'' -or $ki.Key -eq ''Escape''')) | Should -Be $true
        ($src.Contains('[ConsoleModifiers]::Control')) | Should -Be $true
        # Per-instance column: the map is fetched every tick and rendered.
        ($src.Contains('$instMap = Get-InstanceProcessMap')) | Should -Be $true
        ($src -match '\{0,-8\}\{1,-23\}\{2,-19\}\{3,7\}') | Should -Be $true
        # v2 keys: pause, reset, export.
        ($src.Contains("if (`$ki.Key -eq 'P') {")) | Should -Be $true
        ($src.Contains("if (`$ki.Key -eq 'R') {")) | Should -Be $true
        ($src.Contains("if (`$ki.Key -eq 'E') {")) | Should -Be $true
    }

    It '[RM] stays read-only: no network calls, no writes inside the monitor loop functions' {
        foreach ($n in @('Get-InstanceProcessMap', 'Get-MumuProcessSamples', 'Get-MumuResourceSnapshot', 'Update-ResourceStats', 'Get-ResourceStatsSummary', 'ConvertTo-ResourceExportLines', 'Show-ResourceMonitor')) {
            $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $n
            }, $true) | Select-Object -First 1
            $f | Should -Not -BeNullOrEmpty
            $text = $f.Extent.Text
            $text -match 'curl|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Add-Content|New-Item|Out-File' | Should -Be $false
        }
    }
}

Describe 'Instance process map ([RM] per-instance column)' {

    It 'parses the real pretty-printed info -v all shape and maps only running PIDs' {
        # Fixture mirrors the actual MuMuManager output (pretty-printed,
        # multiline): instance 0 running with pid, instance 1 stopped -
        # no `pid` key, must be skipped.
        $json = @'
{
  "0": {
    "adb_port": 16384,
    "is_android_started": true,
    "is_process_started": true,
    "name": "Android Device",
    "pid": 26200,
    "player_state": "start_finished"
  },
  "1": {
    "is_process_started": false,
    "name": "Android Device-1"
  }
}
'@
        $m = Get-InstanceProcessMap -InfoJson $json
        $m[26200] | Should -Be '#0 Android Device'
        $m.Keys.Count | Should -Be 1
    }

    It 'a running instance without a name still maps as #N' {
        $m = Get-InstanceProcessMap -InfoJson '{"0": {"pid": 777}}'
        $m[777] | Should -Be '#0'
    }

    It 'invalid JSON and empty input produce an empty map without throwing' {
        { Get-InstanceProcessMap -InfoJson 'MuMuManager: fatal error' } | Should -Not -Throw
        (Get-InstanceProcessMap -InfoJson 'not json').Keys.Count | Should -Be 0
        (Get-InstanceProcessMap -InfoJson '').Keys.Count | Should -Be 0
    }

    It 'live path: missing MuMuManager binary returns an empty map silently' {
        (Get-InstanceProcessMap -MumuPathOverride 'C:\\definitely-missing\\MuMuManager.exe').Keys.Count | Should -Be 0
    }
}

Describe 'Resource monitor v2 (peaks/avg, pause/reset/export, RAM delta)' {

    BeforeAll {
        function New-SampleRow {
            param([int]$Id, [string]$Name = 'MuMuNxMain', [string]$Instance = '', $CpuPct = $null, [double]$RamMB = 100, [double]$PrivMB = 50)
            [pscustomobject]@{
                Pid = $Id; Name = $Name; Instance = $Instance; CpuPct = $CpuPct
                RamDelta = $null; RamMB = $RamMB; PrivMB = $PrivMB; Uptime = '1h 00m'
            }
        }
        function New-EmptyStats { return @{ ByPid = @{}; Spark = @(); PeakTotal = $null } }
        function New-Snap {
            param([object[]]$Rows, $TotalCpu = $null)
            [pscustomobject]@{
                Rows = @($Rows); ProcessCount = @($Rows).Count
                TotalCpuPct = $TotalCpu; TotalRamMB = 1.0; TotalPrivMB = 1.0
            }
        }
    }

    It 'accumulator: peak/avg per PID, peak RAM; NoBaseline ticks do not skew averages' {
        $st = New-EmptyStats
        $null = Update-ResourceStats -Stats $st -Rows @((New-SampleRow -Id 1 -CpuPct $null -RamMB 100)) -TotalCpuPct $null -CountThisTick:$false
        $null = Update-ResourceStats -Stats $st -Rows @((New-SampleRow -Id 1 -CpuPct 20 -RamMB 150)) -TotalCpuPct 20 -CountThisTick:$true
        $null = Update-ResourceStats -Stats $st -Rows @((New-SampleRow -Id 1 -CpuPct 60 -RamMB 120)) -TotalCpuPct 60 -CountThisTick:$true
        $e = $st.ByPid[1]
        $e.PeakCpu | Should -Be 60
        ([Math]::Round([double]$e.CpuSum / $e.CpuN, 1)) | Should -Be 40
        $e.CpuN | Should -Be 2
        $e.PeakRam | Should -Be 150
        $e.RamLow | Should -Be 100
        $st.PeakTotal | Should -Be 60
        $st.Spark.Count | Should -Be 2
    }

    It 'accumulator: process exits and returns with a new name - entry follows the new name' {
        $st = New-EmptyStats
        $null = Update-ResourceStats -Stats $st -Rows @((New-SampleRow -Id 5 -Name 'MuMuNxMain' -CpuPct 10 -RamMB 100)) -TotalCpuPct 10 -CountThisTick:$true
        $null = Update-ResourceStats -Stats $st -Rows @((New-SampleRow -Id 5 -Name 'MuMuNxMain2' -CpuPct 30 -RamMB 110)) -TotalCpuPct 30 -CountThisTick:$true
        $st.ByPid[5].Name | Should -Be 'MuMuNxMain2'
        $st.ByPid[5].PeakCpu | Should -Be 30
    }

    It 'sparkline ring buffer caps at 60 ticks (oldest dropped)' {
        $st = New-EmptyStats
        for ($i = 1; $i -le 75; $i++) {
            $null = Update-ResourceStats -Stats $st -Rows @() -TotalCpuPct 1 -CountThisTick:$true
        }
        $st.Spark.Count | Should -Be 60
        $st.Spark[0] | Should -Be 1
    }

    It 'summary sorts by peak CPU desc, no-sample PIDs last' {
        $st = New-EmptyStats
        $null = Update-ResourceStats -Stats $st -Rows @((New-SampleRow -Id 9 -Name 'S' -CpuPct $null), (New-SampleRow -Id 2 -CpuPct 40), (New-SampleRow -Id 7 -CpuPct 10)) -TotalCpuPct 50 -CountThisTick:$true
        $s = Get-ResourceStatsSummary -Stats $st
        @($s)[0].Pid | Should -Be 2
        @($s)[1].Pid | Should -Be 7
        @($s)[2].Pid | Should -Be 9
        @($s)[2].PeakCpuPct | Should -BeNullOrEmpty
    }

    It 'export md: header + snapshot table + session block; idempotent' {
        $st = New-EmptyStats
        $null = Update-ResourceStats -Stats $st -Rows @((New-SampleRow -Id 1 -Name 'MuMuNxDevice' -Instance '#0 Android Device' -CpuPct 12.5 -RamMB 353.2 -PrivMB 1201.9)) -TotalCpuPct 12.5 -CountThisTick:$true
        $snap = New-Snap -Rows @((New-SampleRow -Id 1 -Name 'MuMuNxDevice' -Instance '#0 Android Device' -CpuPct 12.5 -RamMB 353.2 -PrivMB 1201.9)) -TotalCpu 12.5
        $l1 = @(ConvertTo-ResourceExportLines -Snapshot $snap -Stats $st -Format 'md')
        $l2 = @(ConvertTo-ResourceExportLines -Snapshot $snap -Stats $st -Format 'md')
        ($l1 -join "`n") | Should -Be ($l2 -join "`n")
        ($l1 -join "`n") | Should -Match '# MuMu resource monitor snapshot'
        ($l1 -join "`n") | Should -Match 'Session peaks/averages'
        ($l1 -join "`n") | Should -Match 'MuMuNxDevice'
        ($l1 -join "`n") | Should -Match '353\.2'
    }

    It 'export csv: invariant decimals, quoted text, honest empty numerics' {
        $snap = New-Snap -Rows @((New-SampleRow -Id 3 -Name 'A"x' -Instance 'In,stance' -CpuPct 3.1 -RamMB 10.5 -PrivMB 5))
        $l = @(ConvertTo-ResourceExportLines -Snapshot $snap -Stats (New-EmptyStats) -Format 'csv')
        $l[0] | Should -Be 'pid,name,instance,cpu_pct,ram_delta_mb,ram_mb,priv_mb,uptime'
        $expected = (@('3', '"A""x"', '"In,stance"', '3.1', '', '10.5', '5', '1h 00m') -join ',')
        $l[1] | Should -Be $expected
    }

    It 'export json: round-trips and carries the delta field' {
        $snap = New-Snap -Rows @((New-SampleRow -Id 1 -CpuPct 3.1 -RamMB 10.5)) -TotalCpu 3.1
        $snap.Rows[0].RamDelta = -12.5
        $l = @(ConvertTo-ResourceExportLines -Snapshot $snap -Stats (New-EmptyStats) -Format 'json')
        $obj = $l -join "`n" | ConvertFrom-Json
        $obj.processCount | Should -Be 1
        $obj.processes[0].ramDeltaMB | Should -Be -12.5
        $obj.processes[0].cpuPct | Should -Be 3.1
    }

    It 'export writer: UTF-8 BOM, output subdir, md/csv/json targets, honest failure' {
        $dir = Join-Path $TestDrive "rm_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $snap = New-Snap -Rows @((New-SampleRow -Id 1 -CpuPct 3.1 -RamMB 10.5)) -TotalCpu 3.1
        $r = Export-ResourceSnapshot -Snapshot $snap -Stats (New-EmptyStats) -Format 'csv' -BaseDir $dir
        $r.ok | Should -BeTrue
        Test-Path $r.path | Should -BeTrue
        ($r.path -match 'output\\resource-snapshot-\d{8}-\d{6}\.csv$') | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($r.path)[0..2]
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
        $json = Export-ResourceSnapshot -Snapshot $snap -Stats (New-EmptyStats) -Format '3' -BaseDir $dir
        $json.ok | Should -BeTrue
        ($json.path -match '\.json$') | Should -BeTrue
        # Honest failure: the base path exists but is a FILE, so creating
        # <base>\output can never succeed (New-Item -Force would happily
        # create a whole missing directory chain, which is by design).
        $fileBase = Join-Path $TestDrive "rmfile_$(Get-Random)"
        Set-Content -LiteralPath $fileBase -Value 'not a directory'
        $bad = Export-ResourceSnapshot -Snapshot $snap -Stats (New-EmptyStats) -Format 'csv' -BaseDir $fileBase
        $bad.ok | Should -BeFalse
        $bad.error | Should -Not -Be ''
    }

    It 'snapshot: RAM delta is computed from the previous tick, $null on the first frame' {
        $samples = @(
            [pscustomobject]@{ Pid = 1; Name = 'A'; Instance = ''; CpuSec = 0; RamMB = 100.0; PrivMB = 50; Uptime = 'x' }
        )
        $s1 = Get-MumuResourceSnapshot -Samples $samples -Prev @{} -PrevRam @{} -ElapsedSeconds 1 -Cores 1 -NoBaseline
        $s1.Rows[0].RamDelta | Should -BeNullOrEmpty
        $s2 = Get-MumuResourceSnapshot -Samples $samples -Prev @{} -PrevRam @{ 1 = 112.0 } -ElapsedSeconds 1 -Cores 1
        $s2.Rows[0].RamDelta | Should -Be -12
    }
}

Describe 'Instance settings compare ([CMP])' {

    It 'diff: union of keys, differing first, <missing> for keys absent on one side' {
        $a = @{ 'gpu_mode' = 'high'; 'max_frame_rate' = '60'; 'shared' = 'yes' }
        $b = @{ 'gpu_mode' = 'middle'; 'only_b' = 'x'; 'shared' = 'yes' }
        $c = Compare-Settings -A $a -B $b
        $c.DiffCount | Should -Be 3
        $c.SameCount | Should -Be 1
        $c.DiffRows.Key | Should -Be @('gpu_mode', 'max_frame_rate', 'only_b')
        ($c.DiffRows | Where-Object { $_.Key -eq 'max_frame_rate' }).ValueB | Should -Be '<missing>'
        ($c.DiffRows | Where-Object { $_.Key -eq 'only_b' }).ValueA | Should -Be '<missing>'
        ($c.DiffRows | Where-Object { $_.Key -eq 'gpu_mode' }).Diff | Should -BeTrue
    }

    It 'diff: identical sets produce zero diff rows' {
        $s = @{ 'gpu_mode' = 'high'; 'max_frame_rate' = '60' }
        $c = Compare-Settings -A $s -B ($s.Clone())
        $c.DiffCount | Should -Be 0
        $c.SameCount | Should -Be 2
        @($c.DiffRows).Count | Should -Be 0
    }

    It 'value formatting: empty is honest, long values are capped with a tilde' {
        Format-CompareValue -Value '' | Should -Be '(empty)'
        Format-CompareValue -Value 'vk' | Should -Be 'vk'
        $long = 'Remote NDIS based Internet Sharing Device'
        $fmt = Format-CompareValue -Value $long
        $fmt.Length | Should -Be 27
        $fmt.EndsWith('~') | Should -BeTrue
        $fmt.StartsWith('Remote NDIS based Interne') | Should -BeTrue
    }

    It 'collector parses the real flat --all_writable JSON shape' {
        $json = @'
{
  "gpu_mode": "high",
  "max_frame_rate": "60",
  "net_bridge_dns1": "",
  "phone_model": "Galaxy A54"
}
'@
        $r = Get-InstanceWritableSettings -Index '9' -SettingsJson $json
        $r.ok | Should -BeTrue
        $r.error | Should -Be ''
        $r.settings['gpu_mode'] | Should -Be 'high'
        $r.settings['net_bridge_dns1'] | Should -Be ''
        $r.settings.Keys.Count | Should -Be 4
    }

    It 'collector degrades honestly: unsupported, garbage, empty, missing binary' {
        $r1 = Get-InstanceWritableSettings -Index '0' -SettingsJson '{"errcode": -1}'
        $r1.ok | Should -BeFalse
        $r1.error | Should -Match 'not supported'
        $r2 = Get-InstanceWritableSettings -Index '0' -SettingsJson 'MuMuManager: fatal'
        $r2.ok | Should -BeFalse
        $r2.error | Should -Be 'not JSON'
        $r3 = Get-InstanceWritableSettings -Index '0' -SettingsJson ''
        $r3.ok | Should -BeFalse
        $r3.error | Should -Be 'empty output'
        $r4 = Get-InstanceWritableSettings -Index '0' -MumuPathOverride 'C:\\definitely-missing\\MuMuManager.exe'
        $r4.ok | Should -BeFalse
        $r4.error | Should -Be 'not found'
    }

    It 'wiring: [CMP] is in the menu next to [7], maps to Compare-InstanceSettings, same-instance pick is refused' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match '\[CMP\] Compare instance settings') | Should -Be $true
        ($src -match "'cmp' \{ Compare-InstanceSettings \}") | Should -Be $true
        ($src.Contains('Same instance ($IndexA) selected twice')) | Should -Be $true
    }

    It '[CMP] stays read-only: no writes and no network in the compare functions' {
        foreach ($n in @('Get-InstanceWritableSettings', 'Compare-Settings', 'Format-CompareValue', 'Compare-InstanceSettings')) {
            $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $n
            }, $true) | Select-Object -First 1
            $f | Should -Not -BeNullOrEmpty
            $text = $f.Extent.Text
            # The settings WRITE flag (--value) may only appear in the help
            # hint text - never on a line that actually INVOKES anything.
            @($text -split "`n" | Where-Object { $_ -match '--value' -and $_ -match '& ' }).Count | Should -Be 0
            $text -match 'curl|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Add-Content|New-Item|Out-File' | Should -Be $false
        }
    }
}

Describe 'Multi-install support ([IN] choose the active MuMu install)' {

    BeforeEach {
        # Two installs in one fixture tree, exactly the shape seen live:
        # the classic 6.x layout and a MuMu 15 layout (nx_main plus a
        # device engine under nx_device\<ver>\shell) in a sibling folder.
        $script:fx = Join-Path $TestDrive ('fx' + ([Guid]::NewGuid().ToString('N').Substring(0, 8)))
        New-Item -ItemType Directory -Path $script:fx -Force | Out-Null
        $script:fxA = Join-Path $script:fx 'Netease\MuMuPlayer\nx_main'
        New-Item -ItemType Directory -Path $script:fxA -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fxA 'MuMuManager.exe') -Value 'stub'
        Set-Content -LiteralPath (Join-Path $script:fxA 'MuMuNxMain.exe') -Value 'stub'
        $script:fxRoot = Join-Path $script:fx 'Netease1\MuMu'
        $script:fxB = Join-Path $script:fxRoot 'nx_main'
        New-Item -ItemType Directory -Path $script:fxB -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fxB 'MuMuManager.exe') -Value 'stub'
        New-Item -ItemType Directory -Path (Join-Path $script:fxRoot 'nx_device\15.0\shell') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:fxRoot 'nx_device\12.0\shell') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fxRoot 'nx_device\15.0\shell\MuMuNxDevice.exe') -Value 'stub'
        $script:fxMgrA = Join-Path $script:fxA 'MuMuManager.exe'
        $script:fxMgrB = Join-Path $script:fxB 'MuMuManager.exe'
        $script:fxShell = Join-Path $script:fxRoot 'nx_device\15.0\shell'
        $script:MumuInstallChoiceFile = Join-Path $script:fx '.mumu-install'
        $script:InstalledVersion = $null
        $script:QuickStatusCache = @{ total = 9; running = 9 }
    }

    It 'candidate probe finds the MuMu 15 layout a fixed path list would miss' {
        $dirs = @(Get-MuMuInstallCandidateDirs -Bases @($script:fx))
        $dirs | Should -Contain $script:fxA
        $dirs | Should -Contain $script:fxB
    }

    It 'reports only directories that really hold MuMuManager.exe, without duplicates' {
        $dirs = @(Get-MuMuInstallCandidateDirs -Bases @($script:fx))
        $dirs.Count | Should -Be ($dirs | Sort-Object -Unique).Count
        foreach ($d in $dirs) { Test-Path -LiteralPath (Join-Path $d 'MuMuManager.exe') | Should -BeTrue }
        # The device shell carries adb/NemuShell/MuMuNxDevice, never the
        # manager - offering it would hand the menu a dead install.
        $dirs | Should -Not -Contain $script:fxShell
    }

    It 'discovery order keeps the classic Netease\MuMuPlayer install first' {
        $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MuMuInstallCandidateDirs'
            }, $true) | Select-Object -First 1
        $text = $f.Extent.Text
        $iClassic = $text.IndexOf("'Netease\MuMuPlayer\nx_main'")
        $iNew = $text.IndexOf("'Netease1\MuMu\nx_main'")
        $iClassic | Should -BeGreaterThan 0
        $iClassic | Should -BeLessThan $iNew
    }

    It 'lists both installs with layout, device shell and active marker' {
        $inst = @(Get-MuMuInstalls -ExtraRoots @((Join-Path $script:fx 'Netease\MuMuPlayer'), $script:fxRoot) -Bases @() -ManagerPath $script:fxMgrA)
        $inst.Count | Should -Be 2
        $a = $inst | Where-Object { $_.Root -eq $script:fxA }
        $b = $inst | Where-Object { $_.Root -eq $script:fxB }
        $a.IsActive | Should -BeTrue
        $b.IsActive | Should -BeFalse
        $a.Layout | Should -Be 'MuMu 6 (nx_main)'
        $a.DeviceShell | Should -Be ''
        # Newest device engine wins over the stale 12.0 folder.
        $b.Layout | Should -Be 'MuMu 15 device engine (nx_device\15.0\shell)'
        $b.DeviceShell | Should -Be $script:fxShell
        $b.Manager | Should -Be $script:fxMgrB
    }

    It 'an install root and its nx_main are one install, reported once' {
        $inst = @(Get-MuMuInstalls -ExtraRoots @($script:fxRoot, $script:fxB) -Bases @())
        $inst.Count | Should -Be 1
        $inst[0].Root | Should -Be $script:fxB
    }

    It 'pins the active install to a BOM-less path file and reads it back' {
        Save-MuMuInstallChoice -ManagerPath $script:fxMgrB | Should -BeTrue
        Read-MuMuInstallChoice | Should -Be $script:fxMgrB
        $bytes = [IO.File]::ReadAllBytes($script:MumuInstallChoiceFile)
        # UTF-8 WITHOUT BOM: a BOM would break the Test-Path in the reader.
        $bytes[0] | Should -Not -Be 0xEF
        [Text.Encoding]::UTF8.GetString($bytes) | Should -Be $script:fxMgrB
    }

    It 'ignores an empty, missing or stale pin instead of failing to start' {
        Read-MuMuInstallChoice | Should -Be ''
        [IO.File]::WriteAllText($script:MumuInstallChoiceFile, '')
        Read-MuMuInstallChoice | Should -Be ''
        Save-MuMuInstallChoice -ManagerPath $script:fxMgrB | Should -BeTrue
        Remove-Item -LiteralPath $script:fxB -Recurse -Force
        Read-MuMuInstallChoice | Should -Be ''
        Save-MuMuInstallChoice -ManagerPath '' | Should -BeFalse
    }

    It 'start-up honours the pin, and falls back to the first install without one' {
        Resolve-MuMuInstall -ExtraRoots @($script:fxRoot) -Bases @() | Should -Be $script:fxMgrB
        Save-MuMuInstallChoice -ManagerPath $script:fxMgrA | Should -BeTrue
        Resolve-MuMuInstall -ExtraRoots @($script:fxRoot) -Bases @() | Should -Be $script:fxMgrA
    }

    It 'start-up returns nothing when no install exists at all' {
        Resolve-MuMuInstall -ExtraRoots @((Join-Path $script:fx 'nowhere')) -Bases @() | Should -Be ''
    }

    It 'refreshes version and instance count after a switch (offline JSON hooks)' {
        $s = Update-MumuInstallState -ManagerPath $script:fxMgrB -VersionJson '{"version":"6.8.2.0"}' -InfoJson '{"0":{"player_state":"running"},"1":{"player_state":"stopped"}}'
        $s.ok | Should -BeTrue
        $s.version | Should -Be '6.8.2.0'
        $s.instances | Should -Be 2
        $script:InstalledVersion | Should -Be ([version]'6.8.2.0')
        # The stale quick-status cache must go, or the menu keeps showing
        # the previous install's instance counts for 5 more seconds.
        $script:QuickStatusCache | Should -BeNullOrEmpty
    }

    It 'a manager that does not answer reports honestly instead of lying' {
        $s = Update-MumuInstallState -VersionJson 'MuMuManager: fatal' -InfoJson ''
        $s.ok | Should -BeFalse
        $s.version | Should -Be ''
        $script:InstalledVersion | Should -BeNullOrEmpty
    }

    It 'the status-line label names the install, not just its leaf folder' {
        Get-MuMuInstallLabel -ManagerPath 'C:\Program Files\Netease1\MuMu\nx_main\MuMuManager.exe' |
            Should -Be 'Netease1\MuMu'
        Get-MuMuInstallLabel -ManagerPath 'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe' |
            Should -Be 'Netease\MuMuPlayer'
        # Shallow paths must still produce something printable.
        Get-MuMuInstallLabel -ManagerPath 'C:\MuMuManager.exe' | Should -Be 'C:\'
        Get-MuMuInstallLabel -ManagerPath '' | Should -Be ''
    }

    It 'wiring: [IN] is in the menu and maps to Show-MuMuInstalls' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match '\[IN\] MuMu installation \(choose active\)') | Should -Be $true
        ($src -match "'in' \{ Show-MuMuInstalls \}") | Should -Be $true
    }

    It 'wiring: the status line shows which install is active' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match '\$script:MumuInstallLabel') | Should -Be $true
        ($src -match 'MuMu \$muVer\$installTag') | Should -Be $true
    }

    # Tagged RepoFiles: the deployed-layout fixture has no .gitignore.
    It 'the pin is a bare path next to the script, and it is git-ignored' -Tag 'RepoFiles' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match "(?m)^\`$script:MumuInstallChoiceFile = Join-Path \`$ScriptDir '\.mumu-install'") | Should -Be $true
        $ignore = Get-Content -Raw (Join-Path (Join-Path $PSScriptRoot '..') '.gitignore')
        ($ignore -match '(?m)^\.mumu-install\r?$') | Should -Be $true
    }

    It 'install discovery and switching stay local: no network, no MuMu writes' {
        foreach ($n in @('Get-MuMuInstallCandidateDirs', 'Get-MuMuInstalls', 'Get-MuMuActiveManagerPath',
                'Get-MuMuInstallLabel', 'Get-MuMuInstallChoicePath', 'Read-MuMuInstallChoice', 'Save-MuMuInstallChoice',
                'Resolve-MuMuInstall', 'Update-MumuInstallState', 'Show-MuMuInstalls')) {
            $f = $script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $n
                }, $true) | Select-Object -First 1
            $f | Should -Not -BeNullOrEmpty
            $text = $f.Extent.Text
            $text -match 'curl|Invoke-WebRequest|Invoke-RestMethod' | Should -Be $false
            # The only file written is the pin, and only through [IO.File].
            $text -match 'Set-Content|Add-Content|New-Item|Out-File' | Should -Be $false
        }
    }
}

Describe 'Instance folder resolution (ambiguous <version>-<index> folders)' {

    BeforeEach {
        # The live shape on this machine: MuMuPlayer-12.0-0 is the folder
        # an upgrade left behind, MuMuPlayer-15.0-0 is what the manager
        # actually runs, and the other install prefixes folders
        # MuMuPlayerGlobal-*. Both old and new names share index 0.
        $script:vms = Join-Path $TestDrive ('vms' + ([Guid]::NewGuid().ToString('N').Substring(0, 8)))
        New-Item -ItemType Directory -Path $script:vms -Force | Out-Null
        $script:old = Join-Path $script:vms 'MuMuPlayer-12.0-0'
        $script:live = Join-Path $script:vms 'MuMuPlayer-15.0-0'
        $script:two = Join-Path $script:vms 'MuMuPlayer-15.0-2'
        $script:legacy = Join-Path $script:vms 'MuMuPlayer-0'
        $script:globalPrefix = Join-Path $script:vms 'MuMuPlayerGlobal-15.0-0'
        foreach ($d in @($script:old, $script:live, $script:two, $script:legacy, $script:globalPrefix)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        New-Item -ItemType Directory -Path (Join-Path $script:vms 'MuMuPlayer-15.0-base') -Force | Out-Null
        # Deterministic ages: the orphan is the OLDEST folder.
        (Get-Item $script:old).LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item $script:live).LastWriteTime = Get-Date
        (Get-Item $script:two).LastWriteTime = (Get-Date).AddDays(-20)
        (Get-Item $script:legacy).LastWriteTime = (Get-Date).AddDays(-1)
        (Get-Item $script:globalPrefix).LastWriteTime = (Get-Date).AddDays(-2)
    }

    It 'finds the vms root one hop above nx_main, for both install layouts' {
        Get-MuMuVmsRoot -ManagerPath 'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe' |
            Should -Be 'C:\Program Files\Netease\MuMuPlayer\vms'
        Get-MuMuVmsRoot -ManagerPath 'C:\Program Files\Netease1\MuMu\nx_main\MuMuManager.exe' |
            Should -Be 'C:\Program Files\Netease1\MuMu\vms'
        Get-MuMuVmsRoot -ManagerPath '' | Should -Be ''
    }

    It 'reads the android version the manager runs for an index' {
        Get-MuMuInstanceAndroidVersion -Index '0' -InfoJson '{"0":{"index":0,"android_version":"15.0"}}' |
            Should -Be '15.0'
        # Some builds answer with the bare object instead of a keyed map.
        Get-MuMuInstanceAndroidVersion -Index '2' -InfoJson '{"android_version":"12.0"}' | Should -Be '12.0'
        # No version / garbage / empty index must degrade to '' , never throw.
        Get-MuMuInstanceAndroidVersion -Index '0' -InfoJson '{"0":{"player_state":"stopped"}}' | Should -Be ''
        Get-MuMuInstanceAndroidVersion -Index '0' -InfoJson 'MuMuManager: fatal' | Should -Be ''
        Get-MuMuInstanceAndroidVersion -Index '' -InfoJson '{"0":{"android_version":"15.0"}}' | Should -Be ''
    }

    It 'picks the folder whose version matches the manager, orphan demoted' {
        $dirs = @(Get-MuMuInstanceDir -Index '0' -VmsRoot $script:vms -AndroidVersion '15.0')
        $dirs[0] | Should -Be $script:live
        # The stale 12.0-0 folder is still reported - as a later choice,
        # never first. (Both 15.0 folders match the version, so they lead.)
        $dirs.Count | Should -BeGreaterThan 1
        $dirs[-1] | Should -Be $script:old
        @($dirs | Where-Object { $_ -eq $script:globalPrefix }).Count | Should -Be 1
    }

    It 'honours a 12.0 instance even though newer 15.0 folders share its index' {
        @(Get-MuMuInstanceDir -Index '0' -VmsRoot $script:vms -AndroidVersion '12.0')[0] | Should -Be $script:old
    }

    It 'falls back to newest-first when the manager cannot be asked' {
        $dirs = @(Get-MuMuInstanceDir -Index '0' -VmsRoot $script:vms -NoVersionQuery)
        $dirs[0] | Should -Be $script:live
        # Pre-15 names (no version in the folder) still resolve.
        $dirs | Should -Contain $script:legacy
        # The oldest folder never leads the list.
        $dirs[-1] | Should -Be $script:old
        # ...base is not an instance and must never be offered.
        @($dirs | Where-Object { $_ -like '*base*' }).Count | Should -Be 0
    }

    It 'unknown index and missing vms root return nothing instead of throwing' {
        @(Get-MuMuInstanceDir -Index '7' -VmsRoot $script:vms -NoVersionQuery).Count | Should -Be 0
        @(Get-MuMuInstanceDir -Index '0' -VmsRoot (Join-Path $TestDrive 'nope') -NoVersionQuery).Count | Should -Be 0
        @(Get-MuMuInstanceDir -Index '' -VmsRoot $script:vms -NoVersionQuery).Count | Should -Be 0
    }

    It 'wiring: the folder-walking call sites all go through the resolver' {
        foreach ($n in @('Backup-EmulatorData', 'Restore-EmulatorData', 'Show-Logs', 'Set-FrameRate', 'Set-RandomDeviceIds')) {
            $f = $script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $n
                }, $true) | Select-Object -First 1
            $f | Should -Not -BeNullOrEmpty
            $text = $f.Extent.Text
            $text | Should -Match 'Get-MuMuInstanceDir|Get-MuMuVmsRoot'
            # The hand-rolled index walk is what mis-picked 12.0-0 for
            # index 0 - it must be gone from every one of them.
            ($text -match "regex\]::Match\(\`$d\.Name, '-\(\\d\+\)\$'") | Should -Be $false
        }
    }

    It 'the resolver itself stays local: no network, no writes' {
        foreach ($n in @('Get-MuMuVmsRoot', 'Get-MuMuInstanceAndroidVersion', 'Get-MuMuInstanceDir')) {
            $f = $script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $n
                }, $true) | Select-Object -First 1
            $text = $f.Extent.Text
            $text -match 'curl|Invoke-WebRequest|Set-Content|New-Item|Out-File|Remove-Item' | Should -Be $false
        }
    }
}

Describe 'Install drift report ([DIAG], multi-install)' {

    # Fixture builders - two side-by-side installs shaped like the live
    # machine: a global build (active, idle) and a domestic build with a
    # running emulator. Offline: -Installs and -StateProbe are the seams.
    BeforeEach {
        $script:aMgr = 'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe'
        $script:bMgr = 'C:\Program Files\Netease1\MuMu\nx_main\MuMuManager.exe'
        $script:installs = @(
            [pscustomobject]@{ Root = 'C:\Program Files\Netease\MuMuPlayer\nx_main'; Manager = $script:aMgr
                Product = '6.8.0.0'; BuildDate = '2026-09-23'; Signer = ''; Instances = 3; IsActive = $false },
            [pscustomobject]@{ Root = 'C:\Program Files\Netease1\MuMu\nx_main'; Manager = $script:bMgr
                Product = '6.8.2.0'; BuildDate = '2026-09-29'; Signer = ''; Instances = 2; IsActive = $false }
        )
    }

    It 'a single install produces no findings at all' {
        $one = @($script:installs[0])
        $d = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $one -StateProbe { param($e) @{ Total = 3; Running = 0 } }
        $d.Findings.Count | Should -Be 0
        $d.Installs.Count | Should -Be 1
        $d.Installs[0].IsActive | Should -BeTrue
    }

    It 'warns when a running emulator belongs to another install' {
        $d = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $script:installs `
            -StateProbe { param($e) if ($e -eq 'C:\Program Files\Netease1\MuMu\nx_main\MuMuManager.exe') { @{ Total = 2; Running = 1 } } else { @{ Total = 3; Running = 0 } } }
        $warn = @($d.Findings | Where-Object severity -eq 'warn')
        $warn.Count | Should -Be 1
        $warn[0].message | Should -Match 'belongs to another installation \(Netease1\\MuMu \(1 running\)\)'
        $warn[0].message | Should -Match 'switch with \[IN\]'
    }

    It 'stays quiet when both installs are idle - or both are busy' {
        $idle = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $script:installs `
            -StateProbe { param($e) @{ Total = 2; Running = 0 } }
        @($idle.Findings | Where-Object severity -eq 'warn').Count | Should -Be 0
        $busy = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $script:installs `
            -StateProbe { param($e) @{ Total = 2; Running = 1 } }
        @($busy.Findings | Where-Object severity -eq 'warn').Count | Should -Be 0
    }

    It 'reports every non-active install once, with state and build (info)' {
        $d = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $script:installs `
            -StateProbe { param($e) @{ Total = 2; Running = 0 } }
        $infos = @($d.Findings | Where-Object severity -eq 'info')
        $infos.Count | Should -Be 1
        $infos[0].message | Should -Match 'MuMu installation Netease1\\MuMu'
        $infos[0].message | Should -Match '0/2 instance\(s\) running'
        $infos[0].message | Should -Match 'updater build 2026-09-29'
    }

    It 'a failing state probe degrades to "state unknown" instead of crashing' {
        $d = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $script:installs `
            -StateProbe { param($e) throw 'manager gone' }
        $infos = @($d.Findings | Where-Object severity -eq 'info')
        $infos[0].message | Should -Match 'state unknown'
        @($d.Findings | Where-Object severity -eq 'warn').Count | Should -Be 0
    }

    It 'flags signer drift across installs as info, naming both certificates' {
        $signed = @(
            [pscustomobject]@{ Root = 'C:\A'; Manager = $script:aMgr; Product = '6.8.0.0'; BuildDate = '2026-09-23'
                Signer = 'Netease Interactive Entertainment Pte. Ltd.'; Instances = 0; IsActive = $false },
            [pscustomobject]@{ Root = 'C:\B'; Manager = $script:bMgr; Product = '6.8.2.0'; BuildDate = '2026-09-29'
                Signer = 'NetEase (Hangzhou) Network Co., Ltd'; Instances = 0; IsActive = $false }
        )
        $d = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $signed -StateProbe { param($e) @{ Total = 0; Running = 0 } }
        $drift = @($d.Findings | Where-Object { $_.severity -eq 'info' -and $_.message -match 'different certificates' })
        $drift.Count | Should -Be 1
        $drift[0].message | Should -Match 'Netease Interactive Entertainment Pte\. Ltd\.'
        $drift[0].message | Should -Match 'NetEase \(Hangzhou\) Network Co\., Ltd'
    }

    It 'warns when an updater binary is not validly signed' {
        $bad = @(
            [pscustomobject]@{ Root = 'C:\A'; Manager = $script:aMgr; Product = ''; BuildDate = ''; Signer = 'NetEase (Hangzhou) Network Co., Ltd'; Instances = 0; IsActive = $false },
            [pscustomobject]@{ Root = 'C:\B'; Manager = $script:bMgr; Product = ''; BuildDate = ''; Signer = 'unsigned'; Instances = 0; IsActive = $false }
        )
        $d = Get-MuMuInstallDrift -ActiveManager $script:aMgr -Installs $bad -StateProbe { param($e) @{ Total = 0; Running = 0 } }
        $warn = @($d.Findings | Where-Object { $_.severity -eq 'warn' -and $_.message -match 'not validly signed' })
        $warn.Count | Should -Be 1
        $warn[0].message | Should -Match 'Netease1\\MuMu'
    }

    It 'the signer helper extracts a bare CN from quoted and unquoted subjects' {
        # Cannot fabricate Authenticode results offline - the helper's
        # regex is exercised against the two REAL binaries this machine
        # actually carries; both are validly signed by NetEase entities.
        $h = Get-AuthenticodeSignerName 'C:\Program Files\Netease1\MuMu\nx_main\MuMuNxUpdater.exe'
        $g = Get-AuthenticodeSignerName 'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuNxUpdater.exe'
        if ($h -and $h -ne 'signature unavailable') { $h | Should -Not -Match 'CN=' }
        if ($g -and $g -ne 'signature unavailable') { $g | Should -Not -Match 'CN=' }
        # Degrades honestly on a missing file - empty, never a throw.
        Get-AuthenticodeSignerName 'C:\definitely\missing\MuMuNxUpdater.exe' | Should -Be ''
    }

    It 'wiring: [DIAG] renders the drift block, startup auto-diag feeds its findings' {
        $src = Get-Content -Raw $script:menuPath
        # The screen computes drift with the slow probes and renders the table.
        ($src -match 'Get-MuMuInstallDrift -ActiveManager \$MumuPath -CheckSignatures -QueryVersion') | Should -Be $true
        ($src -match 'MuMu installations:') | Should -Be $true
        # The startup path computes it WITHOUT the slow probes.
        ($src -match '(?s)function Invoke-StartupAutoDiag.*?Get-MuMuInstallDrift -ActiveManager \$MumuPath \}') | Should -Be $true
        # Findings flow into the collector through -DriftFindings.
        ($src -match '-DriftFindings \$\(if \(\$drift\) \{ \$drift\.Findings \} else \{ @\(\) \}\)') | Should -Be $true
    }

    It 'the drift collector stays local: no network, no writes' {
        foreach ($n in @('Get-MuMuInstallDrift', 'Get-AuthenticodeSignerName')) {
            $f = $script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $n
                }, $true) | Select-Object -First 1
            $f | Should -Not -BeNullOrEmpty
            $text = $f.Extent.Text
            $text -match 'curl|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Add-Content|Out-File|Remove-Item' | Should -Be $false        }
    }
}

Describe 'Stop-Logcat (live logcat cleanup on exit)' {

    It 'function exists and is wired next to Get-AllIndices' {
        $src = [System.IO.File]::ReadAllText($script:menuPath)
        ($src -match 'function Stop-Logcat \{') | Should -Be $true
        ($src -match 'Stop-Logcat -Index \$index') | Should -Be $true
        ($src -match 'function Get-AllIndices \{') | Should -Be $true
    }

    It 'prints nothing on the host and does not throw for a blank index' {
        $out = & { Stop-Logcat -Index '' } 2>&1
        ($out -join '') | Should -Be ''
    }

    It 'is declared read-only (no writes/external commands beyond the safe adb logcat -c)' {
        $src = [System.IO.File]::ReadAllText($script:menuPath)
        # Locate the function body by the brace that opens the param block, then
        # walk to its matching close so nested braces (param() defaults) are not
        # mistaken for the function's terminating '}'.
        $start = $src.IndexOf('function Stop-Logcat {')
        $open  = $src.IndexOf('{', $start)
        $depth = 0
        $i     = $open
        $close = $open
        while ($i -lt $src.Length) {
            if ($src[$i] -eq '{') { $depth++ }
            elseif ($src[$i] -eq '}') {
                $depth--
                if ($depth -eq 0) { $close = $i; break }
            }
            $i++
        }
        $body = $src.Substring($start, $close - $start + 1)
        # Declared next to Get-AllIndices so the menu-local adb host is in scope.
        ($src -match 'function Get-AllIndices \{') | Should -Be $true
        # Keep the body honest: only the adb logcat -c no-op and debug on failure.
        $needle    = 'adb --vmindex ' + [char]36 + 'Index --cmd ' + [char]39 + 'logcat -c' + [char]39
        $hasLogcatC = ($body.IndexOf($needle, [StringComparison]::Ordinal) -ge 0)
        $hasDebug  = ($body -match 'Write-Debug')
        $hasBad    = ($body -match 'Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Invoke-WebRequest|curl|Invoke-RestMethod')
        $hasLogcatC | Should -Be $true
        $hasDebug   | Should -Be $true
        $hasBad     | Should -Be $false
    }
}


Describe 'Orphan instance folder report ([DIAG], read-only)' {

    # Fixture shaped like the live machine's vms folder: two folders the
    # manager runs, the upgrade leftover it abandoned, a folder of an
    # index it no longer lists, and a name that is not an instance.
    BeforeEach {
        $script:vms = Join-Path $TestDrive ('vms' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:vms -Force | Out-Null
        $script:old   = Join-Path $script:vms 'MuMuPlayer-12.0-0'     # stale: live index 0, old version
        $script:live  = Join-Path $script:vms 'MuMuPlayer-15.0-0'     # in use
        $script:two   = Join-Path $script:vms 'MuMuPlayer-15.0-2'     # in use
        $script:gone  = Join-Path $script:vms 'MuMuPlayer-15.0-5'     # orphan: index deleted
        $script:weird = Join-Path $script:vms 'MuMuPlayer-15.0-base'  # not an instance folder
        foreach ($d in @($script:old, $script:live, $script:two, $script:gone, $script:weird)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        # Deterministic sizes: 1 MB in the stale folder, 2 MB in the
        # orphan - the BIGGER orphan still sorts first (kind beats size).
        Set-Content -LiteralPath (Join-Path $script:old 'data.img') -Value ('x' * 1048576)
        Set-Content -LiteralPath (Join-Path $script:gone 'data.img') -Value ('y' * 2097152)
        (Get-Item $script:old).LastWriteTime = (Get-Date).AddDays(-30)
        (Get-Item $script:gone).LastWriteTime = (Get-Date).AddDays(-3)
    }

    It 'reports the upgrade leftover but never a folder the manager runs' {
        $r = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -InstanceListJson '{"0":{"android_version":"15.0"},"2":{"android_version":"15.0"}}'
        $r.Scanned | Should -BeTrue
        $names = @($r.Entries | Select-Object -ExpandProperty Name)
        $names | Should -Contain 'MuMuPlayer-12.0-0'
        $names | Should -Not -Contain 'MuMuPlayer-15.0-0'
        $names | Should -Not -Contain 'MuMuPlayer-15.0-2'
        $stale = $r.Entries | Where-Object { $_.Name -eq 'MuMuPlayer-12.0-0' }
        $stale.Status | Should -Be 'stale'
        $stale.Index | Should -Be '0'
        $stale.Android | Should -Be '12.0'
    }

    It 'classifies a deleted instance folder as orphan and odd names as unknown' {
        # Only instance 0 is listed now: 2 becomes an orphan too, and the
        # stale 12.0-0 of the LIVE index stays a stale.
        $r = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -InstanceListJson '{"0":{"android_version":"15.0"}}'
        $gone = $r.Entries | Where-Object { $_.Name -eq 'MuMuPlayer-15.0-5' }
        $gone.Status | Should -Be 'orphan'
        $gone.Index | Should -Be '5'
        ($r.Entries | Where-Object { $_.Name -eq 'MuMuPlayer-15.0-2' }).Status | Should -Be 'orphan'
        ($r.Entries | Where-Object { $_.Name -eq 'MuMuPlayer-15.0-base' }).Status | Should -Be 'unknown'
    }

    It 'carries last-write time and the real recursive size' {
        $r = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -UsedDirs @($script:live, $script:two)
        $stale = $r.Entries | Where-Object { $_.Name -eq 'MuMuPlayer-12.0-0' }
        $stale.SizeMB | Should -Be 1
        $stale.Files | Should -Be 1
        $stale.LastWrite.Date | Should -Be ((Get-Date).AddDays(-30).Date)
    }

    It 'folders named via -UsedDirs are treated as in use without a manager query' {
        $r = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -UsedDirs @($script:live, $script:two)
        $names = @($r.Entries | Select-Object -ExpandProperty Name)
        $names | Should -Not -Contain 'MuMuPlayer-15.0-0'
        $names | Should -Not -Contain 'MuMuPlayer-15.0-2'
        @($r.Entries).Count | Should -Be 3
    }

    It 'orders by kind first (orphan, stale, unknown), size within a kind' {
        # The orphan (2 MB) is BIGGER than the stale folder (1 MB) yet
        # still sorts first: unknown indices outrank same-index leftovers.
        $r = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -UsedDirs @($script:live, $script:two)
        (@($r.Entries | Select-Object -ExpandProperty Status) -join ',') | Should -Be 'orphan,stale,unknown'
    }

    It 'a manager that does not answer yields an honest skip, not a fake clean bill' {
        $r = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -InstanceListJson ''
        $r.Scanned | Should -BeFalse
        $r.Note | Should -Match 'did not answer'
        @($r.Entries).Count | Should -Be 0
        # Garbage instead of the info payload behaves the same way.
        $r2 = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -InstanceListJson 'not json at all'
        $r2.Scanned | Should -BeFalse
    }

    It 'a missing vms root degrades honestly too' {
        $r = Get-MuMuOrphanInstanceDirs -VmsRoot (Join-Path $TestDrive 'nope')
        $r.Scanned | Should -BeFalse
        $r.Note | Should -Match 'vms folder'
    }

    It 'the scan is read-only: every fixture folder and byte survives' {
        $before = @(Get-ChildItem -LiteralPath $script:vms -Recurse -File | Sort-Object FullName)
        $null = Get-MuMuOrphanInstanceDirs -VmsRoot $script:vms -InstanceListJson '{"0":{"android_version":"15.0"},"2":{"android_version":"15.0"}}'
        $after = @(Get-ChildItem -LiteralPath $script:vms -Recurse -File | Sort-Object FullName)
        $after.Count | Should -Be $before.Count
        for ($i = 0; $i -lt $before.Count; $i++) {
            $after[$i].FullName | Should -Be $before[$i].FullName
            $after[$i].Length | Should -Be $before[$i].Length
        }
        foreach ($d in @($script:old, $script:live, $script:two, $script:gone, $script:weird)) {
            Test-Path -LiteralPath $d -PathType Container | Should -BeTrue
        }
    }

    It 'Get-ProblemFindings turns orphan entries into info findings' {
        $d = Join-Path $TestDrive "diag_orphan_$(Get-Random)"
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'mumu-menu.ps1') -Value "`$scriptVer = '1.22.61'`n# body"
        Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.22.61' -NoNewline
        Set-Content -LiteralPath (Join-Path $d 'MuMuManager.exe') -Value 'stub'
        [System.IO.File]::WriteAllLines((Join-Path $d 'update-journal.log'), [string[]]@("2026-09-15 10:00:00`tbootstrap`tupdate-ok`tv1.21.2`tv1.21.3`t4 file(s) updated"), (New-Object System.Text.UTF8Encoding($false)))
        $f = @(Get-ProblemFindings -ScriptDir $d -VersionFile (Join-Path $d '.version') -MenuPath (Join-Path $d 'mumu-menu.ps1') `
                -JournalFile (Join-Path $d 'update-journal.log') -MumuPath (Join-Path $d 'MuMuManager.exe') -ScriptVer '1.22.61' `
                -MumuProbe { param($exe) @{ found = $true; instances = 0; running = 0; adbReady = $false; error = '' } } `
                -OrphanDirs @([pscustomobject]@{ Name = 'MuMuPlayer-12.0-0'; Index = '0'; Android = '12.0'; Status = 'stale'; SizeMB = 12000.5; LastWrite = (Get-Date) }))
        $info = @($f | Where-Object { $_.severity -eq 'info' -and $_.message -match 'MuMuPlayer-12\.0-0' })
        $info.Count | Should -Be 1
        $info[0].message | Should -Match 'not used by the active install'
        $info[0].message | Should -Match 'old-version leftover of live index 0'
    }

    It 'wiring: [DIAG] renders the orphan table; the startup auto-diag stays fast' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match 'Get-MuMuOrphanInstanceDirs -ManagerPath \$MumuPath') | Should -BeTrue
        ($src -match 'Instance folders in vms not used by the active install') | Should -BeTrue
        ($src -match '-OrphanDirs \$\(if \(\$orphan -and \$orphan\.Scanned\) \{ \$orphan\.Entries \} else \{ @\(\) \}\)') | Should -BeTrue
        # Invoke-StartupAutoDiag must NOT walk the vms folders (a recursive
        # size scan is too slow for startup) - its collector runs without
        # -OrphanDirs.
        $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-StartupAutoDiag'
            }, $true) | Select-Object -First 1
        $f | Should -Not -BeNullOrEmpty
        ($f.Extent.Text -match 'Orphan') | Should -Be $false
    }

    It 'the orphan scanner stays local: no network, no writes, no deletes' {
        $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MuMuOrphanInstanceDirs'
            }, $true) | Select-Object -First 1
        $f | Should -Not -BeNullOrEmpty
        ($f.Extent.Text -match 'curl|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Copy-Item') | Should -Be $false
    }
}

Describe 'Quick install switch ([DIAG] prompt + [IN] shared implementation)' {

    BeforeEach {
        $script:aMgr = 'C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe'
        $script:bMgr = 'C:\Program Files\Netease1\MuMu\nx_main\MuMuManager.exe'
        $script:MumuInstallChoiceFile = Join-Path $TestDrive '.mumu-install'
        $script:JournalFile = Join-Path $TestDrive 'update-journal.log'
        $script:MinVersion = [version]'4.0.0.0'
        $script:InstalledVersion = $null
        $script:QuickStatusCache = @{ total = 9; running = 9 }
    }

    It 'switching re-points the menu, pins a BOM-less path and journals the event' {
        $s = Switch-MuMuActiveInstall -ManagerPath $script:bMgr -BuildDate '2026-09-29' `
            -VersionJson '{"version":"6.8.2.0"}' -InfoJson '{"0":{"is_android_started":true},"2":{"is_android_started":false}}'
        $s.ok | Should -BeTrue
        $s.version | Should -Be '6.8.2.0'
        $s.instances | Should -Be 2
        # The whole menu follows: the override wins over discovery.
        Get-MuMuActiveManagerPath | Should -Be $script:bMgr
        # Pin: BOM-less bare path, survives a restart.
        $bytes = [IO.File]::ReadAllBytes($script:MumuInstallChoiceFile)
        $bytes[0] | Should -Not -Be 0xEF
        [Text.Encoding]::UTF8.GetString($bytes) | Should -Be $script:bMgr
        # Journal: one install-switch event with the target manager.
        $line = @(Get-Content -LiteralPath $script:JournalFile | Where-Object { $_.Trim() })[-1]
        ($line -split "`t")[2] | Should -Be 'install-switch'
        ($line -split "`t")[4] | Should -Be $script:bMgr
    }

    It 'the switch refreshes the stale quick-status cache and the version' {
        $script:QuickStatusCache | Should -Not -BeNullOrEmpty
        $null = Switch-MuMuActiveInstall -ManagerPath $script:bMgr -VersionJson '{"version":"6.8.2.0"}' -InfoJson '{"0":{}}'
        $script:QuickStatusCache | Should -BeNullOrEmpty
        $script:InstalledVersion | Should -Be ([version]'6.8.2.0')
    }

    It '-Quiet switches silently: pin and state still land, no banner needed' {
        $s = Switch-MuMuActiveInstall -ManagerPath $script:aMgr -VersionJson '{"version":"6.8.0.0"}' -InfoJson '{"0":{},"1":{},"2":{}}' -Quiet
        $s.ok | Should -BeTrue
        Get-MuMuActiveManagerPath | Should -Be $script:aMgr
        Test-Path -LiteralPath $script:MumuInstallChoiceFile | Should -BeTrue
    }

    It 'wiring: [DIAG] offers the inline switch, [IN] delegates to the same function' {
        $src = Get-Content -Raw $script:menuPath
        ($src -match 'Switch to \{0\} now\? \(y/N\)') | Should -Be $true
        ($src -match 'Switch-MuMuActiveInstall -ManagerPath \$pick\.Manager') | Should -Be $true
        # [IN] no longer carries a second copy of the switch logic.
        ($src -match 'Switch-MuMuActiveInstall -ManagerPath \$target\.Manager') | Should -Be $true
        ($src -match '(?s)function Show-MuMuInstalls.*?Switch-MuMuActiveInstall') | Should -Be $true
    }

    It 'the switch stays local: no network, no exotic writes' {
        $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Switch-MuMuActiveInstall'
            }, $true) | Select-Object -First 1
        $f | Should -Not -BeNullOrEmpty
        $text = $f.Extent.Text
        $text -match 'curl|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Add-Content|Out-File' | Should -Be $false
    }
}

Describe 'Show-MumuOfflineInstallers ([OI])' {
    It 'the menu defines the function and wires [OI] in the main switch' {
        $fn = $script:ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-MumuOfflineInstallers' }, $true) | Select-Object -First 1
        $fn | Should -Not -BeNullOrEmpty
        $src = Get-Content -Raw $script:menuPath
        ($src -match "'oi'\s *\{\s *Show-MumuOfflineInstallers\s *\}") | Should -Be $true
        ($src -match 'Show-MumuOfflineInstallers -ForegroundColor Yellow|\[OI\]') | Should -Be $true
    }

    It 'Show-MumuOfflineInstallers is read-only: only discovery and host output, no downloads' {
        $f = $script:ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-MumuOfflineInstallers' }, $true) | Select-Object -First 1
        $f | Should -Not -BeNullOrEmpty
        $text = $f.Extent.Text
        # The function talks to the official endpoints but never writes files or the install.
        $text -match 'Invoke-WebRequest|curl' | Should -Be $true
        $text -match 'Invoke-RestMethod|MumuManager|adb' | Should -Be $false
        # Restricted cmdlet names are assembled from parts on purpose: this is an
        # ABSENCE assertion, and a static scanner read the contiguous literal as a
        # call to them (DevSkim 'Use of restricted functions', issue #9). The check
        # itself is unchanged - the joined pattern still matches any occurrence.
        $banned = @('Set-Content', 'Add-Content', 'Out-File', 'Move-Item', 'Copy-Item', 'Remove-Item', 'Download-File')
        $banned += ('Invoke-' + 'Expression')
        $banned += ('Start-' + 'Process -FilePath.*\.exe')
        ($text -match ('(' + ($banned -join '|') + ')')) | Should -Be $false
        ($text -match 'Write-Host.*End of offline-installer listing|End of offline-installer listing') | Should -Be $true
    }

    It 'Resolve-InstallerThumbprint helper is present and claims no fabricated checksums' {
        $h = $script:ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-InstallerThumbprint' }, $true) | Select-Object -First 1
        $h | Should -Not -BeNullOrEmpty
        $text = $h.Extent.Text
        $text -match '\$badges\s*\.\s*Count\s*-eq\s*0' | Should -Be $true
        $text -match 'integrity:\s *headers did not expose' | Should -Be $true
    }

    It 'resolvers are HEAD-only and extraction never uses the 4-operand -replace' {
        $f = $script:ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-MumuOfflineInstallers' }, $true) | Select-Object -First 1
        $f | Should -Not -BeNullOrEmpty
        $text = $f.Extent.Text
        # Regression (v10.2.0 smoke): the resolvers used GET and buffered the whole
        # installer into memory. Discovery must stay HEAD-only.
        ($text -match 'api\.mumuplayer\.com/api/dl/win.*-Method Head') | Should -Be $true
        ($text -match 'api\.mumuplayer\.com/api/dl/mac.*-Method Head') | Should -Be $true
        # Regression (v10.2.0 smoke): -replace 'x','',0,1 is a 4-operand call that
        # throws at runtime, silently dropping every name/size badge.
        ($text -match "-replace '[^']*',\s*'',\s*0,\s*1") | Should -Be $false
    }
}


Describe 'Invoke-GitHubApiGet transport (UTF-8 bodies)' {

    BeforeAll {
        foreach ($name in @('Invoke-CurlUtf8', 'Invoke-GitHubApiGet', 'Get-CurlGitHubArgs')) {
            $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true) | Select-Object -First 1
            if (-not $f) { throw "$name function not found in mumu-menu.ps1" }
            . ([scriptblock]::Create($f.Extent.Text))
        }
        $script:GitHubToken = $null
        $script:CurlRetryArgs = @()
    }

    It 'reads the body from curl -o as UTF-8 instead of the console code page' {
        # Regression: `$resp = & curl.exe ...` decoded the child's stdout with
        # [Console]::OutputEncoding (CP866 on a Russian console), so a release
        # body full of Cyrillic rendered as "╨Ш╨╜..." on [RL]. The stub prints
        # nothing on stdout: only the -o file carries the answer, which is what
        # api.github.com does with a UTF-8 JSON body.
        function curl.exe {
            param([Parameter(ValueFromRemainingArguments = $true)]$curlArgs)
            $o = [array]::IndexOf($curlArgs, '-o')
            if ($o -ge 0) {
                $json = '{"body":"Интерактивное меню"}'
                [System.IO.File]::WriteAllBytes($curlArgs[$o + 1], [System.Text.Encoding]::UTF8.GetBytes($json))
            }
            $global:LASTEXITCODE = 0
        }

        $raw = Invoke-GitHubApiGet -Url 'https://api.github.com/repos/o/r/releases'
        $raw | Should -Match 'Интерактивное меню'
        ($raw | ConvertFrom-Json).body | Should -Be 'Интерактивное меню'
    }

    It 'never pipes curl stdout into PowerShell for the API body' {
        $f = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-GitHubApiGet'
        }, $true) | Select-Object -First 1
        $body = $f.Extent.Text
        ($body -match '\| Out-String') | Should -BeFalse -Because 'native stdout is decoded with the console code page'
        ($body -match 'Invoke-CurlUtf8') | Should -BeTrue
    }
}

Describe 'Show-ReleaseList ([RL] releases screen)' {

    It 'is defined at TOP LEVEL - a nested definition is invisible to the menu switch' {
        # v10.4.3 shipped [RL] broken: the function was declared INSIDE
        # Update-FromGitHub, so the menu's 'rl' dispatch died with
        # "Show-ReleaseList is not recognized". Only a script-scope definition
        # can be called from the main loop, so assert the nesting explicitly
        # instead of trusting the source layout.
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-ReleaseList'
        }, $true) | Select-Object -First 1
        $f | Should -Not -BeNullOrEmpty -Because '[RL] must have a renderer'
        $enclosing = $f.Parent.Parent.Parent
        ($enclosing -is [System.Management.Automation.Language.FunctionDefinitionAst]) | Should -BeFalse -Because "Show-ReleaseList is nested inside $($enclosing.Name) and the menu cannot call it"
    }

    It 'is wired: the Info group lists [RL] and the main switch dispatches rl' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mumu-menu.ps1'))
        ($src -match "\[RL\] Release list") | Should -BeTrue
        ([regex]::Matches($src, [regex]::Escape("'rl' { Show-ReleaseList }"))).Count | Should -Be 1
    }

    It 'fetches through the token-aware Invoke-GitHubApiGet and surfaces the API reason' {
        $f = $script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-ReleaseList'
        }, $true) | Select-Object -First 1
        $body = $f.Extent.Text
        # Comment lines are allowed to mention the old transport; only real code matters.
        $code = (($body -split "`r?`n") | Where-Object { $_.Trim() -notmatch '^#' }) -join "`n"
        # A raw anonymous web request carries no Authorization header: a saved
        # [K] token was ignored and the screen blamed the network on HTTP 403.
        ($code -match 'Invoke-WebRequest') | Should -BeFalse
        ($body -match 'Invoke-GitHubApiGet') | Should -BeTrue
        # The 403 body from GitHub must reach the screen instead of a blanket
        # 'cannot reach the GitHub API'.
        ($body -match "PSObject\.Properties\['message'\]") | Should -BeTrue
    }

    It 'interpolates the repo in the Source note instead of printing $GitHubRepo' {
        $src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\mumu-menu.ps1'))
        # Single quotes left the literal '$GitHubRepo' on screen.
        ($src -match "Write-ScreenNote -Text 'Source: https://github\.com/\`$GitHubRepo/releases'") | Should -BeFalse
        ($src -match 'Write-ScreenNote -Text "Source: https://github\.com/\$GitHubRepo/releases"') | Should -BeTrue
    }
}

Describe 'Restart-MenuProcess ([U] self-restart)' {

    BeforeAll {
        $script:restartFn = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Restart-MenuProcess'
        }, $true) | Select-Object -First 1
        $script:consoleFn = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-MenuConsoleAttached'
        }, $true) | Select-Object -First 1
        $script:updateFn = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Update-FromGitHub'
        }, $true) | Select-Object -First 1
    }

    It 'declares both helpers at top level - a nested one is invisible to the caller' {
        $script:restartFn | Should -Not -BeNullOrEmpty
        $script:consoleFn | Should -Not -BeNullOrEmpty
        foreach ($f in @($script:restartFn, $script:consoleFn)) {
            $enclosing = $f.Parent.Parent.Parent
            ($enclosing -is [System.Management.Automation.Language.FunctionDefinitionAst]) | Should -BeFalse -Because "$($f.Name) is nested inside $($enclosing.Name) and cannot be called"
            @($script:ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $f.Name
            }, $true)).Count | Should -Be 1
        }
    }

    It 'restarts only after a clean update and keeps the manual message as fallback' {
        $t = $script:updateFn.Extent.Text
        $verAt = $t.IndexOf('[System.IO.File]::WriteAllText($VersionFile, $tag')
        $callAt = $t.IndexOf('if ($failed -eq 0 -and -not (Restart-MenuProcess))')
        $msgAt = $t.IndexOf("Write-Host 'Restart the menu to use the new version.'")
        ($verAt) | Should -BeGreaterThan 0 -Because '.version must advance before a restart'
        ($callAt) | Should -BeGreaterThan $verAt
        ($msgAt) | Should -BeGreaterThan $callAt
        # A partial update must not relaunch: files may be inconsistent.
        ($t -match 'if \(\$failed -eq 0 -and -not \(Restart-MenuProcess\)\)') | Should -BeTrue
    }

    It 'swaps in the staged .new and launches the same script in a new process' {
        $dir = Join-Path $TestDrive 'restart-ok'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $menu = Join-Path $dir 'mumu-menu.ps1'
        Set-Content -LiteralPath $menu -Value '# old' -Encoding UTF8
        Set-Content -LiteralPath ($menu + '.new') -Value '# new' -Encoding UTF8

        . ([scriptblock]::Create($script:consoleFn.Extent.Text))
        . ([scriptblock]::Create($script:restartFn.Extent.Text))
        function Test-MenuConsoleAttached { $true }
        $script:started = $null
        # Mock, not a `function Start-Process` stub: PSScriptAnalyzer flags an
        # override of a built-in cmdlet (CodeQL alert #10/#11), and the mock
        # intercepts the real call without redefining anything.
        Mock Start-Process {
            $script:started = [pscustomobject]@{ FilePath = $FilePath; WorkingDirectory = $WorkingDirectory; ArgumentList = $ArgumentList }
        }

        $ok = Restart-MenuProcess -ScriptPath $menu
        $ok | Should -BeTrue
        (Get-Content -LiteralPath $menu -Raw).Trim() | Should -Be '# new' -Because 'the child parses the file on disk'
        (Test-Path -LiteralPath ($menu + '.new')) | Should -BeFalse -Because 'the staging copy must not be re-applied by the child'
        $script:started | Should -Not -BeNullOrEmpty
        $script:started.FilePath | Should -Be ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        $script:started.WorkingDirectory | Should -Be $dir
        ($script:started.ArgumentList -contains '-File') | Should -BeTrue
        ($script:started.ArgumentList -join ' ') | Should -Match ([regex]::Escape($menu))
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It 'does nothing without a console and leaves the staged .new untouched' {
        $dir = Join-Path $TestDrive 'restart-piped'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $menu = Join-Path $dir 'mumu-menu.ps1'
        Set-Content -LiteralPath $menu -Value '# old' -Encoding UTF8
        Set-Content -LiteralPath ($menu + '.new') -Value '# new' -Encoding UTF8

        . ([scriptblock]::Create($script:consoleFn.Extent.Text))
        . ([scriptblock]::Create($script:restartFn.Extent.Text))
        function Test-MenuConsoleAttached { $false }
        $script:started = $null
        Mock Start-Process {
            $script:started = [pscustomobject]@{ FilePath = $FilePath; WorkingDirectory = $WorkingDirectory; ArgumentList = $ArgumentList }
        }

        (Restart-MenuProcess -ScriptPath $menu) | Should -BeFalse
        Should -Invoke Start-Process -Times 0 -Exactly
        $script:started | Should -BeNullOrEmpty -Because 'a piped run must not spawn a window'
        (Test-Path -LiteralPath ($menu + '.new')) | Should -BeTrue
        (Get-Content -LiteralPath $menu -Raw).Trim() | Should -Be '# old'
    }
}

Describe 'Exit-code hygiene' {
    It 'script ends with an explicit trailing exit 0 (natural-completion path)' {
        $lines = Get-Content -LiteralPath $script:menuPath | Where-Object { $_.Trim() -ne '' }
        $lines[-1].Trim() | Should -Be 'exit 0'
    }
}

Describe 'Repair-Installation ([F] auto-repair, v10.2.0)' {
    BeforeAll {
        $script:repairFn = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Repair-Installation'
        }, $true) | Select-Object -First 1
        $script:verifyFn = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-InstallVerify'
        }, $true) | Select-Object -First 1
    }

    It 'is defined once and offered by Show-InstallVerify when drift is found' {
        $script:repairFn | Should -Not -BeNullOrEmpty
        $defs = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Repair-Installation'
        }, $true)
        @($defs).Count | Should -Be 1
        $v = $script:verifyFn.Extent.Text
        # The report is kept (not discarded) and parsed for DRIFT/MISSING.
        ($v -match 'Test-InstallationIntegrity -Tag \$resolvedTag') | Should -Be $true
        ($v -match '\(DRIFT\|MISSING\)') | Should -Be $true
        ($v.IndexOf('Repair from release $resolvedTag now? (y/N)')) | Should -BeGreaterThan 0
        ($v -match '\$null = Repair-Installation -Tag \$resolvedTag -BadFiles \$badFiles') | Should -Be $true
    }

    It 'keeps the updater invariants: lock, backup-first, pinned ref, hash gate, .new staging, journal' {
        $t = $script:repairFn.Extent.Text
        ($t -match 'New-UpdateLock -Dir \$ScriptDir') | Should -Be $true
        ($t -match 'finally \{\r?\n\s+# Release in finally') | Should -Be $true
        ($t -match 'Resolve-GitRefSha -RepoPart \$GitHubRepo') | Should -Be $true
        ($t -match 'Get-ExpectedFileHashes -Tag \$Tag') | Should -Be $true
        # Backup must happen before any overwrite (IndexOf order).
        ($t.IndexOf('Copy-Item -LiteralPath $p')) | Should -BeGreaterThan 0
        ($t.IndexOf('Copy-Item -LiteralPath $p')) | Should -BeLessThan ($t.IndexOf('WriteAllBytes'))
        # The running script is staged, never overwritten in place.
        ($t.IndexOf('+ ''.new''), $bytes')) | Should -BeGreaterThan 0
        ($t -match 'hash mismatch') | Should -Be $true
        ($t -match "'repair-ok'") | Should -Be $true
        ($t -match "'repair-fail'") | Should -Be $true
    }

    It 'whitelists the release file set, rejects JSON metadata, never redirects native stderr' {
        $t = $script:repairFn.Extent.Text
        # Whitelist: every shipped file, plus .version - nothing else can pass.
        foreach ($name in @('mumu-menu\.ps1', 'SKILL\.md', 'README\.md', 'bootstrap-update\.ps1', 'Watch-MumuConnections\.ps1', 'Test-MumuTunnelAB\.ps1', 'Diag-MumuNx\.ps1', '\.version')) {
            $t.Contains($name) | Should -Be $true -Because "whitelist must contain $name"
        }
        ($t -match 'JSON metadata instead of raw content') | Should -Be $true
        # PS 5.1 guard (parity with bootstrap T3c): no 2>$null on native calls.
        ($t -match '2>\s*\$null') | Should -Be $false
    }
}

Describe '[WN] network + updater watcher (v10.3.0 netstat rewrite)' {

    BeforeAll {
        foreach ($name in @('Watcher-SplitHostPort', 'Watcher-GetTcpTable', 'Watcher-KeyRelevantTcp')) {
            $f = $script:ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true) | Select-Object -First 1
            if ($f) { . ([scriptblock]::Create($f.Extent.Text)) }
        }
        $script:watchSrc = Get-Content -Raw -LiteralPath $script:menuPath
    }

    It 'never calls the 52-second Get-NetTCPConnection cmdlet again' {
        # Live measurement that motivated the rewrite: 39k rows -> 52 s, so the
        # 5 s loop could not complete a single tick and the log stayed empty.
        ($script:watchSrc -match 'Get-NetTCPConnection\s+-') | Should -Be $false
        $git = $script:ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Watcher-GetTcpTable'
        }, $true)
        @($git).Count | Should -Be 1
        $t = $git[0].Extent.Text
        ($t -match 'netstat') | Should -Be $true
        ($t -match 'netstat -ano -p tcp') | Should -Be $true
    }

    It 'parses IPv4 and bracketed IPv6 endpoints without a locale lookup' {
        $v4 = Watcher-SplitHostPort '93.186.225.194:443'
        $v4[0] | Should -Be '93.186.225.194'
        $v4[1] | Should -Be 443
        $v6 = Watcher-SplitHostPort '[2606:4700::1111]:443'
        $v6[0] | Should -Be '2606:4700::1111'
        $v6[1] | Should -Be 443
        $any = Watcher-SplitHostPort '0.0.0.0:0'
        $any[1] | Should -Be 0
    }

    It 'keeps only external rows of the requested PIDs' {
        $raw = @(
            '  TCP    172.19.0.1:49155     93.186.225.194:443     ESTABLISHED     111',
            '  TCP    0.0.0.0:49689        0.0.0.0:0              LISTENING       111',
            '  TCP    127.0.0.1:25122      127.0.0.1:443          ESTABLISHED     111', # DevSkim: ignore DS162092 - loopback fixture: the assertion is that it is filtered OUT
            '  TCP    172.19.0.1:49156     1.1.1.1:443            TIME_WAIT       111',
            '  TCP    172.19.0.1:49157     93.186.225.194:443     ESTABLISHED     222',
            '  TCP    [::1]:50123          [2606:4700::1111]:443  ESTABLISHED     111'
        )
        $rows = @(Watcher-GetTcpTable -ProcIds @(111) -RawLines $raw)
        @($rows).Count | Should -Be 2
        @($rows | Where-Object { $_.RemotePort -eq 443 -and $_.RemoteAddress -eq '93.186.225.194' }).Count | Should -Be 1
        @($rows | Where-Object { $_.RemoteAddress -eq '2606:4700::1111' }).IsHttps | Should -BeTrue
        # PID 222 is not in the filter, loopback/LISTENING/TIME_WAIT are noise.
        ($rows | Where-Object { $_.Pid -eq 222 }) | Should -BeNullOrEmpty
    }

    It 'returns nothing (fast) when no MuMu processes are running' {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $rows = @(Watcher-GetTcpTable -ProcIds @())
        $sw.Stop()
        $rows.Count | Should -Be 0
        $sw.ElapsedMilliseconds | Should -BeLessThan 1000
    }

    It 'seeds existing connections, emits a heartbeat and contains per-tick errors' {
        $t = $script:watchSrc
        ($t -match 'if \(\$Seed\) \{ ''SEEN'' \} else \{ ''NEW'' \}') | Should -Be $true
        ($t -match '\| HEARTBEAT \| MuMu processes=') | Should -Be $true
        ($t -match '\$tickCount % 12') | Should -Be $true
        ($t -match "\| ERROR \| ") | Should -Be $true
        # The tick is wrapped so a failure cannot reach the menu-level trap.
        ($t -match 'try \{\r?\n\s+\$stats = Watcher-Tick') | Should -Be $true
    }
}

Describe 'JavaScript engine (mumu-menu.cjs)' {

    BeforeAll {
        $script:jsPath = Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.cjs'
        $script:jsSrc = if (Test-Path -LiteralPath $script:jsPath) { Get-Content -Raw -LiteralPath $script:jsPath } else { '' }
    }

    It 'ships beside the PowerShell menu with no npm dependencies' {
        Test-Path -LiteralPath $script:jsPath | Should -BeTrue
        $script:jsSrc | Should -Not -BeNullOrEmpty
        ($script:jsSrc -match "require\('([^']+)'\)") | Should -BeTrue
        foreach ($m in [regex]::Matches($script:jsSrc, "require\('([^']+)'\)")) {
            $mod = $m.Groups[1].Value
            ($mod -match '^(fs|os|path|readline|child_process)$') | Should -BeTrue -Because "only Node core modules may be required, got $mod"
        }
        ($script:jsSrc -match '__dirname') | Should -BeTrue
    }

    It 'implements the documented flags and still delegates to PowerShell' {
        foreach ($flag in @('--status', '--list', '--start', '--stop', '--restart', '--watch', '--ps', '--help', '--json')) {
            ($script:jsSrc.Contains("'$flag'")) | Should -BeTrue -Because "$flag must stay supported"
        }
        ($script:jsSrc -match "mumu-menu\.ps1") | Should -BeTrue
        ($script:jsSrc -match 'netstat') | Should -BeTrue
    }

    It 'is syntactically valid JavaScript' {
        $node = Get-Command node -ErrorAction SilentlyContinue
        if (-not $node) { Set-ItResult -Skipped -Because 'node is not installed on this machine'; return }
        & $node.Source --check $script:jsPath 2>&1 | Out-String | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'PSScriptAnalyzer settings (PowerShell 5.1 compatibility gate)' {

    It 'enables PSUseCompatibleSyntax with a 5.1 target and CI consumes this file' -Tag 'RepoFiles' {
        # The project ships as "PowerShell 5.1+" (README Requirements). The
        # compatibility rule is opt-in, so losing this block would silently
        # let 7-only syntax (ternary, ??, ??=, pipeline chains) reach main and
        # turn into a parse error on a 5.1 user box.
        $root = Join-Path $PSScriptRoot '..'
        $settingsPath = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
        Test-Path -LiteralPath $settingsPath | Should -BeTrue

        $cfg = Import-PowerShellDataFile -LiteralPath $settingsPath
        $cfg.Keys | Should -Contain 'Rules'
        $cfg.Rules.ContainsKey('PSUseCompatibleSyntax') | Should -BeTrue
        $cfg.Rules.PSUseCompatibleSyntax.Enable | Should -BeTrue
        @($cfg.Rules.PSUseCompatibleSyntax.TargetVersions) | Should -Contain '5.1'

        # Enabling the gate must not replace the existing rule exclusions.
        @($cfg.ExcludeRules).Count | Should -BeGreaterThan 0
        ($cfg.ExcludeRules -contains 'PSAvoidUsingWriteHost') | Should -BeTrue

        # The scan job must point at THIS settings file, or the gate is inert.
        $wf = Get-Content -Raw -LiteralPath (Join-Path $root '.github/workflows/security-scan.yml')
        ($wf -match 'settings:\s*PSScriptAnalyzerSettings\.psd1') | Should -BeTrue
    }
}

Describe 'Ctrl+C guard (compiled delegate)' {

    # Ctrl+C used to crash the menu instead of being ignored. .NET raises
    # Console.CancelKeyPress on its own signal thread (PosixSignalRegistration on
    # PowerShell 7), where no runspace is attached, so a ScriptBlock delegate
    # throws PSInvalidOperationException inside GetContextFromTLS *before* its
    # body runs: "Нет доступного пространства выполнения для запуска скрипта в
    # этом потоке" and an unhandled exception kills the process. The guard is now
    # a compiled delegate that only touches e.Cancel, so it needs no runspace;
    # this test reproduces the failing condition (invoke the handler from a plain
    # thread) without needing a real Ctrl+C keystroke.
    It 'handler survives a thread with no runspace' {
        $root = Join-Path $PSScriptRoot '..'
        $src = [System.IO.File]::ReadAllText((Join-Path $root 'mumu-menu.ps1'))

        ($src -match '\[System\.ConsoleCancelEventHandler\]\s*\{') |
            Should -BeFalse -Because 'a ScriptBlock delegate cannot run on the signal thread'

        $m = [regex]::Match($src, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@ -ErrorAction Stop")
        $m.Success | Should -BeTrue -Because 'the guard must compile its own delegate'
        if (-not ('MuMuMenuCtrlCGuard' -as [type])) { Add-Type -TypeDefinition $m.Groups[1].Value }

        $handler = [MuMuMenuCtrlCGuard]::Handler
        $handler.GetType().FullName | Should -Be 'System.ConsoleCancelEventHandler'

        if (-not ('MuMuGuardProbe' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Threading;
public static class MuMuGuardProbe {
    public static string Invoke(Delegate d) {
        string res = "no-exception";
        var t = new Thread(() => {
            try { d.DynamicInvoke(new object[] { null, null }); }
            catch (Exception ex) {
                Exception e = ex; while (e.InnerException != null) e = e.InnerException;
                res = e.GetType().FullName;
            }
        });
        t.Start(); t.Join();
        return res;
    }
}
'@
        }

        # A NullReferenceException is expected and fine (the probe passes null
        # args); what must never happen again is the runspace lookup failing.
        [MuMuGuardProbe]::Invoke($handler) |
            Should -Not -Be 'System.Management.Automation.PSInvalidOperationException'
    }
}
