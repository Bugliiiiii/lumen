import AppKit
import Foundation
import SwiftUI

enum SelfTest {
    @MainActor
    static func run() -> Int32 {
        do {
            try checkDefaults()
            try checkConnectorNames()
            try checkSettingsRoundTrip()
            try renderSettingsView()
            try renderControlCenterView()
            print("MonitorSwitchMac self-test: 14 assertions passed")
            return 0
        } catch {
            fputs("MonitorSwitchMac self-test failed: \(error)\n", stderr)
            return 1
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestError.assertion(message) }
    }

    private static func checkDefaults() throws {
        let settings = AppSettings()
        try require(settings.windowsInput == 0x0F, "Windows input must be DP1")
        try require(settings.macInput == 0x11, "Mac input must be HDMI1")
        try require(settings.shortcutText == "⌥⌘S", "default shortcut must be Option-Command-S")
    }

    private static func checkConnectorNames() throws {
        try require(InputSourceCatalog.connectorName(for: 0x0F) == "DisplayPort 1", "DP1 name")
        try require(InputSourceCatalog.connectorName(for: 0x10) == "DisplayPort 2", "DP2 name")
        try require(InputSourceCatalog.connectorName(for: 0x11) == "HDMI 1", "HDMI1 name")
        try require(InputSourceCatalog.connectorName(for: 0x12) == "HDMI 2", "HDMI2 name")
        try require(InputSourceCatalog.connectorName(for: 0x7F) == "Input 127", "unknown input name")
    }

    private static func checkSettingsRoundTrip() throws {
        let suiteName = "MonitorSwitchMacSelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestError.assertion("temporary defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var expected = AppSettings()
        expected.windowsLabel = "工作电脑"
        expected.shortcutKey = "K"
        try SettingsStore.save(expected, defaults: defaults)
        try require(SettingsStore.load(defaults: defaults) == expected, "settings round trip")
    }

    @MainActor
    private static func renderSettingsView() throws {
        let model = AppModel()
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        let size = hostingView.fittingSize
        try require(size.width <= 460, "settings width is \(size.width)")
        try require(size.height <= 680, "settings height is \(size.height)")
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SelfTestError.assertion("settings bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw SelfTestError.assertion("settings PNG")
        }
        try require(png.count > 10_000, "settings PNG is empty")
        try png.write(to: URL(fileURLWithPath: "/private/tmp/monitor-switch-settings-preview.png"), options: .atomic)
    }

    @MainActor
    private static func renderControlCenterView() throws {
        let model = AppModel()
        let view = ControlCenterPanelView(
            appModel: model,
            onOpenSettings: {},
            onQuit: {}
        )
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize
        try require(size.width <= 360, "control center width is \(size.width)")
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SelfTestError.assertion("control center bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw SelfTestError.assertion("control center PNG")
        }
        try require(png.count > 5_000, "control center PNG is empty")
        try png.write(to: URL(fileURLWithPath: "/private/tmp/monitor-switch-cc-preview.png"), options: .atomic)
    }
}

private enum SelfTestError: LocalizedError {
    case assertion(String)

    var errorDescription: String? {
        switch self {
        case .assertion(let message): "assertion failed: \(message)"
        }
    }
}
