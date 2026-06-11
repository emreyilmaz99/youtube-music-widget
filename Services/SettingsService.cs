using System.IO;
using System.Text.Json;
using YTMusicWidget.Models;

namespace YTMusicWidget.Services;

/// <summary>Ayarlari %APPDATA%\YTMusicWidget\settings.json icine okur/yazar.</summary>
public class SettingsService
{
    private readonly string _path;
    private static readonly JsonSerializerOptions Opts = new() { WriteIndented = true };

    public SettingsService()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "YTMusicWidget");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "settings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (File.Exists(_path))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_path)) ?? new AppSettings();
        }
        catch { /* bozuk dosya -> varsayilan */ }
        return new AppSettings();
    }

    public void Save(AppSettings settings)
    {
        try { File.WriteAllText(_path, JsonSerializer.Serialize(settings, Opts)); }
        catch { /* yazilamadi -> sessizce gec */ }
    }
}
