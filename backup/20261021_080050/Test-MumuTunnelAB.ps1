#requires -Version 5.1
<#
.SYNOPSIS
    A/B diagnostic for MuMu networking: capture snapshots and diff them
    to see exactly what changes when the VPN/accelerator tunnel is toggled.

.DESCRIPTION
    READ-ONLY. The script NEVER enables/disables adapters, NEVER edits routes,
    proxies or VPN settings. You toggle the tunnel manually between snapshots;
    the script only records and compares.

    One snapshot captures:
      - TCP connections of MuMu processes (MuMu*) with resolved owner names
      - Local source addresses in use (LAN IP vs tunnel fake-IP 198.18.*)
      - IPv4 routes: default routes, 198.18.* fake-IP routes, and a recursive
        lookup for every unique MuMu destination IP
      - Active network adapters
      - WinINET proxy state

    Compare mode aligns snapshots A and B and reports:
      - New / gone TCP destinations per process
      - Which connections moved off/on the tunnel (local source address change)
      - Added / removed routes (any change in default, fake-IP or MuMu destinations)
      - Proxy changes

    Log lines follow the same compact format as Watch-MumuConnections.ps1:
      '2026-09-27 10:15:00 | MuMuNxMain (pid 123) | 198.18.0.1:51000 -> 34.36.47.246:443'

    Every snapshot also identifies the OWNER of the Wintun tunnel adapter
    (read-only): it finds the Up '*Wintun*' adapter, resolves who listens on
    the classic proxy-core ports (SOCKS 10808/10809, mihomo 7890-7893),
    walks each owner's parent process chain and records path + command line.
    If none of the owners is a MuMu process, the snapshot warns that the
    MuMu tunnel toggle does not control this adapter (field case: the owner
    was INCY, a system-wide TUN proxy). Nothing is ever killed or changed.

.PARAMETER Capture
    Capture a snapshot. -Label marks it (A or B is conventional).

.PARAMETER NoOwnerLookup
    Skip the tunnel-owner identification (faster, e.g. in loops).

.PARAMETER Label
    Snapshot label, e.g. -Label A (default 'A').

.PARAMETER List
    List stored snapshots and exit.

.PARAMETER Compare
    Compare two snapshots: -Compare A,B (order matters: A = before, B = after).
    Accepts both '-Compare A,B' (array) and "-Compare 'A,B'" (quoted).

.PARAMETER Watch
    Arms the watcher: loads snapshot -Label (default 'A'), polls the 198.18.*
    fake-IP routes every -IntervalSec seconds and, the moment they disappear
    or reappear (you toggle the tunnel), captures snapshot B automatically
    and prints the diff report against the stored snapshot.

.PARAMETER IntervalSec
    Watch poll interval in seconds. Default: 2. The state change is confirmed
    on two consecutive polls (debounce), so reaction time is ~2-4 s.

.PARAMETER Clean
    Delete all stored snapshots.

.PARAMETER SnapDir
    Directory for snapshots. Default: %TEMP%\mumu-ab

.EXAMPLE
    .\Test-MumuTunnelAB.ps1 -Capture -Label A      # 1) with tunnel as-is
    # ... toggle the tunnel OFF (or change node) yourself ...
    .\Test-MumuTunnelAB.ps1 -Capture -Label B      # 2) after the change
    .\Test-MumuTunnelAB.ps1 -Compare A,B           # 3) diff report

.EXAMPLE
    .\Test-MumuTunnelAB.ps1 -Capture -Label A
    .\Test-MumuTunnelAB.ps1 -Watch                 # toggle the tunnel now:
                                                   # B + diff are automatic
#>
[CmdletBinding()]
param(
    [switch]$Capture,
    [string]$Label = 'A',
    [switch]$List,
    [string[]]$Compare,
    [switch]$Watch,
    [switch]$Clean,
    [switch]$NoOwnerLookup,
    [string]$SnapDir = (Join-Path -Path $env:TEMP -ChildPath 'mumu-ab'),
    [int]$IntervalSec = 2
)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Continue'

function Get-Timestamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-SnapshotPath {
    param([string]$Name)
    return (Join-Path -Path $SnapDir -ChildPath ("snapshot-{0}.json" -f $Name))
}

function Get-MumuConnections {
    $rows = @(Get-NetTCPConnection -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Established' })
    $procMap = @{}
    foreach ($procId in @($rows | Select-Object -ExpandProperty OwningProcess -Unique)) {
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($null -ne $proc -and $proc.ProcessName -like 'MuMu*') {
            $procMap[$procId] = $proc.ProcessName
        }
    }
    $list = @()
    foreach ($row in ($rows | Where-Object { $procMap.ContainsKey($_.OwningProcess) } |
            Sort-Object -Property RemoteAddress, RemotePort, LocalPort)) {
        $list += [pscustomobject]@{
            Key       = '{0}:{1}->{2}:{3}#{4}' -f $row.LocalAddress, $row.LocalPort,
                            $row.RemoteAddress, $row.RemotePort, $row.OwningProcess
            Process   = $procMap[$row.OwningProcess]
            Pid       = $row.OwningProcess
            Local     = '{0}:{1}' -f $row.LocalAddress, $row.LocalPort
            Remote    = '{0}:{1}' -f $row.RemoteAddress, $row.RemotePort
            RemoteIp  = $row.RemoteAddress
            LocalIp   = $row.LocalAddress
        }
    }
    return $list
}

function Get-RouteFacts {
    $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $default = @($routes | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
        ForEach-Object { '{0} metric {1} via {2}' -f $_.InterfaceAlias, $_.RouteMetric, $_.NextHop } | Sort-Object)
    $fakeIp = @($routes | Where-Object { $_.DestinationPrefix -like '198.18.*' } |
        ForEach-Object { '{0}: {1}' -f $_.InterfaceAlias, $_.DestinationPrefix } | Sort-Object)
    return [pscustomobject]@{ Default = $default; FakeIp = $fakeIp }
}

function Get-Adapters {
    return @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' |
        ForEach-Object { '{0}: {1}' -f $_.Name, $_.InterfaceDescription } | Sort-Object)
}

function Get-RegValueOrDefault {
    param($Object, [string]$Name, [string]$Default = '')
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return [string]$prop.Value }
    return $Default
}

function Get-ProxyFacts {
    $i = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    return ('ProxyEnable={0}; ProxyServer={1}; PAC={2}' -f
        (Get-RegValueOrDefault -Object $i -Name 'ProxyEnable' -Default '0'),
        (Get-RegValueOrDefault -Object $i -Name 'ProxyServer'),
        (Get-RegValueOrDefault -Object $i -Name 'AutoConfigURL'))
}

function Get-TunnelOwnerFacts {
    # READ-ONLY probe: who owns the Wintun tunnel adapter?
    # The 198.18.0.0/16 fake-IP range is the classic sing-box/mihomo/v2ray
    # TUN signature and such cores usually listen on SOCKS 10808/10809 or
    # mihomo 7890-7893. Resolving those port owners plus their parent chain
    # reliably names the tunnel owner (field case: INCY). Nothing is killed.

    $result = [pscustomobject]@{
        AdapterLine = ''
        Details     = @()
        Warning     = ''
    }

    $tun = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -like '*Wintun*' -and $_.Status -eq 'Up' } |
        Select-Object -First 1)
    if (@($tun).Count -eq 0) {
        $result.Warning = 'Up-адаптер *Wintun* не найден — туннель сейчас выключен'
        return $result
    }
    $result.AdapterLine = '{0}: {1}' -f $tun[0].Name, $tun[0].InterfaceDescription

    $corePorts = @(10808, 10809, 7890, 7891, 7892, 7893)
    $listen = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $corePorts -contains $_.LocalPort })
    $ownerPids = @($listen | Select-Object -ExpandProperty OwningProcess -Unique |
        Where-Object { $_ -gt 0 })

    $details = @()
    $ownerNames = @()
    foreach ($procId in $ownerPids) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
        if ($null -eq $proc) { continue }
        $ownerNames += [string]$proc.Name
        $ports = @($listen | Where-Object { $_.OwningProcess -eq $procId } |
            Select-Object -ExpandProperty LocalPort -Unique | Sort-Object)
        $chain = @()
        $cur = [int]$proc.ParentProcessId
        for ($i = 0; $i -lt 6 -and $cur -gt 0; $i++) {
            $par = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
            if ($null -eq $par) { break }
            $chain += ('{0} (pid {1})' -f $par.Name, $par.ProcessId)
            $cur = [int]$par.ParentProcessId
        }
        $details += ('{0} (pid {1}) ports {2} | {3} | {4} | chain: {5}' -f
            $proc.Name, $proc.ProcessId, ($ports -join '/'),
            [string]$proc.ExecutablePath, [string]$proc.CommandLine,
            ($(if ($chain.Count) { $chain -join ' <- ' } else { '<root>' })))
    }
    $result.Details = $details

    $mumuOwners = @($ownerNames | Where-Object { $_ -like 'MuMu*' })
    if ($details.Count -gt 0 -and $mumuOwners.Count -eq 0) {
        $result.Warning = ('Туннель {0} принадлежит НЕ MuMu ({1}). Тумблер туннеля в MuMu на него не влияет — управляйте из интерфейса владельца.' -f
            $tun[0].Name, (($ownerNames | Select-Object -Unique | Sort-Object) -join ', '))
    }
    return $result
}

function New-Snapshot {
    param([string]$Name, [switch]$NoOwner)

    $conns = @(Get-MumuConnections)
    $routeFacts = Get-RouteFacts
    $owner = $null
    if (-not $NoOwner) { $owner = Get-TunnelOwnerFacts }

    $routeLookups = @()
    foreach ($ip in @($conns | Select-Object -ExpandProperty RemoteIp -Unique)) {
        $best = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -match '/' } |
            Where-Object {
                $net, $maskLen = $_.DestinationPrefix.Split('/')
                if ($null -eq $maskLen) { return $false }
                try {
                    $netIp = [ipaddress]$net
                    $ipIp  = [ipaddress]$ip
                    if ($netIp.AddressFamily -ne $ipIp.AddressFamily) { return $false }
                    $addrNet = $netIp.GetAddressBytes(); $addrIp = $ipIp.GetAddressBytes()
                    $full = [math]::Floor([int]$maskLen / 8); $rest = [int]$maskLen % 8
                    for ($i = 0; $i -lt $full; $i++) { if ($addrNet[$i] -ne $addrIp[$i]) { return $false } }
                    if ($rest -gt 0) {
                        $m = [byte](256 - [math]::Pow(2, 8 - $rest))
                        if (($addrNet[$full] -band $m) -ne ($addrIp[$full] -band $m)) { return $false }
                    }
                    return $true
                } catch { return $false }
            } |
            Sort-Object -Property { -[int]($_.DestinationPrefix.Split('/')[1]) }, RouteMetric |
            Select-Object -First 1
        if ($null -ne $best) {
            $routeLookups += '{0} -> {1} (metric {2})' -f $ip, $best.InterfaceAlias, $best.RouteMetric
        } else {
            $routeLookups += '{0} -> <no route>' -f $ip
        }
    }

    $snap = [pscustomobject]@{
        Label      = $Name
        Timestamp  = Get-Timestamp
        MumuPids   = @(Get-Process MuMu* -ErrorAction SilentlyContinue |
            ForEach-Object { '{0}={1}' -f $_.ProcessName, $_.Id })
        Connections = $conns
        Sources    = @($conns | Select-Object -ExpandProperty LocalIp -Unique | Sort-Object)
        Destinations = @($conns | Select-Object -ExpandProperty Remote -Unique | Sort-Object)
        RouteDefaults = $routeFacts.Default
        RouteFakeIp   = $routeFacts.FakeIp
        RouteLookups  = @($routeLookups | Sort-Object)
        Adapters   = Get-Adapters
        Proxy      = Get-ProxyFacts
        TunnelAdapter = $(if ($NoOwner) { '' } else { $owner.AdapterLine })
        TunnelOwner   = $(if ($NoOwner) { @() } else { @($owner.Details) })
        TunnelWarning = $(if ($NoOwner) { '' } else { $owner.Warning })
    }

    if (-not (Test-Path $SnapDir)) { $null = New-Item -ItemType Directory -Path $SnapDir -Force }
    $snap | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-SnapshotPath $Name) -Encoding UTF8
    return $snap
}

function Show-Snapshot {
    param($Snap)
    ('snapshot [{0}] @ {1}' -f $Snap.Label, $Snap.Timestamp)
    ('  MuMu processes : {0}' -f ($Snap.MumuPids -join ', '))
    ('  connections   : {0}' -f @($Snap.Connections).Count)
    ('  src addresses : {0}' -f ($Snap.Sources -join ', '))
    ('  default routes: {0}' -f ($Snap.RouteDefaults -join ' | '))
    ('  fake-ip routes: {0}' -f (@($Snap.RouteFakeIp) -join ' | '))
    ('  proxy         : {0}' -f $Snap.Proxy)
    if ($Snap.TunnelAdapter) { ('  tunnel adapter: {0}' -f $Snap.TunnelAdapter) }
    foreach ($line in @($Snap.TunnelOwner)) { ('  tunnel owner  : {0}' -f $line) }
    if ($Snap.TunnelWarning) { ('  >> ВНИМАНИЕ: {0}' -f $Snap.TunnelWarning) }
    foreach ($line in $Snap.Connections) {
        ('    {0} | {1} (pid {2}) | {3} -> {4}' -f $line.Key.PadRight(38), $line.Process, $line.Pid, $line.Local, $line.Remote)
    }
    foreach ($line in $Snap.RouteLookups) { ('    route: ' + $line) }
}

function Write-Diff {
    param($A, $B)

    $out = @()
    $out += ('#' + ('=' * 78))
    $out += ('# A/B DIFF: [{0}] {1}  ->  [{2}] {3}' -f $A.Label, $A.Timestamp, $B.Label, $B.Timestamp)
    $out += ('#' + ('=' * 78))

    # -- processes
    $goneP = @($A.MumuPids | Where-Object { $B.MumuPids -notcontains $_ })
    $newP  = @($B.MumuPids | Where-Object { $A.MumuPids -notcontains $_ })
    $out += ''
    $out += ('MuMu processes: {0} -> {1}' -f @($A.MumuPids).Count, @($B.MumuPids).Count)
    if ($goneP.Count) { $out += ('  - gone: ' + ($goneP -join ', ')) }
    if ($newP.Count)  { $out += ('  + new : ' + ($newP -join ', ')) }

    # -- connections by destination endpoint (ignore ports/pids: judge by who->where)
    $aEnds = @($A.Connections | ForEach-Object { '{0}|{1}' -f $_.Process, $_.Remote } | Sort-Object -Unique)
    $bEnds = @($B.Connections | ForEach-Object { '{0}|{1}' -f $_.Process, $_.Remote } | Sort-Object -Unique)
    $out += ''
    $out += ('TCP endpoints (process -> remote): {0} -> {1}' -f $aEnds.Count, $bEnds.Count)
    foreach ($x in @($aEnds | Where-Object { $bEnds -notcontains $_ })) { $out += ('  - ' + $x) }
    foreach ($x in @($bEnds | Where-Object { $aEnds -notcontains $_ })) { $out += ('  + ' + $x) }

    # -- source address migration (tunnel vs direct)
    $out += ''
    $out += ('Source addresses: [{0}] -> [{1}]' -f ($A.Sources -join ', '), ($B.Sources -join ', '))
    $fakeA = @($A.Sources | Where-Object { $_ -like '198.18.*' }).Count
    $fakeB = @($B.Sources | Where-Object { $_ -like '198.18.*' }).Count
    $out += ('  fake-IP(198.18.*) src connections: {0} -> {1}' -f $fakeA, $fakeB)
    if ($fakeA -gt 0 -and $fakeB -eq 0) { $out += '  >> tunnel NO LONGER carries MuMu traffic (direct path now)' }
    if ($fakeA -eq 0 -and $fakeB -gt 0) { $out += '  >> MuMu traffic moved INTO the tunnel' }

    # -- per-destination route changes
    $out += ''
    $out += 'Route lookup changes (unique MuMu destinations):'
    $aRoutes = @{}; foreach ($line in $A.RouteLookups) { $aRoutes[($line -split ' -> ')[0]] = $line }
    $bRoutes = @{}; foreach ($line in $B.RouteLookups) { $bRoutes[($line -split ' -> ')[0]] = $line }
    $routeChanged = $false
    foreach ($ip in ($aRoutes.Keys + $bRoutes.Keys | Sort-Object -Unique)) {
        $va = if ($aRoutes.ContainsKey($ip)) { $aRoutes[$ip] } else { '<none>' }
        $vb = if ($bRoutes.ContainsKey($ip)) { $bRoutes[$ip] } else { '<none>' }
        if ($va -ne $vb) { $out += ('  ~ {0}:  "{1}"  ->  "{2}"' -f $ip, $va, $vb); $routeChanged = $true }
    }
    if (-not $routeChanged) { $out += '  (no changes)' }

    # -- default route / fake-ip route / adapter / proxy
    foreach ($pair in @(
        @{ Title = 'Default routes'; A = $A.RouteDefaults; B = $B.RouteDefaults },
        @{ Title = 'Fake-IP routes (198.18.*)'; A = $A.RouteFakeIp; B = $B.RouteFakeIp },
        @{ Title = 'Active adapters'; A = $A.Adapters; B = $B.Adapters }
    )) {
        $out += ''
        $out += ('{0}:' -f $pair.Title)
        $gone = @($pair.A | Where-Object { $pair.B -notcontains $_ })
        $new  = @($pair.B | Where-Object { $pair.A -notcontains $_ })
        if (-not $gone.Count -and -not $new.Count) { $out += '  (no changes)' }
        foreach ($x in $gone) { $out += ('  - ' + $x) }
        foreach ($x in $new)  { $out += ('  + ' + $x) }
    }
    $out += ''
    $out += ('Proxy: {0}' -f $A.Proxy)
    if ($A.Proxy -ne $B.Proxy) { $out += ('  -> {0}' -f $B.Proxy) } else { $out += '  (no changes)' }

    return $out
}

function Test-FakeIpPresent {
    $fakeRoutes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.DestinationPrefix -like '198.18.*' })
    return ($fakeRoutes.Count -gt 0)
}

function Write-SavedReport {
    param($A, $B, [string]$Suffix)
    $report = Write-Diff -A $A -B $B
    $reportPath = Join-Path -Path $SnapDir -ChildPath ('diff-{0}.txt' -f $Suffix)
    $report | Set-Content -LiteralPath $reportPath -Encoding UTF8
    $report | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host ('Отчёт сохранён: ' + $reportPath)
}

if ($Clean) {
    if (Test-Path $SnapDir) {
        Remove-Item -LiteralPath $SnapDir -Recurse -Force
        Write-Host ('Удалено: ' + $SnapDir)
    } else {
        Write-Host ('Нечего удалять: ' + $SnapDir + ' не существует')
    }
    return
}

if ($List) {
    if (-not (Test-Path $SnapDir)) { Write-Host 'Снимков пока нет.'; return }
    foreach ($f in (Get-ChildItem -LiteralPath $SnapDir -Filter 'snapshot-*.json' | Sort-Object Name)) {
        $s = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        ('{0,-10} {1}  connections: {2},  sources: {3}' -f $s.Label, $s.Timestamp,
            @($s.Connections).Count, (@($s.Sources) -join ','))
    }
    return
}

if ($Compare) {
    $flat = @($Compare | Where-Object { $_ })
    if ($flat.Count -eq 1) { $parts = @($flat[0].Split(',')) }
    elseif ($flat.Count -ge 2) { $parts = @($flat[0], $flat[1]) }
    else { throw 'Формат: -Compare A,B' }
    if ($parts.Count -ne 2) { throw 'Формат: -Compare A,B' }
    $pa = Get-SnapshotPath $parts[0]; $pb = Get-SnapshotPath $parts[1]
    foreach ($p in @($pa, $pb)) {
        if (-not (Test-Path $p)) { throw ('Снимок не найден: ' + $p + ' — сначала -Capture -Label ' + (Split-Path $p -Leaf)) }
    }
    $sa = Get-Content -LiteralPath $pa -Raw | ConvertFrom-Json
    $sb = Get-Content -LiteralPath $pb -Raw | ConvertFrom-Json
    Write-SavedReport -A $sa -B $sb -Suffix ('{0}-vs-{1}' -f $parts[0], $parts[1])
    return
}

if ($Watch) {
    $snapAPath = Get-SnapshotPath $Label
    if (-not (Test-Path $snapAPath)) {
        throw ("Снимок [{0}] не найден ({1}) — сначала -Capture -Label {0}" -f $Label, $snapAPath)
    }
    $sa = Get-Content -LiteralPath $snapAPath -Raw | ConvertFrom-Json
    $wasPresent = Test-FakeIpPresent
    $stateNow = 'ЕСТЬ (туннель активен)'
    if (-not $wasPresent) { $stateNow = 'НЕТ (туннель выключен)' }
    Write-Host ("Режим наблюдения: база = снимок [{0}] от {1}" -f $sa.Label, $sa.Timestamp)
    Write-Host ("  fake-IP маршруты 198.18.* : {0}" -f $stateNow)
    Write-Host "  Жду исчезновение/появление маршрута (Ctrl+C — отмена)..."
    $consecutive = 0
    while ($true) {
        Start-Sleep -Seconds $IntervalSec
        $isPresent = Test-FakeIpPresent
        if ($isPresent -eq $wasPresent) { $consecutive = 0; continue }
        $consecutive++
        if ($consecutive -lt 2) { continue }
        $state = 'ПОЯВИЛСЯ'
        if (-not $isPresent) { $state = 'ИСЧЕЗ' }
        Write-Host ("{0}  fake-IP маршрут {1} — снимаю снимок [B]..." -f (Get-Timestamp), $state)
        $sb = New-Snapshot -Name 'B' -NoOwner:$NoOwnerLookup
        Show-Snapshot -Snap $sb
        Write-SavedReport -A $sa -B $sb -Suffix ('{0}-auto-vs-B' -f $sa.Label)
        return
    }
}

if ($Capture) {
    $snap = New-Snapshot -Name $Label -NoOwner:$NoOwnerLookup
    Show-Snapshot -Snap $snap
    return
}

Write-Host 'Укажите режим: -Capture -Label A [-NoOwnerLookup] | -List | -Compare A,B | -Watch | -Clean'
