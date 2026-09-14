namespace MonitorSwitch.Windows;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly AppSettings _settings;
    private readonly DdcMonitorService _ddc = new();
    private readonly HotkeyWindow _hotkey = new();
    private readonly UpdateManager _updateManager = new();
    private readonly NotifyIcon _trayIcon;
    private readonly ToolStripMenuItem _currentInputItem;
    private readonly ToolStripMenuItem _updateItem;
    private readonly System.Windows.Forms.Timer? _initialUpdateTimer;
    private SettingsForm? _settingsForm;

    internal TrayApplicationContext()
    {
        _settings = SettingsStore.Load();
        _currentInputItem = new ToolStripMenuItem("当前输入：等待扫描") { Enabled = false };
        _updateItem = new ToolStripMenuItem("检查更新…", null, async (_, _) => await HandleUpdateMenuAsync());

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("KTC H27T22S") { Enabled = false });
        menu.Items.Add(_currentInputItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("切换到 Mac · HDMI 1", null, async (_, _) => await SwitchToMacAsync());
        menu.Items.Add("扫描显示器", null, async (_, _) => await RefreshCurrentInputAsync(showErrors: true));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_updateItem);
        menu.Items.Add("设置…", null, (_, _) => ShowSettings());
        menu.Items.Add("退出", null, (_, _) => ExitThread());

        _trayIcon = new NotifyIcon
        {
            Icon = IconFactory.Create(),
            Text = "Lumen",
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
        if (_settings.AutomaticallyChecksForUpdates)
        {
            var updateTimer = new System.Windows.Forms.Timer { Interval = 1500 };
            _initialUpdateTimer = updateTimer;
            updateTimer.Tick += async (_, _) =>
            {
                updateTimer.Stop();
                await CheckForUpdatesAsync(showCurrent: false);
            };
            updateTimer.Start();
        }
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

    private async Task CheckForUpdatesAsync(bool showCurrent)
    {
        _updateItem.Enabled = false;
        try
        {
            var release = await _updateManager.CheckForUpdatesAsync();
            if (release is null)
            {
                _updateItem.Text = "检查更新…";
                if (showCurrent) ShowInfo("当前已是最新版本");
                return;
            }

            _updateItem.Text = $"更新到 {release.TagName}…";
            _trayIcon.BalloonTipTitle = "Lumen 有新版本";
            _trayIcon.BalloonTipText = $"{release.TagName} 已发布，可从托盘菜单安装。";
            _trayIcon.BalloonTipIcon = ToolTipIcon.Info;
            _trayIcon.ShowBalloonTip(5000);
        }
        catch (Exception exception)
        {
            if (showCurrent) ShowError($"检查更新失败：{exception.Message}");
        }
        finally
        {
            _updateItem.Enabled = true;
        }
    }

    private async Task HandleUpdateMenuAsync()
    {
        var release = _updateManager.LatestRelease;
        if (release is null)
        {
            await CheckForUpdatesAsync(showCurrent: true);
            return;
        }
        if (MessageBox.Show(
                $"下载并安装 Lumen {release.TagName}？程序会自动重启。",
                "Lumen 更新",
                MessageBoxButtons.OKCancel,
                MessageBoxIcon.Information) != DialogResult.OK)
        {
            return;
        }

        _updateItem.Enabled = false;
        _updateItem.Text = "正在下载更新…";
        try
        {
            await _updateManager.DownloadAndInstallAsync(release);
            ExitThread();
        }
        catch (Exception exception)
        {
            _updateItem.Text = $"更新到 {release.TagName}…";
            _updateItem.Enabled = true;
            ShowError($"更新失败：{exception.Message}");
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
            },
            _updateManager);
        _settingsForm.FormClosed += (_, _) => _settingsForm = null;
        _settingsForm.Show();
    }

    private void ShowError(string message)
    {
        _trayIcon.BalloonTipTitle = "Lumen";
        _trayIcon.BalloonTipText = message;
        _trayIcon.BalloonTipIcon = ToolTipIcon.Warning;
        _trayIcon.ShowBalloonTip(5000);
    }

    private void ShowInfo(string message)
    {
        _trayIcon.BalloonTipTitle = "Lumen";
        _trayIcon.BalloonTipText = message;
        _trayIcon.BalloonTipIcon = ToolTipIcon.Info;
        _trayIcon.ShowBalloonTip(3000);
    }

    protected override void ExitThreadCore()
    {
        _hotkey.Dispose();
        _initialUpdateTimer?.Dispose();
        _updateManager.Dispose();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _settingsForm?.Dispose();
        base.ExitThreadCore();
    }
}
