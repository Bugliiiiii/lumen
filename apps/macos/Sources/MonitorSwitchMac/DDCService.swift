@preconcurrency import AppleSiliconDDC
import Foundation

struct MonitorSnapshot: Equatable, Sendable {
    var id: String
    var name: String
    var serial: String
    var currentInput: UInt8
    var connection: String
    var nativeWidth: Int
    var nativeHeight: Int
    var logicalWidth: Int
    var logicalHeight: Int
    var refreshRate: Int
    var isHiDPI: Bool
    var isDDCSupported: Bool
    var isBrightnessSupported: Bool
    var isVolumeSupported: Bool
    var brightness: Double?
    var volume: Double?

    init(
        id: String = "",
        name: String,
        serial: String,
        currentInput: UInt8,
        connection: String,
        nativeWidth: Int = 0,
        nativeHeight: Int = 0,
        logicalWidth: Int = 0,
        logicalHeight: Int = 0,
        refreshRate: Int = 60,
        isHiDPI: Bool = false,
        isDDCSupported: Bool = true,
        isBrightnessSupported: Bool = false,
        isVolumeSupported: Bool = false,
        brightness: Double? = nil,
        volume: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.serial = serial
        self.currentInput = currentInput
        self.connection = connection
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.refreshRate = refreshRate
        self.isHiDPI = isHiDPI
        self.isDDCSupported = isDDCSupported
        self.isBrightnessSupported = isBrightnessSupported
        self.isVolumeSupported = isVolumeSupported
        self.brightness = brightness
        self.volume = volume
    }

    var nativeResolutionText: String {
        guard nativeWidth > 0 && nativeHeight > 0 else { return "未知" }
        return "\(nativeWidth) × \(nativeHeight)"
    }

    var logicalModeText: String {
        guard logicalWidth > 0 && logicalHeight > 0 else { return "未知" }
        let hidpiSuffix = isHiDPI ? " HiDPI" : ""
        return "看起来像 \(logicalWidth) × \(logicalHeight)\(hidpiSuffix)"
    }
}

enum DDCServiceError: LocalizedError {
    case noDisplay
    case unreadableInput
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "未找到可通过 DDC/CI 控制的外接显示器。请检查转接线并确认显示器已开启 DDC/CI。"
        case .unreadableInput:
            "显示器已连接，但线材或转接器没有返回当前输入源。"
        case .writeFailed(let connector):
            "切换到 \(connector) 失败。转接线可能没有传递 DDC/CI。"
        }
    }
}

final class DDCService {
    private let inputSourceVCP: UInt8 = 0x60

    func scan(selectedMonitorId: String? = nil, monitorHint: String = "") throws -> MonitorSnapshot {
        let monitors = DisplayDiscoveryService.shared.discoverMonitors()
        guard let target = DisplayDiscoveryService.shared.selectTargetMonitor(
            monitors: monitors,
            selectedId: selectedMonitorId,
            monitorHint: monitorHint
        ) else {
            // Check if any external monitor exists whose DDC is unreadable
            if let firstExternal = monitors.first(where: { !$0.isBuiltin }) {
                if !firstExternal.isDDCSupported {
                    throw DDCServiceError.unreadableInput
                }
            }
            throw DDCServiceError.noDisplay
        }

        guard let currentInput = target.currentInput else {
            throw DDCServiceError.unreadableInput
        }

        return MonitorSnapshot(
            id: target.id,
            name: target.name,
            serial: target.serialNumber,
            currentInput: currentInput,
            connection: target.connection,
            nativeWidth: target.nativeWidth,
            nativeHeight: target.nativeHeight,
            logicalWidth: target.logicalWidth,
            logicalHeight: target.logicalHeight,
            refreshRate: target.refreshRate,
            isHiDPI: target.isHiDPI,
            isDDCSupported: target.isDDCSupported,
            isBrightnessSupported: target.isBrightnessSupported,
            isVolumeSupported: target.isVolumeSupported,
            brightness: target.currentBrightness,
            volume: target.currentVolume
        )
    }

    func switchInput(selectedMonitorId: String? = nil, monitorHint: String = "", input: UInt8) throws {
        let display = try findDisplayService(selectedMonitorId: selectedMonitorId, monitorHint: monitorHint)
        let success = AppleSiliconDDC.write(
            service: display.service,
            command: inputSourceVCP,
            value: UInt16(input),
            numOfWriteCycles: 2,
            numOfRetryAttemps: 1
        )
        guard success else {
            throw DDCServiceError.writeFailed(InputSourceCatalog.connectorName(for: input))
        }
    }

    private func findDisplayService(selectedMonitorId: String?, monitorHint: String) throws -> AppleSiliconDDC.IOregService {
        let externalServices = AppleSiliconDDC.getIoregServicesForMatching().filter {
            $0.service != nil && $0.location == "External"
        }
        guard !externalServices.isEmpty else {
            throw DDCServiceError.noDisplay
        }

        let monitors = DisplayDiscoveryService.shared.discoverMonitors()
        if let target = DisplayDiscoveryService.shared.selectTargetMonitor(
            monitors: monitors,
            selectedId: selectedMonitorId,
            monitorHint: monitorHint
        ) {
            // Find matched IOregService by target's serial or location
            if externalServices.count == 1 {
                return externalServices[0]
            }

            if let matched = externalServices.first(where: {
                (!target.serialNumber.isEmpty && ($0.alphanumericSerialNumber == target.serialNumber || String($0.serialNumber) == target.serialNumber))
                    || (!target.id.isEmpty && $0.ioDisplayLocation == target.id)
            }) {
                return matched
            }

            // Fallback match on product name
            let candidates = externalServices.filter {
                $0.productName.localizedCaseInsensitiveContains(target.modelName)
            }
            if candidates.count == 1 {
                return candidates[0]
            }
        }

        // If only 1 external service exists, safe to control
        if externalServices.count == 1 {
            return externalServices[0]
        }

        // Ambiguous: never pick first service to avoid writing to wrong monitor!
        throw DDCServiceError.noDisplay
    }
}
