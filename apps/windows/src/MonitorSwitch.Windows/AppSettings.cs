using System.Text.Json;

namespace MonitorSwitch.Windows;

[Flags]
public enum HotkeyModifiers : uint
{
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Win = 0x0008,
}

public sealed class AppSettings
{
    public string MonitorHint { get; set; } = "KTC H27T22S";
    public byte WindowsInput { get; set; } = 0x0F;
    public byte MacInput { get; set; } = 0x11;
    public string WindowsLabel { get; set; } = "Windows";
    public string MacLabel { get; set; } = "Mac";
    public HotkeyModifiers HotkeyModifiers { get; set; } = HotkeyModifiers.Control | HotkeyModifiers.Alt;
    public Keys HotkeyKey { get; set; } = Keys.S;

    public string HotkeyText => $"{FormatModifiers(HotkeyModifiers)}{HotkeyKey}";

    public AppSettings Copy() => new()
    {
        MonitorHint = MonitorHint,
        WindowsInput = WindowsInput,
        MacInput = MacInput,
        WindowsLabel = WindowsLabel,
        MacLabel = MacLabel,
        HotkeyModifiers = HotkeyModifiers,
        HotkeyKey = HotkeyKey,
    };

    public void Apply(AppSettings source)
    {
        MonitorHint = source.MonitorHint;
        WindowsInput = source.WindowsInput;
        MacInput = source.MacInput;
        WindowsLabel = source.WindowsLabel;
        MacLabel = source.MacLabel;
        HotkeyModifiers = source.HotkeyModifiers;
        HotkeyKey = source.HotkeyKey;
    }

    private static string FormatModifiers(HotkeyModifiers modifiers)
    {
        var parts = new List<string>();
        if (modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
        if (modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
        if (modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
        if (modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
        return parts.Count == 0 ? string.Empty : string.Join(" + ", parts) + " + ";
    }
}

public static class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MonitorSwitch");
    private static readonly string FilePath = Path.Combine(DirectoryPath, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            return File.Exists(FilePath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOptions) ?? new AppSettings()
                : new AppSettings();
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            return new AppSettings();
        }
    }

    public static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(DirectoryPath);
        var temporaryPath = FilePath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(settings, JsonOptions));
        File.Move(temporaryPath, FilePath, true);
    }
}
