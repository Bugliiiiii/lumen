# Monitor Switch

Monitor Switch is a pair of small native tray apps for one desk setup:

- KTC H27T22S
- Windows PC with an RTX 4060 Ti on DisplayPort 1
- M5 MacBook Air on HDMI 1 through a UGREEN USB-C to HDMI cable

Both apps send DDC/CI input-source commands directly through the display cable. They do not share the screen, stream video, control the keyboard or mouse, or communicate over the network.

## Default shortcuts

| Platform | Shortcut | Action |
| --- | --- | --- |
| Windows | `Ctrl + Alt + S` | Switch to Mac on HDMI 1 |
| macOS | `Option + Command + S` | Switch to Windows on DisplayPort 1 |

The shortcuts and input labels can be changed in each app. The first scan is read-only. Monitor Switch never cycles through unknown input values automatically.

## Input mapping

Monitor Switch uses the standard MCCS input-source VCP code `0x60`.

| Friendly name | Connector | Value |
| --- | --- | --- |
| Windows | DisplayPort 1 | `0x0F` |
| Mac | HDMI 1 | `0x11` |

These are the standard MCCS values and the defaults for this setup. The monitor still has to accept input-source writes over both cable paths. In particular, the UGREEN USB-C to HDMI cable must pass DDC/CI traffic.

## Build macOS

Requirements:

- Apple Silicon Mac
- Swift 6 or newer
- Internet access for the pinned AppleSiliconDDC package on the first build

```sh
cd apps/macos
swift run MonitorSwitchMac --self-test
./scripts/build-app.sh
open artifacts/Monitor\ Switch.app
```

Move the built app to `/Applications` before enabling "Launch at login".

## Build Windows

Requirements:

- Windows 10 or 11
- .NET 8 SDK

```powershell
dotnet run --project apps/windows/tests/MonitorSwitch.Windows.Tests/MonitorSwitch.Windows.Tests.csproj
dotnet publish apps/windows/src/MonitorSwitch.Windows/MonitorSwitch.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o artifacts/windows
```

Run `MonitorSwitch.Windows.exe`. It stays in the notification area and does not require administrator rights.

## Before the first switch

1. Enable DDC/CI in the H27T22S on-screen menu if that setting is present.
2. Open Monitor Switch and run "Scan display" on each computer.
3. Confirm that the app reads the current input.
4. Test Windows to Mac first. Then test Mac to Windows.

If the Mac scan cannot read input `0x60`, the USB-C to HDMI conversion is not forwarding DDC/CI. The app reports that failure without attempting a blind write.

## Privacy

Monitor Switch has no networking, analytics, account, telemetry, or updater. Settings remain in the current user's local application data.

## Dependency

The macOS client uses [waydabber/AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) at a pinned revision under its MIT license.
