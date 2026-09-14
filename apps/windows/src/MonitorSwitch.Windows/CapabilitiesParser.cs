using System.Globalization;
using System.Text.RegularExpressions;

namespace MonitorSwitch.Windows;

public static partial class CapabilitiesParser
{
    [GeneratedRegex(@"(?:^|\s)60\s*\(([^)]*)\)", RegexOptions.IgnoreCase)]
    private static partial Regex InputSourceRegex();

    [GeneratedRegex(@"\b(?:0x)?([0-9a-f]{1,2})\b", RegexOptions.IgnoreCase)]
    private static partial Regex HexValueRegex();

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
}
