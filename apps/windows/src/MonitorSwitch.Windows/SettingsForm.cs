namespace MonitorSwitch.Windows;

internal sealed class SettingsForm : Form
{
    private static readonly Color WindowSurface = Color.FromArgb(243, 243, 243);
    private static readonly Color PrimaryText = Color.FromArgb(31, 31, 31);
    private static readonly Color SecondaryText = Color.FromArgb(96, 96, 96);

    private readonly AppSettings _settings;
    private readonly Func<Task<MonitorSnapshot>> _scan;
    private readonly Func<Task> _switchToMac;
    private readonly Action<AppSettings> _save;
    private readonly UpdateManager _updateManager;
    private readonly Label _monitorValue;
    private readonly Label _displayModeValue;
    private readonly PillLabel _connectionBadge;
    private readonly PillLabel _currentValue;
    private readonly Label _statusValue;
    private readonly FluentTextBox _hotkeyBox;
    private readonly CheckBox _startupCheck;
    private readonly CheckBox _automaticUpdatesCheck;
    private readonly FluentTextBox _windowsLabelBox;
    private readonly FluentTextBox _macLabelBox;
    private readonly Panel _updateBanner;
    private readonly Label _updateLabel;
    private readonly FluentButton _installUpdateButton;
    private readonly FluentButton _scanButton;
    private readonly FluentButton _switchButton;
    private HotkeyModifiers _pendingModifiers;
    private Keys _pendingKey;

    internal SettingsForm(
        AppSettings settings,
        Func<Task<MonitorSnapshot>> scan,
        Func<Task> switchToMac,
        Action<AppSettings> save,
        UpdateManager updateManager)
    {
        _settings = settings;
        _scan = scan;
        _switchToMac = switchToMac;
        _save = save;
        _updateManager = updateManager;
        _pendingModifiers = settings.HotkeyModifiers;
        _pendingKey = settings.HotkeyKey;

        Text = "Lumen 设置";
        Font = new Font("Segoe UI", 9.5F);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(500, 725);
        BackColor = WindowSurface;
        AutoScaleMode = AutoScaleMode.Dpi;

        var title = new Label
        {
            Text = "Lumen",
            Font = new Font("Segoe UI Variable Display Semibold", 21F),
            ForeColor = PrimaryText,
            AutoSize = true,
            Margin = new Padding(0),
        };
        var subtitle = new Label
        {
            Text = "显示器输入切换",
            Font = new Font("Segoe UI", 9.5F),
            ForeColor = SecondaryText,
            AutoSize = true,
            Margin = new Padding(1, 2, 0, 0),
        };

        _monitorValue = new Label
        {
            Text = string.IsNullOrWhiteSpace(settings.MonitorHint) ? "外接显示器" : settings.MonitorHint,
            AutoEllipsis = true,
            Dock = DockStyle.Fill,
            Font = new Font("Segoe UI Variable Text Semibold", 12.5F),
            ForeColor = PrimaryText,
            TextAlign = ContentAlignment.MiddleLeft,
        };
        _displayModeValue = new Label
        {
            Text = "等待检测显示器规格…",
            AutoEllipsis = true,
            Dock = DockStyle.Fill,
            Font = new Font("Segoe UI", 9F),
            ForeColor = SecondaryText,
            TextAlign = ContentAlignment.MiddleLeft,
        };
        _connectionBadge = new PillLabel("等待检测", Color.FromArgb(96, 96, 96), Color.FromArgb(242, 242, 242));
        _currentValue = new PillLabel("● 当前输入未知", Color.FromArgb(0, 95, 184), Color.FromArgb(235, 245, 255));
        _currentValue.Dock = DockStyle.Left;
        _statusValue = new Label
        {
            Text = "仅读取显示器与发送 DDC/CI 硬件切换指令",
            ForeColor = SecondaryText,
            Dock = DockStyle.Fill,
            AutoEllipsis = true,
            TextAlign = ContentAlignment.MiddleLeft,
        };

        _windowsLabelBox = new FluentTextBox(settings.WindowsLabel);
        _macLabelBox = new FluentTextBox(settings.MacLabel);
        _hotkeyBox = new FluentTextBox(settings.HotkeyText) { ReadOnly = true };
        _hotkeyBox.InputKeyDown += CaptureHotkey;
        _startupCheck = FluentCheckBox("登录 Windows 时自动启动", StartupManager.IsEnabled());
        _automaticUpdatesCheck = FluentCheckBox("自动检查更新", settings.AutomaticallyChecksForUpdates);

        _scanButton = new FluentButton("扫描检测", FluentButtonKind.Secondary);
        _scanButton.Click += async (_, _) => await RunScanAsync();
        _switchButton = new FluentButton($"切换到 {settings.MacLabel}", FluentButtonKind.Primary);
        _switchButton.Click += async (_, _) => await RunSwitchAsync();

        _updateLabel = new Label
        {
            Dock = DockStyle.Fill,
            Font = new Font("Segoe UI Variable Text Semibold", 9.5F),
            ForeColor = Color.FromArgb(0, 95, 184),
            TextAlign = ContentAlignment.MiddleLeft,
        };
        _installUpdateButton = new FluentButton("立即更新", FluentButtonKind.Primary)
        {
            Dock = DockStyle.Right,
            Width = 100,
        };
        _installUpdateButton.Click += async (_, _) => await InstallUpdateAsync();
        _updateBanner = BuildUpdateBanner();

        var main = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(24, 20, 24, 18),
            BackColor = WindowSurface,
            ColumnCount = 1,
            RowCount = 7,
        };
        main.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 54));
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 185));
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 12));
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 124));
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 12));
        main.RowStyles.Add(new RowStyle(SizeType.Absolute, 175));
        main.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var header = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Margin = new Padding(8, 0, 0, 0),
            BackColor = WindowSurface,
        };
        header.Controls.Add(title);
        header.Controls.Add(subtitle);
        main.Controls.Add(header, 0, 0);
        main.Controls.Add(BuildHeroCard(), 0, 1);
        main.Controls.Add(BuildNamesCard(), 0, 3);
        main.Controls.Add(BuildPreferencesCard(), 0, 5);

        var footer = BuildFooter();
        main.Controls.Add(footer, 0, 6);
        Controls.Add(main);

        _updateManager.UpdateAvailable += HandleUpdateAvailable;
        FormClosed += (_, _) => _updateManager.UpdateAvailable -= HandleUpdateAvailable;
    }

    protected override void OnHandleCreated(EventArgs eventArgs)
    {
        base.OnHandleCreated(eventArgs);
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000)) return;
        var preference = NativeMethods.DwmWindowCorner.Round;
        _ = NativeMethods.DwmSetWindowAttribute(Handle, NativeMethods.DwmWindowCornerPreference, ref preference, sizeof(int));
        var backdrop = 2;
        _ = NativeMethods.DwmSetWindowAttribute(Handle, NativeMethods.DwmSystemBackdropType, ref backdrop, sizeof(int));
    }

    protected override void OnShown(EventArgs eventArgs)
    {
        base.OnShown(eventArgs);
        if (_updateManager.LatestRelease is { } release) ShowUpdate(release);
        _ = RunScanAsync();
    }

    private FluentCard BuildHeroCard()
    {
        var card = new FluentCard { Dock = DockStyle.Fill };
        var layout = CardLayout(4);
        layout.Padding = new Padding(16, 12, 16, 12);
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var monitorRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, BackColor = Color.White };
        monitorRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        monitorRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        monitorRow.Controls.Add(_monitorValue, 0, 0);
        monitorRow.Controls.Add(_connectionBadge, 1, 0);
        layout.Controls.Add(monitorRow, 0, 0);

        layout.Controls.Add(_displayModeValue, 0, 1);

        var inputArea = new Panel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(0, 5, 0, 5) };
        inputArea.Controls.Add(_currentValue);
        layout.Controls.Add(inputArea, 0, 2);

        var actions = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, BackColor = Color.White };
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 36));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 64));
        _scanButton.Dock = DockStyle.Fill;
        _scanButton.Margin = new Padding(0, 0, 6, 0);
        _switchButton.Dock = DockStyle.Fill;
        _switchButton.Margin = new Padding(6, 0, 0, 0);
        actions.Controls.Add(_scanButton, 0, 0);
        actions.Controls.Add(_switchButton, 1, 0);
        layout.Controls.Add(actions, 0, 3);
        card.Controls.Add(layout);
        return card;
    }

    private FluentCard BuildNamesCard()
    {
        var card = new FluentCard { Dock = DockStyle.Fill };
        var layout = CardLayout(2);
        layout.Padding = new Padding(16, 14, 16, 14);
        layout.ColumnCount = 2;
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 70));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(FieldEditor("Windows 名称", _windowsLabelBox, new Padding(0, 0, 7, 0)), 0, 0);
        layout.Controls.Add(FieldEditor("Mac 名称", _macLabelBox, new Padding(7, 0, 0, 0)), 1, 0);
        var caption = Caption("用于按钮和当前输入状态，不改变显示器端口映射");
        layout.SetColumnSpan(caption, 2);
        layout.Controls.Add(caption, 0, 1);
        card.Controls.Add(layout);
        return card;
    }

    private FluentCard BuildPreferencesCard()
    {
        var card = new FluentCard { Dock = DockStyle.Fill };
        var layout = CardLayout(4);
        layout.Padding = new Padding(16, 12, 16, 10);
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 49));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var hotkeyRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, BackColor = Color.White };
        hotkeyRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        hotkeyRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 170));
        hotkeyRow.Controls.Add(BodyLabel("全局切换快捷键"), 0, 0);
        _hotkeyBox.Dock = DockStyle.Fill;
        hotkeyRow.Controls.Add(_hotkeyBox, 1, 0);
        layout.Controls.Add(hotkeyRow, 0, 0);
        layout.Controls.Add(_startupCheck, 0, 1);

        var updateRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, BackColor = Color.White };
        updateRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        updateRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 104));
        updateRow.Controls.Add(_automaticUpdatesCheck, 0, 0);
        var checkButton = new FluentButton("检查更新", FluentButtonKind.Quiet) { Dock = DockStyle.Fill };
        checkButton.Click += async (_, _) => await CheckForUpdatesAsync(checkButton);
        updateRow.Controls.Add(checkButton, 1, 0);
        layout.Controls.Add(updateRow, 0, 2);
        layout.Controls.Add(Caption("只连接 GitHub Releases，不含遥测、账号或使用数据"), 0, 3);
        card.Controls.Add(layout);
        return card;
    }

    private Panel BuildUpdateBanner()
    {
        var banner = new Panel
        {
            Dock = DockStyle.Top,
            Height = 48,
            BackColor = Color.FromArgb(235, 245, 255),
            Padding = new Padding(12, 7, 8, 7),
            Visible = false,
        };
        banner.Controls.Add(_updateLabel);
        banner.Controls.Add(_installUpdateButton);
        return banner;
    }

    private Panel BuildFooter()
    {
        var panel = new Panel { Dock = DockStyle.Fill, BackColor = WindowSurface, Padding = new Padding(0, 8, 0, 0) };
        var footerRow = new Panel { Dock = DockStyle.Fill, BackColor = WindowSurface };
        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Right,
            Width = 230,
            FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false,
            BackColor = WindowSurface,
        };
        var save = new FluentButton("保存设置", FluentButtonKind.Primary) { Width = 112, Height = 38 };
        save.Click += (_, _) => SaveAndClose();
        var close = new FluentButton("关闭", FluentButtonKind.Secondary) { Width = 94, Height = 38, DialogResult = DialogResult.Cancel };
        close.Click += (_, _) => Close();
        buttons.Controls.Add(save);
        buttons.Controls.Add(close);
        footerRow.Controls.Add(_statusValue);
        footerRow.Controls.Add(buttons);
        panel.Controls.Add(footerRow);
        panel.Controls.Add(_updateBanner);
        AcceptButton = save;
        CancelButton = close;
        return panel;
    }

    private static TableLayoutPanel CardLayout(int rows) => new()
    {
        Dock = DockStyle.Fill,
        ColumnCount = 1,
        RowCount = rows,
        BackColor = Color.White,
    };

    private static Control FieldEditor(string title, FluentTextBox textBox, Padding margin)
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1, BackColor = Color.White, Margin = margin };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        panel.Controls.Add(FieldLabel(title), 0, 0);
        textBox.Dock = DockStyle.Fill;
        panel.Controls.Add(textBox, 0, 1);
        return panel;
    }

    private static Label FieldLabel(string text) => new()
    {
        Text = text,
        Font = new Font("Segoe UI Variable Text Semibold", 9F),
        ForeColor = SecondaryText,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
    };

    private static Label BodyLabel(string text) => new()
    {
        Text = text,
        ForeColor = PrimaryText,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
    };

    private static Label Caption(string text) => new()
    {
        Text = text,
        ForeColor = SecondaryText,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        Font = new Font("Segoe UI", 8.5F),
        AutoEllipsis = true,
    };

    private static CheckBox FluentCheckBox(string text, bool isChecked) => new()
    {
        Text = text,
        Checked = isChecked,
        Dock = DockStyle.Fill,
        FlatStyle = FlatStyle.System,
        ForeColor = PrimaryText,
        UseVisualStyleBackColor = true,
    };

    private async Task RunScanAsync()
    {
        _scanButton.Enabled = false;
        _statusValue.Text = "正在检测显示器与 DDC/CI…";
        try
        {
            var snapshot = await _scan();
            _monitorValue.Text = snapshot.Description;
            _displayModeValue.Text = $"原生：{snapshot.NativeResolutionText}   当前：{snapshot.CurrentModeText}";
            if (snapshot.IsDdcSupported)
            {
                _connectionBadge.SetAppearance("● 在线", Color.FromArgb(15, 123, 15), Color.FromArgb(233, 247, 233));
                _currentValue.Text = FriendlyInput(snapshot.CurrentInput);
                _switchButton.Enabled = true;
                _statusValue.Text = snapshot.AdvertisedInputs.Contains(_settings.MacInput)
                    ? $"已检测到 {InputSourceCatalog.ConnectorName(_settings.MacInput)}，可以执行切换"
                    : $"显示器未声明 {InputSourceCatalog.ConnectorName(_settings.MacInput)}，仍可按固定映射测试";
            }
            else
            {
                _connectionBadge.SetAppearance("DDC 不可读取", Color.FromArgb(164, 38, 44), Color.FromArgb(253, 237, 238));
                _currentValue.Text = "● 当前输入不可读取";
                _switchButton.Enabled = false;
                _statusValue.Text = "已识别显示器型号与分辨率，但 DDC/CI 未响应（请确认显示器开启 DDC/CI）";
            }
        }
        catch (Exception exception)
        {
            _connectionBadge.SetAppearance("不可用", Color.FromArgb(164, 38, 44), Color.FromArgb(253, 237, 238));
            _statusValue.Text = exception.Message;
        }
        finally
        {
            _scanButton.Enabled = true;
        }
    }

    private async Task RunSwitchAsync()
    {
        _switchButton.Enabled = false;
        _statusValue.Text = "正在发送切换命令…";
        try
        {
            await _switchToMac();
            _currentValue.Text = $"● {_settings.MacLabel} · {InputSourceCatalog.ConnectorName(_settings.MacInput)}";
            _statusValue.Text = $"已发送切换到 {_settings.MacLabel}";
        }
        catch (Exception exception)
        {
            _statusValue.Text = exception.Message;
        }
        finally
        {
            _switchButton.Enabled = true;
        }
    }

    private async Task CheckForUpdatesAsync(Control button)
    {
        button.Enabled = false;
        _statusValue.Text = "正在检查 GitHub Releases…";
        try
        {
            var release = await _updateManager.CheckForUpdatesAsync();
            _statusValue.Text = release is null ? "当前已是最新版本" : $"发现新版本 {release.TagName}";
            if (release is not null) ShowUpdate(release);
        }
        catch (Exception exception)
        {
            _statusValue.Text = $"检查更新失败：{exception.Message}";
        }
        finally
        {
            button.Enabled = true;
        }
    }

    private async Task InstallUpdateAsync()
    {
        var release = _updateManager.LatestRelease;
        if (release is null) return;
        if (MessageBox.Show(
                $"下载并安装 Lumen {release.TagName}？程序会自动重启。",
                "Lumen 更新",
                MessageBoxButtons.OKCancel,
                MessageBoxIcon.Information) != DialogResult.OK)
        {
            return;
        }

        _installUpdateButton.Enabled = false;
        _installUpdateButton.Text = "正在下载…";
        try
        {
            await _updateManager.DownloadAndInstallAsync(release);
            Application.Exit();
        }
        catch (Exception exception)
        {
            _statusValue.Text = $"更新失败：{exception.Message}";
            _installUpdateButton.Text = "重试更新";
            _installUpdateButton.Enabled = true;
        }
    }

    private void HandleUpdateAvailable(object? sender, UpdateRelease release)
    {
        if (IsDisposed || Disposing || !IsHandleCreated) return;
        if (InvokeRequired)
        {
            BeginInvoke(() => ShowUpdate(release));
            return;
        }
        ShowUpdate(release);
    }

    private void ShowUpdate(UpdateRelease release)
    {
        _updateLabel.Text = $"新版本 {release.TagName} 已发布";
        _updateBanner.Visible = true;
    }

    private string FriendlyInput(byte input) => input switch
    {
        var value when value == _settings.WindowsInput => $"● {_settings.WindowsLabel} · {InputSourceCatalog.ConnectorName(_settings.WindowsInput)}",
        var value when value == _settings.MacInput => $"● {_settings.MacLabel} · {InputSourceCatalog.ConnectorName(_settings.MacInput)}",
        _ => $"● {InputSourceCatalog.ConnectorName(input)}",
    };

    private void CaptureHotkey(object? sender, KeyEventArgs eventArgs)
    {
        eventArgs.SuppressKeyPress = true;
        if (eventArgs.KeyCode is Keys.ControlKey or Keys.Menu or Keys.ShiftKey or Keys.LWin or Keys.RWin) return;

        _pendingModifiers = 0;
        if (eventArgs.Control) _pendingModifiers |= HotkeyModifiers.Control;
        if (eventArgs.Alt) _pendingModifiers |= HotkeyModifiers.Alt;
        if (eventArgs.Shift) _pendingModifiers |= HotkeyModifiers.Shift;
        if ((ModifierKeys & Keys.LWin) != 0 || (ModifierKeys & Keys.RWin) != 0) _pendingModifiers |= HotkeyModifiers.Win;
        _pendingKey = eventArgs.KeyCode;

        var preview = new AppSettings { HotkeyModifiers = _pendingModifiers, HotkeyKey = _pendingKey };
        _hotkeyBox.Text = preview.HotkeyText;
    }

    private void SaveAndClose()
    {
        if (_pendingModifiers == 0)
        {
            _statusValue.Text = "快捷键至少需要一个修饰键";
            return;
        }

        _settings.HotkeyModifiers = _pendingModifiers;
        _settings.HotkeyKey = _pendingKey;
        _settings.WindowsLabel = string.IsNullOrWhiteSpace(_windowsLabelBox.Text) ? "Windows" : _windowsLabelBox.Text.Trim();
        _settings.MacLabel = string.IsNullOrWhiteSpace(_macLabelBox.Text) ? "Mac" : _macLabelBox.Text.Trim();
        _settings.AutomaticallyChecksForUpdates = _automaticUpdatesCheck.Checked;
        try
        {
            _save(_settings);
            StartupManager.SetEnabled(_startupCheck.Checked);
            Close();
        }
        catch (Exception exception)
        {
            _statusValue.Text = exception.Message;
        }
    }
}
