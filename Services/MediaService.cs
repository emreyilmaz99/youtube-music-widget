using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Windows.Media.Control;

namespace YTMusicWidget.Services;

/// <summary>
/// Windows SMTC (System Media Transport Controls) uzerinden calan medyayi okur
/// ve oynatma kontrollerini gonderir. YouTube Music (tarayici), Spotify vb. ile calisir.
/// </summary>
public class MediaService
{
    private GlobalSystemMediaTransportControlsSessionManager? _manager;

    public async Task InitializeAsync()
    {
        try { _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync(); }
        catch { _manager = null; }
    }

    public GlobalSystemMediaTransportControlsSession? Current => _manager?.GetCurrentSession();

    public async Task TogglePlayPauseAsync()
    {
        try { var s = Current; if (s != null) await s.TryTogglePlayPauseAsync(); } catch { }
    }

    public async Task NextAsync()
    {
        try { var s = Current; if (s != null) await s.TrySkipNextAsync(); } catch { }
    }

    public async Task PreviousAsync()
    {
        try { var s = Current; if (s != null) await s.TrySkipPreviousAsync(); } catch { }
    }

    public async Task SeekAsync(long ticks)
    {
        try { var s = Current; if (s != null) await s.TryChangePlaybackPositionAsync(ticks); } catch { }
    }

    /// <summary>Kapak gorselini WinRT stream'inden okuyup donmus bir BitmapImage olarak dondurur.</summary>
    public async Task<ImageSource?> LoadThumbnailAsync(GlobalSystemMediaTransportControlsSessionMediaProperties props)
    {
        try
        {
            if (props.Thumbnail == null) return null;
            using var ras = await props.Thumbnail.OpenReadAsync();
            using var stream = ras.AsStreamForRead();
            var ms = new MemoryStream();
            await stream.CopyToAsync(ms);
            if (ms.Length < 50) return null;
            ms.Position = 0;

            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.StreamSource = ms;
            bmp.EndInit();
            bmp.Freeze();   // UI thread disinda da kullanilabilsin
            return bmp;
        }
        catch { return null; }
    }
}
