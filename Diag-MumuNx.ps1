#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Read-only diagnostic snapshot of MuMuNxService.exe: process state, hosted
    services, listening endpoints, TCP/UDP connections and related MuMu processes.

.DESCRIPTION
    Purely passive: no VPN, route, proxy or firewall changes. Resolves remote
    IPs against the Windows DNS cache (name resolution only) and enriches
    with WHOIS-lite owner info for non-RFC1918 addresses (online queries).
    Output: %PUBLIC%\MuMuNx-<timestamp>.txt

.NOTES
    Must run elevated (the service runs as SYSTEM; per-PID connection mapping
    and service details are unreliable without elevation).
#>
[CmdletBinding()]
param(
    [string]$OutDir = $env:PUBLIC,
    [string]$ServiceName = 'MuMuNxService'
)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Continue'

function Get-Timestamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-OwnerForIp {
    param([string]$Ip)
    if (-not $Ip -or $Ip -match '^(0\.|127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|198\.18\.|::1|fe80)' ) { return '' }
    try {
        $ptr = (Resolve-DnsName -Name $Ip -Type PTR -DnsOnly -QuickTimeout -ErrorAction Stop |
            Select-Object -First 1 -ExpandProperty NameHost -ErrorAction SilentlyContinue)
        if ($ptr) { return $ptr }
    } catch [System.Exception] {
        return ''
    }
    return ''
}

$logLines = @()
function Add-Log {
    param([string]$Line)
    $script:logLines += $Line
}

Add-Log ('=' * 78)
Add-Log ('MuMuNx diagnostic snapshot | {0}' -f (Get-Timestamp))
Add-Log ('=' * 78)

# --- 1. Windows service entry -------------------------------------------------
Add-Log ''
Add-Log ('--- Windows service (pattern: {0}) ---' -f $ServiceName)
$svc = Get-CimInstance Win32_Service -Filter ("Name = '{0}'" -f $ServiceName) -ErrorAction SilentlyContinue
if (-not $svc) {
    $svc = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*MuMu*' -or $_.DisplayName -like '*MuMu*' }
    if ($svc) { Add-Log ('(exact name {0} not found; showing MuMu-related services instead)' -f $ServiceName) }
}
if ($svc) {
    foreach ($s in @($svc)) {
        Add-Log ('  Name        : {0}' -f $s.Name)
        Add-Log ('  DisplayName : {0}' -f $s.DisplayName)
        Add-Log ('  State       : {0} / StartMode {1}' -f $s.State, $s.StartMode)
        Add-Log ('  ProcessId   : {0}' -f $s.ProcessId)
        Add-Log ('  PathName    : {0}' -f $s.PathName)
        Add-Log ('  Account     : {0}' -f $s.StartName)
    }
} else {
    Add-Log '  (no MuMu-related Windows service registered)'
}

# --- 2. Process tree ----------------------------------------------------------
Add-Log ''
Add-Log '--- MuMu processes ---'
$mumuProcs = @(Get-Process -Name 'MuMu*' -ErrorAction SilentlyContinue)
$procRows = @{}
foreach ($p in $mumuProcs) {
    $ci = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f $p.Id) -ErrorAction SilentlyContinue
    $cmd = if ($ci) { $ci.CommandLine } else { '' }
    $exe = if ($ci) { $ci.ExecutablePath } else { $p.Path }
    $procRows[$p.Id] = $p.ProcessName
    Add-Log ('  pid {0,-7} {1,-26} exe: {2}' -f $p.Id, $p.ProcessName, $exe)
    if ($cmd) { Add-Log ('            cmd: {0}' -f $cmd) }
}

# --- 3. Listening endpoints ---------------------------------------------------
Add-Log ''
Add-Log '--- Listening endpoints (MuMu only) ---'
$listens = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $procRows.ContainsKey($_.OwningProcess) } |
    Sort-Object -Property LocalAddress, LocalPort)
if ($listens.Count) {
    foreach ($l in $listens) {
        Add-Log ('  {0} (pid {1}) LISTEN {2}:{3}' -f $procRows[$l.OwningProcess], $l.OwningProcess, $l.LocalAddress, $l.LocalPort)
    }
} else {
    Add-Log '  (none)'
}

# --- 4. TCP + UDP connections of MuMu processes --------------------------------
Add-Log ''
Add-Log '--- TCP connections (MuMu only) ---'
$tcp = @(Get-NetTCPConnection -ErrorAction SilentlyContinue |
    Where-Object { $procRows.ContainsKey($_.OwningProcess) -and $_.State -ne 'Listen' } |
    Sort-Object -Property RemoteAddress, RemotePort, LocalPort)
$dnsCache = @{}
foreach ($e in (Get-DnsClientCache -ErrorAction SilentlyContinue)) {
    if ($e.Data -match '^\d{1,3}(\.\d{1,3}){3}$') { $dnsCache[$e.Data] = $e.Entry }
}
foreach ($c in $tcp) {
    $host_ = ''
    if ($dnsCache.ContainsKey($c.RemoteAddress)) { $host_ = $dnsCache[$c.RemoteAddress] }
    if (-not $host_) { $host_ = Get-OwnerForIp -Ip $c.RemoteAddress }
    Add-Log ('  {0} (pid {1}) {2}:{3} -> {4}:{5} [{6}]{7}' -f
        $procRows[$c.OwningProcess], $c.OwningProcess,
        $c.LocalAddress, $c.LocalPort, $c.RemoteAddress, $c.RemotePort, $c.State,
        ($(if ($host_) { '  ' + $host_ } else { '' })))
}
if (-not $tcp.Count) { Add-Log '  (none)' }

Add-Log ''
Add-Log '--- UDP endpoints (MuMu only) ---'
$udp = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
    Where-Object { $procRows.ContainsKey($_.OwningProcess) })
if ($udp.Count) {
    foreach ($u in ($udp | Sort-Object -Property LocalAddress, LocalPort)) {
        Add-Log ('  {0} (pid {1}) UDP {2}:{3}' -f $procRows[$u.OwningProcess], $u.OwningProcess, $u.LocalAddress, $u.LocalPort)
    }
} else {
    Add-Log '  (none)'
}

# --- 5. Firewall rules touching MuMu (read-only) -------------------------------
Add-Log ''
Add-Log '--- Firewall rules mentioning MuMu (read-only view) ---'
$rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*MuMu*' })
if ($rules.Count) {
    foreach ($r in ($rules | Select-Object -First 12)) {
        $apps = @($r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Program)
        Add-Log ('  [{0}] {1} dir={2} action={3} profile={4}' -f $r.Enabled, $r.DisplayName, $r.Direction, $r.Action, $r.Profile)
        foreach ($a in $apps) { if ($a -and $a -ne 'Any') { Add-Log ('      app: {0}' -f $a) } }
    }
} else {
    Add-Log '  (no MuMu firewall rules found)'
}

Add-Log ''
Add-Log ('snapshot finished {0}' -f (Get-Timestamp))

$outFile = Join-Path -Path $OutDir -ChildPath ('MuMuNx-{0}.txt' -f (Get-Date).ToString('yyyyMMdd-HHmmss'))
$logLines -join "`r`n" | Set-Content -LiteralPath $outFile -Encoding UTF8
Write-Host ('Готово. Лог: ' + $outFile)
