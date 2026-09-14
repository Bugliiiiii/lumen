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
            try checkInputStatusSynchronizer()
            try renderSettingsView()
            try renderUpdateBanner()
            try renderControlCenterView()
            print("MonitorSwitchMac self-test: 27 assertions passed")
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
        try require(settings.automaticallyChecksForUpdates, "automatic update checks enabled by default")
        try require(UpdateService.isVersionNewer("v0.4.0", than: "0.3.0"), "newer release version")
        try require(!UpdateService.isVersionNewer("v0.3.0", than: "0.3.0"), "same release version")
        try require(UpdateService.isVersionNewer("v1.0", than: "0.9.9"), "major release version")
        try require(!UpdateService.isVersionNewer("invalid", than: "0.3.0"), "invalid release version")
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
        expected.automaticallyChecksForUpdates = false
        try SettingsStore.save(expected, defaults: defaults)
        try require(SettingsStore.load(defaults: defaults) == expected, "settings round trip")
    }

    @MainActor
    private static func checkInputStatusSynchronizer() throws {
        var refreshCount = 0
        let synchronizer = InputStatusSynchronizer(interval: .seconds(60)) {
            refreshCount += 1
        }
        synchronizer.start()
        try require(refreshCount == 1, "input status sync must refresh immediately when panel opens")
        try require(synchronizer.isRunning, "input status sync must run while panel is visible")
        synchronizer.stop()
        try require(!synchronizer.isRunning, "input status sync must stop when panel closes")
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
    private static func renderUpdateBanner() throws {
        let release = UpdateRelease(
            version: VersionNumber("0.4.0")!,
            tagName: "v0.4.0",
            downloadURL: URL(string: "https://github.com/Bugliiiiii/lumen/releases/download/v0.4.0/Lumen-macOS-arm64.dmg")!,
            downloadSize: 2_000_000,
            checksumURL: URL(string: "https://github.com/Bugliiiiii/lumen/releases/download/v0.4.0/SHA256SUMS.txt")!,
            releasePageURL: URL(string: "https://github.com/Bugliiiiii/lumen/releases/tag/v0.4.0")!
        )
        let service = UpdateService(initialRelease: release)
        let hostingView = NSHostingView(rootView: UpdateBannerView(service: service))
        let size = hostingView.fittingSize
        try require(size.width <= 420, "update banner width is \(size.width)")
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SelfTestError.assertion("update banner PNG")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let renderedPNG = representation.representation(using: .png, properties: [:]) else {
            throw SelfTestError.assertion("rendered update banner PNG")
        }
        try require(renderedPNG.count > 1_000, "update banner PNG is empty")
        try renderedPNG.write(to: URL(fileURLWithPath: "/private/tmp/monitor-switch-update-preview.png"), options: .atomic)
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
        try png.write(to: URL(fileURLWithPath: "/private/tmp/monitor-switch-cc-preview.png"), options: .atomic)

        // Test dual-display rendering
        let originalDisplays = ResolutionController.shared.displays
        defer { ResolutionController.shared.displays = originalDisplays }

        let mockMode = DisplayModeItem(modeNumber: 1, width: 2560, height: 1440, refreshRate: 165, isHiDPI: false)
        let mockExternal = ManagedDisplay(
            displayID: 9999,
            name: "H27T22S",
            isBuiltin: false,
            isMain: false,
            isMirrored: false,
            mirrorMasterID: nil,
            isDisconnected: false,
            vendorID: 0x4d67,
            productID: 0x2725,
            currentMode: mockMode,
            recommendedModes: [RecommendedMode(mode: mockMode, badge: "最佳推荐", systemImage: "sparkles", subtitle: "2K 165Hz 原生")],
            standardModes: [],
            fineTuningModes: [],
            availableResolutions: [mockMode],
            availableRefreshRates: [60, 120, 144, 165]
        )

        var dualList = originalDisplays
        dualList.append(mockExternal)
        ResolutionController.shared.displays = dualList

        let dualView = ControlCenterPanelView(appModel: model, onOpenSettings: {}, onQuit: {})
        let dualHost = NSHostingView(rootView: dualView)
        let dualSize = dualHost.fittingSize
        try require(dualSize.width <= 360, "dual control center width is \(dualSize.width)")
        dualHost.frame = NSRect(origin: .zero, size: dualSize)
        dualHost.layoutSubtreeIfNeeded()
        if let rep = dualHost.bitmapImageRepForCachingDisplay(in: dualHost.bounds) {
            dualHost.cacheDisplay(in: dualHost.bounds, to: rep)
            if let dpng = rep.representation(using: .png, properties: [:]) {
                try require(dpng.count > 5_000, "dual PNG is empty")
                try dpng.write(to: URL(fileURLWithPath: "/private/tmp/monitor-switch-cc-dual-preview.png"), options: .atomic)
            }
        }

        // Test disconnected display rendering
        var mockDisconnected = mockExternal
        mockDisconnected.isDisconnected = true
        var discList = originalDisplays
        discList.append(mockDisconnected)
        ResolutionController.shared.displays = discList

        let discView = ControlCenterPanelView(appModel: model, onOpenSettings: {}, onQuit: {})
        let discHost = NSHostingView(rootView: discView)
        let discSize = discHost.fittingSize
        try require(discSize.width <= 360, "disconnected control center width is \(discSize.width)")
        discHost.frame = NSRect(origin: .zero, size: discSize)
        discHost.layoutSubtreeIfNeeded()
        if let rep = discHost.bitmapImageRepForCachingDisplay(in: discHost.bounds) {
            discHost.cacheDisplay(in: discHost.bounds, to: rep)
            if let dispng = rep.representation(using: .png, properties: [:]) {
                try require(dispng.count > 5_000, "disconnected PNG is empty")
                try dispng.write(to: URL(fileURLWithPath: "/private/tmp/monitor-switch-cc-disconnected-preview.png"), options: .atomic)
            }
        }
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
