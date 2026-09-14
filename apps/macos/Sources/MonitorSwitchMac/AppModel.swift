import AppKit
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published private(set) var snapshot: MonitorSnapshot?
    @Published private(set) var statusText = "仅读取显示器，不会自动切换"
    @Published private(set) var isBusy = false
    @Published var launchAtLogin: Bool

    private let ddc = DDCService()
    private let hotKey = HotKeyController()
    var settingsDidChange: (() -> Void)?

    init() {
        settings = SettingsStore.load()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var currentInputText: String {
        guard let input = snapshot?.currentInput else { return "未知" }
        let friendly = InputSourceCatalog.friendlyName(for: input, settings: settings)
        return "● \(friendly) · \(InputSourceCatalog.connectorName(for: input))"
    }

    func start() {
        registerHotKey(showError: false)
        scan(showError: false)
    }

    func scan(showError: Bool = true) {
        guard !isBusy else { return }
        isBusy = true
        statusText = "正在读取 DDC/CI…"
        do {
            snapshot = try ddc.scan(monitorHint: settings.monitorHint)
            statusText = "已检测到输入源，可以执行切换"
        } catch {
            snapshot = nil
            statusText = error.localizedDescription
            if showError { presentError(error) }
        }
        isBusy = false
        settingsDidChange?()
    }

    func switchToWindows() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        statusText = "正在发送切换命令…"
        do {
            try ddc.switchInput(monitorHint: settings.monitorHint, input: settings.windowsInput)
            statusText = "已发送切换到 Windows"
        } catch {
            statusText = error.localizedDescription
            presentError(error)
        }
        settingsDidChange?()
    }

    func save() {
        do {
            guard !settings.shortcutModifiers.isEmpty else {
                throw HotKeyError.missingModifier
            }
            try registerHotKeyOrThrow()
            try SettingsStore.save(settings)
            try updateLaunchAtLogin()
            statusText = "设置已保存"
            settingsDidChange?()
        } catch {
            statusText = error.localizedDescription
            presentError(error)
        }
    }

    private func registerHotKey(showError: Bool) {
        do {
            try registerHotKeyOrThrow()
        } catch {
            statusText = error.localizedDescription
            if showError { presentError(error) }
        }
    }

    private func registerHotKeyOrThrow() throws {
        try hotKey.register(settings: settings) { [weak self] in
            Task { @MainActor in self?.switchToWindows() }
        }
    }

    private func updateLaunchAtLogin() throws {
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin && !enabled {
            try SMAppService.mainApp.register()
        } else if !launchAtLogin && enabled {
            try SMAppService.mainApp.unregister()
        }
    }

    private func presentError(_ error: Error) {
        NSApp.requestUserAttention(.informationalRequest)
        let alert = NSAlert()
        alert.messageText = "Monitor Switch"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
