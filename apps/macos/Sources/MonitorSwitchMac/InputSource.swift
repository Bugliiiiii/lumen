import Foundation

struct InputSource: Equatable, Identifiable {
    let value: UInt8
    let connectorName: String
    let friendlyName: String

    var id: UInt8 { value }
    var displayName: String { "\(friendlyName) · \(connectorName)" }
}

enum InputSourceCatalog {
    static let windowsValue: UInt8 = 0x0F
    static let macValue: UInt8 = 0x11

    static func connectorName(for value: UInt8) -> String {
        switch value {
        case 0x01: "VGA 1"
        case 0x03: "DVI 1"
        case 0x0F: "DisplayPort 1"
        case 0x10: "DisplayPort 2"
        case 0x11: "HDMI 1"
        case 0x12: "HDMI 2"
        case 0x1B: "USB-C"
        default: "Input \(value)"
        }
    }

    static func friendlyName(for value: UInt8, settings: AppSettings) -> String {
        switch value {
        case settings.windowsInput: settings.windowsLabel
        case settings.macInput: settings.macLabel
        default: connectorName(for: value)
        }
    }
}
