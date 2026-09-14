using System.ComponentModel;

namespace MonitorSwitch.Windows;

internal sealed class HotkeyWindow : NativeWindow, IDisposable
{
    private const int HotkeyId = 1;
    private Action? _handler;
    private bool _registered;
    private uint _registeredModifiers;
    private uint _registeredKey;

    internal HotkeyWindow()
    {
        CreateHandle(new CreateParams());
    }

    internal void Register(AppSettings settings, Action handler)
    {
        var previousRegistered = _registered;
        var previousModifiers = _registeredModifiers;
        var previousKey = _registeredKey;
        var previousHandler = _handler;
        Unregister();
        var modifiers = (uint)settings.HotkeyModifiers | NativeMethods.ModNoRepeat;
        if (!NativeMethods.RegisterHotKey(Handle, HotkeyId, modifiers, (uint)settings.HotkeyKey))
        {
            if (previousRegistered && NativeMethods.RegisterHotKey(Handle, HotkeyId, previousModifiers, previousKey))
            {
                _registered = true;
                _registeredModifiers = previousModifiers;
                _registeredKey = previousKey;
                _handler = previousHandler;
            }
            throw new InvalidOperationException(
                $"快捷键 {settings.HotkeyText} 已被其他程序占用。",
                new Win32Exception());
        }

        _handler = handler;
        _registered = true;
        _registeredModifiers = modifiers;
        _registeredKey = (uint)settings.HotkeyKey;
    }

    internal void Unregister()
    {
        if (!_registered) return;
        NativeMethods.UnregisterHotKey(Handle, HotkeyId);
        _registered = false;
        _handler = null;
        _registeredModifiers = 0;
        _registeredKey = 0;
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == NativeMethods.WmHotkey && message.WParam.ToInt32() == HotkeyId)
        {
            _handler?.Invoke();
        }
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        Unregister();
        DestroyHandle();
    }
}
