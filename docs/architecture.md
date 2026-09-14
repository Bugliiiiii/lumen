# Architecture

## Product boundary

Lumen controls one or more external monitors: switching active input connectors, adjusting brightness and volume via DDC/CI, injecting HiDPI modes, and rearranging display positions. It does not switch USB devices, move pointer input, transmit pixels, or contact another computer.

## Data flow

```text
global shortcut, tray action, or control center slider
          |
          v
local platform app
          |
          v
DDC/CI VCP through the active display cable
          |
          v
monitor applies input switch / brightness / volume
```

The two platform clients never communicate with each other. Each one operates independently on its connected display.

## Safety rules

- Discovery reads monitor identity, capabilities, and current VCP values.
- Discovery never writes a candidate value.
- Input switching (`0x60`) only happens after a tray action, button press, or registered shortcut.
- Brightness (`0x10`) and volume (`0x62`) only change in response to explicit slider interaction.
- The app writes one configured value and does not retry with different inputs.
- A successful input-source write is not read back because changing input can remove the original DDC path before verification completes.
- Errors contain the failed operation but no machine identity or personal path.

## Platform implementation

### Windows

The Windows client uses `EnumDisplayMonitors`, the physical-monitor functions in `Dxva2.dll`, and `SetVCPFeature`. It uses `RegisterHotKey` for the global shortcut and the current user's `Run` registry key for launch at login.

### macOS

The macOS client uses AppKit for the menu bar, SwiftUI for the settings panel, Carbon's hot-key registration, and `SMAppService` for launch at login. DDC access comes from the MIT-licensed AppleSiliconDDC package, which uses the Apple Silicon `IOAVService` path. HiDPI injection uses the private SkyLight / CGSDisplayServices frameworks.

## Local settings

Both apps store only:

- selected display identity
- friendly input labels
- DP1 and HDMI1 values
- global shortcut
- launch-at-login choice
- brightness and volume levels (macOS)
- HiDPI mode preferences (macOS)

No settings are synchronized between computers.
