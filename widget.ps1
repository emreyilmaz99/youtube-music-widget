# YouTube Music / medya widget'i
# kapak + buzlu arkaplan + ilerleme (seek) + ses slider'i + tekrar + ayarlar (vurgu rengi) + kucultme
# Windows SMTC uzerinden calisir: YouTube Music (tarayici/uygulama), Spotify vb.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# Tek instance
$script:mutex = New-Object System.Threading.Mutex($false, "Local\YTMusicWidgetSingleton")
if (-not $script:mutex.WaitOne(0)) {
  try { ([System.Threading.EventWaitHandle]::OpenExisting("Local\YTMusicWidgetShow")).Set() } catch {}
  exit
}
$script:showEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Local\YTMusicWidgetShow")

$settingsPath = Join-Path $PSScriptRoot "settings.json"
$script:accent = 'FF5C5C'; $script:accentLight = 'FF8A5C'; $script:mode = 'card'; $script:opacity = 0.97
$script:cardLeft = $null; $script:cardTop = $null; $script:barLeft = $null; $script:barTop = $null
if (Test-Path $settingsPath) {
  try {
    $cfg = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($cfg.accent) { $script:accent = "$($cfg.accent)" }
    if ($cfg.accentLight) { $script:accentLight = "$($cfg.accentLight)" }
    if ($cfg.mode) { $script:mode = "$($cfg.mode)" }
    if ($cfg.opacity) { $script:opacity = [double]$cfg.opacity }
    if ($null -ne $cfg.cardLeft) { $script:cardLeft = [double]$cfg.cardLeft }
    if ($null -ne $cfg.cardTop)  { $script:cardTop  = [double]$cfg.cardTop }
    if ($null -ne $cfg.barLeft)  { $script:barLeft  = [double]$cfg.barLeft }
    if ($null -ne $cfg.barTop)   { $script:barTop   = [double]$cfg.barTop }
  } catch {}
}

if (-not ([System.Management.Automation.PSTypeName]'WinInput').Type) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinInput {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
}
"@
}

# CoreAudio: gercek sistem sesi oku/yaz
if (-not ([System.Management.Automation.PSTypeName]'AudioCtl').Type) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
  int RegisterControlChangeNotify(IntPtr n);
  int UnregisterControlChangeNotify(IntPtr n);
  int GetChannelCount(out uint c);
  int SetMasterVolumeLevel(float level, Guid ctx);
  int SetMasterVolumeLevelScalar(float level, Guid ctx);
  int GetMasterVolumeLevel(out float level);
  int GetMasterVolumeLevelScalar(out float level);
  int SetChannelVolumeLevel(uint ch, float level, Guid ctx);
  int SetChannelVolumeLevelScalar(uint ch, float level, Guid ctx);
  int GetChannelVolumeLevel(uint ch, out float level);
  int GetChannelVolumeLevelScalar(uint ch, out float level);
  int SetMute(bool mute, Guid ctx);
  int GetMute(out bool mute);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, out IAudioEndpointVolume aev); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator { int NotImpl1(); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] public class MMDeviceEnumeratorComObject {}
public static class AudioCtl {
  static IAudioEndpointVolume Vol() {
    var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
    IMMDevice dev; Marshal.ThrowExceptionForHR(en.GetDefaultAudioEndpoint(0, 1, out dev));
    IAudioEndpointVolume aev; var iid = typeof(IAudioEndpointVolume).GUID;
    Marshal.ThrowExceptionForHR(dev.Activate(ref iid, 1, IntPtr.Zero, out aev));
    return aev;
  }
  public static float GetVolume() { float v; Marshal.ThrowExceptionForHR(Vol().GetMasterVolumeLevelScalar(out v)); return v; }
  public static void SetVolume(float v) { Marshal.ThrowExceptionForHR(Vol().SetMasterVolumeLevelScalar(v, Guid.Empty)); }
  public static bool GetMute() { bool m; Marshal.ThrowExceptionForHR(Vol().GetMute(out m)); return m; }
  public static void SetMute(bool m) { Marshal.ThrowExceptionForHR(Vol().SetMute(m, Guid.Empty)); }
}
'@
}

# WinRT SMTC
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.RandomAccessStreamReference,Windows.Storage.Streams,ContentType=WindowsRuntime]
$null = [Windows.Media.MediaPlaybackAutoRepeatMode,Windows.Media,ContentType=WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
})[0]
$script:asStreamM = [System.IO.WindowsRuntimeStreamExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsStreamForRead' -and $_.GetParameters().Count -eq 1
} | Select-Object -First 1

function Await($t, $rt) {
  $at = $asTaskGeneric.MakeGenericMethod($rt)
  $nt = $at.Invoke($null, @($t))
  $null = $nt.Wait(5000)
  if ($nt.IsCompleted) { return $nt.Result } else { return $null }
}

$script:mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Music Widget" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ResizeMode="NoResize"
        SizeToContent="WidthAndHeight" ShowInTaskbar="False"
        Left="40" Top="180" Opacity="0.97">
  <Window.Resources>
    <Style x:Key="Slim" TargetType="Slider">
      <Setter Property="IsMoveToPointEnabled" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid Background="Transparent" Height="18">
              <Border Height="3" CornerRadius="1.5" Background="#30FFFFFF" VerticalAlignment="Center"/>
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="{x:Static Slider.DecreaseLarge}" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton">
                        <Grid Background="Transparent" Height="18">
                          <Border Height="3" CornerRadius="1.5" VerticalAlignment="Center"
                                  Background="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Slider}}"/>
                        </Grid>
                      </ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="{x:Static Slider.IncreaseLarge}" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Grid Background="Transparent" Height="18"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Focusable="False">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Grid Background="Transparent" Width="14" Height="18">
                          <Ellipse Width="11" Height="11" Fill="White">
                            <Ellipse.Effect><DropShadowEffect Color="#000000" BlurRadius="4" ShadowDepth="0" Opacity="0.5"/></Ellipse.Effect>
                          </Ellipse>
                        </Grid>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid>

    <!-- ============ TAM KART ============ -->
    <Border x:Name="Full" Margin="14" CornerRadius="16" Width="264">
      <Border.Background><SolidColorBrush Color="#FF17171F"/></Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#66FF5C5C" Offset="0"/>
          <GradientStop Color="#22FFFFFF" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.BorderThickness>1</Border.BorderThickness>
      <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="22" ShadowDepth="0" Opacity="0.55"/></Border.Effect>

      <Grid x:Name="CardHost">
        <Canvas>
          <Image x:Name="BgArt" Stretch="UniformToFill" Opacity="0.8">
            <Image.Effect><BlurEffect Radius="26"/></Image.Effect>
          </Image>
        </Canvas>
        <Border>
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#44101016" Offset="0"/>
              <GradientStop Color="#99101016" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
        </Border>

        <StackPanel Margin="14,11,14,12">
          <Grid>
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="TopNote" Text="&#x266B;" Foreground="#FFFF6B6B" FontSize="11" FontFamily="Segoe UI Symbol" VerticalAlignment="Center"/>
              <TextBlock x:Name="AppName" Text="MUZIK" Foreground="#FFBABAC2" FontSize="9" FontWeight="Bold"
                         FontFamily="Segoe UI" Margin="5,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <TextBlock x:Name="GearBtn" Text="&#x2699;" Foreground="#FF9A9AA6" FontSize="13"
                         FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="0,0,11,0" ToolTip="Ayarlar"/>
              <TextBlock x:Name="MinBtn" Text="&#x2212;" Foreground="#FF9A9AA6" FontSize="14"
                         FontFamily="Segoe UI" Cursor="Hand" Margin="0,-3,11,0" ToolTip="Kucult"/>
              <TextBlock x:Name="CloseBtn" Text="&#x2715;" Foreground="#FF9A9AA6" FontSize="11"
                         FontFamily="Segoe UI" Cursor="Hand" ToolTip="Kapat"/>
            </StackPanel>
          </Grid>

          <Grid Margin="0,10,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Grid.Column="0" Width="56" Height="56" CornerRadius="10" Background="#FF2C2C36">
              <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="10" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
              <Grid>
                <TextBlock x:Name="NoArt" Text="&#x266B;" Foreground="#FF55555F" FontSize="22"
                           FontFamily="Segoe UI Symbol" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                <Border CornerRadius="10"><Border.Background><ImageBrush x:Name="ArtBrush" Stretch="UniformToFill"/></Border.Background></Border>
              </Grid>
            </Border>
            <StackPanel Grid.Column="1" Margin="10,1,0,0" VerticalAlignment="Center">
              <TextBlock x:Name="TrackTitle" Text="Muzik calmiyor" Foreground="#FFF6F6FA" FontSize="13"
                         FontWeight="SemiBold" FontFamily="Segoe UI" TextTrimming="CharacterEllipsis" MaxHeight="36" TextWrapping="Wrap"/>
              <TextBlock x:Name="TrackArtist" Text="Bir sarki baslat" Foreground="#FFA8A8B2" FontSize="10.5"
                         FontFamily="Segoe UI" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
            </StackPanel>
          </Grid>

          <Grid Margin="0,9,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock x:Name="CurT" Grid.Column="0" Text="0:00" Foreground="#FFB0B0BA" FontSize="9"
                       FontFamily="Segoe UI" VerticalAlignment="Center" Margin="2,0,7,0"/>
            <Slider x:Name="Prog" Grid.Column="1" Style="{StaticResource Slim}" Foreground="#FFFF6B6B"
                    Minimum="0" Maximum="100" Value="0" VerticalAlignment="Center"/>
            <TextBlock x:Name="TotT" Grid.Column="2" Text="0:00" Foreground="#FFB0B0BA" FontSize="9"
                       FontFamily="Segoe UI" VerticalAlignment="Center" Margin="7,0,2,0"/>
          </Grid>

          <Grid Margin="0,7,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
              <TextBlock x:Name="PrevBtn" Text="&#x23EE;" Foreground="#FFE8E8EC" FontSize="15"
                         FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="2,0,12,0" VerticalAlignment="Center" ToolTip="Onceki"/>
              <Border x:Name="PlayWrap" Width="34" Height="34" CornerRadius="17" Cursor="Hand" ToolTip="Oynat/Duraklat">
                <Border.Background>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#FFFF5C5C" Offset="0"/><GradientStop Color="#FFFF8A5C" Offset="1"/>
                  </LinearGradientBrush>
                </Border.Background>
                <Border.Effect><DropShadowEffect Color="#FF5C5C" BlurRadius="12" ShadowDepth="0" Opacity="0.55"/></Border.Effect>
                <TextBlock x:Name="PlayBtn" Text="&#x25B6;" Foreground="White" FontSize="13"
                           FontFamily="Segoe UI Symbol" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="2,0,0,0"/>
              </Border>
              <TextBlock x:Name="NextBtn" Text="&#x23ED;" Foreground="#FFE8E8EC" FontSize="15"
                         FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="12,0,0,0" VerticalAlignment="Center" ToolTip="Sonraki"/>
              <TextBlock x:Name="RptBtn" Text="&#x1F501;" Foreground="#FFE8E8EC" FontSize="13" Opacity="0.7"
                         FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="13,0,0,0" VerticalAlignment="Center" ToolTip="Tekrar"/>
            </StackPanel>

            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <Slider x:Name="VolS" Width="58" Style="{StaticResource Slim}" Foreground="#FFFFFFFF"
                      Minimum="0" Maximum="100" Value="50" VerticalAlignment="Center" ToolTip="Ses"/>
              <TextBlock x:Name="MuteBtn" Text="&#x1F50A;" Foreground="#FFB8B8C2" FontSize="13"
                         FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="7,0,0,0" VerticalAlignment="Center" ToolTip="Sessiz"/>
            </StackPanel>
          </Grid>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ============ AYARLAR PANELI ============ -->
    <Border x:Name="Settings" Margin="14" CornerRadius="16" Width="264" Visibility="Collapsed" Background="#FF14141B">
      <Border.BorderBrush><SolidColorBrush Color="#33FFFFFF"/></Border.BorderBrush>
      <Border.BorderThickness>1</Border.BorderThickness>
      <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="22" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
      <StackPanel Margin="16,13,16,15">
        <Grid>
          <TextBlock Text="Ayarlar" Foreground="#FFF2F2F6" FontSize="13" FontWeight="SemiBold" FontFamily="Segoe UI"/>
          <TextBlock x:Name="SetClose" Text="&#x2715;" HorizontalAlignment="Right" Foreground="#FF9A9AA6"
                     FontSize="12" FontFamily="Segoe UI" Cursor="Hand"/>
        </Grid>

        <TextBlock Text="VURGU RENGI" Foreground="#FF8A8A94" FontSize="9" FontWeight="Bold"
                   FontFamily="Segoe UI" Margin="0,14,0,9"/>
        <StackPanel Orientation="Horizontal">
          <Border x:Name="SwA" Width="32" Height="32" CornerRadius="16" Margin="0,0,11,0" Cursor="Hand" BorderThickness="0" BorderBrush="White">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FFFF5C5C" Offset="0"/><GradientStop Color="#FFFF8A5C" Offset="1"/></LinearGradientBrush></Border.Background>
          </Border>
          <Border x:Name="SwB" Width="32" Height="32" CornerRadius="16" Margin="0,0,11,0" Cursor="Hand" BorderThickness="0" BorderBrush="White">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FF4C8DFF" Offset="0"/><GradientStop Color="#FF7BB0FF" Offset="1"/></LinearGradientBrush></Border.Background>
          </Border>
          <Border x:Name="SwC" Width="32" Height="32" CornerRadius="16" Margin="0,0,11,0" Cursor="Hand" BorderThickness="0" BorderBrush="White">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FFB57BFF" Offset="0"/><GradientStop Color="#FFD6A8FF" Offset="1"/></LinearGradientBrush></Border.Background>
          </Border>
          <Border x:Name="SwD" Width="32" Height="32" CornerRadius="16" Margin="0,0,11,0" Cursor="Hand" BorderThickness="0" BorderBrush="White">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FF2FD9A0" Offset="0"/><GradientStop Color="#FF5CE6BC" Offset="1"/></LinearGradientBrush></Border.Background>
          </Border>
          <Border x:Name="SwE" Width="32" Height="32" CornerRadius="16" Cursor="Hand" BorderThickness="0" BorderBrush="White">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FFFF5CA8" Offset="0"/><GradientStop Color="#FFFF8AC4" Offset="1"/></LinearGradientBrush></Border.Background>
          </Border>
        </StackPanel>

        <TextBlock Text="GORUNUM MODU" Foreground="#FF8A8A94" FontSize="9" FontWeight="Bold"
                   FontFamily="Segoe UI" Margin="0,16,0,9"/>
        <StackPanel Orientation="Horizontal">
          <Border x:Name="ModeCard" CornerRadius="8" Height="30" Width="100" Background="#FF2A2A36"
                  BorderBrush="White" BorderThickness="0" Cursor="Hand" Margin="0,0,10,0">
            <TextBlock Text="Kart" Foreground="#FFE8E8EC" FontSize="11" FontFamily="Segoe UI"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <Border x:Name="ModeBar" CornerRadius="8" Height="30" Width="100" Background="#FF2A2A36"
                  BorderBrush="White" BorderThickness="0" Cursor="Hand">
            <TextBlock Text="Kompakt cubuk" Foreground="#FFE8E8EC" FontSize="11" FontFamily="Segoe UI"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
        </StackPanel>

        <TextBlock Text="SAYDAMLIK" Foreground="#FF8A8A94" FontSize="9" FontWeight="Bold"
                   FontFamily="Segoe UI" Margin="0,16,0,6"/>
        <Slider x:Name="OpacityS" Style="{StaticResource Slim}" Foreground="#FFFFFFFF"
                Minimum="40" Maximum="100" Value="97"/>

        <Border x:Name="SetDone" CornerRadius="9" Height="32" Margin="0,18,0,0" Cursor="Hand">
          <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FFFF5C5C" Offset="0"/><GradientStop Color="#FFFF8A5C" Offset="1"/></LinearGradientBrush></Border.Background>
          <TextBlock Text="Bitti" Foreground="White" FontSize="12" FontWeight="SemiBold"
                     FontFamily="Segoe UI" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </StackPanel>
    </Border>

    <!-- ============ KOMPAKT CUBUK ============ -->
    <Border x:Name="Bar" Margin="14" CornerRadius="14" Visibility="Collapsed">
      <Border.Background><SolidColorBrush Color="#FF17171F"/></Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#66FF5C5C" Offset="0"/><GradientStop Color="#22FFFFFF" Offset="1"/></LinearGradientBrush>
      </Border.BorderBrush>
      <Border.BorderThickness>1</Border.BorderThickness>
      <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="20" ShadowDepth="0" Opacity="0.55"/></Border.Effect>
      <Grid>
        <Grid Margin="10,6,10,12">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="118"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Column="0" Width="40" Height="40" CornerRadius="8" Background="#FF2C2C36" VerticalAlignment="Center">
            <Grid>
              <TextBlock x:Name="BarNoArt" Text="&#x266B;" Foreground="#FF55555F" FontSize="16"
                         FontFamily="Segoe UI Symbol" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              <Border CornerRadius="8"><Border.Background><ImageBrush x:Name="BarArtBrush" Stretch="UniformToFill"/></Border.Background></Border>
            </Grid>
          </Border>

          <StackPanel Grid.Column="1" Margin="10,0,8,0" VerticalAlignment="Center">
            <TextBlock x:Name="BarTitle" Text="Muzik calmiyor" Foreground="#FFF6F6FA" FontSize="12"
                       FontWeight="SemiBold" FontFamily="Segoe UI" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="BarArtist" Text="Bir sarki baslat" Foreground="#FFA8A8B2" FontSize="10"
                       FontFamily="Segoe UI" TextTrimming="CharacterEllipsis" Margin="0,1,0,0"/>
          </StackPanel>

          <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,10,0">
            <TextBlock x:Name="BarPrev" Text="&#x23EE;" Foreground="#FFE8E8EC" FontSize="14"
                       FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="0,0,11,0" VerticalAlignment="Center" ToolTip="Onceki"/>
            <Border x:Name="BarPlayWrap" Width="30" Height="30" CornerRadius="15" Cursor="Hand" ToolTip="Oynat/Duraklat">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FFFF5C5C" Offset="0"/><GradientStop Color="#FFFF8A5C" Offset="1"/></LinearGradientBrush>
              </Border.Background>
              <Border.Effect><DropShadowEffect Color="#FF5C5C" BlurRadius="10" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
              <TextBlock x:Name="BarPlay" Text="&#x25B6;" Foreground="White" FontSize="12"
                         FontFamily="Segoe UI Symbol" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="2,0,0,0"/>
            </Border>
            <TextBlock x:Name="BarNext" Text="&#x23ED;" Foreground="#FFE8E8EC" FontSize="14"
                       FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="11,0,0,0" VerticalAlignment="Center" ToolTip="Sonraki"/>
          </StackPanel>

          <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,10,0">
            <TextBlock x:Name="BarMute" Text="&#x1F50A;" Foreground="#FFB8B8C2" FontSize="13"
                       FontFamily="Segoe UI Symbol" Cursor="Hand" VerticalAlignment="Center" ToolTip="Ses (uzerine gel) - sessiz (tikla)"/>
            <Popup x:Name="VolPop" PlacementTarget="{Binding ElementName=BarMute}" Placement="Top"
                   StaysOpen="True" AllowsTransparency="True" PopupAnimation="Fade" HorizontalOffset="-58" VerticalOffset="-2">
              <Border x:Name="VolPopBorder" Background="#FF20202A" CornerRadius="10" Padding="13,9" BorderBrush="#33FFFFFF" BorderThickness="1" Margin="8">
                <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="18" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
                <Slider x:Name="BarVolS" Width="104" Style="{StaticResource Slim}" Foreground="#FFFFFFFF"
                        Minimum="0" Maximum="100" Value="50" VerticalAlignment="Center"/>
              </Border>
            </Popup>
          </StackPanel>

          <StackPanel Grid.Column="4" Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock x:Name="BarGear" Text="&#x2699;" Foreground="#FF9A9AA6" FontSize="12"
                       FontFamily="Segoe UI Symbol" Cursor="Hand" Margin="0,0,10,0" VerticalAlignment="Center" ToolTip="Ayarlar"/>
            <TextBlock x:Name="BarClose" Text="&#x2715;" Foreground="#FF9A9AA6" FontSize="11"
                       FontFamily="Segoe UI" Cursor="Hand" VerticalAlignment="Center" ToolTip="Kapat"/>
          </StackPanel>
        </Grid>

        <Slider x:Name="BarProg" Style="{StaticResource Slim}" Foreground="#FFFF6B6B" VerticalAlignment="Bottom"
                Margin="10,0,10,2" Minimum="0" Maximum="100" Value="0" ToolTip="Ilerleme"/>
      </Grid>
    </Border>

    <!-- ============ KUCULTULMUS: YUVARLAK KAPAK ============ -->
    <Border x:Name="Mini" Margin="14" Width="64" Height="64" CornerRadius="32" Visibility="Collapsed" Cursor="Hand" ToolTip="Ac">
      <Border.Background><SolidColorBrush Color="#FF1B1B24"/></Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#AAFF5C5C" Offset="0"/><GradientStop Color="#44FFFFFF" Offset="1"/></LinearGradientBrush>
      </Border.BorderBrush>
      <Border.BorderThickness>1.5</Border.BorderThickness>
      <Border.Effect><DropShadowEffect Color="#FF5C5C" BlurRadius="20" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
      <Grid>
        <TextBlock x:Name="MiniNote" Text="&#x266B;" Foreground="#FF77777F" FontSize="22"
                   FontFamily="Segoe UI Symbol" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        <Border CornerRadius="32"><Border.Background><ImageBrush x:Name="MiniArt" Stretch="UniformToFill"/></Border.Background></Border>
      </Grid>
    </Border>

  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$ctrl = @{}
foreach ($n in 'Full','Mini','MiniArt','MiniNote','CardHost','BgArt','TopNote','AppName','GearBtn','MinBtn','CloseBtn',
               'ArtBrush','NoArt','TrackTitle','TrackArtist','CurT','Prog','TotT',
               'PrevBtn','PlayWrap','PlayBtn','NextBtn','RptBtn','VolS','MuteBtn',
               'Settings','SetClose','SetDone','SwA','SwB','SwC','SwD','SwE','ModeCard','ModeBar','OpacityS',
               'Bar','BarNoArt','BarArtBrush','BarTitle','BarArtist','BarPrev','BarPlayWrap','BarPlay','BarNext','BarVolS','BarMute','BarGear','BarClose','VolPop','VolPopBorder','BarProg') {
  $ctrl[$n] = $win.FindName($n)
}

# ---- renk yardimcilari + tema ----
function CClr($hex) { [System.Windows.Media.ColorConverter]::ConvertFromString($hex) }
function CBrush($hex) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }
function CGrad($h1, $h2) {
  $g = New-Object System.Windows.Media.LinearGradientBrush
  $g.StartPoint = New-Object System.Windows.Point(0,0); $g.EndPoint = New-Object System.Windows.Point(1,1)
  $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop((CClr $h1), 0)))
  $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop((CClr $h2), 1)))
  return $g
}

$script:presets = @{
  SwA = @('FF5C5C','FF8A5C'); SwB = @('4C8DFF','7BB0FF'); SwC = @('B57BFF','D6A8FF')
  SwD = @('2FD9A0','5CE6BC'); SwE = @('FF5CA8','FF8AC4')
}

function Apply-Accent {
  $m = $script:accent; $l = $script:accentLight
  $ctrl.PlayWrap.Background    = CGrad ("#FF"+$m) ("#FF"+$l)
  $ctrl.PlayWrap.Effect.Color  = CClr ("#FF"+$m)
  $ctrl.Prog.Foreground        = CBrush ("#FF"+$m)
  $ctrl.Full.BorderBrush       = CGrad ("#66"+$m) "#22FFFFFF"
  $ctrl.Mini.BorderBrush       = CGrad ("#AA"+$m) "#44FFFFFF"
  $ctrl.Mini.Effect.Color      = CClr ("#FF"+$m)
  $ctrl.TopNote.Foreground     = CBrush ("#FF"+$m)
  $ctrl.SetDone.Background      = CGrad ("#FF"+$m) ("#FF"+$l)
  $ctrl.Bar.BorderBrush        = CGrad ("#66"+$m) "#22FFFFFF"
  $ctrl.BarPlayWrap.Background  = CGrad ("#FF"+$m) ("#FF"+$l)
  $ctrl.BarPlayWrap.Effect.Color = CClr ("#FF"+$m)
  $ctrl.BarProg.Foreground       = CBrush ("#FF"+$m)
  # secili swatch'i isaretle
  foreach ($k in 'SwA','SwB','SwC','SwD','SwE') {
    $ctrl[$k].BorderThickness = if ($script:presets[$k][0] -eq $m) { '2.5' } else { '0' }
  }
}
function Show-Settings {
  $ctrl.Full.Visibility='Collapsed'; $ctrl.Bar.Visibility='Collapsed'; $ctrl.Mini.Visibility='Collapsed'
  $ctrl.Settings.Visibility='Visible'; $win.UpdateLayout()
  $wa = [System.Windows.SystemParameters]::WorkArea
  if ($win.Left + $win.ActualWidth -gt $wa.Right)  { $win.Left = $wa.Right - $win.ActualWidth - 4 }
  if ($win.Top + $win.ActualHeight -gt $wa.Bottom) { $win.Top  = $wa.Bottom - $win.ActualHeight - 4 }
  if ($win.Left -lt $wa.Left) { $win.Left = $wa.Left + 4 }
  if ($win.Top  -lt $wa.Top)  { $win.Top  = $wa.Top + 4 }
}
function Hide-Settings { $ctrl.Settings.Visibility='Collapsed'; Set-Mode $script:mode }
function Set-Mode($m) {
  $script:mode = $m
  $ctrl.Settings.Visibility='Collapsed'
  if ($m -eq 'bar') {
    $ctrl.Full.Visibility='Collapsed'; $ctrl.Mini.Visibility='Collapsed'; $ctrl.Bar.Visibility='Visible'
    $win.UpdateLayout()
    if ($null -ne $script:barLeft) { $win.Left = $script:barLeft; $win.Top = $script:barTop }
    else { $wa = [System.Windows.SystemParameters]::WorkArea; $win.Left = $wa.Left + ($wa.Width - $win.ActualWidth)/2; $win.Top = $wa.Bottom - $win.ActualHeight - 2 }
  } else {
    $ctrl.Bar.Visibility='Collapsed'; $ctrl.Mini.Visibility='Collapsed'; $ctrl.Full.Visibility='Visible'
    $win.UpdateLayout()
    if ($null -ne $script:cardLeft) { $win.Left = $script:cardLeft; $win.Top = $script:cardTop }
    else { $win.Left = 40; $win.Top = 180 }
  }
  Clamp-OnScreen
  Save-Settings
  $ctrl.ModeCard.BorderThickness = if ($m -eq 'card') { '2' } else { '0' }
  $ctrl.ModeBar.BorderThickness  = if ($m -eq 'bar')  { '2' } else { '0' }
}
function Save-Settings {
  try { @{ accent=$script:accent; accentLight=$script:accentLight; mode=$script:mode; opacity=$script:opacity
           cardLeft=$script:cardLeft; cardTop=$script:cardTop; barLeft=$script:barLeft; barTop=$script:barTop } | ConvertTo-Json | Set-Content $settingsPath -Encoding utf8 } catch {}
}
function Clamp-OnScreen {
  # tum monitorleri kapsayan sanal ekran (2. ekran konumu korunsun)
  $vl = [System.Windows.SystemParameters]::VirtualScreenLeft
  $vt = [System.Windows.SystemParameters]::VirtualScreenTop
  $vw = [System.Windows.SystemParameters]::VirtualScreenWidth
  $vh = [System.Windows.SystemParameters]::VirtualScreenHeight
  if ($win.Left + $win.ActualWidth  -gt $vl + $vw) { $win.Left = $vl + $vw - $win.ActualWidth  - 2 }
  if ($win.Top  + $win.ActualHeight -gt $vt + $vh) { $win.Top  = $vt + $vh - $win.ActualHeight - 2 }
  if ($win.Left -lt $vl) { $win.Left = $vl + 2 }
  if ($win.Top  -lt $vt) { $win.Top  = $vt + 2 }
}
function Save-Pos {
  if ($script:mode -eq 'bar') { $script:barLeft = $win.Left; $script:barTop = $win.Top }
  else { $script:cardLeft = $win.Left; $script:cardTop = $win.Top }
  Save-Settings
}
function Set-Accent($key) {
  $p = $script:presets[$key]
  $script:accent = $p[0]; $script:accentLight = $p[1]
  Apply-Accent; Save-Settings
}

$ctrl.CardHost.Add_SizeChanged({
  $w = $ctrl.CardHost.ActualWidth; $h = $ctrl.CardHost.ActualHeight
  $ctrl.BgArt.Width = $w; $ctrl.BgArt.Height = $h
  $r = New-Object System.Windows.Rect(0, 0, $w, $h)
  $ctrl.CardHost.Clip = New-Object System.Windows.Media.RectangleGeometry($r, 16, 16)
})

$script:lastTitle = $null
$script:scrub = $false
$script:volSync = $false
$script:artReloads = 0

function Get-Session { try { return $script:mgr.GetCurrentSession() } catch { return $null } }
function Fmt-Time([double]$sec) { if ($sec -lt 0){$sec=0}; ("{0}:{1:00}" -f [int][math]::Floor($sec/60), [int][math]::Floor($sec%60)) }

function Load-Thumbnail($props) {
  try {
    if (-not $props.Thumbnail) { $ctrl.ArtBrush.ImageSource=$null; $ctrl.MiniArt.ImageSource=$null; $ctrl.BarArtBrush.ImageSource=$null; $ctrl.BgArt.Source=$null; $ctrl.NoArt.Visibility='Visible'; $ctrl.BarNoArt.Visibility='Visible'; return }
    $ras = Await ($props.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
    if (-not $ras) { return }
    $net = $script:asStreamM.Invoke($null, @($ras))
    $ms = New-Object System.IO.MemoryStream; $net.CopyTo($ms)
    if ($ms.Length -lt 50) { $ms.Dispose(); return }
    $ms.Position = 0
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit(); $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bmp.StreamSource = $ms; $bmp.EndInit(); $bmp.Freeze()
    $ctrl.ArtBrush.ImageSource = $bmp; $ctrl.MiniArt.ImageSource = $bmp; $ctrl.BarArtBrush.ImageSource = $bmp; $ctrl.BgArt.Source = $bmp
    $ctrl.NoArt.Visibility = 'Collapsed'; $ctrl.BarNoArt.Visibility = 'Collapsed'
    $ms.Dispose()
  } catch { }
}

function Update-Media {
  $s = Get-Session
  if (-not $s) {
    $ctrl.TrackTitle.Text="Muzik calmiyor"; $ctrl.TrackArtist.Text="Bir sarki baslat"; $ctrl.AppName.Text="MUZIK"
    $ctrl.BarTitle.Text="Muzik calmiyor"; $ctrl.BarArtist.Text="Bir sarki baslat"
    $ctrl.PlayBtn.Text=[string][char]0x25B6; $ctrl.BarPlay.Text=[string][char]0x25B6
    $ctrl.ArtBrush.ImageSource=$null; $ctrl.MiniArt.ImageSource=$null; $ctrl.BarArtBrush.ImageSource=$null; $ctrl.BgArt.Source=$null
    $ctrl.NoArt.Visibility='Visible'; $ctrl.BarNoArt.Visibility='Visible'
    $ctrl.CurT.Text="0:00"; $ctrl.TotT.Text="0:00"; if (-not $script:scrub) { $ctrl.Prog.Value=0; $ctrl.BarProg.Value=0 }
    $script:lastTitle=$null; return
  }
  try {
    $pb = $s.GetPlaybackInfo()
    $playing = ("$($pb.PlaybackStatus)" -eq 'Playing')
    if ($playing) { $ctrl.PlayBtn.Text=[string][char]0x23F8; $ctrl.PlayBtn.Margin='0,0,0,0'; $ctrl.BarPlay.Text=[string][char]0x23F8; $ctrl.BarPlay.Margin='0,0,0,0' }
    else          { $ctrl.PlayBtn.Text=[string][char]0x25B6; $ctrl.PlayBtn.Margin='2,0,0,0'; $ctrl.BarPlay.Text=[string][char]0x25B6; $ctrl.BarPlay.Margin='2,0,0,0' }

    if ($pb.Controls.IsRepeatEnabled) {
      $mode = "$($pb.AutoRepeatMode)"
      if ($mode -eq 'Track' -or $mode -eq 'List') { $ctrl.RptBtn.Opacity=1.0; $ctrl.RptBtn.Foreground = CBrush ("#FF"+$script:accent) }
      else { $ctrl.RptBtn.Opacity=1.0; $ctrl.RptBtn.Foreground = CBrush '#FFE8E8EC' }
    } else { $ctrl.RptBtn.Opacity=0.7; $ctrl.RptBtn.Foreground = CBrush '#FFE8E8EC' }

    $tl = $s.GetTimelineProperties()
    $endSec = $tl.EndTime.TotalSeconds
    if ($endSec -gt 0) {
      $posSec = $tl.Position.TotalSeconds
      if ($playing) { $el = ([datetimeoffset]::Now - $tl.LastUpdatedTime).TotalSeconds; if ($el -gt 0 -and $el -lt 3600) { $posSec += $el } }
      if ($posSec -gt $endSec) { $posSec = $endSec }
      $ctrl.TotT.Text = Fmt-Time $endSec
      if (-not $script:scrub) {
        $ctrl.Prog.Maximum = $endSec; $ctrl.Prog.Value = $posSec; $ctrl.CurT.Text = Fmt-Time $posSec
        $ctrl.BarProg.Maximum = $endSec; $ctrl.BarProg.Value = $posSec
      }
    } else { $ctrl.CurT.Text="0:00"; $ctrl.TotT.Text="0:00"; if (-not $script:scrub) { $ctrl.Prog.Value=0; $ctrl.BarProg.Value=0 } }

    $props = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    if (-not $props) { return }
    $title = if ($props.Title) { $props.Title } else { "Bilinmeyen parca" }
    $artist = if ($props.Artist) { $props.Artist } else { "" }
    $ctrl.TrackTitle.Text = $title; $ctrl.TrackArtist.Text = $artist
    $ctrl.BarTitle.Text = $title; $ctrl.BarArtist.Text = $artist
    $app = "$($s.SourceAppUserModelId)"
    $ctrl.AppName.Text = if ($app -match 'chrome|msedge|firefox|opera|brave') { "YOUTUBE MUSIC" } elseif ($app -match 'spotify') { "SPOTIFY" } else { "MUZIK" }
    # baslik kapaktan once degisebilir; degisince birkac poll boyunca kapagi yeniden cek
    if ($title -ne $script:lastTitle) { $script:lastTitle = $title; $script:artReloads = 4 }
    if ($script:artReloads -gt 0) { Load-Thumbnail $props; $script:artReloads-- }
  } catch { }
}

function Sync-Volume {
  try {
    if ($ctrl.VolS.IsMouseCaptureWithin -or $ctrl.BarVolS.IsMouseCaptureWithin) { return }
    $v = [math]::Round([AudioCtl]::GetVolume()*100)
    $script:volSync = $true; $ctrl.VolS.Value = $v; $ctrl.BarVolS.Value = $v; $script:volSync = $false
    $muted = [AudioCtl]::GetMute()
    $micon = if ($muted) { [string][char]0xD83D + [string][char]0xDD07 } else { [string][char]0xD83D + [string][char]0xDD0A }
    $ctrl.MuteBtn.Text = $micon; $ctrl.BarMute.Text = $micon
    $op = if ($muted) { 0.4 } else { 1.0 }
    $ctrl.VolS.Opacity = $op; $ctrl.BarVolS.Opacity = $op
  } catch { }
}

# ---- aksiyonlar ----
$ctrl.PlayWrap.Add_MouseLeftButtonUp({ $s=Get-Session; if ($s) { $null=$s.TryTogglePlayPauseAsync() }; $args[1].Handled=$true })
$ctrl.PrevBtn.Add_MouseLeftButtonUp({ $s=Get-Session; if ($s) { $null=$s.TrySkipPreviousAsync() }; $args[1].Handled=$true })
$ctrl.NextBtn.Add_MouseLeftButtonUp({ $s=Get-Session; if ($s) { $null=$s.TrySkipNextAsync() }; $args[1].Handled=$true })
$ctrl.CloseBtn.Add_MouseLeftButtonUp({ $win.Close() })
$ctrl.MinBtn.Add_MouseLeftButtonUp({ $ctrl.Full.Visibility='Collapsed'; $ctrl.Settings.Visibility='Collapsed'; $ctrl.Mini.Visibility='Visible'; $args[1].Handled=$true })
$ctrl.GearBtn.Add_MouseLeftButtonUp({ Show-Settings; $args[1].Handled=$true })
$ctrl.SetClose.Add_MouseLeftButtonUp({ Hide-Settings; $args[1].Handled=$true })
$ctrl.SetDone.Add_MouseLeftButtonUp({ Hide-Settings; $args[1].Handled=$true })
$ctrl.OpacityS.Add_ValueChanged({ $script:opacity = [math]::Round($ctrl.OpacityS.Value/100.0, 2); $win.Opacity = $script:opacity; Save-Settings })
$ctrl.BarGear.Add_MouseLeftButtonUp({ Show-Settings; $args[1].Handled=$true })
$ctrl.SwA.Add_MouseLeftButtonUp({ Set-Accent 'SwA'; $args[1].Handled=$true })
$ctrl.SwB.Add_MouseLeftButtonUp({ Set-Accent 'SwB'; $args[1].Handled=$true })
$ctrl.SwC.Add_MouseLeftButtonUp({ Set-Accent 'SwC'; $args[1].Handled=$true })
$ctrl.SwD.Add_MouseLeftButtonUp({ Set-Accent 'SwD'; $args[1].Handled=$true })
$ctrl.SwE.Add_MouseLeftButtonUp({ Set-Accent 'SwE'; $args[1].Handled=$true })
$ctrl.ModeCard.Add_MouseLeftButtonUp({ Set-Mode 'card'; $args[1].Handled=$true })
$ctrl.ModeBar.Add_MouseLeftButtonUp({ Set-Mode 'bar'; $args[1].Handled=$true })

# cubuk butonlari
$ctrl.BarPlayWrap.Add_MouseLeftButtonUp({ $s=Get-Session; if ($s) { $null=$s.TryTogglePlayPauseAsync() }; $args[1].Handled=$true })
$ctrl.BarPrev.Add_MouseLeftButtonUp({ $s=Get-Session; if ($s) { $null=$s.TrySkipPreviousAsync() }; $args[1].Handled=$true })
$ctrl.BarNext.Add_MouseLeftButtonUp({ $s=Get-Session; if ($s) { $null=$s.TrySkipNextAsync() }; $args[1].Handled=$true })
$ctrl.BarClose.Add_MouseLeftButtonUp({ $win.Close() })
$ctrl.BarVolS.Add_ValueChanged({ if (-not $script:volSync) { try { [AudioCtl]::SetVolume([float]($ctrl.BarVolS.Value/100.0)) } catch {} } })
$ctrl.BarMute.Add_MouseLeftButtonUp({ try { [AudioCtl]::SetMute(-not [AudioCtl]::GetMute()); Sync-Volume } catch {}; $args[1].Handled=$true })

# cubukta ses: hoparlor uzerine gelince slider popup'i ac, ayrilinca kapat
$ctrl.BarMute.Add_MouseEnter({ $ctrl.VolPop.IsOpen = $true; $volPopTimer.Start() })
$volPopTimer = New-Object System.Windows.Threading.DispatcherTimer
$volPopTimer.Interval = [TimeSpan]::FromMilliseconds(350)
$volPopTimer.Add_Tick({
  if (-not ($ctrl.BarMute.IsMouseOver -or $ctrl.VolPopBorder.IsMouseOver)) { $ctrl.VolPop.IsOpen = $false; $volPopTimer.Stop() }
})

# cubuk ilerleme cubugu (seek)
$ctrl.BarProg.Add_PreviewMouseLeftButtonDown({ $script:scrub = $true })
$ctrl.BarProg.Add_PreviewMouseLeftButtonUp({
  $val = $ctrl.BarProg.Value
  $s = Get-Session; if ($s) { try { $null = $s.TryChangePlaybackPositionAsync(([timespan]::FromSeconds($val)).Ticks) } catch {} }
  $script:scrub = $false
})
$ctrl.BarProg.Add_LostMouseCapture({ $script:scrub = $false })

$ctrl.RptBtn.Add_MouseLeftButtonUp({
  $s = Get-Session
  if ($s) { try { $pb=$s.GetPlaybackInfo(); if ($pb.Controls.IsRepeatEnabled) {
    $next = switch ("$($pb.AutoRepeatMode)") { 'None'{[Windows.Media.MediaPlaybackAutoRepeatMode]::List} 'List'{[Windows.Media.MediaPlaybackAutoRepeatMode]::Track} default{[Windows.Media.MediaPlaybackAutoRepeatMode]::None} }
    $null=$s.TryChangeAutoRepeatModeAsync($next) } } catch {} }
  $args[1].Handled=$true
})

$ctrl.Prog.Add_PreviewMouseLeftButtonDown({ $script:scrub=$true })
$ctrl.Prog.Add_PreviewMouseLeftButtonUp({
  $val = $ctrl.Prog.Value; $ctrl.CurT.Text = Fmt-Time $val
  $s = Get-Session; if ($s) { try { $null=$s.TryChangePlaybackPositionAsync(([timespan]::FromSeconds($val)).Ticks) } catch {} }
  $script:scrub=$false
})
$ctrl.Prog.Add_ValueChanged({ if ($script:scrub) { $ctrl.CurT.Text = Fmt-Time $ctrl.Prog.Value } })
$ctrl.Prog.Add_LostMouseCapture({ $script:scrub=$false })

$ctrl.VolS.Add_ValueChanged({ if (-not $script:volSync) { try { [AudioCtl]::SetVolume([float]($ctrl.VolS.Value/100.0)) } catch {} } })
$ctrl.MuteBtn.Add_MouseLeftButtonUp({ try { [AudioCtl]::SetMute(-not [AudioCtl]::GetMute()); Sync-Volume } catch {}; $args[1].Handled=$true })

# ---- surukleme ----
$script:drag=$false; $script:dragMoved=$false; $script:dpi=1.0
$btns = @($ctrl.PrevBtn,$ctrl.PlayBtn,$ctrl.PlayWrap,$ctrl.NextBtn,$ctrl.RptBtn,$ctrl.MuteBtn,$ctrl.CloseBtn,$ctrl.MinBtn,$ctrl.GearBtn,
          $ctrl.SetClose,$ctrl.SetDone,$ctrl.SwA,$ctrl.SwB,$ctrl.SwC,$ctrl.SwD,$ctrl.SwE,$ctrl.ModeCard,$ctrl.ModeBar,
          $ctrl.BarPrev,$ctrl.BarPlay,$ctrl.BarPlayWrap,$ctrl.BarNext,$ctrl.BarMute,$ctrl.BarGear,$ctrl.BarClose)
function Test-Interactive($src) {
  $cur = $src
  for ($i=0; $i -lt 14 -and $cur; $i++) {
    if ($cur -is [System.Windows.Controls.Slider]) { return $true }
    foreach ($b in $btns) { if ($cur -eq $b) { return $true } }
    if ($cur -is [System.Windows.Media.Visual]) { $cur = [System.Windows.Media.VisualTreeHelper]::GetParent($cur) } else { break }
  }
  return $false
}
$win.Add_PreviewMouseLeftButtonDown({
  if (Test-Interactive $args[1].OriginalSource) { return }
  $pt = New-Object WinInput+POINT; [void][WinInput]::GetCursorPos([ref]$pt)
  $script:dragStartX=$pt.X; $script:dragStartY=$pt.Y; $script:winStartLeft=$win.Left; $script:winStartTop=$win.Top
  $script:dragMoved=$false; $script:drag=$true
  $ps=[System.Windows.PresentationSource]::FromVisual($win); if ($ps) { $script:dpi=$ps.CompositionTarget.TransformToDevice.M11 } else { $script:dpi=1.0 }
  [void]$win.CaptureMouse()
})
$win.Add_MouseMove({
  if (-not $script:drag) { return }
  if ($args[1].LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
  $pt = New-Object WinInput+POINT; [void][WinInput]::GetCursorPos([ref]$pt)
  $ddx=$pt.X-$script:dragStartX; $ddy=$pt.Y-$script:dragStartY
  if ([math]::Abs($ddx) -gt 3 -or [math]::Abs($ddy) -gt 3) { $script:dragMoved=$true }
  $nl=$script:winStartLeft+($ddx/$script:dpi); $nt=$script:winStartTop+($ddy/$script:dpi)
  $vsL=[System.Windows.SystemParameters]::VirtualScreenLeft; $vsT=[System.Windows.SystemParameters]::VirtualScreenTop
  $vsW=[System.Windows.SystemParameters]::VirtualScreenWidth; $vsH=[System.Windows.SystemParameters]::VirtualScreenHeight
  $nl=[math]::Max($vsL,[math]::Min($nl,$vsL+$vsW-$win.ActualWidth)); $nt=[math]::Max($vsT,[math]::Min($nt,$vsT+$vsH-$win.ActualHeight))
  $win.Left=$nl; $win.Top=$nt
})
$win.Add_MouseLeftButtonUp({
  if (-not $script:drag) { return }
  $script:drag=$false; $win.ReleaseMouseCapture()
  if ($ctrl.Mini.Visibility -eq 'Visible' -and -not $script:dragMoved) { $ctrl.Mini.Visibility='Collapsed'; $ctrl.Full.Visibility='Visible' }
  elseif ($script:dragMoved) { Save-Pos }
})

$showTimer = New-Object System.Windows.Threading.DispatcherTimer
$showTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$showTimer.Add_Tick({ if ($script:showEvent -and $script:showEvent.WaitOne(0)) { $win.Topmost=$false; $win.Topmost=$true; [void]$win.Activate() } })
$showTimer.Start()

$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromSeconds(1)
$pollTimer.Add_Tick({ Update-Media; Sync-Volume })
$pollTimer.Start()

$win.Add_Loaded({
  try {
    $win.Opacity = $script:opacity; $ctrl.OpacityS.Value = $script:opacity * 100
    Apply-Accent; Update-Media; Sync-Volume; Set-Mode $script:mode
  } catch {}
})

[void]$win.ShowDialog()
