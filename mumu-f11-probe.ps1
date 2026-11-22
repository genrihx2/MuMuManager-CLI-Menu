#Requires -Version 5.1
<#
.SYNOPSIS
    MuMu F11 probe: проверяет, даёт ли инстанс на движке 12.0 настоящую смену
    видеорежима (эксклюзивный фуллскрин), а не borderless-растяжку окна.

.DESCRIPTION
    Стадии (запускать по порядку, каждая — одна команда):
      Prepare  — свободный индекс, создание/проверка инстанса на 12.0,
                 хэш-снимок инстансов 15.0 «до», baseline логов, режим монитора «до».
      Wait     — вы нажимаете F11 и Esc, скрипт опрашивает режим монитора.
      Report   — выписка shell.log и graphics_log по паттернам + вердикт.
      Cleanup  — shutdown инстанса, хэш-снимок 15.0 «после», сравнение, опционально delete.

    Инстансы из -ProtectedIndexes (по умолчанию 0,1) не трогаются никогда:
    ни create/clone/delete, ни запись конфигов. F11 нажимает пользователь.

    Совместимость: Windows PowerShell 5.1 и PowerShell 7.
    Кодировка файла: UTF-8 с BOM, переводы строк LF.

.EXAMPLE
    .\mumu-f11-probe.ps1 -Stage Prepare -AllowCreate
    .\mumu-f11-probe.ps1 -Stage Wait
    .\mumu-f11-probe.ps1 -Stage Report
    .\mumu-f11-probe.ps1 -Stage Cleanup
#>
[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'Wait', 'Report', 'Cleanup')]
    [string]$Stage = 'Prepare',

    # -1 — взять первый свободный индекс начиная с 2
    [int]$Index = -1,

    [string]$Root = 'C:\Program Files\Netease\MuMuPlayer',

    [string]$OutDir = (Join-Path $env:USERPROFILE 'mumu-f11-probe'),

    # Индексы, которые нельзя затрагивать ни при каких условиях
    [int[]]$ProtectedIndexes = @(0, 1),

    # Разрешить create нового инстанса (без флага стадия Prepare только проверяет)
    [switch]$AllowCreate,

    # Разрешить delete пробного инстанса на стадии Cleanup
    [switch]$AllowDelete,

    # Сколько секунд опрашивать режим монитора на стадии Wait
    [int]$WatchSeconds = 40
)

$ErrorActionPreference = 'Stop'

$EngineTag    = '12.0'
$ProtectedTag = '15.0'
$StateFile    = Join-Path $OutDir 'state.json'
$ConfigExts   = @('.json', '.cfg', '.ini')

$ShellPatterns = @(
    'onTriggerShortcut',
    'FullScreenMode',
    'key text:\s*F11',
    'windowStateChanged',
    'WindowFullScreen',
    'WindowNoState|WindowMaximized',
    'setFullScreen',
    'FullScreenOutEsc',
    'fullscreen',
    'flushVmKeys',
    'SetWindowPos',
    'geometry|windowRect|screenRect'
)

$GfxPatterns = @(
    'exclusive',
    'Exclusive fullscreen condition detected',
    'SetFullscreenState|FullscreenState|ALLOW_MODE_SWITCH',
    'display.?mode|SetDisplayMode|ChangeDisplaySettings|DEVMODE|dmPelsWidth|dmDisplayFrequency',
    'swapchain|Swapchain|VK_KHR_swapchain|PresentMode|VK_PRESENT_MODE',
    'borderless|frameless|windowed|WindowFullScreen',
    'renderer_platform|render_mode_choose|renderer_mode|gpu_id',
    'resolution|\b\d{3,4}x\d{3,4}\b',
    'refresh|vsync|present_vsync'
)

# --------------------------------------------------------------------------- #
# Общие хелперы
# --------------------------------------------------------------------------- #

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Get-MumuManager {
    param([string]$RootPath)
    $candidates = @(
        (Join-Path $RootPath 'nx_main\MuMuManager.exe'),
        (Join-Path $RootPath 'shell\MuMuManager.exe'),
        (Join-Path $RootPath 'nx_main\mumu-cli.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $found = Get-ChildItem -LiteralPath $RootPath -Recurse -File -Filter 'MuMuManager.exe' -ErrorAction SilentlyContinue |
             Sort-Object FullName | Select-Object -First 1
    if (-not $found) { throw "MuMuManager.exe не найден под '$RootPath'. Укажите -Root." }
    return $found.FullName
}

function Invoke-Mumu {
    param(
        [string]$Manager,
        [string[]]$Arguments
    )
    $raw = & $Manager @Arguments 2>&1
    return (($raw | Out-String).Trim())
}

function Get-MumuInstances {
    param([string]$Manager)
    $text = Invoke-Mumu -Manager $Manager -Arguments @('info', '-v', 'all')
    if (-not $text) { throw 'info -v all вернул пустой ответ.' }
    try {
        return @($text | ConvertFrom-Json)
    }
    catch {
        throw "info -v all вернул не JSON:`n$text"
    }
}

function Get-IndexFromDirName {
    param([string]$Name)
    if ($Name -match '-(\d+)$') { return [int]$Matches[1] }
    return -1
}

function Get-FreeIndex {
    param([object[]]$Instances)
    $used = @($Instances | ForEach-Object { [int]$_.index })
    $i = 2
    while ($used -contains $i) { $i++ }
    return $i
}

function Get-InstanceDirs {
    param([string]$RootPath, [int]$VmIndex)
    $bases = @(
        (Join-Path $RootPath 'vms'),
        (Join-Path $RootPath 'nx_device\12.0\vms'),
        (Join-Path $RootPath 'nx_device\15.0\vms')
    )
    foreach ($b in $bases) {
        if (-not (Test-Path -LiteralPath $b)) { continue }
        Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue |
            Where-Object { (Get-IndexFromDirName $_.Name) -eq $VmIndex }
    }
}

# Замена Get-ChildItem -Include: фильтр по расширению, надёжен с -LiteralPath в 5.1
function Get-InstanceConfigFiles {
    param(
        [string]$Path,
        [switch]$NoRecurse
    )
    if ($NoRecurse) {
        $items = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue)
    }
    else {
        $items = @(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)
    }
    return @($items | Where-Object { $ConfigExts -contains $_.Extension.ToLowerInvariant() })
}

function Get-InstanceEngineTags {
    param([System.IO.DirectoryInfo]$Dir)
    $tags = New-Object System.Collections.Generic.HashSet[string]
    if ($Dir.Name -match '(\d+\.\d+)') { [void]$tags.Add($Matches[1]) }
    foreach ($f in (Get-InstanceConfigFiles -Path $Dir.FullName)) {
        $txt = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $txt) { continue }
        foreach ($m in [regex]::Matches($txt, 'nx_device[\\/]+(\d+\.\d+)')) {
            [void]$tags.Add($m.Groups[1].Value)
        }
    }
    return @($tags)
}

function Get-ShellLogFile {
    param([System.IO.DirectoryInfo]$Dir)
    $logs = Join-Path $Dir.FullName 'logs'
    if (-not (Test-Path -LiteralPath $logs)) { return $null }
    return (Get-ChildItem -LiteralPath $logs -File -Filter 'shell.log*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Get-ProtectedSnapshot {
    param(
        [string]$RootPath,
        [int]$ProbeIndex,
        [string]$Tag = $ProtectedTag
    )
    $rows = @()
    $base = Join-Path $RootPath 'vms'
    if (-not (Test-Path -LiteralPath $base)) { return @() }
    $dirs = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like "*$Tag*" -and (Get-IndexFromDirName $_.Name) -ne $ProbeIndex
            } | Sort-Object Name
    foreach ($d in $dirs) {
        $rows += [pscustomobject]@{
            Instance = $d.Name
            File     = '<dir-lastwrite-utc>'
            Hash     = ('{0:o}' -f $d.LastWriteTimeUtc)
            Size     = 0
        }
        foreach ($f in (Get-InstanceConfigFiles -Path $d.FullName | Sort-Object FullName)) {
            $rows += [pscustomobject]@{
                Instance = $d.Name
                File     = $f.FullName.Substring($base.Length + 1)
                Hash     = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
                Size     = $f.Length
            }
        }
    }
    return $rows
}

if (-not ('MuMuProbe.DEVMODE' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace MuMuProbe
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int   dmFields;
        public int   dmPositionX;
        public int   dmPositionY;
        public int   dmDisplayOrientation;
        public int   dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int   dmBitsPerPel;
        public int   dmPelsWidth;
        public int   dmPelsHeight;
        public int   dmDisplayFlags;
        public int   dmDisplayFrequency;
        public int   dmICMMethod;
        public int   dmICMIntent;
        public int   dmMediaType;
        public int   dmDitherType;
        public int   dmReserved1;
        public int   dmReserved2;
        public int   dmPanningWidth;
        public int   dmPanningHeight;
    }

    public static class Native
    {
        public const int ENUM_CURRENT_SETTINGS = -1;

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    }
}
'@
}

function Get-DisplayMode {
    $dm = [MuMuProbe.DEVMODE]::new()
    $dm.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($dm)
    $ok = [MuMuProbe.Native]::EnumDisplaySettings($null, [MuMuProbe.Native]::ENUM_CURRENT_SETTINGS, [ref]$dm)
    if (-not $ok) {
        return [pscustomobject]@{ Text = 'unknown'; Width = 0; Height = 0; Frequency = 0 }
    }
    return [pscustomobject]@{
        Text      = ('{0}x{1}@{2}Hz' -f $dm.dmPelsWidth, $dm.dmPelsHeight, $dm.dmDisplayFrequency)
        Width     = $dm.dmPelsWidth
        Height    = $dm.dmPelsHeight
        Frequency = $dm.dmDisplayFrequency
    }
}

function Watch-DisplayMode {
    param([int]$Seconds, [int]$IntervalMs = 500)
    $samples = @()
    $current = Get-DisplayMode
    $samples += [pscustomobject]@{ At = (Get-Date); Text = $current.Text }
    Write-Host ("  {0}  {1}" -f (Get-Date).ToString('HH:mm:ss'), $current.Text) -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds $IntervalMs
        $m = Get-DisplayMode
        if ($m.Text -ne $samples[-1].Text) {
            $samples += [pscustomobject]@{ At = (Get-Date); Text = $m.Text }
            Write-Host ("  {0}  {1}   <- ИЗМЕНЕНИЕ" -f (Get-Date).ToString('HH:mm:ss'), $m.Text) -ForegroundColor Yellow
        }
    }
    return $samples
}

function Select-HitsInLines {
    param([string[]]$Lines, [int]$StartLine, [string[]]$Patterns)
    $result = @()
    $n = $StartLine
    foreach ($l in $Lines) {
        $n++
        foreach ($p in $Patterns) {
            if ($l -match $p) {
                $result += [pscustomobject]@{ Line = $n; Pattern = $p; Text = $l.Trim() }
                break
            }
        }
    }
    return $result
}

function Get-NewLogLines {
    param([string]$Path, [int]$FromLine)
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    if ($FromLine -lt 0) { $FromLine = 0 }
    if ($FromLine -ge $lines.Count) { return @() }
    return @($lines[$FromLine..($lines.Count - 1)])
}

function Save-Json {
    param([object]$Value, [string]$Path)
    $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Нет файла состояния '$Path'. Сначала выполните -Stage Prepare."
    }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

# Присваивание поля в объекте состояния: существующее NoteProperty меняем,
# отсутствующее добавляем. Без безусловного Add-Member на PSCustomObject.
function Set-StateField {
    param(
        [object]$State,
        [string]$Name,
        [object]$Value,
        [string]$Path
    )
    $prop = $State.PSObject.Properties[$Name]
    if ($prop) {
        $prop.Value = $Value
    }
    else {
        $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    Save-Json -Value $State -Path $Path
}

# --------------------------------------------------------------------------- #
# Stage: Prepare
# --------------------------------------------------------------------------- #

function Invoke-Prepare {
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    }

    Write-Step "MuMu root: $Root"
    $manager = Get-MumuManager -RootPath $Root
    Write-Host "MuMuManager: $manager"

    Write-Step 'Список инстансов'
    $instances = Get-MumuInstances -Manager $manager
    $instances | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $OutDir '00-info-before.json') -Encoding UTF8
    $instances | Select-Object index, name, is_main, player_state, created_timestamp |
        Format-Table -AutoSize | Out-String | Write-Host

    if ($Index -lt 0) {
        $Index = Get-FreeIndex -Instances $instances
        Write-Host "Свободный индекс выбран автоматически: $Index"
    }
    if ($ProtectedIndexes -contains $Index) {
        throw "Индекс $Index входит в -ProtectedIndexes ($($ProtectedIndexes -join ', ')). Выберите другой."
    }

    $existing = @($instances | Where-Object { [int]$_.index -eq $Index })

    if ($existing.Count -gt 0) {
        Write-Host "Инстанс $Index уже существует: $($existing[0].name)"
    }
    else {
        if (-not $AllowCreate) {
            throw "Инстанс $Index отсутствует. Запустите с -AllowCreate, чтобы создать его (это займёт несколько ГБ)."
        }
        Write-Step "Создание инстанса $Index"
        $createOut = Invoke-Mumu -Manager $manager -Arguments @('create', '-v', "$Index")
        Write-Host $createOut
        Start-Sleep -Seconds 3
        $instances = Get-MumuInstances -Manager $manager
        $instances | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath (Join-Path $OutDir '00-info-after-create.json') -Encoding UTF8
    }

    Write-Step 'Проверка движка нового инстанса'
    $probeDirs = @(Get-InstanceDirs -RootPath $Root -VmIndex $Index)
    if ($probeDirs.Count -eq 0) {
        throw "Каталог инстанса $Index не найден ни в vms, ни в nx_device\*.0\vms. Проверьте создание."
    }
    $probeDir = $probeDirs[0]
    Write-Host "Каталог инстанса: $($probeDir.FullName)"
    $tags = @(Get-InstanceEngineTags -Dir $probeDir)
    Write-Host "Теги движка: $($tags -join ', ')"

    if ($tags -notcontains $EngineTag) {
        $msg = @(
            "Инстанс $Index создан не на движке $EngineTag (теги: $($tags -join ', ')).",
            'CLI create не умеет выбирать движок. Дальше:',
            "  1) $manager control -v $Index shutdown",
            "  2) $manager delete -v $Index",
            "  3) создать инстанс в мультиокне с явным выбором движка $EngineTag, индекс $Index,",
            '  4) снова запустить: .\mumu-f11-probe.ps1 -Stage Prepare'
        ) -join [Environment]::NewLine
        $msg | Set-Content -LiteralPath (Join-Path $OutDir '02-engine-mismatch.txt') -Encoding UTF8
        throw $msg
    }

    Write-Step 'Хэш-снимок защищённых инстансов (до)'
    $protectedBefore = @(Get-ProtectedSnapshot -RootPath $Root -ProbeIndex $Index)
    $protectedBefore | Export-Csv -LiteralPath (Join-Path $OutDir '02-protected-before.csv') `
        -NoTypeInformation -Encoding UTF8
    Write-Host "Файлов в снимке: $($protectedBefore.Count)"

    Write-Step 'Baseline логов'
    $shellLog = Get-ShellLogFile -Dir $probeDir
    $shellBaseline = 0
    $shellLogPath = $null
    if ($shellLog) {
        $shellBaseline = @(Get-Content -LiteralPath $shellLog.FullName).Count
        $shellLogPath = $shellLog.FullName
        Write-Host "shell.log: $shellLogPath (строк: $shellBaseline)"
    }
    else {
        Write-Host 'shell.log пока нет — появится после первого запуска инстанса.' -ForegroundColor Yellow
    }

    $gfxDirs = @(
        (Join-Path $Root 'nx_device\12.0\device\graphics_log'),
        (Join-Path $probeDir.FullName 'logs\graphics_log')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $gfxBaseline = @()
    foreach ($g in $gfxDirs) {
        $gfxBaseline += Get-ChildItem -LiteralPath $g -Recurse -File -ErrorAction SilentlyContinue |
                        Select-Object FullName, Length, LastWriteTimeUtc
    }
    $gfxBaseline | Export-Csv -LiteralPath (Join-Path $OutDir '03-gfx-baseline.csv') `
        -NoTypeInformation -Encoding UTF8
    Write-Host "Файлов graphics_log: $($gfxBaseline.Count)"

    Write-Step 'Режим монитора (до)'
    $modeBefore = Get-DisplayMode
    $modeBefore.Text | Set-Content -LiteralPath (Join-Path $OutDir '04-mode-before-F11.txt') -Encoding UTF8
    Write-Host $modeBefore.Text

    $state = [pscustomobject]@{
        Stage         = 'Prepared'
        Index         = $Index
        Root          = $Root
        Manager       = $manager
        OutDir        = $OutDir
        EngineTag     = $EngineTag
        InstanceDir   = $probeDir.FullName
        ShellLog      = $shellLogPath
        ShellBaseline = $shellBaseline
        GfxDirs       = @($gfxDirs)
        T0            = (Get-Date).ToString('o')
        T1            = $null
        T2            = $null
        ModeBefore    = $modeBefore.Text
    }
    Save-Json -Value $state -Path $StateFile

    Write-Step 'Готово'
    Write-Host @"
Дальше по порядку:
  1) $manager control -v $Index launch
     (дождитесь загрузки Android, окно эмулятора должно быть на переднем плане)
  2) .\mumu-f11-probe.ps1 -Stage Wait
     — скрипт попросит нажать Enter и сразу F11, затем Enter и Esc
  3) .\mumu-f11-probe.ps1 -Stage Report
  4) .\mumu-f11-probe.ps1 -Stage Cleanup
Инстансы $($ProtectedIndexes -join ', ') не затрагиваются.
"@
}

# --------------------------------------------------------------------------- #
# Stage: Wait
# --------------------------------------------------------------------------- #

function Invoke-Wait {
    $state = Read-Json -Path $StateFile
    if ($state.Stage -ne 'Prepared') {
        throw "Неподходящее состояние '$($state.Stage)'. Выполните -Stage Prepare."
    }

    Write-Step "Инстанс $($state.Index): нажмите Enter, затем сразу F11 в окне эмулятора"
    [void](Read-Host 'Enter — начать опрос режима монитора')
    $before = Get-DisplayMode
    Write-Host "Стартовый режим: $($before.Text)"
    Write-Host "Опрос $WatchSeconds сек..." -ForegroundColor DarkGray
    $samples = @(Watch-DisplayMode -Seconds $WatchSeconds)
    $samples | ForEach-Object { '{0:HH:mm:ss.fff};{1}' -f $_.At, $_.Text } |
        Set-Content -LiteralPath (Join-Path $state.OutDir '05-mode-F11-samples.csv') -Encoding UTF8
    $afterF11 = $samples[-1]
    $afterF11.Text | Set-Content -LiteralPath (Join-Path $state.OutDir '05-mode-after-F11.txt') -Encoding UTF8
    Write-Host "Режим после F11: $($afterF11.Text)"

    Write-Step 'Теперь нажмите Esc для выхода из фуллскрина'
    [void](Read-Host 'Enter — начать опрос после Esc')
    $escSeconds = [math]::Max(10, [int]($WatchSeconds / 2))
    $samplesEsc = @(Watch-DisplayMode -Seconds $escSeconds)
    $samplesEsc | ForEach-Object { '{0:HH:mm:ss.fff};{1}' -f $_.At, $_.Text } |
        Set-Content -LiteralPath (Join-Path $state.OutDir '06-mode-Esc-samples.csv') -Encoding UTF8
    $afterEsc = $samplesEsc[-1]
    $afterEsc.Text | Set-Content -LiteralPath (Join-Path $state.OutDir '06-mode-after-Esc.txt') -Encoding UTF8
    Write-Host "Режим после Esc: $($afterEsc.Text)"

    Set-StateField -State $state -Name T1 -Value ((Get-Date).ToString('o')) -Path $StateFile
    Set-StateField -State $state -Name Stage -Value 'Waited' -Path $StateFile
    Write-Host 'Стадия Wait завершена. Дальше: -Stage Report' -ForegroundColor Green
}

# --------------------------------------------------------------------------- #
# Stage: Report
# --------------------------------------------------------------------------- #

function Invoke-Report {
    $state = Read-Json -Path $StateFile
    $out   = $state.OutDir
    $t0    = [datetime]::Parse($state.T0)

    $report = New-Object System.Collections.Generic.List[string]
    $report.Add('# MuMu F11 probe report')
    $report.Add("Инстанс: $($state.Index) | движок: $($state.EngineTag) | каталог: $($state.InstanceDir)")
    $report.Add("T0: $($state.T0)")
    $report.Add('')

    Write-Step 'shell.log: строки после baseline'
    $shellHits = @()
    if ($state.ShellLog -and (Test-Path -LiteralPath $state.ShellLog)) {
        $newLines = @(Get-NewLogLines -Path $state.ShellLog -FromLine ([int]$state.ShellBaseline))
        $shellHits = @(Select-HitsInLines -Lines $newLines `
                           -StartLine ([int]$state.ShellBaseline) -Patterns $ShellPatterns)
        Write-Host "Новых строк: $($newLines.Count), совпадений: $($shellHits.Count)"
    }
    else {
        Write-Host 'shell.log не найден или не был записан в state.' -ForegroundColor Yellow
    }
    $shellHits | Export-Csv -LiteralPath (Join-Path $out '07-shell-hits.csv') `
        -NoTypeInformation -Encoding UTF8
    $report.Add('## shell.log')
    if ($shellHits.Count -eq 0) { $report.Add('(совпадений нет)') }
    foreach ($h in ($shellHits | Select-Object -Last 400)) {
        $report.Add(('{0,7} | {1} | {2}' -f $h.Line, $h.Pattern, $h.Text))
    }
    $report.Add('')

    Write-Step 'graphics_log: файлы, изменённые после T0 (с запасом 5 мин)'
    $gfxHits = @()
    $gfxFiles = @()
    $since = $t0.AddMinutes(-5)
    foreach ($g in @($state.GfxDirs)) {
        if (-not (Test-Path -LiteralPath $g)) { continue }
        $gfxFiles += @(Get-ChildItem -LiteralPath $g -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.LastWriteTime -ge $since })
    }
    foreach ($f in ($gfxFiles | Sort-Object LastWriteTime)) {
        $lines = @(Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue)
        foreach ($h in (Select-HitsInLines -Lines $lines -StartLine 0 -Patterns $GfxPatterns)) {
            $gfxHits += [pscustomobject]@{
                File = $f.Name; Line = $h.Line; Pattern = $h.Pattern; Text = $h.Text
            }
        }
    }
    Write-Host "Файлов: $($gfxFiles.Count), совпадений: $($gfxHits.Count)"
    $gfxHits | Export-Csv -LiteralPath (Join-Path $out '08-gfx-hits.csv') `
        -NoTypeInformation -Encoding UTF8
    $report.Add('## graphics_log')
    if ($gfxHits.Count -eq 0) { $report.Add('(совпадений нет)') }
    foreach ($h in ($gfxHits | Select-Object -Last 400)) {
        $report.Add(('{0} :{1} | {2} | {3}' -f $h.File, $h.Line, $h.Pattern, $h.Text))
    }
    $report.Add('')

    Write-Step 'Строки рендерера 12.0 (discover паттернов)'
    $rendererDir = Join-Path $state.Root 'nx_device\12.0\device'
    $wordRe = [regex]'(?i)fullscreen|full_screen|exclusive|display.?mode|devmode|swapchain|present|borderless|frameless|refresh'
    $dllLines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $rendererDir) {
        foreach ($dll in (Get-ChildItem -LiteralPath $rendererDir -File -Filter 'lib*.dll' -ErrorAction SilentlyContinue)) {
            $bytes = [System.IO.File]::ReadAllBytes($dll.FullName)
            $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
            foreach ($m in [regex]::Matches($text, '[\x20-\x7E]{6,}')) {
                if ($wordRe.IsMatch($m.Value)) { $dllLines.Add("$($dll.Name)`t$($m.Value)") }
            }
        }
    }
    $uniqueDllLines = @($dllLines | Select-Object -Unique)
    $uniqueDllLines | Set-Content -LiteralPath (Join-Path $out '09-renderer-strings.txt') -Encoding UTF8
    Write-Host "Строк рендерера: $($uniqueDllLines.Count)"
    $report.Add('## renderer strings (12.0)')
    $report.Add('См. 09-renderer-strings.txt')
    $report.Add('')

    Write-Step 'Вердикт'
    $modeBefore = [string]$state.ModeBefore
    $modeF11 = 'unknown'
    $modeEsc = 'unknown'
    $pathF11 = Join-Path $out '05-mode-after-F11.txt'
    $pathEsc = Join-Path $out '06-mode-after-Esc.txt'
    if (Test-Path -LiteralPath $pathF11) {
        $modeF11 = (Get-Content -LiteralPath $pathF11 -Raw).Trim()
    }
    if (Test-Path -LiteralPath $pathEsc) {
        $modeEsc = (Get-Content -LiteralPath $pathEsc -Raw).Trim()
    }

    $modeChanged = $false
    if ($modeBefore -ne $modeF11 -and $modeF11 -ne 'unknown') { $modeChanged = $true }

    $modeRestored = $false
    if ($modeEsc -eq $modeBefore -and $modeEsc -ne 'unknown') { $modeRestored = $true }

    $gfxText = ($gfxHits | ForEach-Object { $_.Text }) -join ' '
    $hasExclusiveCall = $gfxText -match '(?i)SetFullscreenState|ALLOW_MODE_SWITCH|Exclusive fullscreen condition detected'

    $hasBorderlessOnly = $false
    if (-not $hasExclusiveCall -and $gfxText -match '(?i)swapchain|borderless|windowed') {
        $hasBorderlessOnly = $true
    }

    $shellText = ($shellHits | ForEach-Object { $_.Text }) -join ' '
    $shellHasState = $shellText -match 'WindowFullScreen'

    $verdict = 'INCONCLUSIVE: данных недостаточно, смотрите 07-shell-hits.csv и 08-gfx-hits.csv'
    $color = 'DarkYellow'
    if (($modeChanged -and $modeRestored) -or $hasExclusiveCall) {
        $verdict = 'EXCLUSIVE: смена видеорежима подтверждена'
        $color = 'Green'
    }
    elseif ($shellHasState -and -not $modeChanged) {
        $verdict = 'BORDERLESS: окно растянуто, режим монитора не менялся'
        $color = 'Yellow'
    }

    $report.Add('## Вердикт')
    $report.Add("- режим до F11:      $modeBefore")
    $report.Add("- режим после F11:   $modeF11")
    $report.Add("- режим после Esc:   $modeEsc")
    $report.Add("- смена режима:      $modeChanged")
    $report.Add("- возврат режима:    $modeRestored")
    $report.Add("- exclusive-вызовы:  $hasExclusiveCall")
    $report.Add("- только swapchain:  $hasBorderlessOnly")
    $report.Add("- WindowFullScreen:  $shellHasState")
    $report.Add('')
    $report.Add("**$verdict**")

    $report | Set-Content -LiteralPath (Join-Path $out 'REPORT.md') -Encoding UTF8
    Write-Host $verdict -ForegroundColor $color
    $report | Select-Object -Last 9 | Write-Host
    Write-Host "Отчёт: $(Join-Path $out 'REPORT.md')"
}

# --------------------------------------------------------------------------- #
# Stage: Cleanup
# --------------------------------------------------------------------------- #

function Invoke-Cleanup {
    $state = Read-Json -Path $StateFile
    $out = $state.OutDir
    $manager = $state.Manager
    $Index = [int]$state.Index

    if ($ProtectedIndexes -contains $Index) {
        throw "Отказ: индекс $Index защищён."
    }

    Write-Step "Остановка инстанса $Index"
    $stillThere = @(Get-MumuInstances -Manager $manager | Where-Object { [int]$_.index -eq $Index })
    if ($stillThere.Count -gt 0) {
        $shutdownOut = Invoke-Mumu -Manager $manager -Arguments @('control', '-v', "$Index", 'shutdown')
        Write-Host $shutdownOut
        Start-Sleep -Seconds 5
    }

    Write-Step 'Хэш-снимок защищённых инстансов (после)'
    $protectedAfter = @(Get-ProtectedSnapshot -RootPath $state.Root -ProbeIndex $Index)
    $protectedAfter | Export-Csv -LiteralPath (Join-Path $out '10-protected-after.csv') `
        -NoTypeInformation -Encoding UTF8

    $beforePath = Join-Path $out '02-protected-before.csv'
    if (Test-Path -LiteralPath $beforePath) {
        $beforeRows = @(Import-Csv -LiteralPath $beforePath)
        $diff = @(Compare-Object -ReferenceObject $beforeRows -DifferenceObject $protectedAfter `
                     -Property Instance, File, Hash)
        if ($diff.Count -eq 0) {
            'OK: защищённые инстансы не изменились' |
                Set-Content -LiteralPath (Join-Path $out '11-protected-diff.txt') -Encoding UTF8
            Write-Host 'OK: защищённые инстансы не изменились' -ForegroundColor Green
        }
        else {
            $diff | Format-Table -AutoSize | Out-String |
                Set-Content -LiteralPath (Join-Path $out '11-protected-diff.txt') -Encoding UTF8
            Write-Host "ВНИМАНИЕ: различия в защищённых инстансах ($($diff.Count)) — см. 11-protected-diff.txt" -ForegroundColor Red
        }
    }

    if ($AllowDelete) {
        Write-Step "Удаление пробного инстанса $Index"
        $deleteOut = Invoke-Mumu -Manager $manager -Arguments @('delete', '-v', "$Index")
        Write-Host $deleteOut
    }
    else {
        Write-Host "Инстанс $Index оставлен. Удалить: -Stage Cleanup -AllowDelete" -ForegroundColor DarkGray
    }

    Set-StateField -State $state -Name T2 -Value ((Get-Date).ToString('o')) -Path $StateFile
    Set-StateField -State $state -Name Stage -Value 'Done' -Path $StateFile
}

# --------------------------------------------------------------------------- #
# Диспетчер
# --------------------------------------------------------------------------- #

switch ($Stage) {
    'Prepare' { Invoke-Prepare }
    'Wait'    { Invoke-Wait }
    'Report'  { Invoke-Report }
    'Cleanup' { Invoke-Cleanup }
}
