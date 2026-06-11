using System.Runtime.InteropServices;

namespace YTMusicWidget.Services;

/// <summary>
/// Windows CoreAudio (MMDevice / IAudioEndpointVolume) uzerinden sistem ana ses
/// seviyesini ve sessize-alma durumunu okur/yazar. COM arabirimleri elle bildirilmistir.
/// </summary>
public class AudioService
{
    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out uint count);
        int SetMasterVolumeLevel(float levelDB, ref Guid ctx);
        int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
        int GetMasterVolumeLevel(out float levelDB);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(uint ch, float levelDB, ref Guid ctx);
        int SetChannelVolumeLevelScalar(uint ch, float level, ref Guid ctx);
        int GetChannelVolumeLevel(uint ch, out float levelDB);
        int GetChannelVolumeLevelScalar(uint ch, out float level);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IAudioEndpointVolume endpointVolume);
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        int NotImpl1();
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumeratorComObject { }

    private Guid _ctx = Guid.Empty;

    private IAudioEndpointVolume GetEndpointVolume()
    {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0 /*eRender*/, 1 /*eMultimedia*/, out IMMDevice device));
        var iid = typeof(IAudioEndpointVolume).GUID;
        Marshal.ThrowExceptionForHR(device.Activate(ref iid, 1 /*CLSCTX_INPROC_SERVER*/, IntPtr.Zero, out IAudioEndpointVolume vol));
        return vol;
    }

    public float GetVolume()
    {
        try { GetEndpointVolume().GetMasterVolumeLevelScalar(out float v); return v; }
        catch { return 0f; }
    }

    public void SetVolume(float scalar0to1)
    {
        try { GetEndpointVolume().SetMasterVolumeLevelScalar(Math.Clamp(scalar0to1, 0f, 1f), ref _ctx); }
        catch { }
    }

    public bool GetMute()
    {
        try { GetEndpointVolume().GetMute(out bool m); return m; }
        catch { return false; }
    }

    public void SetMute(bool mute)
    {
        try { GetEndpointVolume().SetMute(mute, ref _ctx); }
        catch { }
    }
}
