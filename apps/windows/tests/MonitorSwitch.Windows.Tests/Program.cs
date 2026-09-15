using MonitorSwitch.Windows;

int assertionCount = 0;

void AssertEqual<T>(T expected, T actual, string name)
{
    assertionCount++;
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"{name}: expected {expected}, got {actual}");
    }
}

void AssertSequence(IEnumerable<byte> expected, IEnumerable<byte> actual, string name)
{
    assertionCount++;
    if (!expected.SequenceEqual(actual))
    {
        throw new InvalidOperationException($"{name}: expected [{string.Join(',', expected)}], got [{string.Join(',', actual)}]");
    }
}

void AssertThrows(Action action, string name)
{
    assertionCount++;
    try
    {
        action();
        throw new InvalidOperationException($"{name}: expected exception but none was thrown");
    }
    catch (InvalidOperationException)
    {
        // Expected
    }
}

// 1. CapabilitiesParser tests
AssertSequence(
    [0x0F, 0x10, 0x11, 0x12],
    CapabilitiesParser.ParseInputSources("(prot(monitor)type(LCD)model(U27E40)cmds(01 02)vcp(10 12 60(0f 10 11 12) 62 D6(01 04)))"),
    "standard input list");
AssertSequence(
    [0x0F, 0x11],
    CapabilitiesParser.ParseInputSources("vcp(60(0x0f 0X11))"),
    "prefixed values");
AssertEqual(0, CapabilitiesParser.ParseInputSources(null).Count, "null capabilities");
AssertEqual("U27E40", CapabilitiesParser.ParseModel("(prot(monitor)type(LCD)model(U27E40)vcp(60(0f 11)))"), "parse U27E40 model");
AssertEqual(null, CapabilitiesParser.ParseModel("prot(monitor)"), "parse model missing");
AssertEqual(true, CapabilitiesParser.HasBrightnessSupport("vcp(10 60(0f 11))"), "brightness VCP 0x10 supported");
AssertEqual(false, CapabilitiesParser.HasBrightnessSupport("vcp(60(0f 11))"), "brightness VCP 0x10 not supported");
AssertEqual(true, CapabilitiesParser.HasVolumeSupport("vcp(10 60(0f 11) 62)"), "volume VCP 0x62 supported");
AssertEqual(false, CapabilitiesParser.HasVolumeSupport("vcp(10 60(0f 11))"), "volume VCP 0x62 not supported");

// 2. InputSourceCatalog tests
AssertEqual("DisplayPort 1", InputSourceCatalog.ConnectorName(0x0F), "DP1 name");
AssertEqual("HDMI 1", InputSourceCatalog.ConnectorName(0x11), "HDMI1 name");
AssertEqual("Input 127", InputSourceCatalog.ConnectorName(0x7F), "unknown name");

// 3. AppSettings defaults and updates
var settings = new AppSettings();
AssertEqual((byte)0x0F, settings.WindowsInput, "default Windows input");
AssertEqual((byte)0x11, settings.MacInput, "default Mac input");
AssertEqual("Ctrl + Alt + S", settings.HotkeyText, "default hotkey");
AssertEqual(true, settings.AutomaticallyChecksForUpdates, "automatic update checks enabled by default");
AssertEqual("", settings.SelectedMonitorId, "default selectedMonitorId is empty");

settings.AutomaticallyChecksForUpdates = false;
AssertEqual(false, settings.Copy().AutomaticallyChecksForUpdates, "update preference copied");
var appliedSettings = new AppSettings();
appliedSettings.Apply(settings);
AssertEqual(false, appliedSettings.AutomaticallyChecksForUpdates, "update preference applied");

// 4. Legacy KTC settings migration
var legacySettings = new AppSettings
{
    MonitorHint = "H27T22S",
    WindowsLabel = "PC",
    MacLabel = "Mac Studio",
    WindowsInput = 0x0F,
    MacInput = 0x11,
};
AssertEqual(true, legacySettings.MigrateLegacySettings(), "legacy H27T22S hint migrated");
AssertEqual("", legacySettings.MonitorHint, "legacy hint cleared to empty");
AssertEqual("PC", legacySettings.WindowsLabel, "custom WindowsLabel preserved");
AssertEqual("Mac Studio", legacySettings.MacLabel, "custom MacLabel preserved");
AssertEqual((byte)0x0F, legacySettings.WindowsInput, "WindowsInput preserved");
AssertEqual((byte)0x11, legacySettings.MacInput, "MacInput preserved");

var customHintSettings = new AppSettings { MonitorHint = "Dell U2720Q" };
AssertEqual(false, customHintSettings.MigrateLegacySettings(), "custom hint not migrated");
AssertEqual("Dell U2720Q", customHintSettings.MonitorHint, "custom hint preserved");

// 5. UpdateManager tests
AssertEqual(true, UpdateManager.IsVersionNewer("v0.5.0", "0.4.0"), "newer release version");
AssertEqual(false, UpdateManager.IsVersionNewer("v0.4.0", "0.4.0"), "same release version");
AssertEqual(false, UpdateManager.IsVersionNewer("not-a-version", "0.4.0"), "invalid release version");

// 6. DdcMonitorService manufacturer and name formatting
AssertEqual("AOC", DdcMonitorService.DecodeManufacturer(0x05E3), "decode AOC manufacturer");
AssertEqual("KTC", DdcMonitorService.DecodeManufacturer(0x2E83), "decode KTC manufacturer");
AssertEqual("DEL", DdcMonitorService.DecodeManufacturer(0x10AC), "decode DELL manufacturer");
AssertEqual("AOC U27E40", DdcMonitorService.FormatDisplayName("AOC", "U27E40", ""), "format manufacturer and model");
AssertEqual("AOC U27E40", DdcMonitorService.FormatDisplayName("AOC", "AOC U27E40", ""), "format deduplicated model");
AssertEqual("外接显示器", DdcMonitorService.FormatDisplayName("", "", "Generic PnP Monitor"), "filter generic PnP fallback");

// 7. 4K AOC U27E40 descriptor checks
var u27e40 = new MonitorSnapshot(
    Id: @"\\?\DISPLAY#AOC2740#4&1840049&0&UID260#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}",
    Description: "AOC U27E40",
    CurrentInput: 0x11,
    AdvertisedInputs: [0x0F, 0x11],
    Capabilities: "vcp(10 60(0f 11) 62)",
    Manufacturer: "AOC",
    ModelName: "U27E40",
    NativeWidth: 3840,
    NativeHeight: 2160,
    CurrentWidth: 2560,
    CurrentHeight: 1440,
    RefreshRate: 60,
    IsDdcSupported: true,
    IsBrightnessSupported: true,
    IsVolumeSupported: true,
    CurrentBrightness: 100,
    CurrentVolume: 100);

AssertEqual(true, u27e40.Is4K, "U27E40 is 4K");
AssertEqual("3840 × 2160", u27e40.NativeResolutionText, "U27E40 native resolution");
AssertEqual("2560 × 1440 @ 60Hz", u27e40.CurrentModeText, "U27E40 current logical mode");
AssertEqual(150, u27e40.ScalePercent, "U27E40 scale percent");
AssertEqual("2560 × 1440 · 150% · 60Hz", u27e40.FormattedModeText, "U27E40 formatted mode");
AssertEqual("可用", u27e40.DdcStatusText, "U27E40 DDC status");
AssertEqual(true, u27e40.IsBrightnessSupported, "U27E40 brightness supported");
AssertEqual(true, u27e40.IsVolumeSupported, "U27E40 volume supported");

// 8. Unreadable DDC fallback
var unreadableMonitor = new MonitorSnapshot(
    Id: @"\\?\DISPLAY#AOC2740#fallback",
    Description: "AOC U27E40",
    CurrentInput: 0,
    AdvertisedInputs: [],
    Capabilities: null,
    Manufacturer: "AOC",
    ModelName: "U27E40",
    NativeWidth: 3840,
    NativeHeight: 2160,
    CurrentWidth: 3840,
    CurrentHeight: 2160,
    RefreshRate: 60,
    IsDdcSupported: false,
    IsBrightnessSupported: false,
    IsVolumeSupported: false);

AssertEqual("不可读取", unreadableMonitor.DdcStatusText, "unreadable DDC status text");
AssertEqual("AOC U27E40", unreadableMonitor.Description, "model name remains visible");
AssertEqual("3840 × 2160", unreadableMonitor.NativeResolutionText, "native resolution remains visible");

// 9. Single monitor auto-selection
var singleSelection = DdcMonitorService.SelectTarget([u27e40], selectedMonitorId: null, monitorHint: null);
AssertEqual("AOC U27E40", singleSelection?.Description, "auto-select single DDC monitor");

// 10. Multi-monitor ambiguity prevention (cannot write to wrong monitor)
var secondMonitor = new MonitorSnapshot(
    Id: @"\\?\DISPLAY#DEL4096#4&9876543&0&UID261#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}",
    Description: "Dell U2720Q",
    CurrentInput: 0x0F,
    AdvertisedInputs: [0x0F, 0x11],
    Capabilities: "vcp(10 60(0f 11))",
    Manufacturer: "DEL",
    ModelName: "U2720Q",
    NativeWidth: 3840,
    NativeHeight: 2160,
    CurrentWidth: 3840,
    CurrentHeight: 2160,
    RefreshRate: 60,
    IsDdcSupported: true,
    IsBrightnessSupported: true,
    IsVolumeSupported: false);

AssertThrows(() =>
{
    DdcMonitorService.SelectTarget([u27e40, secondMonitor], selectedMonitorId: null, monitorHint: null);
}, "ambiguous two monitors without ID throws exception and prevents wrong-monitor write");

// 11. Multi-monitor explicit ID selection
var explicitSelection = DdcMonitorService.SelectTarget(
    [u27e40, secondMonitor],
    selectedMonitorId: secondMonitor.Id,
    monitorHint: null);
AssertEqual("Dell U2720Q", explicitSelection?.Description, "explicit ID selects exact monitor");

// 12. Unreadable single monitor selection (retains info for UI)
var fallbackTarget = DdcMonitorService.SelectTarget([unreadableMonitor], selectedMonitorId: null, monitorHint: null);
AssertEqual(false, fallbackTarget?.IsDdcSupported, "unreadable DDC target returned with DDC disabled");

Console.WriteLine($"MonitorSwitch.Windows.Tests: {assertionCount} assertions passed");
