using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace MonitorSwitch.Windows;

internal static class IconFactory
{
    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);

    internal static Icon Create()
    {
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.Clear(Color.Transparent);
            using var screen = new SolidBrush(Color.FromArgb(38, 92, 138));
            using var stand = new Pen(Color.FromArgb(38, 92, 138), 3);
            graphics.FillRoundedRectangle(screen, new RectangleF(2, 4, 28, 19), 4);
            graphics.DrawLine(stand, 16, 23, 16, 28);
            graphics.DrawLine(stand, 10, 28, 22, 28);
            using var light = new SolidBrush(Color.FromArgb(225, 238, 248));
            graphics.FillEllipse(light, 22, 7, 4, 4);
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var temporary = Icon.FromHandle(handle);
            return (Icon)temporary.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    private static void FillRoundedRectangle(this Graphics graphics, Brush brush, RectangleF bounds, float radius)
    {
        using var path = new GraphicsPath();
        var diameter = radius * 2;
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        graphics.FillPath(brush, path);
    }
}
