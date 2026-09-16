#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Pester unit tests for mumu-menu.ps1 pure helpers (issue #20).
# The functions are extracted from the script via AST - exactly the
# production code, no copies - and tested offline (no network, no
# emulator). Wired into CI as a separate step in tests.yml.
#
# Run locally:
#   pwsh:  Invoke-Pester -Path tests/mumu-menu.Tests.ps1 -CI
#   PS5.1: powershell -ExecutionPolicy Bypass -File tests/run-pester.ps1

BeforeAll {
    $script:menuPath = Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1'
    $errs = $null
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:menuPath, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) { throw "mumu-menu.ps1 has syntax errors: $($errs[0].Message)" }

    # Dot-source each function directly in the BeforeAll scope so the
    # definitions stay visible to every It (dot-sourcing inside a helper
    # function would scope them to the helper and lose them).
    foreach ($name in @('Get-ContentHash', 'ConvertTo-ShellSafe', 'Compare-ScriptVersion',
                        'Format-JournalEvent', 'Test-ReleaseZip', 'Write-UpdateJournal', 'Test-ScriptVerMatchesTag',
                        'Get-JournalArrow', 'Show-UpdateJournal',
                        'Test-UpdateLockStale', 'Get-UpdateLockMessage', 'New-UpdateLock', 'Remove-UpdateLock',
                        'ConvertTo-JournalMarkdown', 'ConvertTo-JournalCsv', 'ConvertTo-JournalJson', 'Export-UpdateJournal',
                        'Get-ProblemFindings', 'Get-InstallStatus', 'Get-IntegrityVerdict', 'Invoke-MumuManagerProbe',
                        'Get-BackupFolders', 'Build-RollbackPlan', 'Invoke-Rollback', 'Test-CurlCapability',
                        'Get-AutoDiagSummary', 'Invoke-StartupAutoDiag', 'Show-AutoDiagLine',
                        'Read-EtagCacheFile', 'Get-EtagCacheFileState', 'Save-EtagCacheFile', 'Invoke-EtagCacheMaintenance')) {
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
                    'SKILL.md'             = "# skill`n"
                    'README.md'            = "# readme`n"
                    'bootstrap-update.ps1' = "# updater`n"
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
        @($r.Checks) | Should -Contain 'file set: OK (5 files)'
    }

    It 'fails a tampered ZIP on the sha256 check' {
        $zip = Join-Path $script:zDir 'tampered-v1.20.0.zip'
        New-ZipFixture -Path $zip
        Copy-Item -LiteralPath $zip -Destination "$zip.t2" -Force
        $bytes = [System.IO.File]::ReadAllBytes("$zip.t2"); $bytes[100] = $bytes[100] -bxor 0xFF
        [System.IO.File]::WriteAllBytes("$zip.t2", $bytes)
        $r = Test-ReleaseZip -ZipPath "$zip.t2" -ExpectedTag 'v1.20.0'
        $r.Ok | Should -BeFalse
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
        @($f | Where-Object { $_.message -match '1 update-skipped' }).Count | Should -Be 1
        [System.IO.File]::WriteAllBytes($jr, (New-Object byte[] 300000))
        $f2 = Invoke-Diag -Dir $d
        @($f2 | Where-Object { $_.message -match 'rotate to \.old' }).Count | Should -Be 1
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

    It 'the diagnostics screen is wired into the menu' {
        $raw = Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'mumu-menu.ps1') -Raw -Encoding UTF8
        $raw | Should -Match "\[DIAG\] Problem diagnostics"
        $raw | Should -Match "'diag' \{ Show-ProblemDiagnostics \}"
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
        $m[0].Groups[1].Value | Should -Be '"8fb013c179ebd7146fe486203162019386f7fb6c"'
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
            'https://x/tampered' = [pscustomobject]@{ etag = 'W/bad'; body = 'evil body'; sha256 = '0000000000000000000000000000000000000000000000000000000000000000'; timestamp = '2026-09-16 10:00:00' }
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
            Set-Content -LiteralPath (Join-Path $d 'SKILL.md') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d 'README.md') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d 'bootstrap-update.ps1') -Value 'x'
            Set-Content -LiteralPath (Join-Path $d '.version') -Value 'v1.21.7' -NoNewline
            return $d
        }
        function New-RbBackup {
            param([string]$InstallDir, [string]$Ver = '1.20.9', [string]$Stamp = '20260915_120000', [switch]$Incomplete)
            $b = Join-Path (Join-Path $InstallDir 'backup') $Stamp
            New-Item -ItemType Directory -Path $b -Force | Out-Null
            if (-not $Incomplete) {
                Set-Content -LiteralPath (Join-Path $b 'mumu-menu.ps1') -Value "`$scriptVer = '$Ver'"
                Set-Content -LiteralPath (Join-Path $b 'SKILL.md') -Value 'x'
                Set-Content -LiteralPath (Join-Path $b 'README.md') -Value 'x'
                Set-Content -LiteralPath (Join-Path $b 'bootstrap-update.ps1') -Value 'x'
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
        $plan.Files.Count | Should -Be 4
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
        $adbBat = "@echo off`r`necho List of devices attached`r`necho 127.0.0.1:16384`tdevice`r`n"
        [System.IO.File]::WriteAllText($fakeAdb, $adbBat)
        # A MuMuManager stub reporting a running instance without adb_version
        $stub = Join-Path $d 'MuMuManager.cmd'
        [System.IO.File]::WriteAllText((Join-Path $d 'mu-stub-out.txt'), '{"0":{"player_state":"start_finished","adb_host_ip":"127.0.0.1","adb_port":16384}}')
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
        @($f | Where-Object { $_.area -eq 'emulator' -and $_.message -match '1 of 1 instance' }).Count | Should -Be 1
    }

    It 'diagnostics stay quiet for a healthy running instance with ADB ready' {
        $exe = New-MumuStub -Dir $script:emuDir -Json '{"0":{"player_state":"started","adb_version":"1.0.41"}}'
        $f = Invoke-Diag2 -Dir $script:emuDir -MumuExe $exe -Probe $script:emuProbe
        @($f | Where-Object { $_.severity -eq 'error' -or $_.severity -eq 'warn' }).Count | Should -Be 0
        @($f | Where-Object { $_.area -eq 'emulator' -and $_.message -match '1 of 1 instance\(s\) running' }).Count | Should -Be 1
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
