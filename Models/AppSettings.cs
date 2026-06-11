namespace YTMusicWidget.Models;

/// <summary>Kullaniciya ozel kalici ayarlar (%APPDATA%\YTMusicWidget\settings.json).</summary>
public class AppSettings
{
    public string Accent { get; set; } = "FF5C5C";
    public string AccentLight { get; set; } = "FF8A5C";
    public string Mode { get; set; } = "card";        // card | bar | edge
    public double Opacity { get; set; } = 0.97;

    public double? CardLeft { get; set; }
    public double? CardTop { get; set; }
    public double? BarLeft { get; set; }
    public double? BarTop { get; set; }
    public double? EdgeLeft { get; set; }
    public double? EdgeTop { get; set; }
}
