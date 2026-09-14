# Architecture

## Product boundary

Monitor Switch changes one external monitor's active connector. It does not switch USB devices, move pointer input, transmit pixels, or contact another computer.

## Data flow

```text
global shortcut or tray action
          |
          v
local platform app
          |
          v
DDC/CI VCP 0x60 through the active display cable
          |
          v
KTC H27T22S selects DP1 or HDMI1
```

The two clients never communicate with each other. Each one only needs to switch away from its currently visible input.

## Safety rules

- Discovery reads monitor identity, capabilities, and the current value of VCP `0x60`.
- Discovery never writes a candidate value.
- A write only happens after a tray action, button press, or registered shortcut.
- The app writes one configured value and does not retry with different inputs.
- A successful write is not read back because changing input can remove the original DDC path before verification completes.
- Errors contain the failed operation but no machine identity or personal path.

## Platform implementation

### Windows

The Windows client uses `EnumDisplayMonitors`, the physical-monitor functions in `Dxva2.dll`, and `SetVCPFeature`. It uses `RegisterHotKey` for the global shortcut and the current user's `Run` registry key for launch at login.

### macOS

The macOS client uses AppKit for the menu bar, SwiftUI for the settings panel, Carbon's hot-key registration, and `SMAppService` for launch at login. DDC access comes from the MIT-licensed AppleSiliconDDC package, which uses the Apple Silicon `IOAVService` path.

## Local settings

Both apps store only:

- selected display identity
- friendly input labels
- DP1 and HDMI1 values
- global shortcut
- launch-at-login choice

No settings are synchronized between computers.
