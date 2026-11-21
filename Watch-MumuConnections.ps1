#requires -Version 5.1
<#
.SYNOPSIS
    Lightweight diagnostic watcher for MuMu-related TCP connections.

.DESCRIPTION
    Polls the OS TCP table every N seconds (default 5) and appends to a log file
    ONLY newly appeared connections of processes matching the name pattern
    (default 'MuMu*'). Read-only for the network stack: it never modifies VPN,
    proxy, adapter or firewall settings. The only thing it writes is a local
    text log (-LogPath, default %TEMP%\mumu-connections.log), one line per
    connection episode (who -> where, when), with no repeated lines for
    long-lived connections; -NoLog skips that file entirely. If the same
    5-tuple reappears later (a reconnect), it is logged again with the new
    timestamp. Ctrl+C stops the watcher gracefully.

.PARAMETER IntervalSec
    Poll interval in seconds. Default: 5.

.PARAMETER LogPath
    Log file path. Default: %TEMP%\mumu-connections.log

.PARAMETER ProcessPattern
    Wildcard pattern for process names to watch. Default: 'MuMu*'
    (covers MuMuPlayer.exe, MuMuNxMain.exe, MuMuNxUpdater.exe, MuMuVMMHeadless.exe, ...)

.PARAMETER States
    TCP states to log. Default: 'Established'.
    Example: -States Established,Listen to also see who is listening.

.PARAMETER MaxTicks
    Stop after this many polls (0 = run until Ctrl+C). Used for smoke tests.

.PARAMETER LogExisting
    Also log connections that already exist at startup. By default the first
    poll only seeds the dedup set, so the log contains just genuinely new
    connections observed after the start.

.PARAMETER NoLog
    Console only: print new connections but never write the log file. The log
    path is not created and -LogPath is ignored, so the run leaves nothing on
    disk.

.EXAMPLE
    .\Watch-MumuConnections.ps1
.EXAMPLE
    .\Watch-MumuConnections.ps1 -IntervalSec 2 -MaxTicks 2      # smoke test
.EXAMPLE
    .\Watch-MumuConnections.ps1 -States Established,Listen -LogExisting
.EXAMPLE
    .\Watch-MumuConnections.ps1 -NoLog -MaxTicks 2      # console only, nothing on disk
#>
[CmdletBinding()]
param(
    [int]$IntervalSec = 5,
    [string]$LogPath = (Join-Path -Path $env:TEMP -ChildPath 'mumu-connections.log'),
    [string]$ProcessPattern = 'MuMu*',
    [string[]]$States = @('Established'),
    [int]$MaxTicks = 0,
    [switch]$LogExisting,
    [switch]$NoLog
)

Set-StrictMode -Version Latest

function Get-Timestamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

function Add-WatchLine {
    # The single write path. -NoLog is honoured here and nowhere else, so a
    # console-only run cannot leak a log file through a second Add-Content.
    param([string]$Line)
    if ($NoLog) { return }
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value $Line
}

Add-WatchLine -Line (
    "# watch start {0} | pattern '{1}' | states: {2}" -f (Get-Timestamp), $ProcessPattern, ($States -join ',')
)

$logDisplay = if ($NoLog) { 'не пишется (-NoLog)' } else { $LogPath }
Write-Host 'Монитор MuMu-подключений: сеть только читается, VPN/прокси/адаптеры не меняются.'
Write-Host ('  Интервал опроса : {0} с' -f $IntervalSec)
Write-Host ('  Лог             : {0}' -f $logDisplay)
Write-Host ("  Остановка       : Ctrl+C")
Write-Host ""

$seen  = [System.Collections.Generic.HashSet[string]]::new()
$ticks = 0

try {
    while ($true) {
        $rows = @(Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Where-Object { $States -contains $_.State })

        # Resolve process names once per tick for the PIDs actually present.
        $procMap = @{}
        $procIds = @($rows | Select-Object -ExpandProperty OwningProcess -Unique)
        foreach ($procId in $procIds) {
            $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($null -ne $proc) {
                $procMap[$procId] = $proc.ProcessName
            }
        }

        $matched = @($rows | Where-Object {
            $procMap.ContainsKey($_.OwningProcess) -and $procMap[$_.OwningProcess] -like $ProcessPattern
        } | Sort-Object -Property RemoteAddress, RemotePort, LocalPort)

        $newLines = @()
        $seeding  = ($ticks -eq 0 -and -not $LogExisting)

        foreach ($row in $matched) {
            $key = '{0}:{1}->{2}:{3}#{4}' -f $row.LocalAddress, $row.LocalPort,
                $row.RemoteAddress, $row.RemotePort, $row.OwningProcess
            if (-not $seen.Contains($key)) {
                $null = $seen.Add($key)
                if (-not $seeding) {
                    $newLines += ('{0} | {1} (pid {2}) | {3}:{4} -> {5}:{6}' -f
                        (Get-Timestamp), $procMap[$row.OwningProcess], $row.OwningProcess,
                        $row.LocalAddress, $row.LocalPort, $row.RemoteAddress, $row.RemotePort)
                }
            }
        }

        foreach ($line in $newLines) {
            Add-WatchLine -Line $line
            Write-Host ("  + " + $line) -ForegroundColor Green
        }

        if ($newLines.Count -eq 0) {
            Write-Host ("{0}  новых подключений нет (активных: {1})" -f (Get-Timestamp), $matched.Count) -ForegroundColor DarkGray
        }

        $ticks++
        if ($MaxTicks -gt 0 -and $ticks -ge $MaxTicks) {
            Write-Host ("Достигнут лимит опросов ({0})." -f $MaxTicks)
            break
        }
        Start-Sleep -Seconds $IntervalSec
    }
}
finally {
    Add-WatchLine -Line ("# watch stop {0}" -f (Get-Timestamp))
    if ($NoLog) {
        Write-Host 'Остановлено. Лог не писался (-NoLog).'
    } else {
        Write-Host ("Остановлено. Лог: {0}" -f $LogPath)
    }
}
