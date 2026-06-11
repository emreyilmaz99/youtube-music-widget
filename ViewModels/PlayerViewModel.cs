using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Windows.Media.Control;
using YTMusicWidget.Models;
using YTMusicWidget.Services;

namespace YTMusicWidget.ViewModels;

/// <summary>
/// Calan medyayi periyodik olarak okuyup arayuze bagli ozellikleri gunceller;
/// oynatma kontrollerini ve ses/accent/ayar durumunu yonetir.
/// </summary>
public class PlayerViewModel : ObservableObject
{
    private const string PlayGlyphStr = "▶";   // ▶
    private const string PauseGlyphStr = "⏸";  // ⏸
    private const string SpeakerStr = "🔊"; // 🔊
    private const string MutedStr = "🔇";   // 🔇

    private readonly MediaService _media;
    private readonly AudioService _audio;
    private readonly SettingsService _settingsService;
    private readonly AppSettings _settings;
    private readonly DispatcherTimer _timer;

    private string? _lastTitle;
    private int _artReloads;
    private bool _suppressVol;

    public bool UserScrubbing { get; set; }

    public PlayerViewModel(MediaService media, AudioService audio, SettingsService settingsService, AppSettings settings)
    {
        _media = media;
        _audio = audio;
        _settingsService = settingsService;
        _settings = settings;

        PlayPauseCommand = new RelayCommand(async () => await _media.TogglePlayPauseAsync());
        NextCommand = new RelayCommand(async () => await _media.NextAsync());
        PrevCommand = new RelayCommand(async () => await _media.PreviousAsync());
        MuteCommand = new RelayCommand(() => { _audio.SetMute(!_audio.GetMute()); SyncVolume(); });

        ApplyAccent(_settings.Accent, _settings.AccentLight, persist: false);

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += async (_, _) => await PollAsync();
    }

    public async Task StartAsync()
    {
        await _media.InitializeAsync();
        await PollAsync();
        SyncVolume();
        _timer.Start();
    }

    // ---- Komutlar ----
    public ICommand PlayPauseCommand { get; }
    public ICommand NextCommand { get; }
    public ICommand PrevCommand { get; }
    public ICommand MuteCommand { get; }

    // ---- Parca bilgisi ----
    private string _title = "Muzik calmiyor";
    public string Title { get => _title; private set => SetProperty(ref _title, value); }

    private string _artist = "Bir sarki baslat";
    public string Artist { get => _artist; private set => SetProperty(ref _artist, value); }

    private string _appName = "MUZIK";
    public string AppName { get => _appName; private set => SetProperty(ref _appName, value); }

    private ImageSource? _cover;
    public ImageSource? Cover { get => _cover; private set => SetProperty(ref _cover, value); }

    private bool _isPlaying;
    public bool IsPlaying
    {
        get => _isPlaying;
        private set { if (SetProperty(ref _isPlaying, value)) OnPropertyChanged(nameof(PlayGlyph)); }
    }
    public string PlayGlyph => _isPlaying ? PauseGlyphStr : PlayGlyphStr;

    // ---- Zaman cizelgesi ----
    private double _positionSeconds;
    public double PositionSeconds { get => _positionSeconds; private set => SetProperty(ref _positionSeconds, value); }

    private double _durationSeconds = 1;
    public double DurationSeconds { get => _durationSeconds; private set => SetProperty(ref _durationSeconds, value); }

    private string _positionText = "0:00";
    public string PositionText { get => _positionText; private set => SetProperty(ref _positionText, value); }

    private string _durationText = "0:00";
    public string DurationText { get => _durationText; private set => SetProperty(ref _durationText, value); }

    // ---- Ses ----
    private double _volume = 50;
    public double Volume
    {
        get => _volume;
        set { if (SetProperty(ref _volume, value) && !_suppressVol) _audio.SetVolume((float)(value / 100.0)); }
    }

    private bool _muted;
    public bool Muted
    {
        get => _muted;
        private set { if (SetProperty(ref _muted, value)) OnPropertyChanged(nameof(MuteGlyph)); }
    }
    public string MuteGlyph => _muted ? MutedStr : SpeakerStr;

    // ---- Accent / tema ----
    private SolidColorBrush _accentBrush = ColorUtil.Brush("FF5C5C");
    public SolidColorBrush AccentBrush { get => _accentBrush; private set => SetProperty(ref _accentBrush, value); }

    private Brush _playGradient = ColorUtil.Gradient("FF5C5C", "FF8A5C");
    public Brush PlayGradient { get => _playGradient; private set => SetProperty(ref _playGradient, value); }

    public string Accent => _settings.Accent;

    public void ApplyAccent(string accent, string accentLight, bool persist = true)
    {
        _settings.Accent = accent;
        _settings.AccentLight = accentLight;
        AccentBrush = ColorUtil.Brush(accent);
        PlayGradient = ColorUtil.Gradient(accent, accentLight);
        OnPropertyChanged(nameof(Accent));
        if (persist) _settingsService.Save(_settings);
    }

    // ---- Konum / opaklik (kalici) ----
    public double InitialOpacity => _settings.Opacity;
    public string Mode => _settings.Mode;

    public (double? Left, double? Top) InitialPosition() => PositionFor(_settings.Mode);

    public (double? Left, double? Top) PositionFor(string mode) => mode switch
    {
        "bar" => (_settings.BarLeft, _settings.BarTop),
        "edge" => (_settings.EdgeLeft, _settings.EdgeTop),
        _ => (_settings.CardLeft, _settings.CardTop),
    };

    public void SetMode(string mode)
    {
        _settings.Mode = mode;
        _settingsService.Save(_settings);
        OnPropertyChanged(nameof(Mode));
    }

    public void SavePosition(double left, double top)
    {
        switch (_settings.Mode)
        {
            case "bar": _settings.BarLeft = left; _settings.BarTop = top; break;
            case "edge": _settings.EdgeLeft = left; _settings.EdgeTop = top; break;
            default: _settings.CardLeft = left; _settings.CardTop = top; break;
        }
        _settingsService.Save(_settings);
    }

    public void SetOpacity(double opacity)
    {
        _settings.Opacity = Math.Round(opacity, 2);
        _settingsService.Save(_settings);
    }

    // ---- Seek / ses (View'dan cagirilir) ----
    public void Seek(double seconds)
    {
        _ = _media.SeekAsync(TimeSpan.FromSeconds(seconds).Ticks);
    }

    public void SyncVolume()
    {
        try
        {
            _suppressVol = true;
            Volume = Math.Round(_audio.GetVolume() * 100);
            _suppressVol = false;
            Muted = _audio.GetMute();
        }
        catch { _suppressVol = false; }
    }

    // ---- Poll ----
    private async Task PollAsync()
    {
        var session = _media.Current;
        if (session == null)
        {
            Title = "Muzik calmiyor";
            Artist = "Bir sarki baslat";
            AppName = "MUZIK";
            IsPlaying = false;
            Cover = null;
            DurationSeconds = 1;
            if (!UserScrubbing) { PositionSeconds = 0; PositionText = "0:00"; }
            DurationText = "0:00";
            _lastTitle = null;
            return;
        }

        try
        {
            var pb = session.GetPlaybackInfo();
            IsPlaying = pb.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;

            var tl = session.GetTimelineProperties();
            double end = tl.EndTime.TotalSeconds;
            if (end > 0)
            {
                double pos = tl.Position.TotalSeconds;
                if (IsPlaying)
                {
                    double el = (DateTimeOffset.Now - tl.LastUpdatedTime).TotalSeconds;
                    if (el > 0 && el < 3600) pos += el;
                }
                if (pos > end) pos = end;
                DurationSeconds = end;
                DurationText = Fmt(end);
                if (!UserScrubbing)
                {
                    PositionSeconds = pos;
                    PositionText = Fmt(pos);
                }
            }
            else
            {
                DurationSeconds = 1;
                DurationText = "0:00";
                if (!UserScrubbing) { PositionSeconds = 0; PositionText = "0:00"; }
            }

            var props = await session.TryGetMediaPropertiesAsync();
            if (props != null)
            {
                Title = string.IsNullOrWhiteSpace(props.Title) ? "Bilinmeyen parca" : props.Title;
                Artist = props.Artist ?? "";

                string app = session.SourceAppUserModelId ?? "";
                AppName = app.Contains("chrome", StringComparison.OrdinalIgnoreCase)
                          || app.Contains("msedge", StringComparison.OrdinalIgnoreCase)
                          || app.Contains("firefox", StringComparison.OrdinalIgnoreCase)
                          || app.Contains("opera", StringComparison.OrdinalIgnoreCase)
                          || app.Contains("brave", StringComparison.OrdinalIgnoreCase)
                    ? "YOUTUBE MUSIC"
                    : app.Contains("spotify", StringComparison.OrdinalIgnoreCase) ? "SPOTIFY" : "MUZIK";

                // baslik kapaktan once degisebilir; degisince birkac tur kapagi yeniden cek
                if (Title != _lastTitle) { _lastTitle = Title; _artReloads = 4; }
                if (_artReloads > 0)
                {
                    var img = await _media.LoadThumbnailAsync(props);
                    if (img != null) Cover = img;
                    _artReloads--;
                }
            }
        }
        catch { /* gecici SMTC hatasi -> sonraki tur */ }
    }

    private static string Fmt(double sec)
    {
        if (sec < 0) sec = 0;
        return $"{(int)Math.Floor(sec / 60)}:{(int)Math.Floor(sec % 60):00}";
    }
}
