import AppKit
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            settingsDidChange?()
        }
    }
    @Published private(set) var snapshot: MonitorSnapshot?
    @Published private(set) var statusText = "仅读取显示器，不会自动切换"
    @Published private(set) var isBusy = false
    @Published var launchAtLogin: Bool

    private let ddc = DDCService()
    private let hotKey = HotKeyController()
    @Published private(set) var lastTargetInput: UInt8?
    var settingsDidChange: (() -> Void)?

    init() {
        let loaded = SettingsStore.load()
        settings = loaded
        lastTargetInput = loaded.macInput
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var currentInputText: String {
        guard let input = snapshot?.currentInput ?? lastTargetInput else { return "未知" }
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
            let result = try ddc.scan(monitorHint: settings.monitorHint)
            snapshot = result
            lastTargetInput = result.currentInput
            statusText = "已检测到输入源，可以执行切换"
        } catch {
            if let ddcErr = error as? DDCServiceError, case .unreadableInput = ddcErr {
                statusText = "线材不支持状态回读（不影响切换，可在下方直接配置）"
            } else {
                statusText = error.localizedDescription
                if showError { presentError(error) }
            }
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
            lastTargetInput = settings.windowsInput
            if let current = snapshot {
                snapshot = MonitorSnapshot(
                    name: current.name,
                    serial: current.serial,
                    currentInput: settings.windowsInput,
                    connection: current.connection
                )
            }
            statusText = "已发送切换到 \(settings.windowsLabel)"
        } catch {
            statusText = error.localizedDescription
            presentError(error)
        }
        settingsDidChange?()
    }

    func switchToMac() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        statusText = "正在发送切换命令…"
        do {
            try ddc.switchInput(monitorHint: settings.monitorHint, input: settings.macInput)
            lastTargetInput = settings.macInput
            if let current = snapshot {
                snapshot = MonitorSnapshot(
                    name: current.name,
                    serial: current.serial,
                    currentInput: settings.macInput,
                    connection: current.connection
                )
            }
            statusText = "已发送切换到 \(settings.macLabel)"
        } catch {
            statusText = error.localizedDescription
            presentError(error)
        }
        settingsDidChange?()
    }

    func toggleInput() {
        let current = snapshot?.currentInput ?? lastTargetInput
        if current == settings.windowsInput {
            switchToMac()
        } else {
            switchToWindows()
        }
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
            Task { @MainActor in self?.toggleInput() }
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
        alert.messageText = "Lumen"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
