using System.Windows;
using System.Windows.Media;

namespace YTMusicWidget.ViewModels;

/// <summary>"RRGGBB" hex'lerinden WPF fircalari uretir.</summary>
public static class ColorUtil
{
    public static Color FromHex(string rrggbb, string alpha = "FF")
        => (Color)ColorConverter.ConvertFromString("#" + alpha + rrggbb);

    public static SolidColorBrush Brush(string rrggbb, string alpha = "FF")
    {
        var b = new SolidColorBrush(FromHex(rrggbb, alpha));
        b.Freeze();
        return b;
    }

    public static LinearGradientBrush Gradient(string fromHex, string toHex)
    {
        var g = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(1, 1)
        };
        g.GradientStops.Add(new GradientStop(FromHex(fromHex), 0));
        g.GradientStops.Add(new GradientStop(FromHex(toHex), 1));
        g.Freeze();
        return g;
    }
}
