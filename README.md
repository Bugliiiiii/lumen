# Lumen

> *Lumen* — 拉丁语"光"，物理学中光通量的单位。每一束抵达屏幕的信号，都值得被最纯净地呈现。

Lumen 是一款轻量原生的显示器控制中心，为 macOS (Apple Silicon) 和 Windows 10/11 提供菜单栏 / 系统托盘常驻应用。

## 核心能力

### 🔀 一键切换输入源

通过 DDC/CI 协议直接向显示器发送 MCCS VCP `0x60` 指令，在 DisplayPort 和 HDMI 之间瞬间切换，无需触碰显示器按钮。两台电脑共享一块屏幕，一键穿梭。

### 🔍 2K HiDPI 视网膜级缩放

深度集成 macOS SkyLight / CGSDisplayServices 私有框架，为 2K / 4K 外接显示器注入 HiDPI 模式，实现无模糊的视网膜级清晰文字渲染，告别原生缩放的颗粒感。

### 🎛️ 硬件级亮度与音量调节

遵循 MCCS 安全规范，通过 DDC/CI 硬件通道直接控制屏幕亮度 (VCP `0x10`) 和音频音量 (VCP `0x62`)，支持滑块平滑调节。

### 🖥️ 拖拽式屏幕排列

控制中心内置交互式屏幕排列面板，支持直接拖动屏幕缩略图完成多显示器物理位置排列，自动边缘吸附，一键设置主显示器。

### 🪟 Liquid Glass 毛玻璃视觉

菜单栏弹出面板采用 macOS 原生 `NSVisualEffectView` 深度亚克力毛玻璃底衬，搭配半透明卡片与精致边框，呈现控制中心级的视觉质感。

## 快速开始

### macOS (Apple Silicon)

从 [Releases](https://github.com/Bugliiiiii/switch-monitor/releases) 下载 `Lumen-macOS-arm64.zip`，解压后拖入 `/Applications` 即可使用。

### Windows (x64)

从 [Releases](https://github.com/Bugliiiiii/switch-monitor/releases) 下载 `Lumen-Windows-x64.exe`，运行后常驻系统通知区域，无需管理员权限。

## 默认快捷键

| 平台 | 快捷键 | 动作 |
| --- | --- | --- |
| Windows | `Ctrl + Alt + S` | 切换到 Mac (HDMI 1) |
| macOS | `⌥ ⌘ S` | 切换到 Windows (DisplayPort 1) |

快捷键和输入源标签均可在各平台应用内自定义。

## 输入映射

Lumen 使用标准 MCCS 输入源 VCP 码 `0x60`：

| 名称 | 接口 | 值 |
| --- | --- | --- |
| Windows | DisplayPort 1 | `0x0F` |
| Mac | HDMI 1 | `0x11` |

## 从源码构建

### macOS

要求：Apple Silicon Mac，Swift 6+

```sh
cd apps/macos
swift run MonitorSwitchMac --self-test   # 运行自检
./scripts/build-app.sh                   # 构建 Lumen.app
open artifacts/Lumen.app
```

### Windows

要求：Windows 10/11，.NET 8 SDK

```powershell
dotnet run --project apps/windows/tests/MonitorSwitch.Windows.Tests/MonitorSwitch.Windows.Tests.csproj
dotnet publish apps/windows/src/MonitorSwitch.Windows/MonitorSwitch.Windows.csproj `
  -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o artifacts/windows
```

## 首次使用前

1. 在显示器 OSD 菜单中开启 DDC/CI（如果有此选项）。
2. 打开 Lumen，在两台电脑上分别执行一次「扫描显示器」。
3. 确认应用能正确读取当前输入源。
4. 先测试 Windows → Mac 切换，再测试 Mac → Windows。

> 如果 Mac 端扫描无法读取 VCP `0x60`，说明 USB-C 转 HDMI 线缆未透传 DDC/CI 信号。Lumen 会报告该失败，不会尝试盲写。

## 安全边界

- 显示器发现与输入扫描严格只读，绝不通过循环写入来探测端口。
- 仅写入三个 VCP 码：`0x60`（输入切换，仅响应明确的按钮或快捷键）、`0x10`（亮度）、`0x62`（音量）。
- 不包含任何网络通信、遥测上报、远程桌面、视频传输或键鼠共享功能。

## 隐私

Lumen 没有网络连接、分析追踪、账户体系、遥测上报或自动更新。所有配置仅存储在当前用户的本地应用数据目录中。

## 依赖

macOS 客户端使用 [waydabber/AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC)（MIT 许可证，锁定特定版本）。

## 许可证

MIT
