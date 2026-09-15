using System.Globalization;
using System.Text.RegularExpressions;

namespace MonitorSwitch.Windows;

public static partial class CapabilitiesParser
{
    [GeneratedRegex(@"(?<![0-9a-z])60\s*\(([^)]*)\)", RegexOptions.IgnoreCase)]
    private static partial Regex InputSourceRegex();

    [GeneratedRegex(@"(?<![0-9a-z])(?:0x)?([0-9a-f]{1,2})(?![0-9a-z])", RegexOptions.IgnoreCase)]
    private static partial Regex HexValueRegex();

    [GeneratedRegex(@"model\s*\(([^)]+)\)", RegexOptions.IgnoreCase)]
    private static partial Regex ModelRegex();

    [GeneratedRegex(@"(?<![0-9a-z])10(?![0-9a-z])", RegexOptions.IgnoreCase)]
    private static partial Regex BrightnessVcpRegex();

    [GeneratedRegex(@"(?<![0-9a-z])62(?![0-9a-z])", RegexOptions.IgnoreCase)]
    private static partial Regex VolumeVcpRegex();

    public static IReadOnlyList<byte> ParseInputSources(string? capabilities)
    {
        if (string.IsNullOrWhiteSpace(capabilities))
        {
            return [];
        }

        var match = InputSourceRegex().Match(capabilities);
        if (!match.Success)
        {
            return [];
        }

        return HexValueRegex().Matches(match.Groups[1].Value)
            .Select(value => byte.Parse(value.Groups[1].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture))
            .Distinct()
            .ToList();
    }

    public static string? ParseModel(string? capabilities)
    {
        if (string.IsNullOrWhiteSpace(capabilities))
        {
            return null;
        }

        var match = ModelRegex().Match(capabilities);
        return match.Success ? match.Groups[1].Value.Trim() : null;
    }

    public static bool HasBrightnessSupport(string? capabilities) =>
        !string.IsNullOrWhiteSpace(capabilities) && BrightnessVcpRegex().IsMatch(capabilities);

    public static bool HasVolumeSupport(string? capabilities) =>
        !string.IsNullOrWhiteSpace(capabilities) && VolumeVcpRegex().IsMatch(capabilities);
}
