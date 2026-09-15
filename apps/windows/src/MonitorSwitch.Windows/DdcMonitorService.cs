using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace MonitorSwitch.Windows;

public sealed record MonitorSnapshot(
    string Id,
    string Description,
    byte CurrentInput,
    IReadOnlyList<byte> AdvertisedInputs,
    string? Capabilities,
    string Manufacturer = "",
    string ModelName = "",
    int NativeWidth = 0,
    int NativeHeight = 0,
    int CurrentWidth = 0,
    int CurrentHeight = 0,
    int RefreshRate = 0,
    bool IsDdcSupported = true,
    bool IsBrightnessSupported = false,
    bool IsVolumeSupported = false,
    uint? CurrentBrightness = null,
    uint? CurrentVolume = null)
{
    public MonitorSnapshot(string description, byte currentInput, IReadOnlyList<byte> advertisedInputs, string? capabilities)
        : this(description, description, currentInput, advertisedInputs, capabilities)
    {
    }

    public bool Is4K => NativeWidth >= 3840 && NativeHeight >= 2160;

    public string NativeResolutionText =>
        NativeWidth > 0 && NativeHeight > 0
            ? $"{NativeWidth} × {NativeHeight}"
            : "未知";

    public int? ScalePercent =>
        NativeWidth > 0 && CurrentWidth > 0
            ? (int)Math.Round((double)NativeWidth / CurrentWidth * 100)
            : null;

    public string CurrentModeText =>
        CurrentWidth > 0 && CurrentHeight > 0
            ? (RefreshRate > 0
                ? $"{CurrentWidth} × {CurrentHeight} @ {RefreshRate}Hz"
                : $"{CurrentWidth} × {CurrentHeight}")
            : "未知";

    public string FormattedModeText
    {
        get
        {
            if (CurrentWidth <= 0 || CurrentHeight <= 0) return "未知";
            var scale = ScalePercent.HasValue ? $" · {ScalePercent.Value}%" : "";
            var refresh = RefreshRate > 0 ? $" · {RefreshRate}Hz" : "";
            return $"{CurrentWidth} × {CurrentHeight}{scale}{refresh}";
        }
    }

    public string DdcStatusText => IsDdcSupported ? "可用" : "不可读取";
}

public sealed class DdcMonitorService
{
    private const byte InputSourceVcp = 0x60;
    private const byte BrightnessVcp = 0x10;
    private const byte VolumeVcp = 0x62;

    public IReadOnlyList<MonitorSnapshot> EnumerateMonitors()
    {
        var leases = EnumerateLeases();
        try
        {
            return leases.Select(lease => lease.Snapshot).ToList();
        }
        finally
        {
            foreach (var lease in leases)
            {
                lease.Dispose();
            }
        }
    }

    public MonitorSnapshot Scan(AppSettings settings) =>
        Scan(settings.SelectedMonitorId, settings.MonitorHint);

    public MonitorSnapshot Scan() =>
        Scan(null, null);

    public MonitorSnapshot Scan(string? monitorHint) =>
        Scan(null, monitorHint);

    public MonitorSnapshot Scan(string? selectedMonitorId, string? monitorHint)
    {
        var monitors = EnumerateMonitors();
        return SelectTarget(monitors, selectedMonitorId, monitorHint)
            ?? throw new InvalidOperationException("未找到外接显示器。请确认显示器已连接且已开机。");
    }

    public void SwitchInput(AppSettings settings, byte input) =>
        SwitchInput(settings.SelectedMonitorId, settings.MonitorHint, input);

    public void SwitchInput(string monitorHint, byte input) =>
        SwitchInput(null, monitorHint, input);

    public void SwitchInput(string? selectedMonitorId, string? monitorHint, byte input)
    {
        var leases = EnumerateLeases();
        try
        {
            var target = SelectTarget(leases.Select(l => l.Snapshot).ToList(), selectedMonitorId, monitorHint)
                ?? throw new InvalidOperationException("未找到能够接收 DDC/CI 命令的外接显示器。");

            if (!target.IsDdcSupported)
            {
                throw new InvalidOperationException("目标显示器未响应 DDC/CI。请确认显示器已开启 DDC/CI。");
            }

            var lease = leases.FirstOrDefault(l => l.Snapshot.Id == target.Id && l.Handle != IntPtr.Zero)
                ?? throw new InvalidOperationException("未找到可用的显示器控制句柄。");

            if (!NativeMethods.SetVCPFeature(lease.Handle, InputSourceVcp, input))
            {
                throw LastWin32($"切换到 {InputSourceCatalog.ConnectorName(input)} 失败");
            }
        }
        finally
        {
            foreach (var lease in leases)
            {
                lease.Dispose();
            }
        }
    }

    public void SetBrightness(string? selectedMonitorId, string? monitorHint, uint value)
    {
        SetVcpValue(selectedMonitorId, monitorHint, BrightnessVcp, value, "调节亮度");
    }

    public void SetVolume(string? selectedMonitorId, string? monitorHint, uint value)
    {
        SetVcpValue(selectedMonitorId, monitorHint, VolumeVcp, value, "调节音量");
    }

    private static void SetVcpValue(string? selectedMonitorId, string? monitorHint, byte vcpCode, uint value, string actionName)
    {
        if (vcpCode != BrightnessVcp && vcpCode != VolumeVcp)
        {
            throw new ArgumentException($"不支持写入 VCP 代码 0x{vcpCode:X2}，仅允许 0x10 和 0x62", nameof(vcpCode));
        }

        var leases = EnumerateLeases();
        try
        {
            var target = SelectTarget(leases.Select(l => l.Snapshot).ToList(), selectedMonitorId, monitorHint)
                ?? throw new InvalidOperationException("未找到外接显示器。");

            if (vcpCode == BrightnessVcp && !target.IsBrightnessSupported)
            {
                throw new InvalidOperationException("该显示器不支持亮度调节。");
            }

            if (vcpCode == VolumeVcp && !target.IsVolumeSupported)
            {
                throw new InvalidOperationException("该显示器不支持音量调节。");
            }

            var lease = leases.FirstOrDefault(l => l.Snapshot.Id == target.Id && l.Handle != IntPtr.Zero)
                ?? throw new InvalidOperationException("未找到可用的显示器控制句柄。");

            if (!NativeMethods.SetVCPFeature(lease.Handle, vcpCode, value))
            {
                throw LastWin32($"{actionName}失败");
            }
        }
        finally
        {
            foreach (var lease in leases)
            {
                lease.Dispose();
            }
        }
    }

    public static MonitorSnapshot? SelectTarget(
        IReadOnlyList<MonitorSnapshot> monitors,
        string? selectedMonitorId,
        string? monitorHint)
    {
        if (monitors.Count == 0)
        {
            return null;
        }

        // 1. Explicit ID selection
        if (!string.IsNullOrWhiteSpace(selectedMonitorId))
        {
            var matchedById = monitors.FirstOrDefault(m =>
                string.Equals(m.Id, selectedMonitorId, StringComparison.OrdinalIgnoreCase));
            if (matchedById is not null)
            {
                return matchedById;
            }
        }

        // 2. Custom hint selection (if hint is non-empty and not legacy default)
        if (!string.IsNullOrWhiteSpace(monitorHint))
        {
            var matchedByHint = monitors.Where(m =>
                m.Description.Contains(monitorHint, StringComparison.OrdinalIgnoreCase) ||
                m.ModelName.Contains(monitorHint, StringComparison.OrdinalIgnoreCase) ||
                m.Manufacturer.Contains(monitorHint, StringComparison.OrdinalIgnoreCase) ||
                m.Id.Contains(monitorHint, StringComparison.OrdinalIgnoreCase)).ToList();

            if (matchedByHint.Count == 1)
            {
                return matchedByHint[0];
            }
            if (matchedByHint.Count > 1)
            {
                throw new InvalidOperationException($"找到多台匹配“{monitorHint}”的显示器，请在设置中指定目标显示器。");
            }
        }

        // 3. Fallback selection
        var ddcMonitors = monitors.Where(m => m.IsDdcSupported).ToList();
        if (ddcMonitors.Count == 1)
        {
            return ddcMonitors[0];
        }

        if (ddcMonitors.Count > 1)
        {
            throw new InvalidOperationException("检测到多台支持 DDC/CI 的外接显示器，请在设置中指定目标显示器，以防向错误的显示器发送指令。");
        }

        // None has readable DDC
        if (monitors.Count == 1)
        {
            return monitors[0];
        }

        throw new InvalidOperationException("未找到能够读取 DDC/CI 输入源的外接显示器。请确认显示器已开启 DDC/CI。");
    }

    private static List<PhysicalMonitorLease> EnumerateLeases()
    {
        var result = new List<PhysicalMonitorLease>();
        var displayConfigs = QueryDisplayConfigs();

        NativeMethods.MonitorEnumProc callback = (logicalMonitor, _, _, _) =>
        {
            string gdiDeviceName = "";
            var monitorInfo = new NativeMethods.MONITORINFOEX
            {
                cbSize = Marshal.SizeOf<NativeMethods.MONITORINFOEX>()
            };

            if (NativeMethods.GetMonitorInfo(logicalMonitor, ref monitorInfo))
            {
                gdiDeviceName = monitorInfo.szDevice?.Trim() ?? "";
            }

            var (currentWidth, currentHeight, refreshRate, nativeWidth, nativeHeight) =
                GetDisplayModes(gdiDeviceName);

            displayConfigs.TryGetValue(gdiDeviceName, out var config);

            string mfg = config?.Manufacturer ?? "";
            string modelName = config?.FriendlyName ?? "";
            string devicePath = config?.DevicePath ?? "";

            if (!NativeMethods.GetNumberOfPhysicalMonitorsFromHMONITOR(logicalMonitor, out var count) || count == 0)
            {
                // Display without physical monitor handle (unreadable DDC)
                string fallbackId = !string.IsNullOrWhiteSpace(devicePath)
                    ? devicePath
                    : (!string.IsNullOrWhiteSpace(gdiDeviceName) ? gdiDeviceName : $"Display_{result.Count + 1}");

                string description = FormatDisplayName(mfg, modelName, "外接显示器");

                result.Add(new PhysicalMonitorLease(
                    IntPtr.Zero,
                    new MonitorSnapshot(
                        Id: fallbackId,
                        Description: description,
                        CurrentInput: 0,
                        AdvertisedInputs: [],
                        Capabilities: null,
                        Manufacturer: mfg,
                        ModelName: modelName,
                        NativeWidth: nativeWidth,
                        NativeHeight: nativeHeight,
                        CurrentWidth: currentWidth,
                        CurrentHeight: currentHeight,
                        RefreshRate: refreshRate,
                        IsDdcSupported: false,
                        IsBrightnessSupported: false,
                        IsVolumeSupported: false)));
                return true;
            }

            var physical = new NativeMethods.PhysicalMonitor[checked((int)count)];
            if (!NativeMethods.GetPhysicalMonitorsFromHMONITOR(logicalMonitor, count, physical))
            {
                return true;
            }

            foreach (var item in physical)
            {
                bool hasInput = TryReadInput(item.Handle, out var currentInput);
                var capabilities = TryReadCapabilities(item.Handle);

                bool hasBrightness = TryReadVcp(item.Handle, BrightnessVcp, out var brightnessVal, out _);
                bool hasVolume = TryReadVcp(item.Handle, VolumeVcp, out var volumeVal, out _);

                bool isBrightnessSupported = hasBrightness || CapabilitiesParser.HasBrightnessSupport(capabilities);
                bool isVolumeSupported = hasVolume || CapabilitiesParser.HasVolumeSupport(capabilities);
                bool isDdcSupported = hasInput || !string.IsNullOrWhiteSpace(capabilities);

                var advertised = CapabilitiesParser.ParseInputSources(capabilities);
                if (advertised.Count == 0 && isDdcSupported)
                {
                    advertised = [0x0F, 0x10, 0x11, 0x12];
                }

                string? modelFromCap = CapabilitiesParser.ParseModel(capabilities);
                string effectiveModel = !string.IsNullOrWhiteSpace(modelName)
                    ? modelName
                    : (!string.IsNullOrWhiteSpace(modelFromCap) ? modelFromCap : "");

                string description = FormatDisplayName(mfg, effectiveModel, item.Description);

                string id = !string.IsNullOrWhiteSpace(devicePath)
                    ? devicePath
                    : (!string.IsNullOrWhiteSpace(mfg) && config?.ProductCodeId > 0
                        ? $"{mfg}_{config.ProductCodeId:X4}"
                        : (!string.IsNullOrWhiteSpace(gdiDeviceName) ? gdiDeviceName : $"Handle_{item.Handle}"));

                var snapshot = new MonitorSnapshot(
                    Id: id,
                    Description: description,
                    CurrentInput: currentInput,
                    AdvertisedInputs: advertised,
                    Capabilities: capabilities,
                    Manufacturer: mfg,
                    ModelName: effectiveModel,
                    NativeWidth: nativeWidth,
                    NativeHeight: nativeHeight,
                    CurrentWidth: currentWidth,
                    CurrentHeight: currentHeight,
                    RefreshRate: refreshRate,
                    IsDdcSupported: isDdcSupported,
                    IsBrightnessSupported: isBrightnessSupported,
                    IsVolumeSupported: isVolumeSupported,
                    CurrentBrightness: hasBrightness ? brightnessVal : null,
                    CurrentVolume: hasVolume ? volumeVal : null);

                result.Add(new PhysicalMonitorLease(item.Handle, snapshot));
            }

            return true;
        };

        if (!NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero))
        {
            throw LastWin32("枚举显示器失败");
        }

        return result;
    }

    private static (int currentWidth, int currentHeight, int refreshRate, int nativeWidth, int nativeHeight) GetDisplayModes(string gdiDeviceName)
    {
        if (string.IsNullOrWhiteSpace(gdiDeviceName))
        {
            return (0, 0, 0, 0, 0);
        }

        int currentWidth = 0;
        int currentHeight = 0;
        int refreshRate = 0;
        int nativeWidth = 0;
        int nativeHeight = 0;

        var currentMode = new NativeMethods.DEVMODE();
        currentMode.dmSize = (ushort)Marshal.SizeOf<NativeMethods.DEVMODE>();

        if (NativeMethods.EnumDisplaySettings(gdiDeviceName, NativeMethods.EnumCurrentSettings, ref currentMode))
        {
            currentWidth = (int)currentMode.dmPelsWidth;
            currentHeight = (int)currentMode.dmPelsHeight;
            refreshRate = (int)currentMode.dmDisplayFrequency;
            nativeWidth = currentWidth;
            nativeHeight = currentHeight;
        }

        int modeIndex = 0;
        var mode = new NativeMethods.DEVMODE();
        mode.dmSize = (ushort)Marshal.SizeOf<NativeMethods.DEVMODE>();

        while (NativeMethods.EnumDisplaySettings(gdiDeviceName, modeIndex++, ref mode))
        {
            int w = (int)mode.dmPelsWidth;
            int h = (int)mode.dmPelsHeight;
            if (w > nativeWidth || (w == nativeWidth && h > nativeHeight))
            {
                nativeWidth = w;
                nativeHeight = h;
            }
        }

        return (currentWidth, currentHeight, refreshRate, nativeWidth, nativeHeight);
    }

    private static Dictionary<string, DisplayConfigEntry> QueryDisplayConfigs()
    {
        var map = new Dictionary<string, DisplayConfigEntry>(StringComparer.OrdinalIgnoreCase);

        int error = NativeMethods.GetDisplayConfigBufferSizes(
            NativeMethods.QdcOnlySpecified,
            out uint pathCount,
            out uint modeCount);

        if (error != 0 || pathCount == 0)
        {
            return map;
        }

        var paths = new NativeMethods.DISPLAYCONFIG_PATH_INFO[pathCount];
        var modes = new NativeMethods.DISPLAYCONFIG_MODE_INFO[modeCount];

        error = NativeMethods.QueryDisplayConfig(
            NativeMethods.QdcOnlySpecified,
            ref pathCount,
            paths,
            ref modeCount,
            modes,
            IntPtr.Zero);

        if (error != 0)
        {
            return map;
        }

        for (int i = 0; i < pathCount; i++)
        {
            var path = paths[i];

            var source = new NativeMethods.DISPLAYCONFIG_SOURCE_DEVICE_NAME
            {
                Header = new NativeMethods.DISPLAYCONFIG_DEVICE_INFO_HEADER
                {
                    Type = NativeMethods.DisplayConfigDeviceInfoType.GetSourceName,
                    Size = (uint)Marshal.SizeOf<NativeMethods.DISPLAYCONFIG_SOURCE_DEVICE_NAME>(),
                    AdapterId = path.SourceInfo.AdapterId,
                    Id = path.SourceInfo.Id,
                }
            };

            if (NativeMethods.DisplayConfigGetDeviceInfo(ref source) != 0 ||
                string.IsNullOrWhiteSpace(source.ViewGdiDeviceName))
            {
                continue;
            }

            var target = new NativeMethods.DISPLAYCONFIG_TARGET_DEVICE_NAME
            {
                Header = new NativeMethods.DISPLAYCONFIG_DEVICE_INFO_HEADER
                {
                    Type = NativeMethods.DisplayConfigDeviceInfoType.GetTargetName,
                    Size = (uint)Marshal.SizeOf<NativeMethods.DISPLAYCONFIG_TARGET_DEVICE_NAME>(),
                    AdapterId = path.TargetInfo.AdapterId,
                    Id = path.TargetInfo.Id,
                }
            };

            string friendlyName = "";
            string devicePath = "";
            ushort mfgId = 0;
            ushort prodId = 0;
            string mfg = "";

            if (NativeMethods.DisplayConfigGetDeviceInfo(ref target) == 0)
            {
                friendlyName = target.MonitorFriendlyDeviceName?.Trim() ?? "";
                devicePath = target.MonitorDevicePath?.Trim() ?? "";
                mfgId = target.EdidManufactureId;
                prodId = target.EdidProductCodeId;
                mfg = DecodeManufacturer(mfgId);
            }

            map[source.ViewGdiDeviceName] = new DisplayConfigEntry(
                GdiDeviceName: source.ViewGdiDeviceName,
                FriendlyName: friendlyName,
                DevicePath: devicePath,
                ManufacturerId: mfgId,
                ProductCodeId: prodId,
                Manufacturer: mfg);
        }

        return map;
    }

    public static string DecodeManufacturer(ushort id)
    {
        if (id == 0) return "";
        char c1 = (char)(((id >> 10) & 0x1F) + '@');
        char c2 = (char)(((id >> 5) & 0x1F) + '@');
        char c3 = (char)((id & 0x1F) + '@');
        if (c1 >= 'A' && c1 <= 'Z' && c2 >= 'A' && c2 <= 'Z' && c3 >= 'A' && c3 <= 'Z')
        {
            return $"{c1}{c2}{c3}";
        }
        return "";
    }

    public static string FormatDisplayName(string? manufacturer, string? modelName, string? fallback)
    {
        manufacturer = manufacturer?.Trim() ?? "";
        modelName = modelName?.Trim() ?? "";
        fallback = fallback?.Trim() ?? "";

        if (!string.IsNullOrEmpty(modelName))
        {
            if (!string.IsNullOrEmpty(manufacturer) &&
                !modelName.StartsWith(manufacturer, StringComparison.OrdinalIgnoreCase))
            {
                return $"{manufacturer} {modelName}";
            }
            return modelName;
        }

        if (!string.IsNullOrEmpty(fallback) &&
            !string.Equals(fallback, "Generic PnP Monitor", StringComparison.OrdinalIgnoreCase))
        {
            return fallback;
        }

        return !string.IsNullOrEmpty(manufacturer) ? $"{manufacturer} 显示器" : "外接显示器";
    }

    private static bool TryReadInput(IntPtr handle, out byte current)
    {
        current = 0;
        if (handle == IntPtr.Zero) return false;
        if (!NativeMethods.GetVCPFeatureAndVCPFeatureReply(
                handle, InputSourceVcp, out _, out var value, out _))
        {
            return false;
        }

        current = (byte)(value & 0xFF);
        return true;
    }

    private static bool TryReadVcp(IntPtr handle, byte vcpCode, out uint currentValue, out uint maxValue)
    {
        currentValue = 0;
        maxValue = 0;
        if (handle == IntPtr.Zero) return false;
        return NativeMethods.GetVCPFeatureAndVCPFeatureReply(
            handle, vcpCode, out _, out currentValue, out maxValue);
    }

    private static string? TryReadCapabilities(IntPtr handle)
    {
        if (handle == IntPtr.Zero) return null;
        if (!NativeMethods.GetCapabilitiesStringLength(handle, out var length) || length < 2 || length > 64 * 1024)
        {
            return null;
        }

        var bytes = new byte[length];
        if (!NativeMethods.CapabilitiesRequestAndCapabilitiesReply(handle, bytes, length))
        {
            return null;
        }

        var terminator = Array.IndexOf(bytes, (byte)0);
        return Encoding.ASCII.GetString(bytes, 0, terminator >= 0 ? terminator : bytes.Length);
    }

    private static Exception LastWin32(string message)
    {
        var error = new Win32Exception();
        return new InvalidOperationException($"{message}：{error.Message}", error);
    }

    private sealed record DisplayConfigEntry(
        string GdiDeviceName,
        string FriendlyName,
        string DevicePath,
        ushort ManufacturerId,
        ushort ProductCodeId,
        string Manufacturer);

    private sealed class PhysicalMonitorLease(IntPtr handle, MonitorSnapshot snapshot) : IDisposable
    {
        private IntPtr _handle = handle;

        public IntPtr Handle => _handle;
        public MonitorSnapshot Snapshot { get; } = snapshot;

        public void Dispose()
        {
            if (_handle == IntPtr.Zero) return;
            var physical = new[] { new NativeMethods.PhysicalMonitor { Handle = _handle, Description = Snapshot.Description } };
            NativeMethods.DestroyPhysicalMonitors(1, physical);
            _handle = IntPtr.Zero;
        }
    }
}
