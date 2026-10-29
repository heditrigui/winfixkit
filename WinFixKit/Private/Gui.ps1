# WPF front end. Show-FixKitGui (public) calls New-FixKitWindow and shows it.
# Fixes run in a background runspace so the window stays responsive; fixes that need admin
# rights run in a separate elevated PowerShell window, so the GUI itself never needs elevation.

$script:FixKitUi = @{}

$script:WindowXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinFixKit" Width="1120" Height="720" MinWidth="820" MinHeight="480"
        WindowStartupLocation="CenterScreen" Background="#F3F4F6" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="RunButton" TargetType="Button">
      <Setter Property="Background" Value="#2563EB"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="16,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#1D4ED8"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="FlatButton" TargetType="Button" BasedOn="{StaticResource RunButton}">
      <Setter Property="Background" Value="#374151"/>
      <Setter Property="Padding" Value="12,4"/>
      <Setter Property="FontWeight" Value="Normal"/>
    </Style>
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#111827" Padding="22,14">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Border x:Name="ElevationBadge" CornerRadius="11" Padding="11,3" Margin="0,0,18,0" VerticalAlignment="Center">
            <TextBlock x:Name="ElevationText" Foreground="White" FontSize="12"/>
          </Border>
          <CheckBox x:Name="DryRun" IsChecked="True" VerticalAlignment="Center">
            <TextBlock Foreground="White" FontSize="13"><Bold>Dry run</Bold> - preview only, change nothing</TextBlock>
          </CheckBox>
        </StackPanel>
        <StackPanel>
          <TextBlock Text="WinFixKit" Foreground="White" FontSize="22" FontWeight="SemiBold"/>
          <TextBlock Text="Safe, logged Windows repairs for IT support" Foreground="#9CA3AF" FontSize="12"/>
        </StackPanel>
      </DockPanel>
    </Border>
    <Border DockPanel.Dock="Bottom" Background="#E5E7EB" Padding="14,7">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="ClearOutput" Content="Clear output" Style="{StaticResource FlatButton}" Margin="0,0,8,0"/>
          <Button x:Name="OpenLogs" Content="Open log folder" Style="{StaticResource FlatButton}"/>
        </StackPanel>
        <TextBlock x:Name="Status" VerticalAlignment="Center" Foreground="#374151" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
    </Border>
    <Grid Margin="16,14,16,14">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="440"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="FixList" Margin="0,0,14,0"/>
      </ScrollViewer>
      <Border Grid.Column="1" Background="#0F172A" CornerRadius="8" Padding="4">
        <TextBox x:Name="Output" Background="#0F172A" Foreground="#E2E8F0" BorderThickness="0" Padding="10"
                 FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </Border>
    </Grid>
  </DockPanel>
</Window>
'@

$script:CardXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Background="White" BorderBrush="#E5E7EB" BorderThickness="1" CornerRadius="7" Padding="14,10" Margin="0,0,0,8">
  <DockPanel>
    <Button x:Name="RunButton" DockPanel.Dock="Right" Content="{0}" Style="{DynamicResource RunButton}" VerticalAlignment="Center" Margin="12,0,0,0" MinWidth="72"/>
    <StackPanel>
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="{1}" FontSize="14" FontWeight="SemiBold" Foreground="#111827"/>
        {2}
      </StackPanel>
      <TextBlock Text="{3}" FontSize="12" Foreground="#4B5563" TextWrapping="Wrap" Margin="0,3,0,0"/>
    </StackPanel>
  </DockPanel>
</Border>
'@

# Runs inside the background runspace. Returns @{ Text; OpenPath }.
$script:GuiJobScript = {
    param($Manifest, $Command, $Parameters, $DryRun, $LogDir)

    $env:WINFIXKIT_LOGDIR = $LogDir
    Import-Module $Manifest -Force
    $splat = @{} + $Parameters
    if ((Get-Command $Command).Parameters.ContainsKey('WhatIf')) {
        if ($DryRun) { $splat.WhatIf = $true } else { $splat.Confirm = $false }
    }

    $result = @(& $Command @splat)
    if (-not $result) { return @{ Text = 'Nothing to do.'; OpenPath = $null } }
    if ($result[0] -is [System.IO.FileInfo]) {
        return @{ Text = "Report saved to $($result[0].FullName)"; OpenPath = $result[0].FullName }
    }

    $text = switch ($result[0].PSObject.TypeNames[0]) {
        'WinFixKit.StepResult' { $result | Format-Table Status, Step, Target, Message -AutoSize -Wrap | Out-String -Width 170 }
        'WinFixKit.StartupItem' { $result | Format-Table Enabled, Scope, Name, Command -AutoSize -Wrap | Out-String -Width 220 }
        'WinFixKit.DebloatCandidate' { $result | Format-Table Installed, Name, Description -AutoSize | Out-String -Width 170 }
        default { $result | Format-Table -AutoSize -Wrap | Out-String -Width 200 }
    }
    @{ Text = $text.Trim(); OpenPath = $null }
}

function New-FixKitWindow {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $window = [Windows.Markup.XamlReader]::Parse($script:WindowXaml)
    $ui = $script:FixKitUi
    $ui.Clear()
    $ui.Window = $window
    foreach ($name in 'ElevationBadge', 'ElevationText', 'DryRun', 'FixList', 'Output', 'Status', 'OpenLogs', 'ClearOutput') {
        $ui[$name] = $window.FindName($name)
    }
    $ui.Manifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'WinFixKit.psd1'
    $ui.Elevated = Test-FixKitElevation
    $ui.Buttons = [System.Collections.Generic.List[object]]::new()
    $ui.Catalog = @{}

    if ($ui.Elevated) {
        $ui.ElevationBadge.Background = '#15803D'
        $ui.ElevationText.Text = 'Administrator'
    }
    else {
        $ui.ElevationBadge.Background = '#4B5563'
        $ui.ElevationText.Text = 'Standard user - admin asked only when needed'
    }

    $category = $null
    foreach ($item in Get-FixKitCatalog) {
        $ui.Catalog[$item.Id] = $item
        if ($item.Category -ne $category) {
            $category = $item.Category
            $header = [Windows.Controls.TextBlock]::new()
            $header.Text = $category.ToUpper()
            $header.FontSize = 11
            $header.FontWeight = 'SemiBold'
            $header.Foreground = '#6B7280'
            $header.Margin = '2,10,0,6'
            $null = $ui.FixList.Children.Add($header)
        }
        $card = [Windows.Markup.XamlReader]::Parse((New-FixKitCardXaml -Item $item))
        $button = $card.FindName('RunButton')
        $button.Tag = $item.Id
        $button.Add_Click({ param($btn) Invoke-FixKitGuiAction -Id $btn.Tag })
        $ui.Buttons.Add($button)
        $null = $ui.FixList.Children.Add($card)
    }

    $ui.OpenLogs.Add_Click({
            $dir = Get-FixKitLogPath
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
            Start-Process -FilePath explorer.exe -ArgumentList "`"$dir`""
        })
    $ui.ClearOutput.Add_Click({ $script:FixKitUi.Output.Clear() })
    $ui.DryRun.Add_Click({ Update-FixKitStatus })

    $ui.Timer = [Windows.Threading.DispatcherTimer]::new()
    $ui.Timer.Interval = [timespan]::FromMilliseconds(250)
    $ui.Timer.Add_Tick({ Receive-FixKitGuiJob })

    Add-FixKitOutput -Text "WinFixKit ready. Logging to $(Get-FixKitLogPath)"
    Add-FixKitOutput -Text 'Dry run is ON: fixes only show what they would do. Untick it to apply them.'
    Update-FixKitStatus
    $window
}

function New-FixKitCardXaml {
    param($Item)

    $enc = { param($v) [System.Security.SecurityElement]::Escape([string]$v) }
    $tags = [System.Collections.Generic.List[string]]::new()
    $tagXaml = '<Border Background="{0}" CornerRadius="4" Padding="6,1" Margin="8,1,0,0" VerticalAlignment="Center"><TextBlock Text="{1}" FontSize="10" Foreground="{2}"/></Border>'
    if ($Item.RequiresAdmin) { $tags.Add(($tagXaml -f '#FEF3C7', 'ADMIN', '#92400E')) }
    if ($Item.ReadOnly) { $tags.Add(($tagXaml -f '#DCFCE7', 'READ-ONLY', '#166534')) }
    elseif ($Item.Destructive) { $tags.Add(($tagXaml -f '#FEE2E2', 'CHANGES SYSTEM', '#991B1B')) }

    $buttonText = if ($Item.ReadOnly) { 'View' } else { 'Run' }
    # Format placeholders are {0}..{3}; braces in the XAML template are only used for them and for DynamicResource.
    $script:CardXaml.Replace('{0}', $buttonText).Replace('{1}', (& $enc $Item.Title)).Replace('{2}', ($tags -join '')).Replace('{3}', (& $enc $Item.Description))
}

function Add-FixKitOutput {
    param([string]$Text)

    $box = $script:FixKitUi.Output
    $box.AppendText($Text.TrimEnd() + [Environment]::NewLine)
    $box.ScrollToEnd()
}

function Update-FixKitStatus {
    param([string]$Text)

    $ui = $script:FixKitUi
    if (-not $Text) {
        $mode = if ($ui.DryRun.IsChecked) { 'Dry run ON - nothing will be changed' } else { 'Dry run OFF - fixes will be applied after you confirm' }
        $Text = "$mode.   Log: $(Get-FixKitLogPath)"
    }
    $ui.Status.Text = $Text
}

function Invoke-FixKitGuiAction {
    param([string]$Id)

    $ui = $script:FixKitUi
    $item = $ui.Catalog[$Id]
    $dryRun = [bool]$ui.DryRun.IsChecked -and -not $item.ReadOnly
    $needsElevation = $item.RequiresAdmin -and -not $ui.Elevated

    if (-not $item.ReadOnly -and -not $dryRun) {
        $text = "$($item.Title)`n`n$($item.Description)`n`n"
        if ($item.Destructive) { $text += "This makes changes to this PC that may not be undoable.`n" }
        if ($needsElevation) { $text += "Windows will ask for administrator permission, and the fix will run in its own window.`n" }
        $text += "`nEvery step is written to the log. Continue?"
        $icon = if ($item.Destructive) { 'Warning' } else { 'Question' }
        $answer = [Windows.MessageBox]::Show($ui.Window, $text, 'WinFixKit - confirm', 'YesNo', $icon, 'No')
        if ($answer -ne 'Yes') {
            Write-FixLog -Message "GUI: '$($item.Title)' cancelled at confirmation." -Level WARN
            Add-FixKitOutput -Text "Cancelled: $($item.Title)"
            return
        }
    }

    Add-FixKitOutput -Text ''
    $label = if ($dryRun) { '  [DRY RUN]' } else { '' }
    Add-FixKitOutput -Text ('=== {0:HH:mm:ss}  {1}{2} ===' -f (Get-Date), $item.Title, $label)

    if ($needsElevation -and -not $dryRun) {
        Start-FixKitElevated -Item $item
        return
    }
    Start-FixKitGuiJob -Item $item -DryRun $dryRun
}

function Start-FixKitGuiJob {
    param($Item, [bool]$DryRun)

    $ui = $script:FixKitUi
    $ps = [powershell]::Create()
    $null = $ps.AddScript($script:GuiJobScript).
        AddArgument($ui.Manifest).AddArgument($Item.Command).AddArgument($Item.Parameters).
        AddArgument($DryRun).AddArgument((Get-FixKitLogPath))
    $ui.Job = @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Item = $Item; Started = Get-Date }

    foreach ($b in $ui.Buttons) { $b.IsEnabled = $false }
    Update-FixKitStatus -Text "Running: $($Item.Title)..."
    $ui.Timer.Start()
}

function Receive-FixKitGuiJob {
    $ui = $script:FixKitUi
    $job = $ui.Job
    if (-not $job) { $ui.Timer.Stop(); return }
    if (-not $job.Handle.IsCompleted) {
        Update-FixKitStatus -Text ('Running: {0}... {1:N0}s' -f $job.Item.Title, ((Get-Date) - $job.Started).TotalSeconds)
        return
    }

    $ui.Timer.Stop()
    $ps = $job.PowerShell
    try {
        $out = $ps.EndInvoke($job.Handle)
        foreach ($r in $out) {
            if ($r -is [hashtable]) {
                Add-FixKitOutput -Text $r.Text
                if ($r.OpenPath) { Start-Process -FilePath $r.OpenPath }
            }
        }
    }
    catch {
        Add-FixKitOutput -Text "ERROR: $($_.Exception.InnerException.Message)$($_.Exception.Message)"
    }
    foreach ($w in $ps.Streams.Warning) { Add-FixKitOutput -Text "WARNING: $w" }
    foreach ($e in $ps.Streams.Error) { Add-FixKitOutput -Text "ERROR: $e" }
    $ps.Dispose()
    $ui.Job = $null

    foreach ($b in $ui.Buttons) { $b.IsEnabled = $true }
    Update-FixKitStatus
}

function Start-FixKitElevated {
    param($Item)

    $quote = { param($s) "'" + ([string]$s -replace "'", "''") + "'" }
    $paramText = @(foreach ($p in $Item.Parameters.GetEnumerator()) {
            if ($p.Value -is [bool]) { "-$($p.Key):`$$($p.Value.ToString().ToLower())" }
            else { "-$($p.Key) $(& $quote $p.Value)" }
        }) -join ' '

    $command = @"
`$Host.UI.RawUI.WindowTitle = $(& $quote "WinFixKit (Administrator) - $($Item.Title)")
`$env:WINFIXKIT_LOGDIR = $(& $quote (Get-FixKitLogPath))
`$InformationPreference = 'Continue'
Import-Module $(& $quote $script:FixKitUi.Manifest) -Force
'Running: ' + $(& $quote $Item.Title)
''
$($Item.Command) $paramText -Confirm:`$false | Format-Table Status, Step, Target, Message -AutoSize -Wrap
'Log folder: ' + (Get-FixKitLogPath)
`$null = Read-Host 'Finished. Press Enter to close this window'
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $exe = (Get-Process -Id $PID).Path

    try {
        Write-FixLog -Message "GUI: launching elevated window for '$($Item.Title)' ($($Item.Command) $paramText)" -Level ACTION
        Start-Process -FilePath $exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -ErrorAction Stop
        Add-FixKitOutput -Text 'Running in a separate administrator window. Results are also written to the log.'
    }
    catch {
        Write-FixLog -Message "GUI: elevation cancelled or failed for '$($Item.Title)': $($_.Exception.Message)" -Level WARN
        Add-FixKitOutput -Text 'Administrator permission was not granted, nothing was changed.'
    }
}
