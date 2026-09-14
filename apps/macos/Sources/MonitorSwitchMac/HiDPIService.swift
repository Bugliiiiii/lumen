import AppKit
import Foundation
import IOKit

@MainActor
final class HiDPIService: ObservableObject {
    static let shared = HiDPIService()

    @Published var isWorking = false
    @Published var statusError: String?

    private let overridesBase = URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides")

    private init() {}

    func isHiDPIInstalled(vendor: UInt32, product: UInt32) -> Bool {
        let url = overridePlistURL(vendor: vendor, product: product)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func enableHiDPI(vendor: UInt32, product: UInt32, nativeWidth: Int = 2560, nativeHeight: Int = 1440) async -> String? {
        let scaledModes = generateSmoothScaledModes(nativeWidth: nativeWidth, nativeHeight: nativeHeight)
        return writeScaledModesPlist(vendor: vendor, product: product, scaledModes: scaledModes)
    }

    func disableHiDPI(vendor: UInt32, product: UInt32) async -> String? {
        let plistPath = overridePlistURL(vendor: vendor, product: product).path
        guard FileManager.default.fileExists(atPath: plistPath) else { return nil }

        let script = "do shell script \"rm -f '\(plistPath)'\" with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return "创建授权脚本失败"
        }
        appleScript.executeAndReturnError(&error)
        if let error = error {
            return error[NSAppleScript.errorMessage] as? String ?? "取消授权或移除失败"
        }

        triggerDisplayReenumeration(vendor: vendor, product: product)
        ResolutionController.shared.refreshDisplays()
        return nil
    }

    private func writeScaledModesPlist(vendor: UInt32, product: UInt32, scaledModes: [Data]) -> String? {
        let dirPath = overrideDir(vendor: vendor).path
        let plistPath = overridePlistURL(vendor: vendor, product: product).path

        let plist: [String: Any] = [
            "scale-resolutions": scaledModes
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return "生成 plist 配置失败"
        }

        let tmpPath = NSTemporaryDirectory() + "switchmonitor_hidpi_override.plist"
        do {
            try data.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)
        } catch {
            return "写入临时文件失败: \(error.localizedDescription)"
        }

        let script = "do shell script \"mkdir -p '\(dirPath)' && cp '\(tmpPath)' '\(plistPath)'\" with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return "创建授权脚本失败"
        }
        appleScript.executeAndReturnError(&error)
        try? FileManager.default.removeItem(atPath: tmpPath)

        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "未知授权错误"
            if msg.contains("canceled") || msg.contains("Cancel") {
                return "用户取消了管理员授权"
            }
            return "管理员授权失败: \(msg)"
        }

        triggerDisplayReenumeration(vendor: vendor, product: product)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ResolutionController.shared.refreshDisplays()
        }
        return nil
    }

    private func triggerDisplayReenumeration(vendor: UInt32, product: UInt32) {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let cfDict = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let sVendor: UInt32
            let sProduct: UInt32

            if let v = cfDict["DisplayVendorID"] as? UInt32 {
                sVendor = v
            } else if let v = cfDict["DisplayVendorID"] as? Int {
                sVendor = UInt32(bitPattern: Int32(truncatingIfNeeded: v))
            } else { continue }

            if let p = cfDict["DisplayProductID"] as? UInt32 {
                sProduct = p
            } else if let p = cfDict["DisplayProductID"] as? Int {
                sProduct = UInt32(bitPattern: Int32(truncatingIfNeeded: p))
            } else { continue }

            guard sVendor == vendor && sProduct == product else { continue }

            IOServiceRequestProbe(service, 0)
            break
        }
    }

    private func overrideDir(vendor: UInt32) -> URL {
        overridesBase.appendingPathComponent(String(format: "DisplayVendorID-%x", vendor))
    }

    private func overridePlistURL(vendor: UInt32, product: UInt32) -> URL {
        overrideDir(vendor: vendor).appendingPathComponent(String(format: "DisplayProductID-%x", product))
    }

    private func generateSmoothScaledModes(nativeWidth: Int, nativeHeight: Int, minScale: Double = 0.5) -> [Data] {
        var stops: [(width: Int, height: Int)] = []
        let minW = Int((Double(nativeWidth) * minScale).rounded())
        var w = nativeWidth
        while w >= minW {
            let h = Int((Double(w) * Double(nativeHeight) / Double(nativeWidth)).rounded())
            if w >= 800, h >= 600 { stops.append((width: w, height: h)) }
            w -= 16
        }
        return stops.map { encodeScaledMode(backingW: $0.width * 2, backingH: $0.height * 2) }
    }

    private func encodeScaledMode(backingW: Int, backingH: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = UInt8((backingW >> 24) & 0xFF)
        bytes[1] = UInt8((backingW >> 16) & 0xFF)
        bytes[2] = UInt8((backingW >> 8) & 0xFF)
        bytes[3] = UInt8(backingW & 0xFF)
        bytes[4] = UInt8((backingH >> 24) & 0xFF)
        bytes[5] = UInt8((backingH >> 16) & 0xFF)
        bytes[6] = UInt8((backingH >> 8) & 0xFF)
        bytes[7] = UInt8(backingH & 0xFF)
        return Data(bytes)
    }
}
