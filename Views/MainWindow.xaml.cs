using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using YTMusicWidget.ViewModels;

namespace YTMusicWidget.Views;

public partial class MainWindow : Window
{
    private enum ViewState { Card, Bar, Settings, Mini }

    private readonly PlayerViewModel _vm;
    private ViewState _view = ViewState.Card;
    private string _mode;

    public MainWindow(PlayerViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DataContext = vm;
        _mode = vm.Mode;

        Opacity = vm.InitialOpacity;
        OpacitySlider.Value = vm.InitialOpacity * 100;

        ShowMain();
        UpdateModeHighlight();

        Loaded += async (_, _) =>
        {
            await _vm.StartAsync();
            PositionForMode(_mode);
        };
    }

    // ---- gorunum gecisleri ----
    private void SetView(ViewState v)
    {
        _view = v;
        Card.Visibility = v == ViewState.Card ? Visibility.Visible : Visibility.Collapsed;
        Bar.Visibility = v == ViewState.Bar ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = v == ViewState.Settings ? Visibility.Visible : Visibility.Collapsed;
        MiniOrb.Visibility = v == ViewState.Mini ? Visibility.Visible : Visibility.Collapsed;
        UpdateLayout();
        ClampOnScreen();
    }

    /// <summary>Secili moda gore ana gorunumu (kart/cubuk) goster.</summary>
    private void ShowMain() => SetView(_mode == "bar" ? ViewState.Bar : ViewState.Card);

    private void ApplyMode(string mode)
    {
        _mode = mode;
        _vm.SetMode(mode);
        ShowMain();
        PositionForMode(mode);
        UpdateModeHighlight();
    }

    private void PositionForMode(string mode)
    {
        var (l, t) = _vm.PositionFor(mode);
        if (l.HasValue && t.HasValue) { Left = l.Value; Top = t.Value; }
        else
        {
            UpdateLayout();
            var wa = SystemParameters.WorkArea;
            if (mode == "bar") { Left = wa.Left + (wa.Width - ActualWidth) / 2; Top = wa.Bottom - ActualHeight - 4; }
            else { Left = 40; Top = 180; }
        }
        ClampOnScreen();
    }

    private void UpdateModeHighlight()
    {
        ModeCardBtn.BorderThickness = new Thickness(_mode == "card" ? 2 : 0);
        ModeBarBtn.BorderThickness = new Thickness(_mode == "bar" ? 2 : 0);
    }

    private void Gear_Click(object sender, RoutedEventArgs e) => SetView(ViewState.Settings);
    private void Min_Click(object sender, RoutedEventArgs e) => SetView(ViewState.Mini);
    private void SettingsClose_Click(object sender, RoutedEventArgs e) => ShowMain();
    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void Mode_Down(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string mode) ApplyMode(mode);
        e.Handled = true;
    }

    private void Swatch_Down(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string tag)
        {
            var parts = tag.Split('|');
            if (parts.Length == 2) _vm.ApplyAccent(parts[0], parts[1]);
        }
        e.Handled = true;
    }

    private void Opacity_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_vm == null) return;
        double op = e.NewValue / 100.0;
        Opacity = op;
        _vm.SetOpacity(op);
    }

    // ---- seek (kart + cubuk ayni handler'lari paylasir) ----
    private void Seek_Down(object sender, MouseButtonEventArgs e) => _vm.UserScrubbing = true;
    private void Seek_Up(object sender, MouseButtonEventArgs e)
    {
        if (sender is Slider s) _vm.Seek(s.Value);
        _vm.UserScrubbing = false;
    }
    private void Seek_Lost(object sender, MouseEventArgs e) => _vm.UserScrubbing = false;

    // ---- surukleme + orb'da tikla=ac ----
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.ButtonState != MouseButtonState.Pressed) return;

        GetCursorPos(out POINT p0);
        try { DragMove(); } catch { }
        GetCursorPos(out POINT p1);

        bool moved = Math.Abs(p1.X - p0.X) > 3 || Math.Abs(p1.Y - p0.Y) > 3;
        if (moved) _vm.SavePosition(Left, Top);
        else if (_view == ViewState.Mini) ShowMain();   // orb'a tiklayinca geri ac
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
