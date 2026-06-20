Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# Prerequisite detection helpers
# ============================================================

function Test-CommandAvailable {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-RustVersion {
    try {
        $v = & cargo --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return $v.Trim() }
    } catch {}
    return $null
}

function Test-MsvcBuildTools {
    # Look for either the Build Tools or Visual Studio (any edition) with VC
    $paths = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    )
    $vswhere = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $vswhere) { return $false }

    try {
        $found = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        return [bool]$found
    } catch { return $false }
}

function Get-PowerShellInfo {
    return [pscustomobject]@{
        Version = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        Ok      = ($PSVersionTable.PSVersion.Major -ge 5)
    }
}

function Get-PrereqState {
    $rust  = Get-RustVersion
    $msvc  = Test-MsvcBuildTools
    $ps    = Get-PowerShellInfo

    return [pscustomobject]@{
        Rust       = [pscustomobject]@{
            Installed = [bool]$rust
            Detail    = if ($rust) { $rust } else { "Not installed" }
        }
        Msvc       = [pscustomobject]@{
            Installed = $msvc
            Detail    = if ($msvc) { "MSVC Build Tools detected" } else { "Required to compile Rust on Windows" }
        }
        PowerShell = [pscustomobject]@{
            Installed = $ps.Ok
            Detail    = "PowerShell $($ps.Version) ($($ps.Edition))"
        }
        AllOk      = ([bool]$rust -and $msvc -and $ps.Ok)
    }
}

# ============================================================
# Prerequisites Window (Stage 1)
# ============================================================

[xml]$prereqXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PS to EXE - Setup"
        Height="560" Width="720"
        WindowStartupLocation="CenterScreen"
        Background="#FF1E1E2E"
        FontFamily="Segoe UI"
        ResizeMode="NoResize">
  <Window.Resources>
    <Style x:Key="AccentButton" TargetType="Button">
      <Setter Property="Background" Value="#FF7C3AED"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border CornerRadius="8" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#FF8B5CF6"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="#FF3F3F55"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource AccentButton}">
      <Setter Property="Background" Value="#FF3F3F55"/>
    </Style>
  </Window.Resources>

  <Grid Margin="28">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,16">
      <TextBlock Text="Welcome to PS to EXE Builder" Foreground="White" FontSize="22" FontWeight="Bold"/>
      <TextBlock Text="We need to check a few things before you can build executables." Foreground="#FFB8B8D1" FontSize="12" Margin="0,4,0,0"/>
    </StackPanel>

    <Border Grid.Row="1" Background="#FF2B2B40" CornerRadius="10" Padding="18" Margin="0,0,0,14">
      <StackPanel Name="PrereqList"/>
    </Border>

    <Border Grid.Row="2" Background="#FF11111B" CornerRadius="10" Padding="0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Border Background="#FF181826" CornerRadius="10,10,0,0" Padding="12,8">
          <TextBlock Text="SETUP LOG" Foreground="#FF7C3AED" FontWeight="Bold" FontSize="11"/>
        </Border>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
          <TextBox Name="TxtSetupLog" Background="Transparent" BorderThickness="0"
                   Foreground="#FFCDD6F4" FontFamily="Consolas" FontSize="12"
                   IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" Padding="12"/>
        </ScrollViewer>
      </Grid>
    </Border>

    <Grid Grid.Row="3" Margin="0,14,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Ellipse Name="SetupStatusDot" Width="10" Height="10" Fill="#FF6B7280"/>
        <TextBlock Name="TxtSetupStatus" Text="Checking..." Foreground="#FFB8B8D1" Margin="8,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button Name="BtnRecheck" Content="Re-check" Style="{StaticResource SecondaryButton}" Width="110" Height="36" Margin="0,0,10,0"/>
        <Button Name="BtnInstall" Content="Install dependencies" Style="{StaticResource AccentButton}" Width="180" Height="36" Margin="0,0,10,0"/>
        <Button Name="BtnContinue" Content="Continue" Style="{StaticResource AccentButton}" Width="130" Height="36" IsEnabled="False"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
"@

$preReader = New-Object System.Xml.XmlNodeReader $prereqXaml
$preWindow = [Windows.Markup.XamlReader]::Load($preReader)

# The fixed Height/Width in the XAML above is a sane default for a typical
# screen, but smaller displays, high DPI scaling, or a tall taskbar can all
# leave less usable space than that - which pushes the bottom of the window
# off-screen until the user maximizes it. Clamp to the real work area instead
# of guessing a single magic number that works for everyone.
$workArea = [System.Windows.SystemParameters]::WorkArea
if ($preWindow.Height -gt $workArea.Height) { $preWindow.Height = [Math]::Max(420, $workArea.Height - 40) }
if ($preWindow.Width  -gt $workArea.Width)  { $preWindow.Width  = [Math]::Max(560, $workArea.Width  - 40) }

$preCtrl = @{}
$prereqXaml.SelectNodes("//*[@Name]") | ForEach-Object { $preCtrl[$_.Name] = $preWindow.FindName($_.Name) }

function Write-SetupLog {
    param([string]$Msg)
    $preWindow.Dispatcher.Invoke([action]{
        $preCtrl.TxtSetupLog.AppendText("$Msg`r`n")
        $preCtrl.TxtSetupLog.ScrollToEnd()
    })
}

function Set-SetupStatus {
    param([string]$Text, [string]$Color)
    $preWindow.Dispatcher.Invoke([action]{
        $preCtrl.TxtSetupStatus.Text = $Text
        $preCtrl.SetupStatusDot.Fill = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString($Color))
    })
}

function Render-PrereqList {
    param($State)
    $preCtrl.PrereqList.Children.Clear()

    $items = @(
        @{ Name="Rust toolchain (cargo)"; Info=$State.Rust },
        @{ Name="MSVC Build Tools";        Info=$State.Msvc },
        @{ Name="PowerShell 5+";           Info=$State.PowerShell }
    )

    foreach ($it in $items) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = "0,4,0,4"
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = "30"
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = "*"
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = "Auto"
        $row.ColumnDefinitions.Add($c1); $row.ColumnDefinitions.Add($c2); $row.ColumnDefinitions.Add($c3)

        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 14; $dot.Height = 14
        $dot.Fill = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                ($(if ($it.Info.Installed) { "#FF22C55E" } else { "#FFEF4444" }))
            ))
        [System.Windows.Controls.Grid]::SetColumn($dot, 0)

        $name = New-Object System.Windows.Controls.TextBlock
        $name.Text = $it.Name
        $name.Foreground = "White"
        $name.FontSize = 13
        $name.FontWeight = "SemiBold"
        $name.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($name, 1)

        $detail = New-Object System.Windows.Controls.TextBlock
        $detail.Text = $it.Info.Detail
        $detail.Foreground = "#FFB8B8D1"
        $detail.FontSize = 11
        $detail.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($detail, 2)

        [void]$row.Children.Add($dot)
        [void]$row.Children.Add($name)
        [void]$row.Children.Add($detail)
        [void]$preCtrl.PrereqList.Children.Add($row)
    }
}

function Refresh-Prereqs {
    $state = Get-PrereqState
    Render-PrereqList -State $state
    if ($state.AllOk) {
        Set-SetupStatus "All requirements satisfied" "#FF22C55E"
        $preCtrl.BtnContinue.IsEnabled = $true
        $preCtrl.BtnInstall.IsEnabled  = $false
    } else {
        Set-SetupStatus "Missing dependencies - click 'Install dependencies'" "#FFFACC15"
        $preCtrl.BtnContinue.IsEnabled = $false
        $preCtrl.BtnInstall.IsEnabled  = $true
    }
    return $state
}

$preCtrl.BtnRecheck.Add_Click({ [void](Refresh-Prereqs) })

$preCtrl.BtnContinue.Add_Click({
    $preWindow.Tag = "continue"
    $preWindow.Close()
})

$preCtrl.BtnInstall.Add_Click({
    $preCtrl.BtnInstall.IsEnabled  = $false
    $preCtrl.BtnContinue.IsEnabled = $false
    $preCtrl.BtnRecheck.IsEnabled  = $false
    Set-SetupStatus "Installing..." "#FFFACC15"

    $log = { param($m) Write-SetupLog $m }

    # Background runspace so the UI stays responsive
    $script:installState = [hashtable]::Synchronized(@{ Queue = (New-Object System.Collections.Queue); Done=$false; Restart=$false })

    $script:installRs = [runspacefactory]::CreateRunspace()
    $script:installRs.ApartmentState = "STA"
    $script:installRs.Open()
    $script:installRs.SessionStateProxy.SetVariable("State", $script:installState)

    $script:installPs = [powershell]::Create()
    $script:installPs.Runspace = $script:installRs

    # Everything the install needs is defined right here, inside the single
    # scriptblock that runs in the background runspace. This mirrors
    # installrust.ps1 function-for-function and message-for-message, and
    # avoids the brittle "export a function from the main scope, then
    # re-import it inside the runspace" dance entirely.
    [void]$script:installPs.AddScript({
        function Push-Line($m) { $State.Queue.Enqueue([string]$m) }

        function Write-Step  { param([string]$Message) Push-Line "==> $Message" }
        function Write-Ok    { param([string]$Message) Push-Line "    [OK]    $Message" }
        function Write-Warn2 { param([string]$Message) Push-Line "    [WARN]  $Message" }
        function Write-Err   { param([string]$Message) Push-Line "    [ERROR] $Message" }

        function Test-IsAdmin {
            $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Test-WingetAvailable {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
            try {
                winget --version *> $null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }

        function Install-WithWinget {
            param(
                [Parameter(Mandatory)][string]$PackageId,
                [Parameter(Mandatory)][string]$DisplayName,
                [string[]]$ExtraArgs = @()
            )

            Write-Step "Attempting winget install: $DisplayName ($PackageId)"

            $wingetArgs = @(
                'install', '--id', $PackageId,
                '--exact', '--silent',
                '--accept-package-agreements', '--accept-source-agreements',
                '--disable-interactivity'
            ) + $ExtraArgs

            try {
                & winget @wingetArgs
                if ($LASTEXITCODE -eq 0) {
                    Write-Ok "$DisplayName installed via winget."
                    return $true
                }
                Write-Warn2 "winget exited with code $LASTEXITCODE for $DisplayName."
                return $false
            } catch {
                Write-Warn2 "winget threw an exception for $DisplayName : $($_.Exception.Message)"
                return $false
            }
        }

        function Invoke-DownloadFile {
            param(
                [Parameter(Mandatory)][string]$Uri,
                [Parameter(Mandatory)][string]$OutFile
            )

            Write-Step "Downloading $Uri"
            try {
                [Net.ServicePointManager]::SecurityProtocol = `
                    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
                Write-Ok "Downloaded to $OutFile"
                return $true
            } catch {
                Write-Err "Failed to download $Uri : $($_.Exception.Message)"
                return $false
            }
        }

        function Install-MSVCBuildTools {
            $wingetSucceeded = $false

            if (Test-WingetAvailable) {
                $wingetSucceeded = Install-WithWinget `
                    -PackageId 'Microsoft.VisualStudio.2022.BuildTools' `
                    -DisplayName 'Visual Studio 2022 Build Tools' `
                    -ExtraArgs @(
                        '--override',
                        '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows10SDK.19041 --includeRecommended'
                    )
            } else {
                Write-Warn2 "Skipping winget for MSVC Build Tools (unavailable)."
            }

            if ($wingetSucceeded) { return $true }

            Write-Step "Falling back to direct download for MSVC 2022 Build Tools"

            if (-not (Test-IsAdmin)) {
                Write-Warn2 "Not running as Administrator. The Build Tools installer may fail or prompt for elevation."
            }

            $installer = Join-Path $env:TEMP 'vs_buildtools.exe'
            $url       = 'https://aka.ms/vs/17/release/vs_buildtools.exe'

            if (-not (Invoke-DownloadFile -Uri $url -OutFile $installer)) {
                Write-Err "Could not download the Visual Studio Build Tools bootstrapper. Aborting MSVC install."
                return $false
            }

            Write-Step "Running Visual Studio Build Tools installer silently (this can take several minutes)..."

            $arguments = @(
                '--quiet', '--wait', '--norestart', '--nocache',
                '--add', 'Microsoft.VisualStudio.Workload.VCTools',
                '--add', 'Microsoft.VisualStudio.Component.Windows10SDK.19041',
                '--includeRecommended'
            )

            $proc = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru -NoNewWindow

            switch ($proc.ExitCode) {
                0       { Write-Ok  "MSVC 2022 Build Tools installed successfully."; return $true }
                3010    { Write-Ok  "MSVC 2022 Build Tools installed successfully. A reboot is required."; return $true }
                default { Write-Err "MSVC Build Tools installer exited with code $($proc.ExitCode)."; return $false }
            }
        }

        function Install-Rust {
            $wingetSucceeded = $false

            if (Test-WingetAvailable) {
                $wingetSucceeded = Install-WithWinget `
                    -PackageId 'Rustlang.Rustup' `
                    -DisplayName 'Rust (rustup)'
            } else {
                Write-Warn2 "Skipping winget for Rust (unavailable)."
            }

            if ($wingetSucceeded) { return $true }

            Write-Step "Falling back to direct download for Rust (rustup-init)"

            $installer = Join-Path $env:TEMP 'rustup-init.exe'
            $url       = 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'

            if (-not (Invoke-DownloadFile -Uri $url -OutFile $installer)) {
                Write-Err "Could not download rustup-init.exe. Aborting Rust install."
                return $false
            }

            Write-Step "Running rustup-init silently with the default stable toolchain..."

            $arguments = @(
                '-y',
                '--default-toolchain', 'stable',
                '--profile', 'default'
            )

            $proc = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru -NoNewWindow

            if ($proc.ExitCode -eq 0) {
                Write-Ok "Rust installed successfully via rustup-init."
                Write-Warn2 "Open a new terminal (or re-source your profile) so the updated PATH (cargo/rustc) takes effect."
                return $true
            } else {
                Write-Err "rustup-init exited with code $($proc.ExitCode)."
                return $false
            }
        }

        # --------------------------------------------------------
        # Main install flow - mirrors installrust.ps1 step for step
        # --------------------------------------------------------
        Write-Step "Checking winget availability"
        if (Test-WingetAvailable) {
            Write-Ok "winget is available and responding."
        } else {
            Write-Warn2 "winget is not available or not working. The download fallback will be used for all components."
        }

        $needMsvc = -not (Test-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -ErrorAction SilentlyContinue) -and `
                    -not (Test-Path "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe" -ErrorAction SilentlyContinue)

        $needRust = -not (Get-Command cargo -ErrorAction SilentlyContinue)

        if ($needMsvc) {
            $okMsvc = Install-MSVCBuildTools
            if (-not $okMsvc) { Write-Warn2 "MSVC install reported failure - continuing anyway." }
        } else {
            Write-Ok "MSVC Build Tools already present."
        }

        if ($needRust) {
            $okRust = Install-Rust
            if (-not $okRust) { Write-Err "Rust install failed." }
        } else {
            Write-Ok "Rust already installed."
        }

        Write-Step "Done. Review the log above for any errors or pending reboots."

        $State.Done = $true
    })

    $script:installHandle = $script:installPs.BeginInvoke()

    $script:installTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:installTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:installTimer.Add_Tick({
        while ($script:installState.Queue.Count -gt 0) {
            Write-SetupLog $script:installState.Queue.Dequeue()
        }
        if ($script:installState.Done) {
            $script:installTimer.Stop()
            try { $script:installPs.EndInvoke($script:installHandle) | Out-Null } catch {}
            $script:installPs.Dispose()
            $script:installRs.Close(); $script:installRs.Dispose()

            # Newly-installed tools (cargo/rustc) update PATH in the registry,
            # but this already-running process is still holding the PATH it
            # started with in memory. Spawning a new process via Start-Process
            # does NOT fix this - a child inherits the parent's in-memory
            # environment block, not a fresh read from the registry. So we
            # pull the current Machine + User PATH directly from the registry
            # into THIS process instead, which is what actually makes the
            # newly-installed tools visible to Get-Command/cargo right away.
            $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
            $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
            $env:Path    = @($machinePath, $userPath) -join ';'

            Write-SetupLog ""
            Write-SetupLog "Installation finished. Refreshing environment and re-checking..."

            $result = Refresh-Prereqs
            $preCtrl.BtnRecheck.IsEnabled = $true

            if ($result.AllOk) {
                Write-SetupLog "All dependencies detected. You can continue."
            } else {
                Write-SetupLog "Some dependencies still aren't detected after refreshing PATH."
                Write-SetupLog "If this persists, fully close this app (not just this window) and reopen it from the Start menu - some installer types only take effect in a brand new login/session."
            }
        }
    })
    $script:installTimer.Start()
})

# Initial state
$initial = Refresh-Prereqs
if (-not $initial.AllOk) {
    Write-SetupLog "Some dependencies are missing. Click 'Install dependencies' to install them automatically."
} else {
    Write-SetupLog "All dependencies are present. You can continue."
}

# Show prerequisite window first
$preWindow.ShowDialog() | Out-Null

# If user closed it without continuing, exit gracefully
if ($preWindow.Tag -ne "continue") {
    return
}

# ============================================================
# From here on, your existing main builder code continues
# (the XAML for the builder, runspace, BtnBuild handler, etc.)
# ============================================================


Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# XAML UI
# ============================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PS -> EXE Builder"
        Height="700" Width="980"
        WindowStartupLocation="CenterScreen"
        Background="#FF1E1E2E"
        FontFamily="Segoe UI"
        AllowDrop="True"
        ResizeMode="CanResize">
  <Window.Resources>
    <!-- Button style -->
    <Style x:Key="AccentButton" TargetType="Button">
      <Setter Property="Background" Value="#FF7C3AED"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border CornerRadius="8" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#FF8B5CF6"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource AccentButton}">
      <Setter Property="Background" Value="#FF3F3F55"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#FF52526B"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#FF2B2B40"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#FF3F3F55"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8"/>
      <Setter Property="CaretBrush" Value="White"/>
    </Style>

    <Style TargetType="Label">
      <Setter Property="Foreground" Value="#FFB8B8D1"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Margin" Value="0,0,12,0"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="White"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="240"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Sidebar -->
    <Border Background="#FF181826" Grid.Column="0">
      <StackPanel Margin="20">
        
        <TextBlock Text="PS -> EXE" Foreground="White" FontSize="22" FontWeight="Bold" Margin="0,4,0,0"/>
        <TextBlock Text="Builder Studio" Foreground="#FFB8B8D1" FontSize="12" Margin="0,0,0,30"/>

        <TextBlock Text="VERSION" Foreground="#FF7C3AED" FontSize="10" FontWeight="Bold"/>
        <TextBlock Text="1.0.0.1" Foreground="#FFB8B8D1" FontSize="11" Margin="0,2,0,20"/>

        <TextBlock Text="AUTHOR" Foreground="#FF7C3AED" FontSize="10" FontWeight="Bold"/>
        <TextBlock Text="Nazim Hassani" Foreground="#FFB8B8D1" FontSize="11" Margin="0,2,0,20"/>

        
      </StackPanel>
    </Border>

    <!-- Main content -->
    <Grid Grid.Column="1" Margin="24">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Title -->
      <StackPanel Grid.Row="0" Margin="0,0,0,14">
        <TextBlock Text="Convert PowerShell to EXE" Foreground="White" FontSize="22" FontWeight="Bold"/>
        <TextBlock Text="Drag a .ps1 file, choose options, and build a standalone Windows executable." Foreground="#FFB8B8D1" FontSize="12" Margin="0,4,0,0"/>
      </StackPanel>

      <!-- File picker -->
      <Border Grid.Row="1" Background="#FF2B2B40" CornerRadius="10" Padding="12" Margin="0,0,0,10">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <Label Content="POWERSHELL SCRIPT (.PS1)"/>
            <TextBox Name="TxtPs1Path" Margin="0,4,0,0" Height="34" VerticalContentAlignment="Center"/>
          </StackPanel>
          <Button Grid.Column="1" Name="BtnBrowse" Content="Browse..." Style="{StaticResource SecondaryButton}" Margin="10,18,0,0" Width="110" Height="34"/>
        </Grid>
      </Border>

      <!-- Output path -->
      <Border Grid.Row="2" Background="#FF2B2B40" CornerRadius="10" Padding="12" Margin="0,0,0,10">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <Label Content="OUTPUT FOLDER"/>
            <TextBox Name="TxtOutDir" Margin="0,4,0,0" Height="34" VerticalContentAlignment="Center"/>
          </StackPanel>
          <Button Grid.Column="1" Name="BtnBrowseOut" Content="Choose..." Style="{StaticResource SecondaryButton}" Margin="10,18,0,0" Width="110" Height="34"/>
        </Grid>
      </Border>

      <!-- Options -->
      <Border Grid.Row="3" Background="#FF2B2B40" CornerRadius="10" Padding="12" Margin="0,0,0,10">
        <StackPanel>
          <Label Content="BUILD OPTIONS"/>
          <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
            <RadioButton Name="RbAuto" Content="Auto-detect" IsChecked="True" GroupName="Mode"/>
            <RadioButton Name="RbCli"  Content="Force CLI"  GroupName="Mode"/>
            <RadioButton Name="RbGui"  Content="Force GUI"  GroupName="Mode"/>
            <CheckBox Name="CbKeep" Content="Keep Rust project" Margin="20,0,0,0"/>
            <CheckBox Name="CbOpen" Content="Open output folder when done" Margin="20,0,0,0" IsChecked="True"/>
          </StackPanel>
        </StackPanel>
      </Border>

      <!-- File properties (optional) -->
      <Border Grid.Row="4" Background="#FF2B2B40" CornerRadius="10" Padding="12" Margin="0,0,0,10">
        <StackPanel>
          <Label Content="FILE PROPERTIES (OPTIONAL)"/>
          <TextBlock Text="Leave blank to skip - the EXE will build normally without custom version info." Foreground="#FF6B7280" FontSize="11" Margin="0,2,0,10"/>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,8,10">
              <Label Content="PRODUCT NAME" FontSize="10"/>
              <TextBox Name="TxtProductName" Height="32" VerticalContentAlignment="Center"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="8,0,8,10">
              <Label Content="FILE DESCRIPTION" FontSize="10"/>
              <TextBox Name="TxtFileDescription" Height="32" VerticalContentAlignment="Center"/>
            </StackPanel>
            <StackPanel Grid.Column="2" Margin="8,0,0,10">
              <Label Content="VERSION (E.G. 1.0.0.0)" FontSize="10"/>
              <TextBox Name="TxtFileVersion" Height="32" VerticalContentAlignment="Center"/>
            </StackPanel>
          </Grid>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,8,0">
              <Label Content="COMPANY NAME" FontSize="10"/>
              <TextBox Name="TxtCompanyName" Height="32" VerticalContentAlignment="Center"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="8,0,8,0">
              <Label Content="COPYRIGHT" FontSize="10"/>
              <TextBox Name="TxtCopyright" Height="32" VerticalContentAlignment="Center"/>
            </StackPanel>
          </Grid>
        </StackPanel>
      </Border>

      <!-- Log -->
      <Border Grid.Row="5" Background="#FF11111B" CornerRadius="10" Padding="0">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Background="#FF181826" CornerRadius="10,10,0,0" Padding="12,8">
            <TextBlock Text="BUILD LOG" Foreground="#FF7C3AED" FontWeight="Bold" FontSize="11"/>
          </Border>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <TextBox Name="TxtLog"
                     Background="Transparent"
                     BorderThickness="0"
                     Foreground="#FFCDD6F4"
                     FontFamily="Consolas"
                     FontSize="12"
                     IsReadOnly="True"
                     TextWrapping="Wrap"
                     AcceptsReturn="True"
                     Padding="12"/>
          </ScrollViewer>
        </Grid>
      </Border>

      <!-- Bottom bar -->
      <Grid Grid.Row="6" Margin="0,14,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse Name="StatusDot" Width="10" Height="10" Fill="#FF6B7280"/>
          <TextBlock Name="TxtStatus" Text="Idle" Foreground="#FFB8B8D1" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>

        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button Name="BtnClear" Content="Clear Log" Style="{StaticResource SecondaryButton}" Width="110" Height="36" Margin="0,0,10,0"/>
          <Button Name="BtnBuild" Content="BUILD EXE" Style="{StaticResource AccentButton}" Width="160" Height="36"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Grid>
</Window>
"@

# ============================================================
# Load XAML
# ============================================================
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Same screen-fit safety net as the Setup window - this window grew an extra
# row for File Properties, so it's the more likely of the two to overflow a
# shorter screen.
$workArea = [System.Windows.SystemParameters]::WorkArea
if ($window.Height -gt $workArea.Height) { $window.Height = [Math]::Max(480, $workArea.Height - 40) }
if ($window.Width  -gt $workArea.Width)  { $window.Width  = [Math]::Max(700, $workArea.Width  - 40) }

# Get controls
$ctrl = @{}
$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    $ctrl[$_.Name] = $window.FindName($_.Name)
}

# ============================================================
# Logic (same as PsToExeBuilder.ps1)
# ============================================================

$CargoToml = @'
[package]
name = "{0}"
version = "1.0.0"
edition = "2021"

[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
strip = true
panic = "abort"
'@

$MainRsCli = @'
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

const EMBEDDED_PS_SCRIPT: &str = include_str!("script.ps1");

fn main() {
    let args: Vec<String> = env::args().collect();
    let keep_script = args.iter().any(|a| a.eq_ignore_ascii_case("--keep-script"));

    let script_path = match write_embedded_script() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Failed to write embedded script: {}", e);
            pause();
            std::process::exit(1);
        }
    };

    let extra: Vec<String> = args.iter().skip(1)
        .filter(|a| a.as_str() != "--keep-script")
        .cloned()
        .collect();

    let mut cmd = Command::new("powershell.exe");
    cmd.arg("-NoLogo")
        .arg("-NoProfile")
        .arg("-STA")
        .arg("-ExecutionPolicy").arg("Bypass")
        .arg("-File").arg(&script_path);

    for a in &extra { cmd.arg(a); }

    // IMPORTANT: do NOT use .output() and do NOT close stdin.
    // We want PowerShell to share THIS console so:
    //   - Read-Host prompts are visible to the user
    //   - The user can actually type answers
    //   - Write-Host / progress bars stream in real time
    let status = cmd.status();

    if !keep_script {
        let _ = fs::remove_file(&script_path);
    }

    match status {
        Ok(s) => {
            if !s.success() {
                eprintln!("\nPowerShell exited with code {:?}", s.code());
                pause();
                std::process::exit(s.code().unwrap_or(1));
            }
        }
        Err(e) => {
            eprintln!("Failed to launch PowerShell: {}", e);
            pause();
            std::process::exit(1);
        }
    }

    pause();
}

fn pause() {
    println!("\nPress Enter to exit...");
    let mut s = String::new();
    let _ = std::io::stdin().read_line(&mut s);
}

fn write_embedded_script() -> Result<PathBuf, String> {
    let dir = env::temp_dir().join("PsToExeRunner");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join(format!("script_{}.ps1", std::process::id()));

    // UTF-8 with BOM so PowerShell 5.1 doesn't misread non-ASCII chars
    let mut bytes: Vec<u8> = vec![0xEF, 0xBB, 0xBF];
    bytes.extend_from_slice(EMBEDDED_PS_SCRIPT.as_bytes());

    fs::write(&path, &bytes).map_err(|e| e.to_string())?;
    Ok(path)
}
'@

$MainRsGui = @'
#![windows_subsystem = "windows"]

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

const EMBEDDED_PS_SCRIPT: &str = include_str!("script.ps1");

fn main() {
    let script_path = match write_embedded_script() {
        Ok(p) => p,
        Err(e) => {
            let _ = log_error(&format!("write_embedded_script failed: {}", e));
            std::process::exit(1);
        }
    };

    let args: Vec<String> = env::args().skip(1).collect();

    // IMPORTANT for WPF/WinForms:
    //   -STA          -> required by WPF / XamlReader / ShowDialog
    //   -NoProfile    -> faster, predictable
    //   -ExecutionPolicy Bypass
    //   -WindowStyle Hidden -> hides the PowerShell host console window,
    //                         NOT the GUI created by the script
    let mut cmd = Command::new("powershell.exe");
    cmd.arg("-NoLogo")
        .arg("-NoProfile")
        .arg("-STA")
        .arg("-ExecutionPolicy").arg("Bypass")
        .arg("-WindowStyle").arg("Hidden")
        .arg("-File").arg(&script_path);

    for a in &args { cmd.arg(a); }

    // We WAIT for PowerShell to exit so:
    //  - the embedded script file lives long enough
    //  - we can capture errors
    //  - we can clean up the temp file
    let status = cmd.status();

    // Clean up the temporary script
    let _ = fs::remove_file(&script_path);

    match status {
        Ok(s) => {
            if !s.success() {
                let _ = log_error(&format!(
                    "PowerShell exited with code {:?}",
                    s.code()
                ));
                std::process::exit(s.code().unwrap_or(1));
            }
        }
        Err(e) => {
            let _ = log_error(&format!("Failed to launch PowerShell: {}", e));
            std::process::exit(1);
        }
    }
}

fn write_embedded_script() -> Result<PathBuf, String> {
    let dir = env::temp_dir().join("PsToExeRunner");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join(format!("script_{}.ps1", std::process::id()));
    fs::write(&path, EMBEDDED_PS_SCRIPT).map_err(|e| e.to_string())?;
    Ok(path)
}

fn log_error(msg: &str) -> std::io::Result<()> {
    let dir = env::temp_dir().join("PsToExeRunner");
    let _ = fs::create_dir_all(&dir);
    let log = dir.join("last_error.log");
    fs::write(log, msg)
}
'@

# ============================================================
# Helpers
# ============================================================

function Write-Log {
    param([string]$Msg, [string]$Color = "#FFCDD6F4")
    $window.Dispatcher.Invoke([action]{
        $ctrl.TxtLog.AppendText("$Msg`r`n")
        $ctrl.TxtLog.ScrollToEnd()
    })
}

function Set-Status {
    param([string]$Text, [string]$Color)
    $window.Dispatcher.Invoke([action]{
        $ctrl.TxtStatus.Text = $Text
        $ctrl.StatusDot.Fill = (New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString($Color)))
    })
}

function Test-IsGuiScript {
    param([string]$Path)
    $patterns = @(
        'Add-Type\s+-AssemblyName\s+System\.Windows\.Forms',
        'Add-Type\s+-AssemblyName\s+PresentationFramework',
        '\[System\.Windows\.Forms','\[System\.Windows\.MessageBox\]',
        'New-Object\s+System\.Windows\.Forms','Out-GridView',
        '\.ShowDialog\(\)','WPF','XAML'
    )
    try { $c = Get-Content -Path $Path -Raw -ErrorAction Stop } catch { return $false }
    foreach ($p in $patterns) { if ($c -match $p) { return $true } }
    return $false
}

function Get-SafeProjectName {
    param([string]$Name)
    $s = ($Name -replace '[^A-Za-z0-9_-]', '_').Trim('_').ToLower()
    if (-not $s) { $s = "ps_exe" }
    return $s
}
# ============================================================
# Shared state for background <-> UI communication
# ============================================================
$global:PsToExeState = [hashtable]::Synchronized(@{
    Queue     = (New-Object System.Collections.Queue)
    Done      = $false
    Success   = $false
    ExePath   = $null
    KeepPath  = $null
})

# ============================================================
# Events
# ============================================================

$ctrl.BtnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "PowerShell scripts (*.ps1)|*.ps1"
    if ($dlg.ShowDialog() -eq "OK") { $ctrl.TxtPs1Path.Text = $dlg.FileName }
})

$ctrl.BtnBrowseOut.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") { $ctrl.TxtOutDir.Text = $dlg.SelectedPath }
})

$ctrl.BtnClear.Add_Click({ $ctrl.TxtLog.Clear() })

# Drag & drop
$window.Add_Drop({
    $files = $_.Data.GetData([Windows.DataFormats]::FileDrop)
    if ($files -and $files[0] -like "*.ps1") {
        $ctrl.TxtPs1Path.Text = $files[0]
    }
})
$window.Add_DragOver({ $_.Effects = [System.Windows.DragDropEffects]::Copy })

$ctrl.BtnBuild.Add_Click({
    $ps1 = $ctrl.TxtPs1Path.Text.Trim()
    $out = $ctrl.TxtOutDir.Text.Trim()

    if (-not (Test-Path $ps1)) {
        [System.Windows.MessageBox]::Show("Select a valid .ps1 file.","PsToExeBuilder","OK","Warning") | Out-Null
        return
    }
    if (-not $out) {
        $out = Split-Path $ps1 -Parent
        $ctrl.TxtOutDir.Text = $out
    }

    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        [System.Windows.MessageBox]::Show("Cargo (Rust) is not installed. Get it from https://rustup.rs","PsToExeBuilder","OK","Error") | Out-Null
        return
    }

    # Resolve mode
    $isGui = $false
    if ($ctrl.RbGui.IsChecked)      { $isGui = $true }
    elseif ($ctrl.RbCli.IsChecked)  { $isGui = $false }
    else                            { $isGui = Test-IsGuiScript -Path $ps1 }
    $mode = if ($isGui) { "GUI" } else { "CLI" }

    $stem = [IO.Path]::GetFileNameWithoutExtension($ps1)
    $proj = Get-SafeProjectName -Name $stem
    $guid = [Guid]::NewGuid().ToString("N").Substring(0,8)   # [OK] fixed
    $work = Join-Path ([IO.Path]::GetTempPath()) ("ps2exe_" + $guid)
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $projDir = Join-Path $work $proj

    Set-Status "Building..." "#FFFACC15"
    $ctrl.BtnBuild.IsEnabled = $false
    Write-Log "============================================================"
    Write-Log " Building : $ps1"
    Write-Log " Mode     : $mode"
    Write-Log " Output   : $out"
    Write-Log " Workdir  : $projDir"
    Write-Log "============================================================"

    # Reset shared state
    $global:PsToExeState.Queue.Clear()
    $global:PsToExeState.Done    = $false
    $global:PsToExeState.Success = $false
    $global:PsToExeState.ExePath = $null
    $global:PsToExeState.KeepPath= $null

    $keepProject = [bool]$ctrl.CbKeep.IsChecked

    # --------------------------------------------------------
    # Optional file properties (Windows version resource)
    # --------------------------------------------------------
    $productName = $ctrl.TxtProductName.Text.Trim()
    $fileDesc    = $ctrl.TxtFileDescription.Text.Trim()
    $companyName = $ctrl.TxtCompanyName.Text.Trim()
    $copyright   = $ctrl.TxtCopyright.Text.Trim()
    $verRaw      = $ctrl.TxtFileVersion.Text.Trim()

    $hasVersionInfo = [bool]($productName -or $fileDesc -or $companyName -or $copyright -or $verRaw)

    if (-not $verRaw) { $verRaw = "1.0.0.0" }
    $verNums = @($verRaw -split '\.' | ForEach-Object {
        $n = 0
        [void][int]::TryParse($_, [ref]$n)
        [math]::Max(0, [math]::Min(65535, $n))
    })
    while ($verNums.Count -lt 4) { $verNums += 0 }
    $verNums = $verNums[0..3]
    $fileVersionString = $verNums -join "."

    # --------------------------------------------------------
    # Runspace: builds the EXE in background, pushes log lines
    # into the shared queue.
    # --------------------------------------------------------
    # NOTE: must be $script: scope, not local - these are read later by the
    # $timer.Add_Tick handler, which runs as an independent callback after
    # this Add_Click invocation has already returned. Plain local vars here
    # would be invisible to Tick (resolving to $null) once that happens.
    $script:rs = [runspacefactory]::CreateRunspace()
    $script:rs.ApartmentState = "STA"
    $script:rs.ThreadOptions  = "ReuseThread"
    $script:rs.Open()
    $script:rs.SessionStateProxy.SetVariable("State", $global:PsToExeState)
    $script:rs.SessionStateProxy.SetVariable("work", $work)
    $script:rs.SessionStateProxy.SetVariable("proj", $proj)
    $script:rs.SessionStateProxy.SetVariable("projDir", $projDir)
    $script:rs.SessionStateProxy.SetVariable("ps1", $ps1)
    $script:rs.SessionStateProxy.SetVariable("out", $out)
    $script:rs.SessionStateProxy.SetVariable("stem", $stem)
    $script:rs.SessionStateProxy.SetVariable("isGui", $isGui)
    $script:rs.SessionStateProxy.SetVariable("CargoToml", $CargoToml)
    $script:rs.SessionStateProxy.SetVariable("MainRsCli", $MainRsCli)
    $script:rs.SessionStateProxy.SetVariable("MainRsGui", $MainRsGui)
    $script:rs.SessionStateProxy.SetVariable("keepProject", $keepProject)
    $script:rs.SessionStateProxy.SetVariable("hasVersionInfo", $hasVersionInfo)
    $script:rs.SessionStateProxy.SetVariable("productName", $productName)
    $script:rs.SessionStateProxy.SetVariable("fileDesc", $fileDesc)
    $script:rs.SessionStateProxy.SetVariable("companyName", $companyName)
    $script:rs.SessionStateProxy.SetVariable("copyright", $copyright)
    $script:rs.SessionStateProxy.SetVariable("fileVersionString", $fileVersionString)
    $script:rs.SessionStateProxy.SetVariable("verNums", $verNums)

    $script:ps = [powershell]::Create()
    $script:ps.Runspace = $script:rs
    [void]$ps.AddScript({
        function Push-Line($msg) { $State.Queue.Enqueue([string]$msg) }

        try {
            Push-Line ">> cargo new --bin $proj"
            Set-Location $work
            $newOut = & cargo new --bin $proj 2>&1
            $newOut | ForEach-Object { Push-Line $_ }

            Set-Content -Path (Join-Path $projDir "Cargo.toml") `
                        -Value ($CargoToml -f $proj) -Encoding UTF8

            # Re-write as UTF-8 WITH BOM, regardless of the source file's
            # original encoding. powershell.exe (5.1) only reliably detects
            # UTF-8 when a BOM is present; without it, multi-byte chars
            # (emoji, accented text) get corrupted using the system codepage,
            # which breaks the parser once the exe extracts this file again.
            $scriptContent = Get-Content -Path $ps1 -Raw -Encoding UTF8
            Set-Content -Path (Join-Path $projDir "src\script.ps1") -Value $scriptContent -Encoding UTF8

            $mainRsContent = if ($isGui) { $MainRsGui } else { $MainRsCli }
            Set-Content -Path (Join-Path $projDir "src\main.rs") -Value $mainRsContent -Encoding UTF8

            if ($hasVersionInfo) {
                Push-Line ""
                Push-Line ">> Embedding file properties (version resource)"

                # winres shells out to rc.exe (from the MSVC Build Tools we
                # already require), so no extra system dependency is needed -
                # cargo just needs to fetch the crate itself from crates.io.
                Add-Content -Path (Join-Path $projDir "Cargo.toml") `
                            -Value "`n[build-dependencies]`nwinres = `"0.1`"`n" -Encoding UTF8

                function ConvertTo-RustString([string]$s) {
                    return $s.Replace('\', '\\').Replace('"', '\"')
                }

                $packedVer = ([uint64]$verNums[0] -shl 48) -bor ([uint64]$verNums[1] -shl 32) -bor `
                             ([uint64]$verNums[2] -shl 16) -bor ([uint64]$verNums[3])

                $setLines = @()
                $setLines += "    res.set(`"FileVersion`", `"$(ConvertTo-RustString $fileVersionString)`");"
                $setLines += "    res.set(`"ProductVersion`", `"$(ConvertTo-RustString $fileVersionString)`");"
                if ($productName) { $setLines += "    res.set(`"ProductName`", `"$(ConvertTo-RustString $productName)`");" }
                if ($fileDesc)    { $setLines += "    res.set(`"FileDescription`", `"$(ConvertTo-RustString $fileDesc)`");" }
                if ($companyName) { $setLines += "    res.set(`"CompanyName`", `"$(ConvertTo-RustString $companyName)`");" }
                if ($copyright)   { $setLines += "    res.set(`"LegalCopyright`", `"$(ConvertTo-RustString $copyright)`");" }

                $buildRs = @"
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    let mut res = winres::WindowsResource::new();
$($setLines -join "`n")
    res.set_version_info(winres::VersionInfo::FILEVERSION, ${packedVer}u64);
    res.set_version_info(winres::VersionInfo::PRODUCTVERSION, ${packedVer}u64);

    if let Err(e) = res.compile() {
        eprintln!("warning: failed to embed version info: {}", e);
    }
}
"@
                Set-Content -Path (Join-Path $projDir "build.rs") -Value $buildRs -Encoding UTF8
            }

            Push-Line ""
            Push-Line ">> cargo build --release"
            Set-Location $projDir

            # Stream cargo output line by line
            & cargo build --release 2>&1 | ForEach-Object { Push-Line $_ }

            $built = Join-Path $projDir ("target\release\{0}.exe" -f $proj)
            if (Test-Path $built) {
                if (-not (Test-Path $out)) {
                    New-Item -ItemType Directory -Path $out -Force | Out-Null
                }
                $final = Join-Path $out ("{0}.exe" -f $stem)
                Copy-Item -Path $built -Destination $final -Force
                $State.ExePath  = $final
                $State.Success  = $true
                Push-Line ""
                Push-Line "EXE created: $final"
            } else {
                $State.Success = $false
                Push-Line ""
                Push-Line "Build finished but EXE was not produced."
            }
        }
        catch {
            $State.Success = $false
            Push-Line "EXCEPTION: $($_.Exception.Message)"
        }
        finally {
            if (-not $keepProject) {
                Set-Location $env:TEMP
                Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                $State.KeepPath = $projDir
            }
            $State.Done = $true
        }
    })

    $script:asyncHandle = $script:ps.BeginInvoke()

    # --------------------------------------------------------
    # UI timer: drains the queue and updates the log live
    # --------------------------------------------------------
    $script:timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:timer.Interval = [TimeSpan]::FromMilliseconds(120)

    $script:timer.Add_Tick({
        # Drain queued log lines
        while ($global:PsToExeState.Queue.Count -gt 0) {
            $line = $global:PsToExeState.Queue.Dequeue()
            Write-Log $line
        }

        if ($global:PsToExeState.Done) {
            $script:timer.Stop()

            if ($global:PsToExeState.Success) {
                Write-Log ""
                Write-Log "[OK] SUCCESS"
                Write-Log ("EXE: {0}" -f $global:PsToExeState.ExePath)
                Set-Status "Build completed" "#FF22C55E"

                if ($ctrl.CbOpen.IsChecked -and $global:PsToExeState.ExePath) {
                    Start-Process explorer.exe (Split-Path $global:PsToExeState.ExePath -Parent)
                }
            } else {
                Write-Log ""
                Write-Log "[FAIL] BUILD FAILED"
                Set-Status "Build failed" "#FFEF4444"
            }

            if ($global:PsToExeState.KeepPath) {
                Write-Log ("[DIR] Rust project kept at: {0}" -f $global:PsToExeState.KeepPath)
            }

            try { $script:ps.EndInvoke($script:asyncHandle) | Out-Null } catch {}
            $script:ps.Dispose()
            $script:rs.Close()
            $script:rs.Dispose()

            $ctrl.BtnBuild.IsEnabled = $true
        }
    })

    $script:timer.Start()
})

# Initial state
Set-Status "Idle" "#FF6B7280"
$window.ShowDialog() | Out-Null