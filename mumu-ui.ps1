#requires -Version 5.1
<#
.SYNOPSIS
    MuMu Manager - native window (WPF) for the MuMu Manager CLI Menu.

.DESCRIPTION
    The same local MuMuManager.exe the console menu drives, in one window:
    every device as a card with its Android version, state and frame limit,
    accent buttons for launch / stop / restart, a repair that recreates a
    broken device, a frame-rate setter, and a log pane with the raw replies.

    Nothing here re-implements the shell logic. Actions map onto the manager:
      info    -v all        -> the list
      control -v <i> ...    -> launch / shutdown / restart
      delete  -v <i>        -> remove the device (the only removal that also
                                unregisters it; deleting vms folders by hand
                                leaves a ghost the manager keeps listing)
      create  -ver <n>      -> build the device again
      setting -v <i> -k max_frame_rate -val <n>
                            -> the limit the device settings screen shows as
                                "Максимальный FPS". It is NOT
                                customer_config.json's legacy
                                setting.frame_setting.desired_framerate: the
                                player rewrites that file from its own store,
                                so writing it changed nothing on screen.

    Read-only apart from the buttons that say so: refresh and the frame-rate
    read never write. Runs on PowerShell 5.1 and 7 (needs -STA for WPF).

.EXAMPLE
    pwsh -NoProfile -STA -File mumu-ui.ps1
#>
[CmdletBinding()]
param(
    # Full path to MuMuManager.exe. Empty = auto-detect.
    [string]$MumuPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- manager lookup --------------------------------------------------------
# The same candidate order the console menu uses, but read-only: this window
# must open even when MuMu is not installed, and say so instead of failing.
function Find-MumuManager {
    if ($MumuPath -and (Test-Path -LiteralPath $MumuPath -PathType Leaf)) { return $MumuPath }
    $candidates = @()
    foreach ($root in @("$env:ProgramFiles\Netease\MuMuPlayer", "${env:ProgramFiles(x86)}\Netease\MuMuPlayer",
            "$env:LOCALAPPDATA\Netease\MuMuPlayer", "$env:ProgramFiles\Netease\MuMu", "${env:ProgramFiles(x86)}\Netease\MuMu")) {
        if (-not $root) { continue }
        $candidates += (Join-Path $root 'nx_main\MuMuManager.exe')
        $candidates += (Join-Path $root 'MuMuManager.exe')
        $candidates += (Join-Path $root 'shell\MuMuManager.exe')
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
    }
    return ''
}

$script:Mgr = Find-MumuManager
$script:Brush = @{}
function Get-Brush {
    param([string]$Hex)
    if (-not $script:Brush.ContainsKey($Hex)) {
        $script:Brush[$Hex] = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex)
    }
    return $script:Brush[$Hex]
}

# --- window ----------------------------------------------------------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MuMu Manager" Height="760" Width="1080" MinHeight="580" MinWidth="900"
        Background="#0F1016" Foreground="#E8E9EE" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="Accent" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#2F7DF6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="9" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.68"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Accent}">
      <Setter Property="Background" Value="#1C1D26"/>
      <Setter Property="Foreground" Value="#C9CAD3"/>
      <Setter Property="FontWeight" Value="Normal"/>
    </Style>

    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Accent}">
      <Setter Property="Background" Value="#3A1D22"/>
      <Setter Property="Foreground" Value="#FF8A8A"/>
      <Setter Property="FontWeight" Value="Normal"/>
    </Style>

    <Style TargetType="ListViewItem">
      <Setter Property="Foreground" Value="#E8E9EE"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListViewItem">
            <Border x:Name="card" CornerRadius="12" Background="#16171F" BorderBrush="#23242E" BorderThickness="1" Padding="14,12">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="card" Property="Background" Value="#1B1C26"/></Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="card" Property="BorderBrush" Value="#2F7DF6"/>
                <Setter TargetName="card" Property="Background" Value="#1A2233"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Chip" TargetType="Border">
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Padding" Value="7,2"/>
      <Setter Property="Background" Value="#23242E"/>
    </Style>
  </Window.Resources>

  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="150"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" CornerRadius="14" Padding="20,16">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#16233A" Offset="0"/>
          <GradientStop Color="#121420" Offset="0.55"/>
          <GradientStop Color="#141824" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock x:Name="Header" Text="MuMu Manager" FontSize="26" FontWeight="Bold"
                     Foreground="#F2F4F8" Margin="0,0,0,4"/>
          <TextBlock x:Name="SubHeader" Text="читаю устройства..." FontSize="12" Foreground="#7E8296"
                     TextTrimming="CharacterEllipsis"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Border Style="{StaticResource Chip}" Background="#1E2A3A" Margin="0,0,8,0" Padding="12,7">
            <StackPanel>
              <TextBlock Text="УСТРОЙСТВ" FontSize="9" Foreground="#6E87A8" HorizontalAlignment="Center"/>
              <TextBlock x:Name="StatTotal" Text="0" FontSize="19" FontWeight="Bold"
                         Foreground="#8CC4FF" HorizontalAlignment="Center"/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Chip}" Background="#1B2C22" Padding="12,7">
            <StackPanel>
              <TextBlock Text="ЗАПУЩЕНО" FontSize="9" Foreground="#6E9A7E" HorizontalAlignment="Center"/>
              <TextBlock x:Name="StatRunning" Text="0" FontSize="19" FontWeight="Bold"
                         Foreground="#7EE2A8" HorizontalAlignment="Center"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </Grid>
    </Border>

    <TextBlock Grid.Row="1" Text="Устройства" FontSize="13" FontWeight="SemiBold"
                Foreground="#8B8FA3" Margin="4,18,0,8"/>

    <ListView x:Name="InstanceList" Grid.Row="2" Background="Transparent" BorderThickness="0"
              ScrollViewer.HorizontalScrollBarVisibility="Disabled">
      <ListView.ItemTemplate>
        <DataTemplate>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="52"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Width="40" Height="40" CornerRadius="10"
                    Background="{Binding IndexBrush}" VerticalAlignment="Center">
              <TextBlock Text="{Binding Index}" Foreground="#FFFFFF" FontSize="16" FontWeight="Bold"
                         HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>

            <StackPanel Grid.Column="1" Margin="6,0,10,0" VerticalAlignment="Center">
              <TextBlock Text="{Binding Name}" FontSize="15" FontWeight="SemiBold" Foreground="#EDEFF5"/>
              <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
                <Border Style="{StaticResource Chip}" Margin="0,0,6,0">
                  <TextBlock Text="{Binding AndroidLabel}" FontSize="11" Foreground="#8CC4FF"/>
                </Border>
                <Border Style="{StaticResource Chip}" Margin="0,0,6,0">
                  <TextBlock Text="{Binding FpsLabel}" FontSize="11" Foreground="#C6C8D4"/>
                </Border>
                <Border Style="{StaticResource Chip}" Background="{Binding StateChipBrush}">
                  <TextBlock Text="{Binding StateLabel}" FontSize="11" Foreground="{Binding StateBrush}"
                             FontWeight="SemiBold"/>
                </Border>
              </StackPanel>
            </StackPanel>

            <Border Grid.Column="2" Width="4" CornerRadius="2" Background="{Binding StateBrush}"
                    VerticalAlignment="Stretch" Opacity="0.9"/>
          </Grid>
        </DataTemplate>
      </ListView.ItemTemplate>
    </ListView>

    <Border Grid.Row="3" CornerRadius="12" Background="#14151D" Padding="12" Margin="0,6,0,0">
      <StackPanel>
        <WrapPanel Margin="0,0,0,4">
          <Button x:Name="RefreshButton" Content="Обновить" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
          <Button x:Name="CreateButton" Content="Создать устройство" Style="{StaticResource Accent}" Margin="0,0,8,4"/>
          <Button x:Name="SettingsButton" Content="Настройки устройства" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
          <Button x:Name="LaunchButton" Content="Запустить" Style="{StaticResource Accent}" Margin="0,0,8,4"/>
          <Button x:Name="StopButton" Content="Остановить" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
          <Button x:Name="RestartButton" Content="Перезапустить" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
        </WrapPanel>
        <WrapPanel>
          <Button x:Name="CloneButton" Content="Копировать" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
          <Button x:Name="RenameButton" Content="Переименовать" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
          <Button x:Name="BackupButton" Content="Резервная копия" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
          <Button x:Name="RestoreButton" Content="Восстановить" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
          <Button x:Name="RepairButton" Content="Починить устройство" Style="{StaticResource Danger}" Margin="0,0,8,4"/>
          <Button x:Name="DeleteButton" Content="Удалить" Style="{StaticResource Danger}" Margin="0,0,8,4"/>
        </WrapPanel>
      </StackPanel>
    </Border>

    <Border Grid.Row="4" CornerRadius="12" Background="#14151D" Padding="12" Margin="0,8,0,0">
      <WrapPanel>
        <TextBlock Text="Максимальный FPS" VerticalAlignment="Center" Foreground="#8B8FA3"
                    Margin="2,0,10,4" FontSize="12"/>
        <TextBox x:Name="FpsBox" Width="86" Height="32" Margin="0,0,8,4" FontSize="13"
                 Background="#12131B" Foreground="#E3E6EE" BorderBrush="#2A2C38" BorderThickness="1"
                 CaretBrush="#8CC4FF" Padding="8,6" VerticalContentAlignment="Center"/>
        <Button x:Name="ApplyFpsButton" Content="Применить" Style="{StaticResource Accent}" Margin="0,0,8,4"/>
        <Button x:Name="CliButton" Content="Консольное меню" Style="{StaticResource Ghost}" Margin="0,0,8,4"/>
        <Button x:Name="ExitButton" Content="Закрыть" Style="{StaticResource Ghost}" Margin="0,0,0,4"/>
      </WrapPanel>
    </Border>

    <Border Grid.Row="5" CornerRadius="12" Background="#0C0D12" BorderBrush="#1E1F29"
            BorderThickness="1" Margin="0,8,0,0" Padding="2">
      <TextBox x:Name="LogBox" Background="Transparent" Foreground="#A9AEC0" BorderThickness="0"
                FontFamily="Consolas" FontSize="12" IsReadOnly="True" Padding="10,8"
                VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    </Border>

    <TextBlock x:Name="StatusText" Grid.Row="6" Margin="4,10,0,0" FontSize="12"
                Foreground="#7E8296" Text="Готово"/>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml.OuterXml)
$ui = @{}
foreach ($name in @('Header', 'SubHeader', 'StatTotal', 'StatRunning', 'InstanceList', 'RefreshButton', 'CreateButton', 'SettingsButton', 'CloneButton', 'RenameButton', 'BackupButton', 'RestoreButton', 'DeleteButton',
        'LaunchButton', 'StopButton', 'RestartButton', 'RepairButton', 'FpsBox', 'ApplyFpsButton',
        'CliButton', 'ExitButton', 'LogBox', 'StatusText')) {
    $ui[$name] = $window.FindName($name)
}

function Write-Log {
    param([string]$Text)
    $ui.LogBox.AppendText(("[{0}] {1}`r`n" -f (Get-Date).ToString('HH:mm:ss'), $Text))
    $ui.LogBox.ScrollToEnd()
}

function Set-Status {
    param([string]$Text)
    $ui.StatusText.Text = $Text
    $window.Dispatcher.Invoke([Action] {}, 'Background')
}

function Invoke-Mgr {
    # Runs one manager command and returns its text. Never throws: the window
    # reports the failure in the log and keeps working.
    param([string[]]$Arguments, [string]$Label = '')
    if (-not $script:Mgr) { return [pscustomobject]@{ Ok = $false; Text = 'MuMuManager.exe not found' } }
    try {
        $out = @(& $script:Mgr @Arguments 2>&1 | ForEach-Object { "$_" })
        $text = ($out -join "`n").Trim()
        $ok = ($LASTEXITCODE -eq 0) -and -not ($text -match '(?i)"errcode"\s*:\s*[1-9]')
        if ($Label -or $text) { Write-Log ("{0}{1}" -f $(if ($Label) { "$Label -> " } else { '' }), $text) }
        return [pscustomobject]@{ Ok =$ok; Text = $text }
    } catch {
        Write-Log ("{0}: {1}" -f $Label, $_.Exception.Message)
        return [pscustomobject]@{ Ok =$false; Text = $_.Exception.Message }
    }
}

function Get-FrameLimit {
    param([string]$Index)
    if (-not $script:Mgr) { return '' }
    try {
        $raw = (& $script:Mgr setting -v $Index -k max_frame_rate 2>$null | Out-String)
        if ($raw -match '"max_frame_rate"\s*:\s*"?(\d+)"?') { return [int]$Matches[1] }
        if ($raw -match '^\s*"?(\d{1,3})"?\s*$') { return [int]$Matches[1] }
    } catch { Write-Debug "fps read failed: $($_.Exception.Message)" }
    return ''
}

# One manager call for every instance's frame limit instead of one per device:
# spawning MuMuManager costs ~0.2 s, which is what made the list feel slow.
function Get-FrameLimitMap {
    $map = @{}
    if (-not $script:Mgr) { return $map }
    try {
        $raw = (& $script:Mgr setting -v all -k max_frame_rate 2>$null | Out-String)
        $obj = $raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) {
            $v = $p.Value.max_frame_rate
            if ($null -ne $v) { $map[[string]$p.Name] = [string]$v }
        }
    } catch { Write-Debug "fps map failed: $($_.Exception.Message)" }
    return $map
}

function Convert-InstanceRows {
    param($InfoJson, $FpsJson)
    $json = $null
    try { $json = $InfoJson | ConvertFrom-Json } catch { }
    if (-not $json) { return @() }
    $fpsMap = @{}
    try {
        $f = $FpsJson | ConvertFrom-Json
        foreach ($p in $f.PSObject.Properties) {
            if ($null -ne $p.Value.max_frame_rate) { $fpsMap[[string]$p.Name] = [string]$p.Value.max_frame_rate }
        }
    } catch { }
    $rows = @()
    foreach ($prop in $json.PSObject.Properties) {
        $inst = $prop.Value
        $state = 'stopped'
        if ($inst.is_android_started -eq $true) { $state = 'running' }
        elseif ($inst.is_process_started -eq $true) { $state = 'starting' }
        elseif ($inst.player_state) { $state = [string]$inst.player_state }

        switch ($state) {
            'running' { $label = 'работает'; $dot = '#5BE39B'; $chip = '#173A28'; $idx = '#1F6F4A' }
            'starting' { $label = 'запускается'; $dot = '#F0C64A'; $chip = '#3A3218'; $idx = '#7A5E1F' }
            default { $label = 'остановлен'; $dot = '#7A8095'; $chip = '#20222C'; $idx = '#2C3350' }
        }
        if ($state -eq 'start_finished') { $label = 'запускается'; $dot = '#F0C64A'; $chip = '#3A3218' }

        $fps = $fpsMap[[string]$prop.Name]
        $rows += [pscustomobject]@{
            Index          = [string]$prop.Name
            Name           = [string]$inst.name
            AndroidLabel   = ("Android " + [string]$inst.android_version)
            StateLabel     = $label
            FpsLabel       = $(if ($fps) { "FPS $fps" } else { 'FPS —' })
            StateBrush     = (Get-Brush $dot)
            StateChipBrush = (Get-Brush $chip)
            IndexBrush     = (Get-Brush $idx)
        }
    }
    return $rows
}

function Get-Instances {
    if (-not $script:Mgr) { return @() }
    $info = & $script:Mgr info -v all 2>$null | Out-String
    $fps = & $script:Mgr setting -v all -k max_frame_rate 2>$null | Out-String
    return @(Convert-InstanceRows -InfoJson $info -FpsJson $fps)
}

function Apply-InstanceRows {
    param($Rows)
    $rows = @($Rows)
    $selected = $ui.InstanceList.SelectedItem
    $ui.InstanceList.ItemsSource = $rows
    $ui.StatTotal.Text = [string]$rows.Count
    $ui.StatRunning.Text = [string](@($rows | Where-Object { $_.StateLabel -eq 'работает' }).Count)
    if (-not $script:Mgr) {
        $ui.SubHeader.Text = 'MuMuManager.exe не найден — выберите установку в консольном меню [IN]'
    } else {
        $ui.SubHeader.Text = $script:Mgr
    }
    if ($rows.Count -gt 0) {
        $keep = if ($selected) { $selected.Index } else { $rows[0].Index }
        $ui.InstanceList.SelectedItem = ($rows | Where-Object { $_.Index -eq $keep } | Select-Object -First 1)
        if (-not $ui.InstanceList.SelectedItem) { $ui.InstanceList.SelectedIndex = 0 }
    }
    $sel = $ui.InstanceList.SelectedItem
    if ($sel) { $ui.FpsBox.Text = ([string]$sel.FpsLabel -replace '^FPS\s*', '') }
    Set-Status ("Обновлено {0}" -f (Get-Date).ToString('HH:mm:ss'))
}

function Update-View {
    Apply-InstanceRows -Rows (Get-Instances)
}

function Get-SelectedIndex {
    $sel = $ui.InstanceList.SelectedItem
    if (-not $sel) {
        [void][System.Windows.MessageBox]::Show('Сначала выберите устройство в списке.', 'MuMu Manager',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return ''
    }
    return [string]$sel.Index
}

# One-line prompt in the window's style, for rename / clone counts and the
# backup file name. Returns the trimmed text, or $null when cancelled.
function Show-InputDialog {
    param([string]$Title, [string]$Label, [string]$Value = '', [string]$Hint = '')
    [xml]$inXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MuMu Manager" Width="500" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Foreground="#E8E9EE" FontFamily="Segoe UI" ResizeMode="NoResize"
        ShowInTaskbar="False" WindowStartupLocation="CenterOwner">
  <Window.Resources>
    <Style x:Key="Accent" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#2F7DF6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="20,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="9" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.68"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Accent}">
      <Setter Property="Background" Value="#1C1D26"/>
      <Setter Property="Foreground" Value="#C9CAD3"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Padding" Value="16,9"/>
    </Style>
  </Window.Resources>
  <Border CornerRadius="16" Background="#12141C" BorderBrush="#272A3A" BorderThickness="1" Margin="14">
    <Border.Effect><DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/></Border.Effect>
    <Grid Margin="24,20,24,22">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock x:Name="DlgHeader" Grid.Row="0" Text="" FontSize="18" FontWeight="Bold"
                 Foreground="#F2F4F8" Margin="0,0,0,16" Background="Transparent"/>
      <TextBlock x:Name="DlgLabel" Grid.Row="1" Text="" FontSize="12" Foreground="#8B8FA3" Margin="0,0,0,8"/>
      <StackPanel Grid.Row="2" Margin="0,0,0,20">
        <TextBox x:Name="DlgInput" Height="36" FontSize="13" Foreground="#E3E6EE" Background="#12131B"
                 BorderBrush="#2A2C38" BorderThickness="1" Padding="10,7" CaretBrush="#8CC4FF"
                 VerticalContentAlignment="Center"/>
        <TextBlock x:Name="DlgHint" FontSize="11" Foreground="#6F7386" Margin="2,6,0,0"/>
      </StackPanel>
      <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="DlgCancel" Content="Отмена" Style="{StaticResource Ghost}" Margin="0,0,10,0"/>
        <Button x:Name="DlgOk" Content="OK" Style="{StaticResource Accent}"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse($inXaml.OuterXml)
    $dlg.Owner = $window
    $dlg.FindName('DlgHeader').Text = $Title
    $dlg.FindName('DlgLabel').Text = $Label
    $dlg.FindName('DlgHint').Text = $Hint
    $inputBox = $dlg.FindName('DlgInput')
    $inputBox.Text = $Value
    $dlg.Tag = $null

    $accept = { $dlg.Tag = [string]$inputBox.Text; $dlg.Close() }
    $dlg.FindName('DlgOk').Add_Click($accept)
    $dlg.FindName('DlgCancel').Add_Click({ $dlg.Close() })
    $inputBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq [System.Windows.Input.Key]::Enter) { & $accept } })
    $dlg.Add_ContentRendered({ [void]$inputBox.Focus(); $inputBox.SelectAll() })

    $null = $dlg.ShowDialog()
    if ($dlg.Tag -is [string]) { return $dlg.Tag.Trim() }
    return $null
}

# MuMu's own "Создать устройство" sheet, for the parts the CLI exposes.
# $create $ has no orientation switch (only --version, --number and --mini), so
# the dialog offers exactly those three instead of pretending otherwise.
# Returns $null on cancel, else @{ Version; Count; Mini }.
function Show-CreateDialog {
    [xml]$dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Создать устройство" Width="560" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Foreground="#E8E9EE" FontFamily="Segoe UI" ResizeMode="NoResize"
        ShowInTaskbar="False" WindowStartupLocation="CenterOwner">
  <Window.Resources>
    <Style x:Key="Accent" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#2F7DF6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="20,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="9" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.68"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Accent}">
      <Setter Property="Background" Value="#1C1D26"/>
      <Setter Property="Foreground" Value="#C9CAD3"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Padding" Value="16,9"/>
    </Style>
    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#DDE1EA"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" CornerRadius="9" Background="#1B1C26" BorderBrush="#2A2C38"
                    BorderThickness="1" Padding="18,9">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#20222E"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#2F7DF6"/>
                <Setter TargetName="b" Property="Background" Value="#17233A"/>
                <Setter Property="Foreground" Value="#9CC8FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border CornerRadius="16" Background="#12141C" BorderBrush="#272A3A" BorderThickness="1" Margin="14">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </Border.Effect>
    <Grid Margin="24,20,24,22">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid x:Name="DlgHeader" Grid.Row="0" Background="Transparent" Margin="0,0,0,20">
        <StackPanel>
          <TextBlock Text="Создать устройство" FontSize="19" FontWeight="Bold" Foreground="#F2F4F8"/>
          <TextBlock Text="Новый Android-эмулятор MuMu" FontSize="12" Foreground="#7E8296" Margin="0,3,0,0"/>
        </StackPanel>
        <Button x:Name="DlgClose" Content="✕" HorizontalAlignment="Right" VerticalAlignment="Top"
                Width="30" Height="30" Style="{StaticResource Ghost}" Padding="0" FontSize="13"/>
      </Grid>

      <StackPanel Grid.Row="1" Margin="0,0,0,18">
        <TextBlock Text="Версия Android" FontSize="12" Foreground="#8B8FA3" Margin="0,0,0,8"/>
        <StackPanel Orientation="Horizontal">
          <RadioButton x:Name="Ver15" Content="Android 15" GroupName="ver" Style="{StaticResource Seg}" IsChecked="True"/>
          <RadioButton x:Name="Ver12" Content="Android 12" GroupName="ver" Style="{StaticResource Seg}"/>
          <RadioButton x:Name="VerAuto" Content="Авто" GroupName="ver" Style="{StaticResource Seg}"/>
        </StackPanel>
      </StackPanel>

      <StackPanel Grid.Row="2" Margin="0,0,0,18">
        <TextBlock Text="Количество устройств" FontSize="12" Foreground="#8B8FA3" Margin="0,0,0,8"/>
        <StackPanel Orientation="Horizontal">
          <Button x:Name="CountMinus" Content="−" Width="38" Height="38" Padding="0" FontSize="16"
                  Style="{StaticResource Ghost}" Margin="0,0,8,0"/>
          <Border Background="#1B1C26" BorderBrush="#2A2C38" BorderThickness="1" CornerRadius="9"
                  Width="64" Height="38">
            <TextBlock x:Name="CountText" Text="1" FontSize="14" FontWeight="SemiBold"
                        HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <Button x:Name="CountPlus" Content="+" Width="38" Height="38" Padding="0" FontSize="16"
                  Style="{StaticResource Ghost}" Margin="8,0,0,0"/>
        </StackPanel>
      </StackPanel>

      <CheckBox x:Name="MiniBox" Grid.Row="3" Content="Минимальный диск (mini)"
                Foreground="#C9CAD3" FontSize="13" Margin="0,0,0,22"/>

      <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="DlgCancel" Content="Отмена" Style="{StaticResource Ghost}" Margin="0,0,10,0"/>
        <Button x:Name="DlgCreate" Content="Создать" Style="{StaticResource Accent}"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@

    $dlg = [Windows.Markup.XamlReader]::Parse($dlgXaml.OuterXml)
    $dlg.Owner = $window
    $dlg.Tag = 1   # device count

    $countText = $dlg.FindName('CountText')
    $dlg.FindName('CountMinus').Add_Click({ if ([int]$dlg.Tag -gt 1) { $dlg.Tag = [int]$dlg.Tag - 1; $countText.Text = [string]$dlg.Tag } })
    $dlg.FindName('CountPlus').Add_Click({ if ([int]$dlg.Tag -lt 10) { $dlg.Tag = [int]$dlg.Tag + 1; $countText.Text = [string]$dlg.Tag } })
    $dlg.FindName('DlgHeader').Add_MouseLeftButtonDown({ try { $dlg.DragMove() } catch { } })
    $dlg.FindName('DlgClose').Add_Click({ $dlg.Tag = $null; $dlg.Close() })
    $dlg.FindName('DlgCancel').Add_Click({ $dlg.Tag = $null; $dlg.Close() })
    $dlg.FindName('DlgCreate').Add_Click({
            $ver = if ($dlg.FindName('Ver15').IsChecked) { '15' }
            elseif ($dlg.FindName('Ver12').IsChecked) { '12' } else { 'auto' }
            $dlg.Tag = @{ Version = $ver; Count = [int]$countText.Text; Mini = [bool]$dlg.FindName('MiniBox').IsChecked }
            $dlg.Close()
        })

    $null = $dlg.ShowDialog()
    if ($dlg.Tag -is [hashtable]) { return $dlg.Tag }
    return $null
}

# --- device settings -------------------------------------------------------
# Every row below writes one key through "setting -v <i> -k <key> -val <v>"
# and then reads it back: the manager is the source of truth, not what we sent.
function Get-SettingsMap {
    param([string]$Index)
    $map = [ordered]@{}
    if (-not $script:Mgr) { return $map }
    try {
        $raw = (& $script:Mgr setting -v $Index -a 2>$null | Out-String)
        foreach ($line in ($raw -split "`n")) {
            $m = [regex]::Match($line.TrimEnd("`r"), '^\s*"([^"]+)"\s*:\s*"(.*)",?$')
            if ($m.Success) {$map[$m.Groups[1].Value] = $m.Groups[2].Value }
        }
    } catch { Write-Debug "settings read failed:$($_.Exception.Message)" }
    return $map
}

function Save-SettingValue {
    param([string]$Key, [string]$Value)
    $out = (& $script:Mgr setting -v $script:SettingsIndex -k $Key -val $Value 2>&1 | Out-String).Trim()
    # Read back only the key that changed: the full `setting -a` map costs
    # another process spawn per edit and made the window feel sluggish.
    $now = $Value
    try {
        $back = (& $script:Mgr setting -v $script:SettingsIndex -k $Key 2>$null | Out-String).Trim()
        if ($back -match '"([^"]+)"\s*:\s*"(.*)"') { $now = $Matches[2] }
        elseif ($back -match '^\s*"?([^"\s]+)"?\s*$') { $now = $Matches[1] }
    } catch { Write-Debug "read back failed: $($_.Exception.Message)" }
    $ok = ("$now" -eq "$Value")
    Write-Log ("setting {0} {1} = {2} -> {3}{4}" -f $script:SettingsIndex, $Key, $Value, $now, $(if ($out) { " | $out" } else { '' }))
    if ($ok) {
        Set-SettingsStatus ("Сохранено: {0} = {1}" -f $Key, $Value) '#5BE39B'
    } else {
        $shown = if ("$now" -eq '') { 'пусто' } else { "'$now'" }
        Set-SettingsStatus ("Не применилось: {0} = '{1}', менеджер отдаёт {2}" -f $Key, $Value, $shown) '#FF8A8A'
    }
    # A resolution change rewrites width/height/DPI, so only then is the
    # section rebuilt; anything else would just cost another round trip.
    if ($ok -and $Key -eq 'resolution_mode' -and $script:SettingsRefresh) { & $script:SettingsRefresh }
}

function Set-SettingsStatus {
    param([string]$Text, [string]$Color = '#7E8296')
    if (-not $script:SettingsStatusText) { return }
    $script:SettingsStatusText.Text = $Text
    $script:SettingsStatusText.Foreground = (Get-Brush $Color)
}

# GetNewClosure() gives a handler a fresh scope, and inside it $script: points
# at that scope rather than at the file, so a guard written as
# `if (-not $script:SettingsReady) { return }` was always true and every
# dropdown pick was dropped before it reached the manager. The function below
# reads the flag in a normal scope, which is why the rows can test it.
function Test-SettingsReady { return [bool]$script:SettingsReady }

# Row factories: each call has its own scope, so the click handlers keep the
# key they were built for instead of the last one the loop touched.
function New-SettingSwitch {
    param([string]$Key, [string]$Value, $Win)
    $t = New-Object System.Windows.Controls.Primitives.ToggleButton
    $t.Style = $Win.Resources['Switch']
    $t.IsChecked = ($Value -eq 'true')
    $t.Cursor = [System.Windows.Input.Cursors]::Hand
    # GetNewClosure(): without it the handler runs after this function returned
    # and $Key/$t no longer resolve, so the write went out with an empty key.
    $t.Add_Click({
            $v = if ($t.IsChecked) { 'true' } else { 'false' }
            Save-SettingValue -Key $Key -Value $v
        }.GetNewClosure())
    return $t
}

function New-SettingChoice {
    param([string]$Key, [string]$Value,$Options, $Win)
    $c = New-Object System.Windows.Controls.ComboBox
    $c.Style = $Win.Resources['DarkCombo']
    $items = @()
    $known = @($Options | ForEach-Object { $_.v })
    if ($Value -and ($known -notcontains $Value)) {
        $items += [pscustomobject]@{ Value = $Value; Label = ("Сейчас: " + $Value) }
    }
    foreach ($o in $Options) { $items += [pscustomobject]@{ Value = $o.v; Label = $o.l } }
    $c.ItemsSource = $items
    $c.ItemTemplate = [Windows.Markup.XamlReader]::Parse('<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding Label}" Foreground="#E3E6EE" TextTrimming="CharacterEllipsis"/></DataTemplate>')
    $c.SelectedValuePath = 'Value'
    $c.SelectedValue = $Value
    # Read the picked item, not SelectedValue: inside SelectionChanged the
    # SelectedValue property still holds the previous value (it is recomputed
    # after the event), so the write either never happened or repeated the old
    # value. SelectedItem is already the new row by then.
    $c.Add_SelectionChanged({
            if (-not (Test-SettingsReady)) { return }
            $item = $c.SelectedItem
            if (-not $item) { return }
            $v = [string]$item.Value
            if (-not $v -or $v -eq $Value) { return }
            Save-SettingValue -Key $Key -Value $v
        }.GetNewClosure())
    return $c
}

# A preset pick writes several keys at once (brand + model + code). Its own
# state is derived from the current values, so it always shows the row that
# matches the device instead of a value nobody stored anywhere.
function New-SettingPreset {
    param($Options, $Win, $Current)
    $c = New-Object System.Windows.Controls.ComboBox
    $c.Style = $Win.Resources['DarkCombo']
    $items = @()
    $selected = $null
    foreach ($o in $Options) {
        $items += [pscustomobject]@{ Value = $o.v; Label = $o.l }
        $match = $true
        foreach ($k in $o.extra.Keys) { if ([string]$Current[$k] -ne [string]$o.extra[$k]) { $match = $false } }
        if ($match -and -not $selected) { $selected = $o.v }
    }
    $c.ItemsSource = $items
    $c.ItemTemplate = [Windows.Markup.XamlReader]::Parse('<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding Label}" Foreground="#E3E6EE" TextTrimming="CharacterEllipsis"/></DataTemplate>')
    $c.SelectedValuePath = 'Value'
    $c.SelectedValue = $selected
    $c.Add_SelectionChanged({
            if (-not (Test-SettingsReady)) { return }
            $item = $c.SelectedItem
            if (-not $item) { return }
            $pick = [string]$item.Value
            if (-not $pick) { return }
            $opt = $Options | Where-Object { $_.v -eq $pick } | Select-Object -First 1
            if (-not $opt) { return }
            foreach ($k in $opt.extra.Keys) { Save-SettingValue -Key $k -Value ([string]$opt.extra[$k]) }
            Set-SettingsStatus ("Сохранено: {0}" -f $opt.l) '#5BE39B'
        }.GetNewClosure())
    return $c
}

function New-SettingText {
    param([string]$Key, [string]$Value, $Win)
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Style = $Win.Resources['TextInput']
    $tb.Text = $Value
    $tb.Tag = $Value
    $tb.Add_LostFocus({
            if ($tb.Text -ne $tb.Tag) { Save-SettingValue -Key $Key -Value $tb.Text; $tb.Tag = $tb.Text }
        }.GetNewClosure())
    $tb.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $tb.MoveFocus([System.Windows.Input.FocusNavigationDirection]::Next) }
        }.GetNewClosure())
    return $tb
}

# Disk rows show the numbers the manager really reports. `info -v <i>` has
# disk_size_bytes, which is the size MuMu draws for the device; the free space
# comes from the drive that holds the vms folder. A recursive sum over a vms
# folder that is tens of gigabytes would freeze the window for seconds, and
# MuMuManager has no "clean disk" or "expand disk" command, so the cleanup row
# offers the one honest action there is - opening the instance folder.
function Format-Size {
    param([double]$Bytes)
    if ($Bytes -le 0) { return '—' }
    if ($Bytes -ge 1GB) { return ('{0:N1} ГБ' -f ($Bytes / 1GB)) }
    return ('{0:N0} МБ' -f ($Bytes / 1MB))
}

# Not every instance has device_thumbnail: an instance created later can be
# missing the key entirely, and the old code then gave up on the path. The
# folder is still there under vms with MuMu's own naming rule, so when the
# thumbnail is absent the directory is found by its trailing -<index>.
function Get-InstanceFolder {
    param([string]$Index, [string]$Thumb)
    if ($Thumb) {
        try {
            $file = $Thumb -replace '\\{2,}', '\'
            $dir = Split-Path -Parent (Split-Path -Parent $file)
            if ($dir -and (Test-Path -LiteralPath $dir)) { return $dir }
        } catch { Write-Debug "thumbnail path failed: $($_.Exception.Message)" }
    }
    $vms = ''
    if ($script:Mgr) { $vms = Join-Path (Split-Path -Parent (Split-Path -Parent $script:Mgr)) 'vms' }
    if ($vms -and (Test-Path -LiteralPath $vms)) {
        try {
            $hit = Get-ChildItem -LiteralPath $vms -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match ('-' + [regex]::Escape($Index) + '$') } | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        } catch { Write-Debug "vms scan failed: $($_.Exception.Message)" }
    }
    return ''
}

function Get-DeviceDisk {
    param([string]$Index, [string]$Thumb)
    $used = 0.0
    if ($script:Mgr) {
        try {
            $raw = (& $script:Mgr info -v $Index 2>$null | Out-String)
            if ($raw -match '"disk_size_bytes"\s*:\s*(\d+)') { $used = [double]$Matches[1] }
        } catch { Write-Debug "disk size failed: $($_.Exception.Message)" }
    }
    $path = Get-InstanceFolder -Index $Index -Thumb $Thumb
    $free = 0.0
    $drive = ''
    $root = if ($path) { $path } elseif ($script:Mgr) { Split-Path -Parent $script:Mgr } else { '' }
    if ($root) {
        try {
            $di = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($root))
            $free = $di.AvailableFreeSpace
            $drive = $di.Name.TrimEnd('\')
        } catch { Write-Debug "free space failed: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ Used = $used; Free = $free; Drive = $drive; Path = $path }
}

function New-SettingDisk {
    param([string]$Key, [string]$Label, $Win, $Disk)
    if ($Key -eq 'disk_cleanup') {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $(if ($Label) { $Label } else { 'Открыть папку' })
        $b.Style = $Win.Resources['RowBtn']
        $b.Cursor = [System.Windows.Input.Cursors]::Hand
        $b.Add_Click({
                if ($Disk.Path -and (Test-Path -LiteralPath $Disk.Path)) {
                    Start-Process explorer.exe -ArgumentList ('"{0}"' -f $Disk.Path)
                    Write-Log ("disk {0}: open {1}" -f $script:SettingsIndex, $Disk.Path)
                    Set-SettingsStatus ("Открыта папка: {0}" -f $Disk.Path) '#5BE39B'
                } else {
                    Set-SettingsStatus 'Папка инстанса не найдена: менеджер не назвал путь' '#FF8A8A'
                }
            }.GetNewClosure())
        return $b
    }
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.HorizontalAlignment = 'Right'
    $used = New-Object System.Windows.Controls.TextBlock
    $used.Text = ("{0} занято" -f (Format-Size $Disk.Used))
    $used.FontSize = 14
    $used.FontWeight = 'SemiBold'
    $used.Foreground = (Get-Brush '#9CC8FF')
    $used.HorizontalAlignment = 'Right'
    $free = New-Object System.Windows.Controls.TextBlock
    $free.Text = $(if ($Disk.Free -gt 0) { 'свободно {0} на {1}' -f (Format-Size $Disk.Free), $Disk.Drive } else { 'свободное место не прочитано' })
    $free.FontSize = 11
    $free.Foreground = (Get-Brush '#787C8E')
    $free.HorizontalAlignment = 'Right'
    $free.Margin = '0,3,0,0'
    [void]$sp.Children.Add($used)
    [void]$sp.Children.Add($free)
    return $sp
}

function Get-SettingSchema {
    $fps = @(15, 20, 30, 45, 60, 90, 120, 144, 240 | ForEach-Object { @{ v = [string]$_; l = ("$_ FPS") } })
    # Same presets and the same "WxH, DPI (family)" wording MuMu's own
    # resolution menu shows, plus the custom entry it ends with.
    $res = @(
        @{ v = 'tablet.0'; l = '1920 × 1080, 280 DPI (Планшет)' }, @{ v = 'tablet.1'; l = '1600 × 900, 240 DPI (Планшет)' },
        @{ v = 'tablet.2'; l = '1280 × 720, 240 DPI (Планшет)' }, @{ v = 'tablet.3'; l = '960 × 540, 220 DPI (Планшет)' },
        @{ v = 'phone.0'; l = '1080 × 1920, 480 DPI (Телефон)' }, @{ v = 'phone.1'; l = '900 × 1600, 320 DPI (Телефон)' },
        @{ v = 'phone.2'; l = '720 × 1280, 320 DPI (Телефон)' }, @{ v = 'phone.3'; l = '540 × 960, 240 DPI (Телефон)' },
        @{ v = 'widescreen.0'; l = '3440 × 1440, 480 DPI (Сверхширокий)' }, @{ v = 'widescreen.1'; l = '2560 × 1080, 360 DPI (Сверхширокий)' },
        @{ v = 'widescreen.2'; l = '1920 × 864, 240 DPI (Сверхширокий)' }, @{ v = 'widescreen.3'; l = '1680 × 720, 240 DPI (Сверхширокий)' },
        @{ v = 'custom'; l = 'Пользовательский' }
    )
    # Device presets: a pick writes the brand, model and model code together,
    # which is what MuMu's "Модель устройства" sheet does. Free-text rows below
    # stay for anything not in this list.
    $models = @(
        @{ v = 'samsung-a54'; l = 'Samsung Galaxy A54'; extra = @{ phone_brand = 'Samsung'; phone_model = 'Galaxy A54'; phone_miit = 'SM-A546E' } }
        @{ v = 'samsung-s23u'; l = 'Samsung Galaxy S23 Ultra'; extra = @{ phone_brand = 'Samsung'; phone_model = 'SM-S918B'; phone_miit = 'SM-S918B' } }
        @{ v = 'samsung-s21'; l = 'Samsung Galaxy S21'; extra = @{ phone_brand = 'Samsung'; phone_model = 'SM-G991B'; phone_miit = 'SM-G991B' } }
        @{ v = 'xiaomi-13'; l = 'Xiaomi 13'; extra = @{ phone_brand = 'Xiaomi'; phone_model = '2211133G'; phone_miit = '2211133G' } }
        @{ v = 'redmi-note12'; l = 'Xiaomi Redmi Note 12'; extra = @{ phone_brand = 'Xiaomi'; phone_model = '22111317G'; phone_miit = '22111317G' } }
        @{ v = 'pixel-7'; l = 'Google Pixel 7'; extra = @{ phone_brand = 'Google'; phone_model = 'Pixel 7'; phone_miit = 'GVU6C' } }
        @{ v = 'pixel-6a'; l = 'Google Pixel 6a'; extra = @{ phone_brand = 'Google'; phone_model = 'Pixel 6a'; phone_miit = 'GX7AS' } }
        @{ v = 'oneplus-11'; l = 'OnePlus 11'; extra = @{ phone_brand = 'OnePlus'; phone_model = 'PHB110'; phone_miit = 'PHB110' } }
        @{ v = 'oppo-findx6'; l = 'OPPO Find X6'; extra = @{ phone_brand = 'OPPO'; phone_model = 'PGFM10'; phone_miit = 'PGFM10' } }
        @{ v = 'vivo-x90'; l = 'vivo X90'; extra = @{ phone_brand = 'vivo'; phone_model = 'V2218A'; phone_miit = 'V2218A' } }
        @{ v = 'huawei-p60'; l = 'Huawei P60'; extra = @{ phone_brand = 'HUAWEI'; phone_model = 'MNA-AL00'; phone_miit = 'MNA-AL00' } }
        @{ v = 'honor-magic5'; l = 'HONOR Magic5 Pro'; extra = @{ phone_brand = 'HONOR'; phone_model = 'PGT-AN10'; phone_miit = 'PGT-AN10' } }
    )
    return @(
        @{ Title = 'Производительность'; Icon = [char]0xE9D9; Rows = @(
                @{ K = 'performance_mode'; T = 'Настройки производительности'; D = 'Пресет CPU и RAM'; Type = 'choice'; Options = @(
                        @{ v = 'low'; l = 'Низкая (1 ядро, 1 ГБ)' }, @{ v = 'middle'; l = 'Средняя (4 ядра, 6 ГБ)' },
                        @{ v = 'high'; l = 'Высокая (6 ядер, 12 ГБ)' }, @{ v = 'custom'; l = 'Пользовательская' }) }
                @{ K = 'vm_cpu'; T = 'Ядра CPU'; D = 'Сколько ядер видит Android'; Type = 'choice'; Options = @(1..12 | ForEach-Object { @{ v = [string]$_; l = ("$_ яд.") } }) }
                @{ K = 'vm_mem'; T = 'Оперативная память'; D = 'ОЗУ устройства в гигабайтах'; Type = 'choice'; Options = @(0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16 | ForEach-Object { @{ v = ([string]$_); l = ("$_ ГБ") } }) }
                # Only vk and dx survive a write here (checked by reading back:
                # gles/gl/opengl/directx/angle are silently ignored), so these
                # are the two the dropdown offers.
                @{ K = 'renderer_mode'; T = 'Графический рендерер'; D = 'Режим рендеринга, который примет MuMu'; Type = 'choice'; Options = @(
                        @{ v = 'vk'; l = 'Режим Vulkan' }, @{ v = 'dx'; l = 'Режим DirectX' }) }
                @{ K = 'force_discrete_graphics'; T = 'Дискретная графика'; D = 'Как NVIDIA High Performance Mode: отдавать игры на внешнюю видеокарту'; Type = 'bool' }
                @{ K = 'vertical_sync'; T = 'Вертикальная синхронизация'; D = 'Привязать кадры к обновлению экрана'; Type = 'bool' }
                @{ K = 'dynamic_adjust_frame_rate'; T = 'Динамическая подстройка FPS'; D = 'Снижать FPS, когда в игре нет движения'; Type = 'bool' }
                @{ K = 'show_frame_rate'; T = 'Показывать FPS'; D = 'Счётчик кадров в окне устройства'; Type = 'bool' }
            ) }
        @{ Title = 'Дисплей'; Icon = [char]0xE7F4; Rows = @(
                @{ K = 'max_frame_rate'; T = 'Максимальный FPS'; D = 'Тот же предел, что в «Настройки устройства → Дисплей»'; Type = 'choice'; Options =$fps }
                @{ K = 'resolution_mode'; T = 'Разрешение'; D = 'Пресет экрана устройства'; Type = 'choice'; Options =$res }
                @{ K = 'resolution_width'; T = 'Ширина, px'; D = 'Своё значение для пользовательского разрешения'; Type = 'text' }
                @{ K = 'resolution_height'; T = 'Высота, px'; D = 'Своё значение для пользовательского разрешения'; Type = 'text' }
                @{ K = 'resolution_dpi'; T = 'DPI'; D = 'Плотность точек экрана'; Type = 'text' }
                @{ K = 'screen_brightness'; T = 'Яркость'; D = 'От 0 до 100'; Type = 'text' }
                @{ K = 'window_auto_rotate'; T = 'Поворот окна'; D = 'Поворачивать окно вместе с экраном'; Type = 'bool' }
            ) }
        @{ Title = 'Звук'; Icon = [char]0xE767; Rows = @(
                @{ K = 'system_volume_close'; T = 'Глушить при закрытии'; D = 'Выключать звук, когда окно устройства закрыто'; Type = 'bool' }
            ) }
        @{ Title = 'Диск'; Icon = [char]0xEDA2; Rows = @(
                # Same two cards MuMu's own "Диск" page shows. The cleanup and
                # "expand" buttons there have no manager command behind them,
                # so this page reports real numbers and opens the folder
                # instead of pretending to clean or resize anything.
                @{ K = 'disk_cleanup'; T = 'Очистка диска'; D = 'Команды очистки нет — открывается папка инстанса'; Type = 'disk'; Label = 'Открыть папку' }
                @{ K = 'disk_space'; T = 'Дисковое пространство'; D = 'Занято инстансом и свободно на диске MuMu'; Type = 'disk' }
            ) }
        @{ Title = 'Сеть'; Icon = [char]0xE968; Rows = @(
                @{ K = 'net_bridge.enabled'; T = 'Мостовое соединение'; D = 'Сетевой мост вместо NAT'; Type = 'bool' }
                @{ K = 'net_bridge_card'; T = 'Сетевая карта'; D = 'Имя адаптера для моста'; Type = 'text' }
                @{ K = 'net_bridge_ip_mode'; T = 'Режим IP'; D = 'dhcp или static'; Type = 'choice'; Options = @(@{ v = 'dhcp'; l = 'DHCP' }, @{ v = 'static'; l = 'Вручную' }) }
                @{ K = 'net_bridge_ip_addr'; T = 'IP-адрес'; D = 'Для ручного режима'; Type = 'text' }
                @{ K = 'net_bridge_gateway'; T = 'Шлюз'; D = 'Для ручного режима'; Type = 'text' }
                @{ K = 'net_bridge_dns1'; T = 'DNS 1'; D = 'Для ручного режима'; Type = 'text' }
            ) }
        @{ Title = 'Модель'; Icon = [char]0xE8B8; Rows = @(
                @{ K = 'phone_model'; T = 'Модель устройства'; D = 'Готовый набор: бренд, модель и код сразу'; Type = 'preset'; Options = $models }
                @{ K = 'phone_brand'; T = 'Производитель'; D = 'Подмена вендора (Samsung, Xiaomi...)'; Type = 'text' }
                @{ K = 'phone_model'; T = 'Модель'; D = 'Имя устройства для игр'; Type = 'text' }
                @{ K = 'phone_miit'; T = 'Код модели'; D = 'Например SM-A546E'; Type = 'text' }
                @{ K = 'phone_imei'; T = 'IMEI'; D = 'Идентификатор устройства'; Type = 'text' }
                @{ K = 'phone_number'; T = 'Номер телефона'; D = 'Можно оставить пустым'; Type = 'text' }
            ) }
        @{ Title = 'Для разработчиков'; Icon = [char]0xE943; Rows = @(
                @{ K = 'root_permission'; T = 'Root'; D = 'Права суперпользователя в Android'; Type = 'bool' }
                @{ K = 'system_disk_readonly'; T = 'Системный диск только для чтения'; D = 'Защита от изменений системы'; Type = 'bool' }
                @{ K = 'net_bridge_open'; T = 'Открыть сеть моста'; D = 'Разрешить входящие соединения'; Type = 'bool' }
            ) }
        @{ Title = 'Другие'; Icon = [char]0xE712; Rows = @(
                @{ K = 'player_name'; T = 'Имя устройства'; D = 'Как инстанс называется в менеджере'; Type = 'text' }
                @{ K = 'mini_disk'; T = 'Минимальный диск'; D = 'Экономит место на диске'; Type = 'bool' }
                @{ K = 'quit_confirm'; T = 'Подтверждать закрытие'; D = 'Спрашивать перед выходом'; Type = 'bool' }
                @{ K = 'window_size_fixed'; T = 'Фиксированный размер окна'; D = 'Запретить менять размер окна'; Type = 'bool' }
                @{ K = 'window_save_rect'; T = 'Запоминать позицию окна'; D = 'Возвращать окно на то же место'; Type = 'bool' }
                @{ K = 'mouse_style'; T = 'Курсор в стиле игры'; D = 'Скрывать системный курсор'; Type = 'bool' }
                @{ K = 'joystick_auto_connect'; T = 'Автоподключение геймпада'; D = 'Подключать джойстик при запуске'; Type = 'bool' }
                @{ K = 'app_keptlive'; T = 'Не усыплять приложения'; D = 'Держать процессы живыми в фоне'; Type = 'bool' }
                @{ K = 'apk_asscciation'; T = 'Ассоциация APK'; D = 'Открывать APK в MuMu двойным щелчком'; Type = 'bool' }
            ) }
    )
}

$script:RowXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="12" Background="#16171F" BorderBrush="#20222C" BorderThickness="1"
        Padding="14,12" Margin="0,0,0,8">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="4"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <Border x:Name="Ico" Grid.Column="0" Width="3" CornerRadius="2" Background="#2F7DF6"
            VerticalAlignment="Stretch" Margin="0,2,12,2" Opacity="0.55"/>
    <StackPanel Grid.Column="1" Margin="0,0,16,0" VerticalAlignment="Center">
      <TextBlock x:Name="Title" FontSize="13" FontWeight="SemiBold" Foreground="#E8E9EE"/>
      <TextBlock x:Name="Desc" FontSize="11" Foreground="#787C8E" Margin="0,3,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ContentPresenter x:Name="Slot" Grid.Column="2" VerticalAlignment="Center"/>
  </Grid>
</Border>
'@

function Show-SettingsWindow {
    param([string]$Index, [string]$DeviceName)
    [xml]$setXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Настройки устройства" Height="760" Width="1020" MinHeight="560" MinWidth="880"
        Background="#0F1016" Foreground="#E8E9EE" FontFamily="Segoe UI"
        WindowStartupLocation="CenterOwner" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="Switch" TargetType="ToggleButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="track" Width="46" Height="24" CornerRadius="12" Background="#2A2C38">
              <Ellipse x:Name="knob" Width="18" Height="18" Fill="#9AA0B4" HorizontalAlignment="Left" Margin="3,0,0,0"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="#2F7DF6"/>
                <Setter TargetName="knob" Property="Fill" Value="#FFFFFF"/>
                <Setter TargetName="knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="track" Property="Opacity" Value="0.85"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="DarkCombo" TargetType="ComboBox">
      <Setter Property="Foreground" Value="#E3E6EE"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinWidth" Value="190"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="bd" CornerRadius="8" Background="#1B1C26" BorderBrush="#2A2C38" BorderThickness="1"/>
              <ContentPresenter Margin="10,0,28,0" VerticalAlignment="Center" IsHitTestVisible="False"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"/>
              <Path HorizontalAlignment="Right" Margin="0,0,11,0" VerticalAlignment="Center"
                    Data="M 0 0 L 4 4 L 8 0" Stroke="#8B8FA3" StrokeThickness="1.6"/>
              <ToggleButton Focusable="False" ClickMode="Press" Background="Transparent" BorderThickness="0"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton"><Border Background="Transparent"/></ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True"
                     Placement="Bottom" PopupAnimation="Fade" StaysOpen="False">
                <Border Background="#171821" BorderBrush="#2A2C38" BorderThickness="1" CornerRadius="8"
                        Margin="0,4,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        MaxHeight="280">
                  <ScrollViewer VerticalScrollBarVisibility="Auto"><ItemsPresenter/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#3A3D50"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#DDE1EA"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="ib" Background="Transparent" CornerRadius="6" Padding="10,7" Margin="4,2">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ib" Property="Background" Value="#222435"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="ib" Property="Background" Value="#243B5C"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="TextInput" TargetType="TextBox">
      <Setter Property="Background" Value="#12131B"/>
      <Setter Property="Foreground" Value="#E3E6EE"/>
      <Setter Property="BorderBrush" Value="#2A2C38"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CaretBrush" Value="#8CC4FF"/>
      <Setter Property="SelectionBrush" Value="#2F7DF6"/>
      <Setter Property="Width" Value="210"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style x:Key="RowBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#C9CAD3"/>
      <Setter Property="Background" Value="#1C1D26"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="9" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#242633"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.7"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#B9BDCB"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="nb" CornerRadius="9" Padding="12,10" Margin="0,0,0,4" Background="Transparent">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="nb" Property="Background" Value="#191A24"/></Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="nb" Property="Background" Value="#1B2433"/>
                <Setter Property="Foreground" Value="#9CC8FF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="4,0,0,6">
      <TextBlock x:Name="SetTitle" FontSize="22" FontWeight="Bold" Foreground="#F2F4F8"/>
      <TextBlock x:Name="SetSub" FontSize="12" Foreground="#7E8296" Margin="0,3,0,0"/>
    </StackPanel>

    <Grid Grid.Row="1" Margin="0,10,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="212"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <ListBox x:Name="Nav" Grid.Column="0" Background="Transparent" BorderThickness="0" Margin="0,0,14,0"/>
      <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="RowsPanel"/>
      </ScrollViewer>
    </Grid>

    <TextBlock x:Name="SetStatus" Grid.Row="2" Margin="4,10,0,0" FontSize="12" Foreground="#7E8296"
                Text="Изменения сохраняются сразу и проверяются чтением обратно"/>
  </Grid>
</Window>
'@

    $win = [Windows.Markup.XamlReader]::Parse($setXaml.OuterXml)
    $win.Owner = $window
    $win.FindName('SetTitle').Text = 'Настройки устройства'
    $win.FindName('SetSub').Text = ("{0} · инстанс {1} · самые важные ключи MuMu" -f $DeviceName, $Index)

    $script:SettingsIndex = $Index
    $script:SettingsStatusText = $win.FindName('SetStatus')
    $script:SettingsReady = $false
    $panel = $win.FindName('RowsPanel')
    $nav = $win.FindName('Nav')
    $schema = Get-SettingSchema
    $map = Get-SettingsMap -Index $Index

    $script:SettingsRefresh = $null
    $renderSection = {
        param($section)
        $panel.Children.Clear()
        $script:SettingsReady = $false
        $mapNow = Get-SettingsMap -Index $script:SettingsIndex
        # One info call for the whole section instead of one per disk row.
        $disk = $null
        if (@($section.Rows | Where-Object { $_.Type -eq 'disk' }).Count -gt 0) {
            $disk = Get-DeviceDisk -Index $script:SettingsIndex -Thumb ([string]$mapNow['device_thumbnail'])
        }
        foreach ($row in $section.Rows) {
            $value = [string]$mapNow[$row.K]
            $card = [Windows.Markup.XamlReader]::Parse($script:RowXaml)
            $card.FindName('Ico').Background = (Get-Brush $(if ($section.Accent) { $section.Accent } else { '#2F7DF6' }))
            $card.FindName('Title').Text = $row.T
            $card.FindName('Desc').Text = ("{0}  ·  {1}" -f $row.D, $row.K)
            $control = switch ($row.Type) {
                'bool' { New-SettingSwitch -Key $row.K -Value $value -Win $win }
                'choice' { New-SettingChoice -Key $row.K -Value $value -Options $row.Options -Win $win }
                'preset' { New-SettingPreset -Options $row.Options -Win $win -Current $mapNow }
                'disk' { New-SettingDisk -Key $row.K -Label $row.Label -Win $win -Disk $disk }
                default { New-SettingText -Key $row.K -Value $value -Win $win }
            }
            $card.FindName('Slot').Content = $control
            [void]$panel.Children.Add($card)
        }
        $script:SettingsReady = $true
    }
    $script:SettingsRefresh = {
        $i = $nav.SelectedIndex
        if ($i -ge 0) { & $renderSection $schema[$i] }
    }

    foreach ($section in $schema) { [void]$nav.Items.Add($section.Title) }
    $nav.Add_SelectionChanged({
            $i = $nav.SelectedIndex
            if ($i -ge 0) { &$renderSection $schema[$i] }
        })
    $nav.SelectedIndex = 0

    $null = $win.ShowDialog()
    $script:SettingsRefresh = $null
    $script:SettingsStatusText = $null
    return $null
}



# --- actions ---------------------------------------------------------------
$ui.RefreshButton.Add_Click({ Update-View })

$ui.CreateButton.Add_Click({
        $choice = Show-CreateDialog
        if (-not $choice) { Set-Status 'Создание отменено'; return }
        $createArgs = @('create', '-ver', $choice.Version)
        if ($choice.Count -gt 1) {$createArgs += @('-n', [string]$choice.Count) }
        if ($choice.Mini) {$createArgs += '-m' }
        Set-Status ("Создаю устройство: Android {0}, количество {1}..." -f $choice.Version, $choice.Count)
        $before = @(Get-Instances).Count
        $r = Invoke-Mgr -Arguments $createArgs -Label 'create'
        Start-Sleep -Milliseconds 800
        $after = @(Get-Instances).Count
        Update-View
        if ($r.Ok) { Set-Status ("Устройств создано: {0} (было {1}, стало {2})" -f ($after - $before), $before, $after) }
        else { Set-Status 'Создание не удалось — подробности в логе' }
    })

$ui.SettingsButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        $sel = $ui.InstanceList.SelectedItem
        Set-Status "Открываю настройки инстанса${i}..."
        Show-SettingsWindow -Index $i -DeviceName $sel.Name
        Update-View
        Set-Status 'Настройки закрыты'
    })

$ui.RenameButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        $sel = $ui.InstanceList.SelectedItem
        $name = Show-InputDialog -Title 'Переименовать устройство' -Label 'Новое имя' -Value $sel.Name -Hint 'rename -v <инстанс> -n <имя>'
        if (-not $name) { Set-Status 'Переименование отменено'; return }
        $r = Invoke-Mgr -Arguments @('rename', '-v', $i, '-n', $name) -Label "rename $i -> $name"
        Update-View
        Set-Status $(if ($r.Ok) { "Инстанс ${i} теперь '$name'" } else { 'Переименовать не удалось — см. лог' })
    })

$ui.CloneButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        $count = Show-InputDialog -Title 'Копировать устройство' -Label 'Сколько копий создать' -Value '1' -Hint 'clone -v <инстанс> -n <количество>, от 1 до 10'
        if (-not $count) { Set-Status 'Копирование отменено'; return }
        if ($count -notmatch '^\d{1,2}$' -or [int]$count -lt 1 -or [int]$count -gt 10) {
            Set-Status 'Количество копий: целое число от 1 до 10 — ничего не сделано'
            return
        }
        Set-Status "Копирую устройство${i} ($count шт.)..."
        $r = Invoke-Mgr -Arguments @('clone', '-v', $i, '-n', $count) -Label "clone $i x$count"
        Start-Sleep -Milliseconds 800
        Update-View
        Set-Status $(if ($r.Ok) { "Копий создано: $count" } else { 'Копирование не удалось — см. лог' })
    })

$ui.BackupButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        $sel = $ui.InstanceList.SelectedItem
        $safe = ($sel.Name -replace '[^\w\-. ]', '_')
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Title = 'Сохранить резервную копию устройства'
        $dlg.Filter = 'MuMu device data (*.mumudata)|*.mumudata'
        $dlg.FileName = $safe
        if (-not $dlg.ShowDialog($window)) { Set-Status 'Резервная копия отменена'; return }
        $dir = [IO.Path]::GetDirectoryName($dlg.FileName)
        $name = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
        Set-Status "Сохраняю копию инстанса${i}..."
        $r = Invoke-Mgr -Arguments @('export', '-v', $i, '-d', $dir, '-n', $name) -Label "export $i -> $dir\$name"
        Set-Status $(if ($r.Ok) { "Копия сохранена: $dir\$name.mumudata" } else { 'Экспорт не удался — см. лог' })
    })

$ui.RestoreButton.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Title = 'Выберите файл резервной копии'
        $dlg.Filter = 'MuMu device data (*.mumudata)|*.mumudata|Все файлы (*.*)|*.*'
        if (-not $dlg.ShowDialog($window)) { Set-Status 'Восстановление отменено'; return }
        $answer = [System.Windows.MessageBox]::Show(
            ("Устройство будет создано из файла:`n{0}`n`nПродолжить?" -f $dlg.FileName),
            'Восстановить устройство', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { Set-Status 'Восстановление отменено'; return }
        Set-Status 'Импортирую устройство...'
        $r = Invoke-Mgr -Arguments @('import', '-p', $dlg.FileName) -Label "import $($dlg.FileName)"
        Start-Sleep -Milliseconds 800
        Update-View
        Set-Status $(if ($r.Ok) { 'Устройство восстановлено' } else { 'Импорт не удался — см. лог' })
    })

$ui.DeleteButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        $sel = $ui.InstanceList.SelectedItem
        $answer = [System.Windows.MessageBox]::Show(
            ("Устройство '{0}' будет удалено через MuMuManager delete.`n`nДанные устройства пропадут. Продолжить?" -f $sel.Name),
            'Удалить устройство', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { Set-Status 'Удаление отменено'; return }
        Set-Status "Удаляю устройство${i}..."
        $null = Invoke-Mgr -Arguments @('delete', '-v', $i) -Label "delete $i"
        Start-Sleep -Seconds 1
        $still = @(Get-Instances) | Where-Object { $_.Index -eq $i }
        Update-View
        if ($still) { Set-Status "Устройство${i} всё ещё в списке — см. лог" }
        else { Set-Status "Устройство${i} удалено" }
    })

$ui.LaunchButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        Set-Status "Запускаю инстанс${i}..."
        $r = Invoke-Mgr -Arguments @('control', '-v', $i, 'launch') -Label "launch $i"
        Update-View
        Set-Status $(if ($r.Ok) { "Инстанс ${i}: команда запуска принята" } else { "Инстанс ${i}: запуск не удался — см. лог" })
    })

$ui.StopButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        Set-Status "Останавливаю инстанс${i}..."
        $r = Invoke-Mgr -Arguments @('control', '-v', $i, 'shutdown') -Label "shutdown $i"
        Update-View
        Set-Status $(if ($r.Ok) { "Инстанс ${i} остановлен" } else { "Инстанс ${i}: остановка не удалась — см. лог" })
    })

$ui.RestartButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        Set-Status "Перезапускаю инстанс${i}..."
        $r = Invoke-Mgr -Arguments @('control', '-v', $i, 'restart') -Label "restart $i"
        Update-View
        Set-Status $(if ($r.Ok) { "Инстанс ${i} перезапущен" } else { "Инстанс ${i}: перезапуск не удался — см. лог" })
    })

$ui.RepairButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        $sel = $ui.InstanceList.SelectedItem
        $rows = @(Get-Instances)
        $target = $rows | Where-Object { $_.Index -eq $i } | Select-Object -First 1
        $ver = 'auto'
        if ($target) {
            $m = [regex]::Match([string]$target.AndroidLabel, '(\d+)')
            if ($m.Success) {$ver = $m.Groups[1].Value }
        }
        $answer = [System.Windows.MessageBox]::Show(
            ("Устройство '{0}' будет удалено через MuMuManager delete и создано заново (Android {1}).`n`nДанные устройства пропадут. Продолжить?" -f $sel.Name, $ver),
            'Починить устройство', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { Set-Status 'Починка отменена'; return }

        Set-Status "Удаляю устройство${i}..."
        $null = Invoke-Mgr -Arguments @('delete', '-v', $i) -Label "delete $i"
        Start-Sleep -Seconds 2
        $still = @(Get-Instances) | Where-Object { $_.Index -eq $i }
        if ($still) {
            Write-Log "Устройство${i} осталось в списке менеджера — создавать заново небезопасно."
            Set-Status "Удаление не удалось — устройство${i} на месте, см. лог"
            Update-View
            return
        }
        Write-Log "MuMu убрал устройство${i} из списка."
        Set-Status "Создаю новое устройство Android ${ver}..."
        $create = Invoke-Mgr -Arguments @('create', '-ver', $ver) -Label "create -ver $ver"
        Update-View
        if ($create.Ok) { Set-Status "Устройство пересоздано (Android ${ver})" }
        else { Set-Status 'Создание не удалось — подробности в логе' }
    })

$ui.ApplyFpsButton.Add_Click({
        $i = Get-SelectedIndex; if (-not $i) { return }
        $raw = ([string]$ui.FpsBox.Text).Trim()
        if ($raw -notmatch '^\d{1,3}$' -or [int]$raw -lt 1 -or [int]$raw -gt 999) {
            [void][System.Windows.MessageBox]::Show('FPS: целое число от 1 до 999.', 'MuMu Manager',
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }
        Set-Status "Ставлю максимальный FPS =${raw} для инстанса ${i}..."
        $null = Invoke-Mgr -Arguments @('setting', '-v', $i, '-k', 'max_frame_rate', '-val', $raw) -Label "max_frame_rate $i = $raw"
        Start-Sleep -Milliseconds 500
        $now = [string](Get-FrameLimit -Index $i)
        Update-View
        if ($now -eq $raw) { Set-Status "FPS инстанса ${i} теперь ${now}" }
        else { Set-Status ("FPS не применился: менеджер отдаёт '{0}' — см. лог" -f $now) }
    })

$ui.CliButton.Add_Click({
        $menu = Join-Path $PSScriptRoot 'mumu-menu.ps1'
        if (-not (Test-Path -LiteralPath $menu -PathType Leaf)) { Write-Log "mumu-menu.ps1 рядом не найден: $menu"; return }
        $exe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
        try {
            Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $menu) | Out-Null
            Write-Log 'Консольное меню открыто отдельным окном.'
        } catch { Write-Log "Не удалось открыть меню:$($_.Exception.Message)" }
    })

$ui.InstanceList.Add_SelectionChanged({
        $sel = $ui.InstanceList.SelectedItem
        if ($sel) {$ui.FpsBox.Text = ([string]$sel.FpsLabel -replace '^FPS\s*', '') }
    })

$ui.ExitButton.Add_Click({$window.Close() })

$window.Add_Loaded({
        Write-Log 'MuMu Manager: окно запущено.'
        if ($script:Mgr) { Write-Log "MuMuManager: $script:Mgr" } else { Write-Log 'MuMuManager.exe не найден.' }
        Update-View
    })

[void]$window.ShowDialog()
