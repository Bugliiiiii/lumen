namespace MonitorSwitch.Windows;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (UpdateManager.TryRunUpdater(args))
        {
            return;
        }

        UpdateManager.ScheduleCleanup(args);
        using var singleInstance = new Mutex(true, "MonitorSwitch.Windows.SingleInstance", out var createdNew);
        if (!createdNew)
        {
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext());
    }
}
