namespace MonitorSwitch.Windows;

internal sealed class SettingsForm : Form
{
    private readonly AppSettings _settings;
    private readonly Func<Task<MonitorSnapshot>> _scan;
    private readonly Func<Task> _switchToMac;
    private readonly Action<AppSettings> _save;
    private readonly Label _monitorValue;
    private readonly Label _currentValue;
    private readonly Label _statusValue;
    private readonly TextBox _hotkeyBox;
    private readonly CheckBox _startupCheck;
    private readonly TextBox _windowsLabelBox;
    private readonly TextBox _macLabelBox;
    private HotkeyModifiers _pendingModifiers;
    private Keys _pendingKey;

    internal SettingsForm(
        AppSettings settings,
        Func<Task<MonitorSnapshot>> scan,
        Func<Task> switchToMac,
        Action<AppSettings> save)
    {
        _settings = settings;
        _scan = scan;
        _switchToMac = switchToMac;
        _save = save;
        _pendingModifiers = settings.HotkeyModifiers;
        _pendingKey = settings.HotkeyKey;

        Text = "Monitor Switch";
        Font = new Font("Segoe UI", 10F);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(430, 570);
        BackColor = Color.FromArgb(247, 249, 251);
        Padding = new Padding(28, 24, 28, 24);

        var title = new Label
        {
            Text = "Monitor Switch",
            Font = new Font("Segoe UI Semibold", 20F),
            ForeColor = Color.FromArgb(25, 38, 50),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 4),
        };
        var subtitle = new Label
        {
            Text = "KTC H27T22S 输入切换",
            ForeColor = Color.FromArgb(91, 105, 117),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 22),
        };

        _monitorValue = ValueLabel("等待扫描");
        _currentValue = ValueLabel("未知");
        _statusValue = ValueLabel("仅读取显示器，不会自动切换");
        _statusValue.ForeColor = Color.FromArgb(91, 105, 117);

        _windowsLabelBox = NameBox(settings.WindowsLabel);
        _macLabelBox = NameBox(settings.MacLabel);

        var scanButton = SecondaryButton("扫描显示器");
        scanButton.Click += async (_, _) => await RunScanAsync(scanButton);

        var switchButton = PrimaryButton("切换到 Mac");
        switchButton.Click += async (_, _) => await RunSwitchAsync(switchButton);

        _hotkeyBox = new TextBox
        {
            ReadOnly = true,
            ShortcutsEnabled = false,
            Text = settings.HotkeyText,
            Height = 34,
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle,
            Margin = new Padding(0, 5, 0, 0),
        };
        _hotkeyBox.KeyDown += CaptureHotkey;

        _startupCheck = new CheckBox
        {
            Text = "登录 Windows 时启动",
            Checked = StartupManager.IsEnabled(),
            AutoSize = true,
            Margin = new Padding(0, 12, 0, 0),
        };

        var saveButton = SecondaryButton("保存设置");
        saveButton.Click += (_, _) => SaveAndClose();

        var content = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 18,
            AutoSize = false,
            AutoScroll = true,
        };
        content.Controls.Add(title);
        content.Controls.Add(subtitle);
        content.Controls.Add(FieldLabel("当前显示器"));
        content.Controls.Add(_monitorValue);
        content.Controls.Add(FieldLabel("当前输入"));
        content.Controls.Add(_currentValue);
        content.Controls.Add(FieldLabel("输入源名称"));
        var names = new TableLayoutPanel { Dock = DockStyle.Top, ColumnCount = 2, AutoSize = true };
        names.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        names.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        names.Controls.Add(_windowsLabelBox, 0, 0);
        names.Controls.Add(_macLabelBox, 1, 0);
        content.Controls.Add(names);
        content.Controls.Add(scanButton);
        content.Controls.Add(switchButton);
        content.Controls.Add(FieldLabel("全局快捷键"));
        content.Controls.Add(_hotkeyBox);
        content.Controls.Add(_startupCheck);
        content.Controls.Add(_statusValue);
        content.Controls.Add(saveButton);
        Controls.Add(content);
        AcceptButton = saveButton;
    }

    private static Label FieldLabel(string text) => new()
    {
        Text = text,
        Font = new Font("Segoe UI Semibold", 9F),
        ForeColor = Color.FromArgb(91, 105, 117),
        AutoSize = true,
        Margin = new Padding(0, 8, 0, 0),
    };

    private static Label ValueLabel(string text) => new()
    {
        Text = text,
        Font = new Font("Segoe UI Semibold", 11F),
        ForeColor = Color.FromArgb(25, 38, 50),
        AutoSize = true,
        Margin = new Padding(0, 2, 0, 4),
    };

    private static Button PrimaryButton(string text) => new()
    {
        Text = text,
        Height = 42,
        Dock = DockStyle.Top,
        FlatStyle = FlatStyle.Flat,
        BackColor = Color.FromArgb(38, 92, 138),
        ForeColor = Color.White,
        Font = new Font("Segoe UI Semibold", 10F),
        Margin = new Padding(0, 8, 0, 4),
        UseVisualStyleBackColor = false,
    };

    private static TextBox NameBox(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        Height = 32,
        Margin = new Padding(0, 4, 8, 4),
        BorderStyle = BorderStyle.FixedSingle,
    };

    private static Button SecondaryButton(string text) => new()
    {
        Text = text,
        Height = 38,
        Dock = DockStyle.Top,
        FlatStyle = FlatStyle.Flat,
        BackColor = Color.White,
        ForeColor = Color.FromArgb(38, 92, 138),
        Font = new Font("Segoe UI Semibold", 9F),
        Margin = new Padding(0, 8, 0, 4),
        UseVisualStyleBackColor = false,
    };

    private async Task RunScanAsync(Control button)
    {
        button.Enabled = false;
        _statusValue.Text = "正在读取 DDC/CI…";
        try
        {
            var snapshot = await _scan();
            _monitorValue.Text = snapshot.Description;
            _currentValue.Text = FriendlyInput(snapshot.CurrentInput);
            _statusValue.Text = snapshot.AdvertisedInputs.Contains(_settings.MacInput)
                ? "已检测到 HDMI 1，可以执行切换"
                : "显示器未声明 HDMI 1，仍可按固定映射测试";
        }
        catch (Exception exception)
        {
            _statusValue.Text = exception.Message;
        }
        finally
        {
            button.Enabled = true;
        }
    }

    private async Task RunSwitchAsync(Control button)
    {
        button.Enabled = false;
        _statusValue.Text = "正在发送切换命令…";
        try
        {
            await _switchToMac();
            _statusValue.Text = "已发送切换到 Mac";
        }
        catch (Exception exception)
        {
            _statusValue.Text = exception.Message;
        }
        finally
        {
            button.Enabled = true;
        }
    }

    private string FriendlyInput(byte input) => input switch
    {
        var value when value == _settings.WindowsInput => $"● {_settings.WindowsLabel} · DisplayPort 1",
        var value when value == _settings.MacInput => $"● {_settings.MacLabel} · HDMI 1",
        _ => $"● {InputSourceCatalog.ConnectorName(input)}",
    };

    private void CaptureHotkey(object? sender, KeyEventArgs eventArgs)
    {
        eventArgs.SuppressKeyPress = true;
        if (eventArgs.KeyCode is Keys.ControlKey or Keys.Menu or Keys.ShiftKey or Keys.LWin or Keys.RWin)
        {
            return;
        }

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
