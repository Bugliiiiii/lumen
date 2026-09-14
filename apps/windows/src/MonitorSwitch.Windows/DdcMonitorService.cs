using System.ComponentModel;
using System.Text;

namespace MonitorSwitch.Windows;

public sealed record MonitorSnapshot(
    string Description,
    byte CurrentInput,
    IReadOnlyList<byte> AdvertisedInputs,
    string? Capabilities);

public sealed class DdcMonitorService
{
    private const byte InputSourceVcp = 0x60;

    public MonitorSnapshot Scan(string monitorHint)
    {
        using var monitor = FindMonitor(monitorHint, requireReadableInput: true)
            ?? throw new InvalidOperationException("未找到能够读取 DDC/CI 输入源的外接显示器。请确认显示器已开启 DDC/CI。 ");

        if (!TryReadInput(monitor.Handle, out var current))
        {
            throw LastWin32("显示器没有返回当前输入源");
        }

        var capabilities = TryReadCapabilities(monitor.Handle);
        var advertised = CapabilitiesParser.ParseInputSources(capabilities);
        if (advertised.Count == 0)
        {
            advertised = [0x0F, 0x10, 0x11, 0x12];
        }

        return new MonitorSnapshot(monitor.Description, current, advertised, capabilities);
    }

    public void SwitchInput(string monitorHint, byte input)
    {
        using var monitor = FindMonitor(monitorHint, requireReadableInput: true)
            ?? throw new InvalidOperationException("未找到能够接收 DDC/CI 命令的外接显示器。");

        if (!NativeMethods.SetVCPFeature(monitor.Handle, InputSourceVcp, input))
        {
            throw LastWin32($"切换到 {InputSourceCatalog.ConnectorName(input)} 失败");
        }
    }

    private static PhysicalMonitorLease? FindMonitor(string monitorHint, bool requireReadableInput)
    {
        var monitors = EnumeratePhysicalMonitors();
        var ordered = monitors
            .OrderByDescending(monitor => monitor.Description.Contains(monitorHint, StringComparison.OrdinalIgnoreCase))
            .ThenByDescending(monitor => monitor.Description.Contains("KTC", StringComparison.OrdinalIgnoreCase));

        foreach (var monitor in ordered)
        {
            if (!requireReadableInput || TryReadInput(monitor.Handle, out _))
            {
                foreach (var other in monitors.Where(other => !ReferenceEquals(other, monitor)))
                {
                    other.Dispose();
                }
                return monitor;
            }
            monitor.Dispose();
        }

        return null;
    }

    private static List<PhysicalMonitorLease> EnumeratePhysicalMonitors()
    {
        var result = new List<PhysicalMonitorLease>();
        NativeMethods.MonitorEnumProc callback = (logicalMonitor, _, _, _) =>
        {
            if (!NativeMethods.GetNumberOfPhysicalMonitorsFromHMONITOR(logicalMonitor, out var count) || count == 0)
            {
                return true;
            }

            var physical = new NativeMethods.PhysicalMonitor[checked((int)count)];
            if (!NativeMethods.GetPhysicalMonitorsFromHMONITOR(logicalMonitor, count, physical))
            {
                return true;
            }

            result.AddRange(physical.Select(item => new PhysicalMonitorLease(item.Handle, item.Description)));
            return true;
        };

        if (!NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero))
        {
            throw LastWin32("枚举显示器失败");
        }

        return result;
    }

    private static bool TryReadInput(IntPtr handle, out byte current)
    {
        current = 0;
        if (!NativeMethods.GetVCPFeatureAndVCPFeatureReply(
                handle, InputSourceVcp, out _, out var value, out _))
        {
            return false;
        }

        current = (byte)(value & 0xFF);
        return true;
    }

    private static string? TryReadCapabilities(IntPtr handle)
    {
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

    private sealed class PhysicalMonitorLease(IntPtr handle, string description) : IDisposable
    {
        private IntPtr _handle = handle;

        public IntPtr Handle => _handle;
        public string Description { get; } = string.IsNullOrWhiteSpace(description) ? "外接显示器" : description;

        public void Dispose()
        {
            if (_handle == IntPtr.Zero) return;
            var physical = new[] { new NativeMethods.PhysicalMonitor { Handle = _handle, Description = Description } };
            NativeMethods.DestroyPhysicalMonitors(1, physical);
            _handle = IntPtr.Zero;
        }
    }
}
