import AppKit
import Carbon.HIToolbox
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt32

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let control = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    var carbonValue: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var nsModifierFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.command) { result.insert(.command) }
        if contains(.option) { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        if contains(.shift) { result.insert(.shift) }
        return result
    }

    var displayText: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

struct AppSettings: Codable, Equatable {
    var monitorHint = "H27T22S"
    var windowsInput: UInt8 = InputSourceCatalog.windowsValue
    var macInput: UInt8 = InputSourceCatalog.macValue
    var windowsLabel = "Windows"
    var macLabel = "Mac"
    var shortcutModifiers: ShortcutModifiers = [.option, .command]
    var shortcutKey = "S"

    var shortcutText: String { "\(shortcutModifiers.displayText)\(shortcutKey)" }

    enum CodingKeys: String, CodingKey {
        case monitorHint, windowsInput, macInput, windowsLabel, macLabel, shortcutModifiers, shortcutKey
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitorHint = try container.decodeIfPresent(String.self, forKey: .monitorHint) ?? "H27T22S"
        windowsInput = try container.decodeIfPresent(UInt8.self, forKey: .windowsInput) ?? InputSourceCatalog.windowsValue
        macInput = try container.decodeIfPresent(UInt8.self, forKey: .macInput) ?? InputSourceCatalog.macValue
        windowsLabel = try container.decodeIfPresent(String.self, forKey: .windowsLabel) ?? "Windows"
        macLabel = try container.decodeIfPresent(String.self, forKey: .macLabel) ?? "Mac"
        shortcutModifiers = try container.decodeIfPresent(ShortcutModifiers.self, forKey: .shortcutModifiers) ?? [.option, .command]
        shortcutKey = try container.decodeIfPresent(String.self, forKey: .shortcutKey) ?? "S"
    }
}

enum SettingsStore {
    private static let key = "monitorSwitch.settings.v1"

    static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    static func save(_ settings: AppSettings, defaults: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
