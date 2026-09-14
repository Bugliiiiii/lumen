# Project Rules

## Safety boundaries

- Display discovery and input scanning must stay read-only. Never discover ports by cycling through input values.
- Write only MCCS VCP codes `0x60` (input select, only on explicit button/hotkey), `0x10` (brightness slider), and `0x62` (audio volume slider).
- Keep the default hardware mapping aligned with this project: Windows on DisplayPort 1 (`0x0F`) and Mac on HDMI 1 (`0x11`).
- Networking is limited to read-only update checks and release downloads from the official `Bugliiiiii/lumen` GitHub Releases endpoints. Do not add telemetry, remote desktop, video transport, or keyboard/mouse sharing.
- Verify downloaded release assets against `SHA256SUMS.txt` before presenting or applying an update.
- A failed settings or hotkey update must preserve the last working configuration when possible.

## Verification

- macOS: `cd apps/macos && swift run --configuration debug MonitorSwitchMac --self-test`
- macOS package: `cd apps/macos && ./scripts/build-app.sh`
- Windows: `dotnet build apps/windows/src/MonitorSwitch.Windows/MonitorSwitch.Windows.csproj --configuration Release`
- Windows tests: `dotnet run --project apps/windows/tests/MonitorSwitch.Windows.Tests/MonitorSwitch.Windows.Tests.csproj --configuration Release`
