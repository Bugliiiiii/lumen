namespace MonitorSwitch.Windows;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly AppSettings _settings;
    private readonly DdcMonitorService _ddc = new();
    private readonly HotkeyWindow _hotkey = new();
    private readonly NotifyIcon _trayIcon;
    private readonly ToolStripMenuItem _currentInputItem;
    private SettingsForm? _settingsForm;

    internal TrayApplicationContext()
    {
        _settings = SettingsStore.Load();
        _currentInputItem = new ToolStripMenuItem("当前输入：等待扫描") { Enabled = false };

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("KTC H27T22S") { Enabled = false });
        menu.Items.Add(_currentInputItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("切换到 Mac · HDMI 1", null, async (_, _) => await SwitchToMacAsync());
        menu.Items.Add("扫描显示器", null, async (_, _) => await RefreshCurrentInputAsync(showErrors: true));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("设置…", null, (_, _) => ShowSettings());
        menu.Items.Add("退出", null, (_, _) => ExitThread());

        _trayIcon = new NotifyIcon
        {
            Icon = IconFactory.Create(),
            Text = "Monitor Switch",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _trayIcon.DoubleClick += (_, _) => ShowSettings();

        try
        {
            RegisterHotkey();
        }
        catch (Exception exception)
        {
            ShowError(exception.Message);
        }
        _ = RefreshCurrentInputAsync(showErrors: false);
    }

    private void RegisterHotkey(AppSettings? settings = null)
    {
        _hotkey.Register(settings ?? _settings, () => _ = SwitchToMacAsync());
    }

    private async Task<MonitorSnapshot> ScanAsync() =>
        await Task.Run(() => _ddc.Scan(_settings.MonitorHint));

    private async Task RefreshCurrentInputAsync(bool showErrors)
    {
        try
        {
            var snapshot = await ScanAsync();
            _currentInputItem.Text = snapshot.CurrentInput switch
            {
                var input when input == _settings.WindowsInput => "当前输入：Windows · DisplayPort 1",
                var input when input == _settings.MacInput => "当前输入：Mac · HDMI 1",
                _ => $"当前输入：{InputSourceCatalog.ConnectorName(snapshot.CurrentInput)}",
            };
        }
        catch (Exception exception)
        {
            _currentInputItem.Text = "当前输入：不可读取";
            if (showErrors) ShowError(exception.Message);
        }
    }

    private async Task SwitchToMacAsync()
    {
        try
        {
            await Task.Run(() => _ddc.SwitchInput(_settings.MonitorHint, _settings.MacInput));
        }
        catch (Exception exception)
        {
            ShowError(exception.Message);
        }
    }

    private void ShowSettings()
    {
        if (_settingsForm is { IsDisposed: false })
        {
            _settingsForm.Activate();
            return;
        }

        _settingsForm = new SettingsForm(
            _settings.Copy(),
            ScanAsync,
            SwitchToMacAsync,
            settings =>
            {
                RegisterHotkey(settings);
                SettingsStore.Save(settings);
                _settings.Apply(settings);
            });
        _settingsForm.FormClosed += (_, _) => _settingsForm = null;
        _settingsForm.Show();
    }

    private void ShowError(string message)
    {
        _trayIcon.BalloonTipTitle = "Monitor Switch";
        _trayIcon.BalloonTipText = message;
        _trayIcon.BalloonTipIcon = ToolTipIcon.Warning;
        _trayIcon.ShowBalloonTip(5000);
    }

    protected override void ExitThreadCore()
    {
        _hotkey.Dispose();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _settingsForm?.Dispose();
        base.ExitThreadCore();
    }
}
