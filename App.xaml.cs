using System.Threading;
using System.Windows;
using YTMusicWidget.Services;
using YTMusicWidget.ViewModels;
using YTMusicWidget.Views;

namespace YTMusicWidget;

public partial class App : Application
{
    private static Mutex? _instanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Tek instance: ikinci kez acilirsa sessizce cik
        _instanceMutex = new Mutex(initiallyOwned: true, @"Local\YTMusicWidgetWpfSingleton", out bool isNew);
        if (!isNew) { Shutdown(); return; }

        // Composition root: servisler -> ayarlar -> ViewModel -> View
        var settingsService = new SettingsService();
        var settings = settingsService.Load();
        var media = new MediaService();
        var audio = new AudioService();
        var vm = new PlayerViewModel(media, audio, settingsService, settings);

        new MainWindow(vm).Show();
    }
}
