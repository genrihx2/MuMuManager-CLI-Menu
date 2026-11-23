#requires -Version 5.1
<#
.SYNOPSIS
    Runs PSScriptAnalyzer over the repository and writes a SARIF 2.1.0 file.

.DESCRIPTION
    Code scanning used to come from microsoft/psscriptanalyzer-action, which
    pipes Invoke-ScriptAnalyzer straight into ConvertToSARIF. On the runner that
    pipeline died with "Object reference not set to an instance of an object"
    and produced no results.sarif at all, so the workflow reported "the scan did
    not run" instead of findings - and the alerts it had uploaded before stayed
    open because nothing newer was ever published.

    This script does the same two steps without the converter: it analyses every
    tracked script one at a time (so a crash names the file instead of the whole
    pipeline) and serialises the diagnostics as SARIF itself. Nothing here
    depends on a module other than PSScriptAnalyzer.
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$SettingsPath = '',
    [string]$OutFile = 'results.sarif'
)

$ErrorActionPreference = 'Stop'
Import-Module PSScriptAnalyzer -ErrorAction Stop

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
if (-not $SettingsPath) { $SettingsPath = Join-Path $Root 'PSScriptAnalyzerSettings.psd1' }
if (-not (Test-Path -LiteralPath $SettingsPath)) { throw "settings not found: $SettingsPath" }

Write-Host "PSScriptAnalyzer $((Get-Module PSScriptAnalyzer).Version)"

# Same scope as the action: the whole tree, minus VCS metadata, dependencies
# and local tool caches. One call keeps this fast; the per-file fallback below
# only runs when that call throws, so the failing file is named in the log.
$skip = '[\\/](\.git|node_modules|\.tools|\.cloud-attachments)[\\/]'
$diagnostics = @()
try {
    # No -Exclude here: PSScriptAnalyzer 1.25 throws a NullReferenceException for
    # this tree when -Exclude is combined with -Recurse, which is the same shape
    # of failure the runner reported.
    $diagnostics = @(Invoke-ScriptAnalyzer -Path $Root -Recurse -Settings $SettingsPath)
} catch {
    Write-Host "::warning::tree scan threw: $($_.Exception.Message) - retrying per file to name the offender"
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch $skip } |
            Sort-Object FullName)
    Write-Host "scanning $($files.Count) file(s)"
    $diagnostics = @()
    foreach ($file in $files) {
        try {
            $diagnostics += @(Invoke-ScriptAnalyzer -Path $file.FullName -Settings $SettingsPath)
        } catch {
            Write-Host "::error file=$($file.Name)::PSScriptAnalyzer threw on $($file.FullName): $($_.Exception.Message)"
            throw
        }
    }
}
Write-Host "findings: $($diagnostics.Count)"
foreach ($d in $diagnostics) {
    Write-Host ("  {0}  {1}:{2}  {3}" -f $d.RuleName, $d.ScriptName, $d.Line, $d.Message)
}

function ConvertTo-RelativeUri {
    param([string]$FullPath)
    $rel = $FullPath.Substring($Root.Length).TrimStart('\', '/')
    return ($rel -replace '\\', '/')
}

# Minimal SARIF 2.1.0 that code scanning accepts: one run, the rules that
# actually fired, one result per diagnostic.
$ruleIds = @($diagnostics | ForEach-Object { $_.RuleName } | Sort-Object -Unique)
$rules = @()
foreach ($id in $ruleIds) {
    $sample = $diagnostics | Where-Object { $_.RuleName -eq $id } | Select-Object -First 1
    $rules += [ordered]@{
        id               = $id
        shortDescription = [ordered]@{ text = [string]$sample.Message }
    }
}

$results = @()
foreach ($d in $diagnostics) {
    $level = switch ([string]$d.Severity) {
        'Error' { 'error' }
        'Information' { 'note' }
        default { 'warning' }
    }
    $results += [ordered]@{
        ruleId    = [string]$d.RuleName
        level     = $level
        message   = [ordered]@{ text = [string]$d.Message }
        locations = @(
            [ordered]@{
                physicalLocation = [ordered]@{
                    artifactLocation = [ordered]@{ uri = (ConvertTo-RelativeUri $d.ScriptPath) }
                    region           = [ordered]@{ startLine = [int]$d.Line }
                }
            }
        )
    }
}

$sarif = [ordered]@{
    '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
    version   = '2.1.0'
    runs      = @(
        [ordered]@{
            tool    = [ordered]@{ driver = [ordered]@{ name = 'PSScriptAnalyzer'; rules = @($rules) } }
            results = @($results)
        }
    )
}

$json = $sarif | ConvertTo-Json -Depth 12
$outPath = if ([IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path (Get-Location) $OutFile }
[IO.File]::WriteAllText($outPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "wrote $outPath ($((Get-Item $outPath).Length) bytes, $($diagnostics.Count) result(s))"
