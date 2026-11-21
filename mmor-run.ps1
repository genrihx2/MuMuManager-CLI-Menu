# MuMuManager CLI Menu - native .mmor playback driver
# Project:  https://github.com/genrihx2/MuMuManager-CLI-Menu
# License:  Open Source - MIT (see LICENSE)
#
# MuMu has no command for its Operation Recorder and no message/pipe to post a
# recording to: MuMuManager.exe has no script/play verb, and playback only
# exists inside the recorder UI. This script drives that UI the way a user
# does - focus the instance, open the recorder, pick the file, press play -
# and it does so in two layers, because the UI only exposes part of itself:
#
#   * elements with an AutomationId are addressed by name (the instance title
#     bar exposes kToolMenu.kToolMenuBtn, kWinMini.kWinMiniBtn, ...);
#   * the recorder menu items and the recorder buttons expose no name and no
#     id at all - only a rectangle - so those two clicks come from a
#     calibration file, captured on this machine with -Record.
#
# That file does not have to be built by hand: -EmitConfig writes it, and a
# run without it writes the template itself. recorderButton is taken from
# kToolMenu.kToolMenuBtn, so the file starts usable; playButton stays null
# until -Record supplies it, and -Apply refuses to press an unset point.
#
# Nothing is pressed unless -Apply is given, and -Apply refuses to click at a
# point it has not been given: default mode is -Probe, which reports every
# window and element it can see and presses nothing.
#
# What this script writes to disk
# -------------------------------
# Exactly one file: the calibration file (mmor-run.json next to this script,
# or -Config). It is written when -EmitConfig is given and when no config
# exists yet; -Record, -Probe and -Apply otherwise write nothing. -NoWrite
# keeps even that file off the disk: the probe still reports windows,
# elements and the click plan it can resolve, and simply says the config was
# not written. -Apply never writes in any mode.
#
# NOTE - the C# helper is compiled here, not downloaded
# -----------------------------------------------------
# Initialize-MmorApi passes a private C# source string to Add-Type, which
# compiles it in-process: Windows PowerShell 5.1 shells out to the csc.exe
# that ships with .NET Framework, PowerShell 7 compiles in memory. The
# compiler leaves its scratch files in %TEMP% and the assembly is loaded into
# this process only - no DLL is fetched from the network or loaded from a
# path, and nothing is dropped next to this script.
#
# NOTE - this is GUI automation, not an API call
# ---------------------------------------------
# -Apply really does drive the mouse: it moves the cursor onto the recorder
# UI and sends mouse_event() down/up there. Window position, DPI, focus and
# timing all affect it, so it is a stopgap - not a supported integration.
#
# MuMu exposes no native .mmor command. MuMuManager.exe 6.8.9.0 has no mmor,
# script or play verb (control = launch/shutdown/restart/show_window/
# hide_window/layout_window/app/tool/shortcut), and playback lives only in the
# MuMuNxMain GUI (ScriptManagerPresenterImpl[runScript], OperationRecorder
# Execute); no pipe or endpoint accepts a recording.
#
# Supported alternatives, without touching the mouse or stealing focus:
#   * Auto-execute on launch - tick 'Auto-execute upon starting the device' on
#     the recording once, then: MuMuManager.exe control -v <n> launch
#     (or restart). Playback starts by itself when the instance boots; native,
#     but one script per instance and only at boot.
#   * Input injection through MuMu's own channel:
#     MuMuManager.exe control -v <n> tool cmd -c "input tap 400 300"
#     Replays taps you supply - not .mmor playback.
#
# Usage:
#   .\mmor-run.ps1 -Instance 0 -Probe
#   .\mmor-run.ps1 -Instance 0 -Probe -EmitConfig   # write/refresh mmor-run.json
#   .\mmor-run.ps1 -Instance 0 -Probe -NoWrite      # ... without writing it
#   .\mmor-run.ps1 -Record            # click the recorder entry, then Play
#   .\mmor-run.ps1 -Instance 0 -File C:\recordings\farm.mmor -Apply

[CmdletBinding()]
param(
    # Instance index the recording belongs to. -Probe accepts a comma list or
    # 'all' to survey every instance at once.
    [string]$Instance = '0',

    # The recording to play. Required for -Apply.
    [string]$File,

    # Calibration file. Default: mmor-run.json next to this script.
    [string]$Config,

    # Survey only: windows, elements, mapping, click plan. Presses nothing.
    [switch]$Probe,

    # Actually send the clicks.
    [switch]$Apply,

    # Write mmor-run.json with recorderButton filled in from the running
    # instance (kToolMenu.kToolMenuBtn). Points already captured are kept;
    # playButton stays null until -Record supplies it.
    [switch]$EmitConfig,

    # Calibration: print the window and normalized point of every click the
    # user makes, so the two unnamed buttons can be located. Presses nothing.
    [switch]$Record,

    # How many clicks -Record waits for before it stops.
    [int]$RecordCount = 2,

    # Seconds to wait for the recorder window after the recorder click.
    [int]$WaitSeconds = 20,

    # Optional explicit path to MuMuManager.exe.
    [string]$MumuManager,

    # Never write anything: a missing calibration file stays missing and
    # -EmitConfig is ignored. Probing, -Record and -Apply are unaffected
    # otherwise (-Apply only reads the config).
    [switch]$NoWrite
)

$ErrorActionPreference = 'Stop'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------
# Win32: windows, geometry, clicks, and the calibration listener.
# ---------------------------------------------------------------------------
function Initialize-MmorApi {
    if ('MmorApi' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class MmorApi {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    // Every visible top-level window as handle|title|class|pid|process|x|y|w|h.
    // Handles travel as strings: an IntPtr does not survive a PowerShell
    // hashtable round-trip, and the caller only passes them back here.
    public static List<string[]> Windows() {
        var found = new List<string[]>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            var title = new StringBuilder(512); GetWindowText(h, title, 512);
            var cls = new StringBuilder(256); GetClassName(h, cls, 256);
            uint pid; GetWindowThreadProcessId(h, out pid);
            string name = "";
            try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { }
            RECT r; GetWindowRect(h, out r);
            found.Add(new string[] {
                h.ToString(), title.ToString(), cls.ToString(), pid.ToString(), name,
                r.Left.ToString(), r.Top.ToString(),
                (r.Right - r.Left).ToString(), (r.Bottom - r.Top).ToString()
            });
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static string Rect(string handle) {
        RECT r;
        if (!GetWindowRect(new IntPtr(long.Parse(handle)), out r)) return "";
        return String.Format("{0},{1} {2}x{3}", r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
    }

    // Any window, not only the MuMu ones: a calibration click may land on the
    // desktop or a taskbar, and the report must say so instead of showing
    // empty title and class.
    public static string[] Describe(string handle) {
        var hwnd = new IntPtr(long.Parse(handle));
        var title = new StringBuilder(512); GetWindowText(hwnd, title, 512);
        var cls = new StringBuilder(256); GetClassName(hwnd, cls, 256);
        uint pid; GetWindowThreadProcessId(hwnd, out pid);
        string name = "";
        try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { }
        RECT r; GetWindowRect(hwnd, out r);
        return new string[] {
            hwnd.ToString(), title.ToString(), cls.ToString(), pid.ToString(), name,
            r.Left.ToString(), r.Top.ToString(),
            (r.Right - r.Left).ToString(), (r.Bottom - r.Top).ToString()
        };
    }

    public static string WindowAtCursor() {
        POINT p; GetCursorPos(out p);
        IntPtr h = WindowFromPoint(p);
        if (h == IntPtr.Zero) return "";
        IntPtr root = GetAncestor(h, 2);   // GA_ROOT
        return root.ToString();
    }

    public static string CursorOver(string handle) {
        POINT p; GetCursorPos(out p);
        return String.Format("{0},{1}", p.X, p.Y);
    }

    public static bool Click(int x, int y, bool doubleClick) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(60);
        for (int i = 0; i < (doubleClick ? 2 : 1); i++) {
            mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);   // LEFTDOWN
            System.Threading.Thread.Sleep(30);
            mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);   // LEFTUP
            System.Threading.Thread.Sleep(120);
        }
        return true;
    }

    public static bool LeftButtonDown() {
        return (GetAsyncKeyState(0x01) & 0x8000) != 0;
    }

    public static bool Focus(string handle) {
        var hwnd = new IntPtr(long.Parse(handle));
        ShowWindow(hwnd, 9);   // SW_RESTORE
        return SetForegroundWindow(hwnd);
    }
}
'@ -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Discovery helpers.
# ---------------------------------------------------------------------------
function Get-MumuManagerPath {
    if ($MumuManager) {
        if (-not (Test-Path -LiteralPath $MumuManager)) { throw "MuMuManager.exe not found: $MumuManager" }
        return (Resolve-Path -LiteralPath $MumuManager).Path
    }
    if ($env:MUMU_MANAGER -and (Test-Path -LiteralPath $env:MUMU_MANAGER)) { return $env:MUMU_MANAGER }
    foreach ($root in @("$env:ProgramFiles\Netease", "${env:ProgramFiles(x86)}\Netease")) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($install in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            foreach ($leaf in @('nx_main\MuMuManager.exe', 'shell\MuMuManager.exe')) {
                $candidate = Join-Path $install.FullName $leaf
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
    }
    throw 'MuMuManager.exe not found - pass -MumuManager <path>.'
}

function Get-InstanceInfo {
    param([string]$MumuPath, [string]$Index)
    $raw = & $MumuPath info -v $Index 2>$null | Out-String
    if (-not $raw.Trim()) { return $null }
    try { $json = $raw | ConvertFrom-Json } catch { return $null }
    if ($json.$Index) { $json = $json.$Index }
    return $json
}

function Get-RunningIndices {
    param([string]$MumuPath, [string]$Requested)
    if ($Requested -eq 'all') {
        $info = & $MumuPath info -v all 2>$null | ConvertFrom-Json
        $out = @()
        foreach ($p in $info.PSObject.Properties) { $out += [string]$p.Name }
        return $out
    }
    return @($Requested -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-WindowList {
    # Visible top-level windows of the MuMu processes, flattened for the report.
    $rows = @()
    foreach ($w in [MmorApi]::Windows()) {
        $proc = [string]$w[4]
        if ($proc -notmatch '^MuMu') { continue }
        $rows += [PSCustomObject]@{
            Handle  = [string]$w[0]
            Title   = [string]$w[1]
            Class   = [string]$w[2]
            Pid     = [string]$w[3]
            Process = $proc
            X       = [int]$w[5]
            Y       = [int]$w[6]
            Width   = [int]$w[7]
            Height  = [int]$w[8]
        }
    }
    return $rows
}

function Get-InstanceWindow {
    # Player window for one instance. Its title is the instance name the
    # manager reports; the command line ('-v N' / '--vm ...-N') is the fallback
    # for renamed or duplicated titles.
    param([object[]]$Windows, [string]$MumuPath, [string]$Index)

    $info = Get-InstanceInfo -MumuPath $MumuPath -Index $Index
    $name = ''
    if ($info -and $info.name) { $name = [string]$info.name }

    $players = @($Windows | Where-Object { $_.Process -eq 'MuMuNxDevice' -and $_.Class -match 'QWindowIcon' })
    if ($name) {
        $hit = @($players | Where-Object { $_.Title.Trim() -eq $name.Trim() })
        if ($hit.Count -ge 1) { return $hit[0] }
    }
    foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name='MuMuNxDevice.exe'" -ErrorAction SilentlyContinue)) {
        $cmd = [string]$proc.CommandLine
        $guess = $null
        if ($cmd -match '--vm\s+\S*-(\d+)\s*$') { $guess = $Matches[1] }
        elseif ($cmd -match '-v\s+(\d+)') { $guess = $Matches[1] }
        if ($guess -ne $Index) { continue }
        $hit = @($players | Where-Object { $_.Pid -eq [string]$proc.ProcessId })
        if ($hit.Count -ge 1) { return $hit[0] }
    }
    return $null
}

function Get-UiaTree {
    # The window's UI Automation descendants. The player title bar and the
    # shell expose real ids; the popup menus and the recorder do not, which is
    # exactly what the probe prints and why the two clicks are calibrated.
    param([string]$Handle, [int]$Max = 40)
    $result = [PSCustomObject]@{ Available = $false; Count = 0; Items = @(); Note = '' }
    try {
        if (-not ('System.Windows.Automation.AutomationElement' -as [type])) {
            Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        }
        $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([long]$Handle))
        if (-not $el) { $result.Note = 'no automation element for this handle'; return $result }
        $all = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        $result.Available = $true
        $result.Count = $all.Count
        $items = @()
        $i = 0
        foreach ($d in $all) {
            if ($i -ge $Max) { break }
            $rect = $d.Current.BoundingRectangle
            $items += [PSCustomObject]@{
                Type = $d.Current.ControlType.ProgrammaticName.Replace('ControlType.', '')
                Id   = $d.Current.AutomationId
                Name = $d.Current.Name
                Rect = ('{0},{1} {2}x{3}' -f [int]$rect.X, [int]$rect.Y, [int]$rect.Width, [int]$rect.Height)
            }
            $i++
        }
        $result.Items = $items
        if ($all.Count -eq 0) { $result.Note = 'empty tree - one opaque surface' }
        return $result
    } catch {
        $result.Note = "UI Automation unavailable: $($_.Exception.Message)"
        return $result
    }
}

function Read-MmorConfig {
    param([string]$Path)
    if (-not $Path) { $Path = Join-Path $script:ScriptDir 'mmor-run.json' }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-RecorderButtonPoint {
    # The recorder entry is the one control involved here that keeps a stable
    # AutomationId: the title bar exposes kToolMenu.kToolMenuBtn. Normalizing
    # its centre means a fresh template already has a usable recorderButton,
    # while the recorder's own buttons (no id, no name) still need -Record.
    param([object]$Window)
    if (-not $Window -or $Window.Width -le 0 -or $Window.Height -le 0) { return $null }
    try {
        if (-not ('System.Windows.Automation.AutomationElement' -as [type])) {
            Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        }
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([long]$Window.Handle))
        if (-not $root) { return $null }
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            'kToolMenu.kToolMenuBtn')
        $btn = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if (-not $btn) { return $null }
        $rect = $btn.Current.BoundingRectangle
        if ($rect.Width -le 0 -or $rect.Height -le 0) { return $null }
        $nx = [Math]::Round((($rect.X + ($rect.Width / 2)) - $Window.X) / $Window.Width, 4)
        $ny = [Math]::Round((($rect.Y + ($rect.Height / 2)) - $Window.Y) / $Window.Height, 4)
        if ($nx -lt 0 -or $nx -gt 1 -or $ny -lt 0 -or $ny -gt 1) { return $null }
        return @($nx, $ny)
    } catch {
        return $null
    }
}

function Format-MmorNumber {
    # A dot as the decimal separator regardless of the Windows locale: the
    # value goes straight into JSON.
    param([double]$Value)
    return $Value.ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-MmorPair {
    # An unknown pair stays null: it must never read as 0,0, which -Apply
    # would happily click.
    param([object]$Pair)
    if ($null -eq $Pair) { return 'null' }
    $arr = @($Pair)
    if ($arr.Count -ne 2 -or $null -eq $arr[0] -or $null -eq $arr[1]) { return 'null' }
    return ('[{0}, {1}]' -f (Format-MmorNumber ([double]$arr[0])), (Format-MmorNumber ([double]$arr[1])))
}

function Write-MmorConfigTemplate {
    # Template that is safe to run: recorderButton comes from the instance
    # title bar, playButton stays null so -Apply stops instead of pressing an
    # uncalibrated point. Existing pairs and delays survive a refresh.
    param([string]$Path, [object]$Point, [object]$Base)

    $recorder = Format-MmorPair $Point
    $play = 'null'
    $row = 'null'
    $openMs = 2500
    $fileMs = 800
    $playMs = 500
    if ($Base) {
        if ($recorder -eq 'null') { $recorder = Format-MmorPair $Base.recorderButton }
        $play = Format-MmorPair $Base.playButton
        $row = Format-MmorPair $Base.fileRow
        if ($Base.delays) {
            if ($Base.delays.afterOpenMs) { $openMs = [int]$Base.delays.afterOpenMs }
            if ($Base.delays.afterFileMs) { $fileMs = [int]$Base.delays.afterFileMs }
            if ($Base.delays.afterPlayMs) { $playMs = [int]$Base.delays.afterPlayMs }
        }
    }

    if ($recorder -eq 'null') {
        $note = 'recorderButton is unknown - start the instance and re-run -EmitConfig, or copy the first -Record pair here.'
    } else {
        $note = 'recorderButton was derived from the instance title-bar tool menu (kToolMenu.kToolMenuBtn); re-check it with -Record if the clicks land off target.'
    }
    $note = $note + ' playButton is null on purpose: run -Record, click the recorder entry and then Play, and put that second pair here - -Apply refuses to press Play without it.'

    $text = @(
        '{'
        ('  "_comment": "{0}",' -f $note)
        ('  "recorderButton": {0},' -f $recorder)
        ('  "fileRow": {0},' -f $row)
        ('  "playButton": {0},' -f $play)
        ('  "delays": {{ "afterOpenMs": {0}, "afterFileMs": {1}, "afterPlayMs": {2} }}' -f $openMs, $fileMs, $playMs)
        '}'
    ) -join "`n"

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $text + "`n", $utf8)
    return $text
}

function Get-Point {
    # Normalized point -> absolute pixel inside a window rectangle.
    param([object]$Config, [string]$Name, [object]$Window)
    if (-not $Config) { return $null }
    $pair = $Config.$Name
    if (-not $pair -or $pair.Count -ne 2) { return $null }
    $nx = [double]$pair[0]
    $ny = [double]$pair[1]
    if ($nx -lt 0 -or $nx -gt 1 -or $ny -lt 0 -or $ny -gt 1) { return $null }
    return [PSCustomObject]@{
        X  = [int]($Window.X + ($Window.Width * $nx))
        Y  = [int]($Window.Y + ($Window.Height * $ny))
        Nx = $nx
        Ny = $ny
    }
}

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------
Initialize-MmorApi
$MumuPath = Get-MumuManagerPath

if ($Record) {
    # Calibration listener: the user clicks the recorder entry and then Play;
    # the script reports which window each click landed in and where, in
    # normalized coordinates. It never sends input.
    Write-Host ''
    Write-Host '  Calibration - click the controls you want the driver to press' -ForegroundColor Cyan
    Write-Host ('  {0} click(s) to capture, Ctrl+C to stop. Nothing is pressed by this script.' -f $RecordCount) -ForegroundColor DarkGray
    $captured = 0
    $wasDown = $false
    while ($captured -lt $RecordCount) {
        $down = [MmorApi]::LeftButtonDown()
        if ($down -and -not $wasDown) {
            Start-Sleep -Milliseconds 120
            $handle = [MmorApi]::WindowAtCursor()
            $info = [MmorApi]::Describe($handle)
            $title = [string]$info[1]
            $class = [string]$info[2]
            $process = [string]$info[4]
            $x = [int]$info[5]
            $y = [int]$info[6]
            $wpx = [int]$info[7]
            $hpx = [int]$info[8]
            $cursor = [MmorApi]::CursorOver($handle)
            $cx = [int]($cursor -split ',')[0]
            $cy = [int]($cursor -split ',')[1]
            if ($wpx -gt 0 -and $hpx -gt 0) {
                # A dot as the decimal separator regardless of the Windows
                # locale: the value goes straight into JSON.
                $nx = [Math]::Round(($cx - $x) / $wpx, 4).ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture)
                $ny = [Math]::Round(($cy - $y) / $hpx, 4).ToString('0.####', [System.Globalization.CultureInfo]::InvariantCulture)
                $captured++
                Write-Host ''
                Write-Host ('  click {0}: {1} {2} ''{3}'' class={4} {5},{6} {7}x{8}' -f $captured, $handle, $process, $title, $class, $x, $y, $wpx, $hpx) -ForegroundColor Gray
                Write-Host ('    normalized: [{0}, {1}]' -f $nx, $ny) -ForegroundColor Green
            } else {
                Write-Host ('  click on {0} ''{1}'' - window has no area, ignored' -f $handle, $title) -ForegroundColor Yellow
            }
        }
        $wasDown = $down
        Start-Sleep -Milliseconds 30
    }
    Write-Host ''
    Write-Host '  Copy the two normalized pairs into mmor-run.json (recorderButton, playButton).' -ForegroundColor Cyan
    exit 0
}

$requested = Get-RunningIndices -MumuPath $MumuPath -Requested $Instance
$windows = @(Get-WindowList)

Write-Host ''
Write-Host '  MuMu .mmor driver' -ForegroundColor Cyan
Write-Host ('  MuMuManager: {0}' -f $MumuPath) -ForegroundColor DarkGray
$modeName = 'PROBE (nothing is pressed)'
if ($Apply -and -not $Probe) { $modeName = 'APPLY (clicks are sent)' }
Write-Host ('  mode: {0}' -f $modeName) -ForegroundColor DarkGray
Write-Host ''

Write-Host '  MuMu windows' -ForegroundColor Cyan
if ($windows.Count -eq 0) {
    Write-Host '    none - start an instance first ([2] in the menu)' -ForegroundColor Yellow
} else {
    foreach ($w in $windows) {
        Write-Host ('    {0,-9} {1,-14} {2,-20} {3,-24} {4},{5} {6}x{7}' -f $w.Handle, $w.Process, $w.Class, $w.Title, $w.X, $w.Y, $w.Width, $w.Height) -ForegroundColor Gray
    }
}

$targets = @()
foreach ($idx in $requested) {
    $info = Get-InstanceInfo -MumuPath $MumuPath -Index $idx
    $win = Get-InstanceWindow -Windows $windows -MumuPath $MumuPath -Index $idx
    $targets += [PSCustomObject]@{ Index = $idx; Info = $info; Window = $win }
}

Write-Host ''
Write-Host '  Instances' -ForegroundColor Cyan
foreach ($t in $targets) {
    $state = 'unknown'
    if ($t.Info) {
        if ($t.Info.is_android_started -eq $true) { $state = 'RUNNING' }
        elseif ($t.Info.is_process_started -eq $true) { $state = 'STARTING' }
        else { $state = 'STOPPED' }
    }
    $winText = 'no window'
    if ($t.Window) { $winText = ('{0} at {1},{2} {3}x{4}' -f $t.Window.Handle, $t.Window.X, $t.Window.Y, $t.Window.Width, $t.Window.Height) }
    Write-Host ('    [{0}] {1,-24} {2,-8} {3}' -f $t.Index, $(if ($t.Info) { $t.Info.name } else { '?' }), $state, $winText) -ForegroundColor Gray
}

foreach ($t in $targets) {
    if (-not $t.Window) { continue }
    Write-Host ''
    Write-Host ('  Elements in instance {0} ({1}, {2})' -f $t.Index, $t.Window.Title, $t.Window.Class) -ForegroundColor Cyan
    $uia = Get-UiaTree -Handle $t.Window.Handle
    if (-not $uia.Available) {
        Write-Host ('    ! {0}' -f $uia.Note) -ForegroundColor Yellow
    } elseif ($uia.Count -eq 0) {
        Write-Host ('    ! 0 elements - {0}' -f $uia.Note) -ForegroundColor Yellow
    } else {
        Write-Host ('    {0} element(s)' -f $uia.Count) -ForegroundColor Gray
        foreach ($item in $uia.Items) {
            if (-not $item.Id -and -not $item.Name) { continue }
            Write-Host ('      {0,-10} id=''{1}'' name=''{2}'' {3}' -f $item.Type, $item.Id, $item.Name, $item.Rect) -ForegroundColor DarkGray
        }
    }
}

$cfgPath = $Config
if (-not $cfgPath) { $cfgPath = Join-Path $script:ScriptDir 'mmor-run.json' }
$cfg = Read-MmorConfig -Path $cfgPath

# A missing calibration file is not a dead end any more: the recorder entry has
# a stable AutomationId, so the template can be written with recorderButton
# already filled in. Only the recorder's unnamed buttons still need -Record.
# -EmitConfig does the same on demand and refreshes recorderButton while
# keeping pairs that were already captured. -NoWrite reports the file it would
# have written and leaves it alone.
if ($NoWrite -and ($EmitConfig -or -not $cfg)) {
    Write-Host ''
    Write-Host ('  Calibration file: {0} (not written: -NoWrite)' -f $cfgPath) -ForegroundColor Cyan
    if ($cfg) {
        Write-Host '    using the existing file as-is' -ForegroundColor Gray
    } else {
        Write-Host '    no file there - -Apply needs one; re-run -Probe without -NoWrite to write the template' -ForegroundColor Yellow
    }
} elseif ($EmitConfig -or -not $cfg) {
    $recorderPoint = $null
    foreach ($t in $targets) {
        if (-not $t.Window) { continue }
        $recorderPoint = Get-RecorderButtonPoint -Window $t.Window
        if ($recorderPoint) { break }
    }
    Write-Host ''
    Write-Host ('  Calibration file: {0}' -f $cfgPath) -ForegroundColor Cyan
    $null = Write-MmorConfigTemplate -Path $cfgPath -Point $recorderPoint -Base $cfg
    if ($recorderPoint) {
        Write-Host ('    + recorderButton [{0}, {1}] <- kToolMenu.kToolMenuBtn' -f $recorderPoint[0], $recorderPoint[1]) -ForegroundColor Gray
    } else {
        Write-Host '    + recorderButton left null - no running instance window to derive it from' -ForegroundColor Yellow
    }
    Write-Host '    playButton: null - run -Record, click the recorder entry, then Play' -ForegroundColor DarkGray
    $cfg = Read-MmorConfig -Path $cfgPath
}

Write-Host ''
Write-Host '  Click plan' -ForegroundColor Cyan
if (-not $cfg) {
    Write-Host ('    ! no config at {0}' -f $cfgPath) -ForegroundColor Yellow
    Write-Host '      run -Record, click the recorder entry and Play, then fill in the file' -ForegroundColor DarkGray
} else {
    foreach ($t in $targets) {
        if (-not $t.Window) { continue }
        $p = Get-Point -Config $cfg -Name 'recorderButton' -Window $t.Window
        if ($p) { Write-Host ('    [{0}] recorder entry -> {1},{2} (normalized {3},{4})' -f $t.Index, $p.X, $p.Y, $p.Nx, $p.Ny) -ForegroundColor Gray }
        else { Write-Host ('    [{0}] recorderButton missing or out of range' -f $t.Index) -ForegroundColor Yellow }
    }
    if ($cfg.fileRow) { Write-Host ('    file row -> normalized {0},{1} inside the recorder window' -f $cfg.fileRow[0], $cfg.fileRow[1]) -ForegroundColor Gray }
    else { Write-Host '    file row: not configured - the recorder must already show the wanted file' -ForegroundColor DarkGray }
    if ($cfg.playButton) { Write-Host ('    play -> normalized {0},{1} inside the recorder window' -f $cfg.playButton[0], $cfg.playButton[1]) -ForegroundColor Gray }
    else { Write-Host '    playButton missing - -Apply would have nothing to press' -ForegroundColor Yellow }
}

if (-not $Apply -or $Probe) {
    Write-Host ''
    Write-Host '  Probe finished. Nothing was pressed.' -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# Apply path: focus, open the recorder, pick the file, press play.
# Every step re-checks what it found before it clicks; the run stops at the
# first missing window or point instead of clicking at a guess.
# ---------------------------------------------------------------------------
if (-not $File) { throw '-File is required for -Apply (the .mmor to play).' }
if (-not (Test-Path -LiteralPath $File)) { throw "recording not found: $File" }
if ($targets.Count -ne 1) { throw '-Apply drives exactly one instance; use -Instance <n>.' }
if (-not $cfg) { throw "No calibration config at $cfgPath - run -Record, then fill it in." }

$target = $targets[0]
if (-not $target.Window) { throw "instance $($target.Index) has no window - start it and retry." }
$player = $target.Window
$baseline = @($windows | ForEach-Object { $_.Handle })

Write-Host ''
Write-Host ('  Playing {0} on instance {1}' -f (Split-Path -Leaf $File), $target.Index) -ForegroundColor Cyan

$null = [MmorApi]::Focus($player.Handle)
Start-Sleep -Milliseconds 400

$entry = Get-Point -Config $cfg -Name 'recorderButton' -Window $player
if (-not $entry) { throw 'recorderButton is missing from the config.' }
Write-Host ('  › click the recorder entry ({0},{1})' -f $entry.X, $entry.Y) -ForegroundColor Gray
[MmorApi]::Click($entry.X, $entry.Y, $false) | Out-Null
$openDelay = 2500
if ($cfg.delays -and $cfg.delays.afterOpenMs) { $openDelay = [int]$cfg.delays.afterOpenMs }
Start-Sleep -Milliseconds $openDelay

$recorder = $null
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while (-not $recorder -and (Get-Date) -lt $deadline) {
    $fresh = @(Get-WindowList)
    $new = @($fresh | Where-Object { $baseline -notcontains $_.Handle })
    if ($new.Count -gt 0) { $recorder = $new[0] }
    if (-not $recorder) { Start-Sleep -Milliseconds 500 }
}
if (-not $recorder) {
    throw "no new window appeared within $WaitSeconds s - the recorder entry point is wrong; re-run -Record."
}
Write-Host ('  › recorder window {0} {1} ''{2}'' {3},{4} {5}x{6}' -f $recorder.Handle, $recorder.Class, $recorder.Title, $recorder.X, $recorder.Y, $recorder.Width, $recorder.Height) -ForegroundColor Gray

if ($cfg.fileRow) {
    $rowPoint = Get-Point -Config $cfg -Name 'fileRow' -Window $recorder
    if (-not $rowPoint) { throw 'fileRow is in the config but out of range.' }
    Write-Host ('  › double-click the file row ({0},{1})' -f $rowPoint.X, $rowPoint.Y) -ForegroundColor Gray
    [MmorApi]::Click($rowPoint.X, $rowPoint.Y, $true) | Out-Null
    $fileDelay = 800
    if ($cfg.delays -and $cfg.delays.afterFileMs) { $fileDelay = [int]$cfg.delays.afterFileMs }
    Start-Sleep -Milliseconds $fileDelay
}

$play = Get-Point -Config $cfg -Name 'playButton' -Window $recorder
if (-not $play) { throw 'playButton is missing from the config.' }
Write-Host ('  › click play ({0},{1})' -f $play.X, $play.Y) -ForegroundColor Gray
[MmorApi]::Click($play.X, $play.Y, $false) | Out-Null
$playDelay = 500
if ($cfg.delays -and $cfg.delays.afterPlayMs) { $playDelay = [int]$cfg.delays.afterPlayMs }
Start-Sleep -Milliseconds $playDelay

# Without reading pixels the only observable is that the recorder is still
# there, so that is all this reports - never "playback started".
Write-Host ('  ✓ clicks sent; the recorder window is still open ({0})' -f $recorder.Handle) -ForegroundColor Green
Write-Host '    Playback itself is not verifiable from the window list - watch the instance.' -ForegroundColor DarkGray
exit 0
