using System.Drawing.Drawing2D;
using System.Diagnostics.CodeAnalysis;

namespace MonitorSwitch.Windows;

internal enum FluentButtonKind { Primary, Secondary, Quiet }

internal sealed class FluentCard : Panel
{
    internal FluentCard()
    {
        BackColor = Color.Transparent;
        Padding = new Padding(1);
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = RoundedPath(ClientRectangle, 9);
        using var fill = new SolidBrush(Color.White);
        using var border = new Pen(Color.FromArgb(229, 229, 229));
        eventArgs.Graphics.FillPath(fill, path);
        eventArgs.Graphics.DrawPath(border, path);
    }

    internal static GraphicsPath RoundedPath(Rectangle bounds, int radius)
    {
        var path = new GraphicsPath();
        var diameter = radius * 2;
        var rect = Rectangle.Inflate(bounds, -1, -1);
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}

internal sealed class FluentButton : Button
{
    private readonly FluentButtonKind _kind;
    private bool _hovered;
    private bool _pressed;

    internal FluentButton(string text, FluentButtonKind kind)
    {
        Text = text;
        _kind = kind;
        Height = 38;
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        UseVisualStyleBackColor = false;
        Font = new Font("Segoe UI Variable Text Semibold", 9.5F);
        Cursor = Cursors.Hand;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }

    protected override void OnMouseEnter(EventArgs eventArgs) { _hovered = true; Invalidate(); base.OnMouseEnter(eventArgs); }
    protected override void OnMouseLeave(EventArgs eventArgs) { _hovered = false; _pressed = false; Invalidate(); base.OnMouseLeave(eventArgs); }
    protected override void OnMouseDown(MouseEventArgs eventArgs) { _pressed = true; Invalidate(); base.OnMouseDown(eventArgs); }
    protected override void OnMouseUp(MouseEventArgs eventArgs) { _pressed = false; Invalidate(); base.OnMouseUp(eventArgs); }
    protected override void OnEnabledChanged(EventArgs eventArgs) { Invalidate(); base.OnEnabledChanged(eventArgs); }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var (background, foreground, border) = Colors();
        using var path = FluentCard.RoundedPath(ClientRectangle, 6);
        using var fill = new SolidBrush(background);
        using var stroke = new Pen(border);
        eventArgs.Graphics.FillPath(fill, path);
        eventArgs.Graphics.DrawPath(stroke, path);
        TextRenderer.DrawText(eventArgs.Graphics, Text, Font, ClientRectangle, foreground,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        if (Focused && ShowFocusCues)
        {
            ControlPaint.DrawFocusRectangle(eventArgs.Graphics, Rectangle.Inflate(ClientRectangle, -4, -4), foreground, background);
        }
    }

    private (Color Background, Color Foreground, Color Border) Colors()
    {
        if (!Enabled) return (Color.FromArgb(242, 242, 242), Color.FromArgb(160, 160, 160), Color.FromArgb(232, 232, 232));
        return _kind switch
        {
            FluentButtonKind.Primary when _pressed => (Color.FromArgb(0, 95, 184), Color.White, Color.FromArgb(0, 95, 184)),
            FluentButtonKind.Primary when _hovered => (Color.FromArgb(25, 117, 210), Color.White, Color.FromArgb(25, 117, 210)),
            FluentButtonKind.Primary => (Color.FromArgb(0, 103, 192), Color.White, Color.FromArgb(0, 103, 192)),
            FluentButtonKind.Quiet when _pressed => (Color.FromArgb(224, 224, 224), Color.FromArgb(0, 95, 184), Color.Transparent),
            FluentButtonKind.Quiet when _hovered => (Color.FromArgb(240, 240, 240), Color.FromArgb(0, 95, 184), Color.Transparent),
            FluentButtonKind.Quiet => (Color.White, Color.FromArgb(0, 95, 184), Color.Transparent),
            _ when _pressed => (Color.FromArgb(232, 232, 232), Color.FromArgb(31, 31, 31), Color.FromArgb(196, 196, 196)),
            _ when _hovered => (Color.FromArgb(249, 249, 249), Color.FromArgb(31, 31, 31), Color.FromArgb(205, 205, 205)),
            _ => (Color.White, Color.FromArgb(31, 31, 31), Color.FromArgb(216, 216, 216)),
        };
    }
}

internal sealed class FluentTextBox : UserControl
{
    private readonly TextBox _input;
    private bool _focused;

    internal FluentTextBox(string text)
    {
        Height = 36;
        BackColor = Color.White;
        Padding = new Padding(10, 7, 10, 5);
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        _input = new TextBox
        {
            Text = text,
            BorderStyle = BorderStyle.None,
            Dock = DockStyle.Fill,
            BackColor = Color.White,
            ForeColor = Color.FromArgb(31, 31, 31),
            Font = new Font("Segoe UI", 9.5F),
        };
        _input.Enter += (_, _) => { _focused = true; Invalidate(); };
        _input.Leave += (_, _) => { _focused = false; Invalidate(); };
        _input.KeyDown += (_, eventArgs) => InputKeyDown?.Invoke(this, eventArgs);
        Controls.Add(_input);
    }

    [AllowNull]
    public override string Text { get => _input?.Text ?? string.Empty; set { if (_input is not null) _input.Text = value ?? string.Empty; } }
    internal bool ReadOnly
    {
        get => _input.ReadOnly;
        set
        {
            _input.ReadOnly = value;
            _input.ShortcutsEnabled = !value;
        }
    }
    internal event KeyEventHandler? InputKeyDown;

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = FluentCard.RoundedPath(ClientRectangle, 6);
        using var border = new Pen(_focused ? Color.FromArgb(0, 103, 192) : Color.FromArgb(210, 210, 210), _focused ? 2F : 1F);
        eventArgs.Graphics.DrawPath(border, path);
    }
}

internal sealed class PillLabel : Label
{
    private Color _fillColor;

    internal PillLabel(string text, Color foreground, Color fill)
    {
        ForeColor = foreground;
        _fillColor = fill;
        AutoSize = false;
        Height = 28;
        Padding = new Padding(10, 0, 10, 0);
        TextAlign = ContentAlignment.MiddleCenter;
        Font = new Font("Segoe UI Variable Text Semibold", 9F);
        Text = text;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }

    internal void SetAppearance(string text, Color foreground, Color fill)
    {
        Text = text;
        ForeColor = foreground;
        _fillColor = fill;
        Invalidate();
    }

    protected override void OnTextChanged(EventArgs eventArgs)
    {
        base.OnTextChanged(eventArgs);
        Width = TextRenderer.MeasureText(Text, Font).Width + 24;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = FluentCard.RoundedPath(ClientRectangle, Height / 2);
        using var brush = new SolidBrush(_fillColor);
        eventArgs.Graphics.FillPath(brush, path);
        TextRenderer.DrawText(eventArgs.Graphics, Text, Font, ClientRectangle, ForeColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
    }
}
