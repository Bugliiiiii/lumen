import Carbon.HIToolbox
import Foundation

enum HotKeyError: LocalizedError {
    case unsupportedKey(String)
    case missingModifier
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedKey(let key): "不支持快捷键 \(key)。请选择 A 到 Z。"
        case .missingModifier: "快捷键至少需要一个修饰键。"
        case .registrationFailed: "快捷键已被其他程序占用。"
        }
    }
}

final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private var registeredKeyCode: UInt32?
    private var registeredModifiers: UInt32 = 0

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.id == 1 else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue().action?()
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerRef
        )
    }

    deinit {
        unregister()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(settings: AppSettings, action: @escaping () -> Void) throws {
        let previousKeyCode = registeredKeyCode
        let previousModifiers = registeredModifiers
        let previousAction = self.action
        unregister()
        guard let keyCode = Self.keyCodes[settings.shortcutKey.uppercased()] else {
            throw HotKeyError.unsupportedKey(settings.shortcutKey)
        }
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let result = RegisterEventHotKey(
            keyCode,
            settings.shortcutModifiers.carbonValue,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard result == noErr else {
            if let previousKeyCode {
                var restoredRef: EventHotKeyRef?
                let restored = RegisterEventHotKey(
                    previousKeyCode,
                    previousModifiers,
                    identifier,
                    GetApplicationEventTarget(),
                    0,
                    &restoredRef
                )
                if restored == noErr {
                    hotKeyRef = restoredRef
                    registeredKeyCode = previousKeyCode
                    registeredModifiers = previousModifiers
                    self.action = previousAction
                }
            }
            throw HotKeyError.registrationFailed
        }
        self.action = action
        registeredKeyCode = keyCode
        registeredModifiers = settings.shortcutModifiers.carbonValue
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        action = nil
        registeredKeyCode = nil
        registeredModifiers = 0
    }

    private static let signature: OSType = 0x4D535748
    private static let keyCodes: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
        "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37,
        "J": 38, "K": 40, "N": 45, "M": 46,
    ]
}
