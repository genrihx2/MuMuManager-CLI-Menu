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
                        'Get-JournalArrow', 'Show-UpdateJournal')) {
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
