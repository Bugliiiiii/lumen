using MonitorSwitch.Windows;

static void AssertEqual<T>(T expected, T actual, string name)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"{name}: expected {expected}, got {actual}");
    }
}

static void AssertSequence(IEnumerable<byte> expected, IEnumerable<byte> actual, string name)
{
    if (!expected.SequenceEqual(actual))
    {
        throw new InvalidOperationException($"{name}: expected [{string.Join(',', expected)}], got [{string.Join(',', actual)}]");
    }
}

AssertSequence(
    [0x0F, 0x10, 0x11, 0x12],
    CapabilitiesParser.ParseInputSources("(prot(monitor)type(LCD)vcp(10 12 60(0f 10 11 12) D6(01 04)))"),
    "standard input list");
AssertSequence(
    [0x0F, 0x11],
    CapabilitiesParser.ParseInputSources("vcp(60(0x0f 0X11))"),
    "prefixed values");
AssertEqual(0, CapabilitiesParser.ParseInputSources(null).Count, "null capabilities");
AssertEqual("DisplayPort 1", InputSourceCatalog.ConnectorName(0x0F), "DP1 name");
AssertEqual("HDMI 1", InputSourceCatalog.ConnectorName(0x11), "HDMI1 name");
AssertEqual("Input 127", InputSourceCatalog.ConnectorName(0x7F), "unknown name");

var settings = new AppSettings();
AssertEqual((byte)0x0F, settings.WindowsInput, "default Windows input");
AssertEqual((byte)0x11, settings.MacInput, "default Mac input");
AssertEqual("Ctrl + Alt + S", settings.HotkeyText, "default hotkey");

Console.WriteLine("MonitorSwitch.Windows.Tests: 9 assertions passed");
