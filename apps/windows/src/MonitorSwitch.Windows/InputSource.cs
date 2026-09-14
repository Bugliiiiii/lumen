namespace MonitorSwitch.Windows;

public sealed record InputSource(byte Value, string ConnectorName, string FriendlyName)
{
    public string DisplayName => $"{FriendlyName} · {ConnectorName}";
}

public static class InputSourceCatalog
{
    private static readonly IReadOnlyDictionary<byte, string> ConnectorNames =
        new Dictionary<byte, string>
        {
            [0x01] = "VGA 1",
            [0x03] = "DVI 1",
            [0x0F] = "DisplayPort 1",
            [0x10] = "DisplayPort 2",
            [0x11] = "HDMI 1",
            [0x12] = "HDMI 2",
            [0x1B] = "USB-C",
        };

    public static string ConnectorName(byte value) =>
        ConnectorNames.TryGetValue(value, out var name) ? name : $"Input {value}";

    public static IReadOnlyList<InputSource> Create(IEnumerable<byte> values, AppSettings settings) =>
        values.Distinct().OrderBy(value => value).Select(value => new InputSource(
            value,
            ConnectorName(value),
            value == settings.WindowsInput ? settings.WindowsLabel :
            value == settings.MacInput ? settings.MacLabel : ConnectorName(value))).ToList();
}
