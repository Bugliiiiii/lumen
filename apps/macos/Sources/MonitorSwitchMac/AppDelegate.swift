import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let currentInputItem = NSMenuItem(title: "当前输入：等待扫描", action: nil, keyEquivalent: "")
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.connected.to.line.below", accessibilityDescription: "Monitor Switch")
            button.image?.isTemplate = true
            button.toolTip = "Monitor Switch"
        }

        menu.delegate = self
        menu.addItem(NSMenuItem(title: "KTC H27T22S", action: nil, keyEquivalent: ""))
        menu.items.last?.isEnabled = false
        currentInputItem.isEnabled = false
        menu.addItem(currentInputItem)
        menu.addItem(.separator())

        let switchItem = NSMenuItem(title: "切换到 Windows · DisplayPort 1", action: #selector(switchToWindows), keyEquivalent: "")
        switchItem.target = self
        menu.addItem(switchItem)

        let scanItem = NSMenuItem(title: "扫描显示器", action: #selector(scanDisplay), keyEquivalent: "")
        scanItem.target = self
        menu.addItem(scanItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出 Monitor Switch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        model.settingsDidChange = { [weak self] in self?.refreshMenu() }
        model.start()
        refreshMenu()

        if ProcessInfo.processInfo.environment["MONITOR_SWITCH_SHOW_SETTINGS"] == "1" {
            showSettings()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.scan(showError: false)
        refreshMenu()
    }

    @objc private func switchToWindows() {
        model.switchToWindows()
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
        if let snapshot = model.snapshot {
            let friendly = InputSourceCatalog.friendlyName(for: snapshot.currentInput, settings: model.settings)
            currentInputItem.title = "当前输入：\(friendly) · \(InputSourceCatalog.connectorName(for: snapshot.currentInput))"
        } else {
            currentInputItem.title = "当前输入：不可读取"
        }
    }
}
