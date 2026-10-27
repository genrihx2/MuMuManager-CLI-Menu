param(
    [string]$ScriptPath = 'mumu-menu.ps1',
    [string[]]$Names = @('Get-AdbIp','Get-AdbPort','Connect-ADBDevice','Get-AdbDeviceInfo','Invoke-QuickADBSelect')
)

$script = Get-Content -Raw $ScriptPath
$errors = @()
$ast = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host 'PARSE-ERRORS:'
    $errors | ForEach-Object { Write-Host ('  ' + $_.Message) }
    exit 1
}

$found = @()
$ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Names -contains $n.Name
}, [ref]$found)

if ($found.Count -eq 0) {
    Write-Host 'MISSING'
    exit 1
}

$found | ForEach-Object { Write-Host ('FOUND: ' + $_.Name) }
