@preconcurrency import AppleSiliconDDC
import Foundation

struct MonitorSnapshot: Equatable {
    let name: String
    let serial: String
    let currentInput: UInt8
    let connection: String
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
            "显示器已连接，但 USB-C 转 HDMI 线没有返回当前输入源。"
        case .writeFailed(let connector):
            "切换到 \(connector) 失败。转接线可能没有传递 DDC/CI。"
        }
    }
}

final class DDCService {
    private let inputSourceVCP: UInt8 = 0x60

    func scan(monitorHint: String) throws -> MonitorSnapshot {
        let display = try findDisplay(monitorHint: monitorHint)
        guard let values = AppleSiliconDDC.read(service: display.service, command: inputSourceVCP) else {
            throw DDCServiceError.unreadableInput
        }

        return MonitorSnapshot(
            name: display.productName.isEmpty ? "KTC H27T22S" : display.productName,
            serial: display.alphanumericSerialNumber,
            currentInput: UInt8(values.current & 0xFF),
            connection: connectionName(display)
        )
    }

    func switchInput(monitorHint: String, input: UInt8) throws {
        let display = try findDisplay(monitorHint: monitorHint)
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

    private func findDisplay(monitorHint: String) throws -> AppleSiliconDDC.IOregService {
        let displays = AppleSiliconDDC.getIoregServicesForMatching().filter { display in
            display.service != nil && (!display.productName.isEmpty || !display.edidUUID.isEmpty)
        }

        if let exact = displays.first(where: { display in
            display.productName.localizedCaseInsensitiveContains(monitorHint)
                || display.manufacturerID.localizedCaseInsensitiveContains("KTC")
        }) {
            return exact
        }
        guard let first = displays.first else {
            throw DDCServiceError.noDisplay
        }
        return first
    }

    private func connectionName(_ display: AppleSiliconDDC.IOregService) -> String {
        let path = [display.transportUpstream, display.transportDownstream]
            .filter { !$0.isEmpty }
            .joined(separator: " → ")
        return path.isEmpty ? "USB-C → HDMI 1" : path
    }
}
