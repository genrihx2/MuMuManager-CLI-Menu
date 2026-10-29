param(
    [string]$Script = 'C:\ggggggg\mumu-manager-cli\mumu-menu.ps1'
)
try {
    $b = [System.IO.File]::ReadAllBytes($Script)
    $t = [System.Text.Encoding]::UTF8.GetString($b)
} catch {
    Write-Host "ERR: $_"
    exit 1
}
$pat = 'function (Show-ReleaseList|Show-ReleaseFetchFailure)'
if ($t -match $pat) {
    Write-Host 'MATCH:' $Matches[0]
}
$at = $t.IndexOf('function Show-ReleaseList {')
Write-Host 'AT=' + $at
$nt = $t.IndexOf('function Show-ReleaseFetchFailure {', $at + 10)
Write-Host 'NT=' + $nt
if ($at -ge 0 -and $nt -gt 0) {
    $seg = $t.Substring($at, $nt - $at)
    $seg | Out-File -Encoding UTF8 'C:\ggggggg\mumu-manager-cli\rl-body.txt'
    Write-Host ('LEN=' + $seg.Length)
}
