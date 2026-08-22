# PowerShell Profile for MuMuManager CLI
# Add this to your PowerShell profile or run this file to add the alias

# Create function alias
function mumu {
    param([Parameter(Position=0)]$Command, [Parameter(ValueFromRemainingArguments)]$MumuArgs)
    
    $scriptPath = Join-Path $PSScriptRoot "mumu-cli.ps1"
    if (Test-Path $scriptPath) {
        & $scriptPath $Command @MumuArgs
    } else {
        Write-Error "mumu-cli.ps1 not found at $scriptPath"
    }
}

# Export alias
Set-Alias -Name mumu -Value mumu