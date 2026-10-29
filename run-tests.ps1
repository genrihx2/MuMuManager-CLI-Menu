Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.7.1 -Force
$r = Invoke-Pester -Path 'C:\ggggggg\mumu-manager-cli\tests\mumu-menu.Tests.ps1' -PassThru
Write-Host ('TOTAL: ' + $r.Summary.TotalCount)
Write-Host ('PASSED: ' + $r.Summary.PassedCount)
Write-Host ('FAILED: ' + $r.Summary.FailedCount)
Write-Host ('SKIPPED: ' + $r.Summary.SkippedCount)
