using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using YTMusicWidget.ViewModels;

namespace YTMusicWidget.Views;

public partial class MainWindow : Window
{
    private enum ViewState { Card, Settings, Mini }

    private readonly PlayerViewModel _vm;
    private ViewState _view = ViewState.Card;

    public MainWindow(PlayerViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DataContext = vm;

        var (left, top) = vm.InitialPosition();
        if (left.HasValue && top.HasValue) { Left = left.Value; Top = top.Value; }
        Opacity = vm.InitialOpacity;
        OpacitySlider.Value = vm.InitialOpacity * 100;

        Loaded += async (_, _) =>
        {
            await _vm.StartAsync();
            ClampOnScreen();
        };
    }

    // ---- gorunum gecisleri ----
    private void SetView(ViewState v)
    {
        _view = v;
        Card.Visibility = v == ViewState.Card ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = v == ViewState.Settings ? Visibility.Visible : Visibility.Collapsed;
        MiniOrb.Visibility = v == ViewState.Mini ? Visibility.Visible : Visibility.Collapsed;
        UpdateLayout();
        ClampOnScreen();
    }

    private void Gear_Click(object sender, RoutedEventArgs e) => SetView(ViewState.Settings);
    private void Min_Click(object sender, RoutedEventArgs e) => SetView(ViewState.Mini);
    private void SettingsClose_Click(object sender, RoutedEventArgs e) => SetView(ViewState.Card);
    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void Swatch_Down(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag)
        {
            var parts = tag.Split('|');
            if (parts.Length == 2) _vm.ApplyAccent(parts[0], parts[1]);
        }
        e.Handled = true;   // pencere suruklemesini tetikleme
    }

    private void Opacity_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_vm == null) return;   // XAML yuklenirken erken tetiklenmesin
        double op = e.NewValue / 100.0;
        Opacity = op;
        _vm.SetOpacity(op);
    }

    // ---- seek ----
    private void Seek_Down(object sender, MouseButtonEventArgs e) => _vm.UserScrubbing = true;
    private void Seek_Up(object sender, MouseButtonEventArgs e)
    {
        _vm.Seek(SeekSlider.Value);
        _vm.UserScrubbing = false;
    }
    private void Seek_Lost(object sender, MouseEventArgs e) => _vm.UserScrubbing = false;

    // ---- surukleme (bos alan) + orb'da tikla=ac, surukle=tasi ----
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.ButtonState != MouseButtonState.Pressed) return;

        GetCursorPos(out POINT p0);
        try { DragMove(); } catch { /* yok say */ }
        GetCursorPos(out POINT p1);

        bool moved = Math.Abs(p1.X - p0.X) > 3 || Math.Abs(p1.Y - p0.Y) > 3;
        if (moved)
        {
            _vm.SavePosition(Left, Top);
        }
        else if (_view == ViewState.Mini)
        {
            SetView(ViewState.Card);   // orb'a tiklayinca karti ac
        }
    }

    private void ClampOnScreen()
    {
        double vl = SystemParameters.VirtualScreenLeft, vt = SystemParameters.VirtualScreenTop;
        double vw = SystemParameters.VirtualScreenWidth, vh = SystemParameters.VirtualScreenHeight;
        if (Left + ActualWidth > vl + vw) Left = vl + vw - ActualWidth - 2;
        if (Top + ActualHeight > vt + vh) Top = vt + vh - ActualHeight - 2;
        if (Left < vl) Left = vl + 2;
        if (Top < vt) Top = vt + 2;
    }
}
