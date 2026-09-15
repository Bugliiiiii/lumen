import CoreGraphics
import Foundation

struct DiscoveredMonitor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let manufacturer: String
    let modelName: String
    let serialNumber: String
    let displayID: CGDirectDisplayID?
    let isBuiltin: Bool

    // Physical & logical mode details
    let nativeWidth: Int
    let nativeHeight: Int
    let logicalWidth: Int
    let logicalHeight: Int
    let refreshRate: Int
    let isHiDPI: Bool
    let hasNativeHiDPI: Bool

    // DDC Capabilities & State (Read-only discovery)
    let isDDCSupported: Bool
    let currentInput: UInt8?
    let isInputSupported: Bool
    let isBrightnessSupported: Bool
    let currentBrightness: Double?
    let isVolumeSupported: Bool
    let currentVolume: Double?
    let advertisedInputs: [UInt8]
    let connection: String

    var is4K: Bool {
        nativeWidth >= 3840 && nativeHeight >= 2160
    }

    var nativeResolutionText: String {
        guard nativeWidth > 0 && nativeHeight > 0 else { return "未知" }
        return "\(nativeWidth) × \(nativeHeight)"
    }

    var scalePercent: Int? {
        guard nativeWidth > 0, logicalWidth > 0 else { return nil }
        return Int(round(Double(nativeWidth) / Double(logicalWidth) * 100))
    }

    var logicalModeText: String {
        guard logicalWidth > 0 && logicalHeight > 0 else { return "未知" }
        if let scale = scalePercent {
            return "\(logicalWidth) × \(logicalHeight) · \(scale)%"
        }
        return "\(logicalWidth) × \(logicalHeight)"
    }

    var ddcStatusText: String {
        if isDDCSupported {
            return "可用"
        }
        return "不可读取"
    }
}
