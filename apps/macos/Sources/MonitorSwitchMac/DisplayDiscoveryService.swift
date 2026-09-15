import AppKit
@preconcurrency import AppleSiliconDDC
import CoreGraphics
import Foundation

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: AnyObject?, _ chipAddress: UInt32, _ offset: UInt32, _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> Int32

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: AnyObject?, _ chipAddress: UInt32, _ offset: UInt32, _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32) -> Int32

@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func CoreDisplay_DisplayCreateInfoDictionary(_ displayID: CGDirectDisplayID) -> Unmanaged<CFDictionary>?

struct DDCReadResult: Equatable, Sendable {
    let command: UInt8
    let current: UInt16
    let max: UInt16
}

final class DisplayDiscoveryService: @unchecked Sendable {
    static let shared = DisplayDiscoveryService()

    private let ddcChipAddress: UInt32 = 0x37
    private let ddcDataAddress: UInt32 = 0x51

    func discoverMonitors() -> [DiscoveredMonitor] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displayIDs, &count) == .success else { return [] }

        let ioregServices = AppleSiliconDDC.getIoregServicesForMatching().filter {
            $0.service != nil && $0.location == "External"
        }

        var results: [DiscoveredMonitor] = []
        var assignedServices: Set<Int> = []

        for did in displayIDs.prefix(Int(count)) {
            let isBuiltin = CGDisplayIsBuiltin(did) != 0

            if isBuiltin {
                let monitor = makeBuiltinMonitor(displayID: did)
                results.append(monitor)
                continue
            }

            // Find best matching IOregService for this external display
            let coreDict = CoreDisplay_DisplayCreateInfoDictionary(did)?.takeRetainedValue() as? [String: Any]
            let matchedService = findBestMatchingService(
                displayID: did,
                coreDict: coreDict,
                availableServices: ioregServices,
                assignedIndices: assignedServices
            )

            if let (index, service) = matchedService {
                assignedServices.insert(index)
                let monitor = makeExternalMonitor(displayID: did, coreDict: coreDict, ioregService: service)
                results.append(monitor)
            } else {
                // External display without matched DDC service
                let monitor = makeExternalMonitorWithoutDDC(displayID: did, coreDict: coreDict)
                results.append(monitor)
            }
        }

        return results
    }

    // MARK: - Safe Target Monitor Selection

    func selectTargetMonitor(
        monitors: [DiscoveredMonitor],
        selectedId: String?,
        monitorHint: String
    ) -> DiscoveredMonitor? {
        let externalControllable = monitors.filter { !$0.isBuiltin && $0.isDDCSupported }

        // 1. Check explicit selected monitor identity
        if let selectedId = selectedId, !selectedId.isEmpty {
            if let matched = externalControllable.first(where: { $0.id == selectedId }) {
                return matched
            }
        }

        // 2. Check monitor hint (if user provided a custom non-KTC hint)
        let trimmedHint = monitorHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty && !isLegacyDefaultKTCHint(trimmedHint) {
            if let matched = externalControllable.first(where: {
                $0.name.localizedCaseInsensitiveContains(trimmedHint)
                    || $0.modelName.localizedCaseInsensitiveContains(trimmedHint)
                    || $0.id.localizedCaseInsensitiveContains(trimmedHint)
            }) {
                return matched
            }
        }

        // 3. Auto-select ONLY if exactly one external controllable monitor exists
        if externalControllable.count == 1 {
            return externalControllable.first
        }

        // 4. If multiple candidates exist and are ambiguous, do NOT blindly pick first
        return nil
    }

    func isLegacyDefaultKTCHint(_ hint: String) -> Bool {
        let normalized = hint.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "H27T22S" || normalized == "KTC H27T22S" || normalized == "KTC"
    }

    // MARK: - Read-only DDC Communication

    func readVCP(service: AnyObject?, command: UInt8) -> DDCReadResult? {
        guard let service = service else { return nil }

        // Attempt 1: Standard VESA DDC checksum (including 0x51 source address)
        if let res = performRead(service: service, command: command, includeSourceAddressInChecksum: true) {
            return res
        }

        // Attempt 2: Alternative checksum without 0x51 (for non-compliant display adapters)
        if let res = performRead(service: service, command: command, includeSourceAddressInChecksum: false) {
            return res
        }

        return nil
    }

    private func performRead(
        service: AnyObject,
        command: UInt8,
        includeSourceAddressInChecksum: Bool
    ) -> DDCReadResult? {
        var packet: [UInt8] = [0x82, 0x01, command, 0]
        var chk: UInt8 = UInt8(ddcChipAddress << 1)
        if includeSourceAddressInChecksum {
            chk ^= UInt8(ddcDataAddress)
        }
        for b in packet[0..<3] {
            chk ^= b
        }
        packet[3] = chk

        for _ in 0..<2 {
            let writeRet = IOAVServiceWriteI2C(service, ddcChipAddress, ddcDataAddress, &packet, UInt32(packet.count))
            guard writeRet == 0 else {
                usleep(25000)
                continue
            }

            usleep(50000)

            var reply = [UInt8](repeating: 0, count: 11)
            let readRet = IOAVServiceReadI2C(service, ddcChipAddress, ddcDataAddress, &reply, UInt32(reply.count))
            guard readRet == 0 else {
                usleep(25000)
                continue
            }

            // Verify packet structure:
            // reply[2]: 0x02 = Get VCP reply
            // reply[3]: 0x00 = Success (no error)
            // reply[4]: command = Matches requested VCP code
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == command else {
                continue
            }

            // Verify checksum: chk = 0x50 ^ reply[0] ... ^ reply[9]
            var expectedChk: UInt8 = 0x50
            for i in 0..<10 {
                expectedChk ^= reply[i]
            }
            guard expectedChk == reply[10] else {
                continue
            }

            let maxVal = (UInt16(reply[6]) << 8) | UInt16(reply[7])
            let curVal = (UInt16(reply[8]) << 8) | UInt16(reply[9])
            return DDCReadResult(command: command, current: curVal, max: maxVal)
        }

        return nil
    }

    // MARK: - Monitor Construction

    private func makeBuiltinMonitor(displayID: CGDirectDisplayID) -> DiscoveredMonitor {
        let modes = fetchDisplayModes(for: displayID)
        let currentMode = fetchCurrentMode(for: displayID, allModes: modes)
        let nativeMode = findNativeResolution(modes: modes)

        return DiscoveredMonitor(
            id: "builtin-\(displayID)",
            name: "内建显示器",
            manufacturer: "Apple",
            modelName: "Liquid Retina",
            serialNumber: "",
            displayID: displayID,
            isBuiltin: true,
            nativeWidth: nativeMode.width,
            nativeHeight: nativeMode.height,
            logicalWidth: currentMode?.width ?? nativeMode.width,
            logicalHeight: currentMode?.height ?? nativeMode.height,
            refreshRate: currentMode?.refreshRate ?? 60,
            isHiDPI: currentMode?.isHiDPI ?? true,
            hasNativeHiDPI: modes.contains(where: { $0.isHiDPI }),
            isDDCSupported: false,
            currentInput: nil,
            isInputSupported: false,
            isBrightnessSupported: true,
            currentBrightness: nil,
            isVolumeSupported: false,
            currentVolume: nil,
            advertisedInputs: [],
            connection: "Internal"
        )
    }

    private func makeExternalMonitor(
        displayID: CGDirectDisplayID,
        coreDict: [String: Any]?,
        ioregService: AppleSiliconDDC.IOregService
    ) -> DiscoveredMonitor {
        let modes = fetchDisplayModes(for: displayID)
        let currentMode = fetchCurrentMode(for: displayID, allModes: modes)
        let nativeMode = findNativeResolution(modes: modes)

        let productAttrs = ioregService.displayAttributes?["ProductAttributes"] as? NSDictionary
        let mfg = (productAttrs?["ManufacturerID"] as? String)
            ?? ioregService.manufacturerID
        var model = (productAttrs?["ProductName"] as? String)
            ?? ioregService.productName
        if model.isEmpty, let names = coreDict?["DisplayProductName"] as? [String: String] {
            model = names["en_US"] ?? names.values.first ?? ""
        }

        let serial: String = {
            if !ioregService.alphanumericSerialNumber.isEmpty {
                return ioregService.alphanumericSerialNumber
            }
            if ioregService.serialNumber > 0 {
                return String(ioregService.serialNumber)
            }
            if let s = coreDict?["DisplaySerialNumber"] as? Int64, s > 0 {
                return String(s)
            }
            if let s = coreDict?["DisplaySerialNumber"] as? Int, s > 0 {
                return String(s)
            }
            return ""
        }()

        let friendlyName = formatMonitorName(manufacturer: mfg, model: model)
        let stableId = formatStableIdentity(
            manufacturer: mfg,
            model: model,
            serial: serial,
            edidUUID: ioregService.edidUUID,
            location: ioregService.ioDisplayLocation
        )

        // Read DDC states (read-only)
        let vcp60 = readVCP(service: ioregService.service, command: 0x60)
        let vcp10 = readVCP(service: ioregService.service, command: 0x10)
        let vcp62 = readVCP(service: ioregService.service, command: 0x62)

        let isDDCSupported = (vcp60 != nil || vcp10 != nil || vcp62 != nil)
        let currentInput = vcp60.map { UInt8($0.current & 0xFF) }
        let currentBrightness = vcp10.map { Double($0.current) }
        let currentVolume = vcp62.map { Double($0.current) }

        let connection = formatConnection(ioregService)

        return DiscoveredMonitor(
            id: stableId,
            name: friendlyName,
            manufacturer: mfg,
            modelName: model,
            serialNumber: serial,
            displayID: displayID,
            isBuiltin: false,
            nativeWidth: nativeMode.width,
            nativeHeight: nativeMode.height,
            logicalWidth: currentMode?.width ?? nativeMode.width,
            logicalHeight: currentMode?.height ?? nativeMode.height,
            refreshRate: currentMode?.refreshRate ?? 60,
            isHiDPI: currentMode?.isHiDPI ?? false,
            hasNativeHiDPI: modes.contains(where: { $0.isHiDPI }),
            isDDCSupported: isDDCSupported,
            currentInput: currentInput,
            isInputSupported: vcp60 != nil,
            isBrightnessSupported: vcp10 != nil,
            currentBrightness: currentBrightness,
            isVolumeSupported: vcp62 != nil,
            currentVolume: currentVolume,
            advertisedInputs: [0x0F, 0x10, 0x11, 0x12],
            connection: connection
        )
    }

    private func makeExternalMonitorWithoutDDC(
        displayID: CGDirectDisplayID,
        coreDict: [String: Any]?
    ) -> DiscoveredMonitor {
        let modes = fetchDisplayModes(for: displayID)
        let currentMode = fetchCurrentMode(for: displayID, allModes: modes)
        let nativeMode = findNativeResolution(modes: modes)

        var model = ""
        if let names = coreDict?["DisplayProductName"] as? [String: String] {
            model = names["en_US"] ?? names.values.first ?? ""
        }
        let vendorNum = (coreDict?["DisplayVendorID"] as? UInt32)
            ?? (coreDict?["DisplayVendorID"] as? Int).map { UInt32($0) }
            ?? 0
        let mfg = decodeVendorID(vendorNum)
        let friendlyName = formatMonitorName(manufacturer: mfg, model: model.isEmpty ? "外接显示器" : model)

        let serial: String = {
            if let s = coreDict?["DisplaySerialNumber"] as? Int64, s > 0 { return String(s) }
            if let s = coreDict?["DisplaySerialNumber"] as? Int, s > 0 { return String(s) }
            return ""
        }()

        let stableId = "\(vendorNum)-\(coreDict?["DisplayProductID"] ?? 0)-\(serial)"

        return DiscoveredMonitor(
            id: stableId,
            name: friendlyName,
            manufacturer: mfg,
            modelName: model,
            serialNumber: serial,
            displayID: displayID,
            isBuiltin: false,
            nativeWidth: nativeMode.width,
            nativeHeight: nativeMode.height,
            logicalWidth: currentMode?.width ?? nativeMode.width,
            logicalHeight: currentMode?.height ?? nativeMode.height,
            refreshRate: currentMode?.refreshRate ?? 60,
            isHiDPI: currentMode?.isHiDPI ?? false,
            hasNativeHiDPI: modes.contains(where: { $0.isHiDPI }),
            isDDCSupported: false,
            currentInput: nil,
            isInputSupported: false,
            isBrightnessSupported: false,
            currentBrightness: nil,
            isVolumeSupported: false,
            currentVolume: nil,
            advertisedInputs: [],
            connection: "USB-C / HDMI"
        )
    }

    // MARK: - Helpers

    private func findBestMatchingService(
        displayID: CGDirectDisplayID,
        coreDict: [String: Any]?,
        availableServices: [AppleSiliconDDC.IOregService],
        assignedIndices: Set<Int>
    ) -> (Int, AppleSiliconDDC.IOregService)? {
        guard !availableServices.isEmpty else { return nil }

        // If only 1 external service and 1 external display
        if availableServices.count == 1 && !assignedIndices.contains(0) {
            return (0, availableServices[0])
        }

        var bestMatch: (Int, AppleSiliconDDC.IOregService)? = nil
        var highestScore = 0

        let dictSerial = (coreDict?["DisplaySerialNumber"] as? Int64)
            ?? (coreDict?["DisplaySerialNumber"] as? Int).map { Int64($0) }
        let dictVendor = (coreDict?["DisplayVendorID"] as? UInt32)
            ?? (coreDict?["DisplayVendorID"] as? Int).map { UInt32($0) }
        let dictProduct = (coreDict?["DisplayProductID"] as? UInt32)
            ?? (coreDict?["DisplayProductID"] as? Int).map { UInt32($0) }
        let dictName = (coreDict?["DisplayProductName"] as? [String: String])?.values.first

        for (idx, service) in availableServices.enumerated() {
            guard !assignedIndices.contains(idx) else { continue }
            var score = 0

            let productAttrs = service.displayAttributes?["ProductAttributes"] as? NSDictionary

            if let dictSerial = dictSerial, dictSerial > 0 {
                if service.serialNumber == dictSerial { score += 10 }
                if String(dictSerial) == service.alphanumericSerialNumber { score += 10 }
            }

            if let dictVendor = dictVendor, dictVendor > 0 {
                if let legacyM = productAttrs?["LegacyManufacturerID"] as? UInt32, legacyM == dictVendor {
                    score += 8
                } else if let legacyM = productAttrs?["LegacyManufacturerID"] as? Int, UInt32(legacyM) == dictVendor {
                    score += 8
                }
            }

            if let dictProduct = dictProduct, dictProduct > 0 {
                if let p = productAttrs?["ProductID"] as? UInt32, p == dictProduct {
                    score += 8
                } else if let p = productAttrs?["ProductID"] as? Int, UInt32(p) == dictProduct {
                    score += 8
                }
            }

            if let dictName = dictName, !dictName.isEmpty {
                if service.productName.localizedCaseInsensitiveContains(dictName)
                    || dictName.localizedCaseInsensitiveContains(service.productName) {
                    score += 6
                }
            }

            if score > highestScore {
                highestScore = score
                bestMatch = (idx, service)
            }
        }

        if highestScore >= 6 {
            return bestMatch
        }

        return nil
    }

    private func formatMonitorName(manufacturer: String, model: String) -> String {
        let trimmedMfg = manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedModel.isEmpty {
            return trimmedMfg.isEmpty ? "外接显示器" : "\(trimmedMfg) 显示器"
        }
        if trimmedMfg.isEmpty {
            return trimmedModel
        }
        if trimmedModel.localizedCaseInsensitiveContains(trimmedMfg) {
            return trimmedModel
        }
        return "\(trimmedMfg) \(trimmedModel)"
    }

    private func formatStableIdentity(
        manufacturer: String,
        model: String,
        serial: String,
        edidUUID: String,
        location: String
    ) -> String {
        if !serial.isEmpty {
            return "\(manufacturer)-\(model)-\(serial)"
        }
        if !edidUUID.isEmpty {
            return edidUUID
        }
        if !location.isEmpty {
            return location
        }
        return "\(manufacturer)-\(model)"
    }

    private func formatConnection(_ service: AppleSiliconDDC.IOregService) -> String {
        let path = [service.transportUpstream, service.transportDownstream]
            .filter { !$0.isEmpty }
            .joined(separator: " → ")
        return path.isEmpty ? "USB-C → HDMI 1" : path
    }

    private func decodeVendorID(_ vendor: UInt32) -> String {
        switch vendor {
        case 0x05E3: return "AOC"
        case 0x4D67: return "KTC"
        case 0x10AC: return "Dell"
        case 0x1E6D: return "LG"
        case 0x4C2D: return "Samsung"
        default: return ""
        }
    }

    private func fetchDisplayModes(for displayID: CGDirectDisplayID) -> [DisplayModeItem] {
        var count: Int32 = 0
        guard CGSGetNumberOfDisplayModes(displayID, &count) == .success, count > 0 else { return [] }

        var items: [DisplayModeItem] = []
        for i in 0..<count {
            var desc = CGSDisplayModeDescription()
            guard CGSGetDisplayModeDescriptionOfLength(displayID, i, &desc, Int32(MemoryLayout<CGSDisplayModeDescription>.size)) == .success else { continue }
            guard (desc.flags & 0x40000000) == 0 else { continue }
            guard desc.width >= 1024, desc.height >= 576 else { continue }

            items.append(DisplayModeItem(
                modeNumber: desc.modeNumber,
                width: Int(desc.width),
                height: Int(desc.height),
                refreshRate: Int(desc.freq),
                isHiDPI: desc.density >= 2.0
            ))
        }
        return items
    }

    private func fetchCurrentMode(for displayID: CGDirectDisplayID, allModes: [DisplayModeItem]) -> DisplayModeItem? {
        guard let currentCG = CGDisplayCopyDisplayMode(displayID) else { return nil }
        let currentID = UInt32(bitPattern: currentCG.ioDisplayModeID)
        if let exact = allModes.first(where: { $0.modeNumber == currentID }) {
            return exact
        }
        let w = currentCG.width
        let h = currentCG.height
        return allModes.first(where: { $0.width == w && $0.height == h })
    }

    private func findNativeResolution(modes: [DisplayModeItem]) -> (width: Int, height: Int) {
        var maxPixels = 0
        var bestWidth = 1920
        var bestHeight = 1080

        for mode in modes {
            let pixels = mode.width * mode.height
            if pixels > maxPixels {
                maxPixels = pixels
                bestWidth = mode.width
                bestHeight = mode.height
            }
        }
        return (bestWidth, bestHeight)
    }
}
