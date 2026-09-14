import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let headerItem = NSMenuItem.sectionHeader(title: "KTC H27T22S")
    private let windowsItem = NSMenuItem(title: "Windows · DisplayPort 1", action: #selector(switchToWindows), keyEquivalent: "")
    private let macItem = NSMenuItem(title: "Mac · HDMI 1", action: #selector(switchToMac), keyEquivalent: "")
    private let scanItem = NSMenuItem(title: "扫描显示器", action: #selector(scanDisplay), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "退出 Monitor Switch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    private var settingsWindow: NSWindow?
    private let panelController = MenuPanelController()
    private var clickInterceptor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Monitor Switch runs continuously in menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()

        updateStatusBarIcon()

        panelController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        panelController.onQuit = {
            NSApp.terminate(nil)
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
        }

        clickInterceptor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self,
                  let button = self.statusItem.button,
                  event.window === button.window,
                  !event.modifierFlags.contains(.command) else { return event }
            self.togglePanel()
            return nil
        }

        model.settingsDidChange = { [weak self] in self?.refreshMenu() }
        model.start()
        refreshMenu()

        if ProcessInfo.processInfo.environment["MONITOR_SWITCH_SHOW_SETTINGS"] == "1" {
            showSettings()
        }
    }

    @objc private func togglePanel() {
        panelController.toggle(for: statusItem, model: model)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show(for: statusItem, model: model)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    @objc private func switchToWindows() {
        model.switchToWindows()
    }

    @objc private func switchToMac() {
        model.switchToMac()
    }

    @objc private func scanDisplay() {
        model.scan()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Monitor Switch"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshMenu() {
        let winConnector = InputSourceCatalog.connectorName(for: model.settings.windowsInput)
        let macConnector = InputSourceCatalog.connectorName(for: model.settings.macInput)
        windowsItem.title = "\(model.settings.windowsLabel) · \(winConnector)"
        macItem.title = "\(model.settings.macLabel) · \(macConnector)"

        let activeInput = model.snapshot?.currentInput ?? model.lastTargetInput
        let isWindows = activeInput == model.settings.windowsInput
        let isMac = activeInput == model.settings.macInput

        windowsItem.state = isWindows ? .on : .off
        macItem.state = isMac ? .on : .off

        let shortcutKey = model.settings.shortcutKey.lowercased()
        let shortcutModifiers = model.settings.shortcutModifiers.nsModifierFlags

        if isWindows {
            macItem.keyEquivalent = shortcutKey
            macItem.keyEquivalentModifierMask = shortcutModifiers
            windowsItem.keyEquivalent = ""
        } else {
            windowsItem.keyEquivalent = shortcutKey
            windowsItem.keyEquivalentModifierMask = shortcutModifiers
            macItem.keyEquivalent = ""
        }

        if let snapshot = model.snapshot {
            headerItem.title = snapshot.name.isEmpty ? "KTC H27T22S" : snapshot.name
            let friendly = InputSourceCatalog.friendlyName(for: snapshot.currentInput, settings: model.settings)
            statusItem.button?.toolTip = "Monitor Switch: \(friendly)"
        } else if let last = model.lastTargetInput {
            headerItem.title = model.settings.monitorHint.isEmpty ? "KTC H27T22S" : model.settings.monitorHint
            let friendly = InputSourceCatalog.friendlyName(for: last, settings: model.settings)
            statusItem.button?.toolTip = "Monitor Switch: \(friendly)"
        } else {
            headerItem.title = model.settings.monitorHint.isEmpty ? "KTC H27T22S" : model.settings.monitorHint
            statusItem.button?.toolTip = "Monitor Switch"
        }

        updateStatusBarIcon()
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem.button else { return }
        let image = Self.createCustomSwitcherIcon()
        image.isTemplate = true
        button.image = image
    }

    private static func createCustomSwitcherIcon() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.2)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Screen frame
            let screenRect = CGRect(x: 1.0, y: 4.5, width: 16.0, height: 10.5)
            ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.strokePath()

            // Stand leg & base
            ctx.move(to: CGPoint(x: 9.0, y: 4.5))
            ctx.addLine(to: CGPoint(x: 9.0, y: 1.5))
            ctx.move(to: CGPoint(x: 6.0, y: 1.5))
            ctx.addLine(to: CGPoint(x: 12.0, y: 1.5))
            ctx.strokePath()

            // Arrows inside screen:
            ctx.setLineWidth(1.0)
            // Top arrow ->
            ctx.move(to: CGPoint(x: 4.8, y: 11.0))
            ctx.addLine(to: CGPoint(x: 12.2, y: 11.0))
            ctx.addLine(to: CGPoint(x: 10.6, y: 12.4))
            ctx.move(to: CGPoint(x: 12.2, y: 11.0))
            ctx.addLine(to: CGPoint(x: 10.6, y: 9.6))
            ctx.strokePath()

            // Bottom arrow <-
            ctx.move(to: CGPoint(x: 13.2, y: 8.0))
            ctx.addLine(to: CGPoint(x: 5.8, y: 8.0))
            ctx.addLine(to: CGPoint(x: 7.4, y: 9.4))
            ctx.move(to: CGPoint(x: 5.8, y: 8.0))
            ctx.addLine(to: CGPoint(x: 7.4, y: 6.6))
            ctx.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }
}
