import AppKit
import CoreGraphics
import Foundation

// MARK: - CGS / SkyLight Private Structures & Symbols

struct CGSDisplayModeDescription {
    var modeNumber: UInt32 = 0
    var flags: UInt32 = 0
    var width: UInt32 = 0
    var height: UInt32 = 0
    var depth: UInt32 = 0
    var dc2: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32,
              UInt32, UInt32) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    var dc3: UInt16 = 0
    var freq: UInt16 = 0
    var dc4: (UInt32, UInt32, UInt32, UInt32) = (0,0,0,0)
    var density: Float = 0.0
}

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetNumberOfDisplayModes")
func CGSGetNumberOfDisplayModes(_ display: CGDirectDisplayID, _ count: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSGetDisplayModeDescriptionOfLength")
func CGSGetDisplayModeDescriptionOfLength(_ display: CGDirectDisplayID, _ index: Int32, _ mode: UnsafeMutablePointer<CGSDisplayModeDescription>, _ length: Int32) -> CGError

@_silgen_name("CGSConfigureDisplayMode")
func CGSConfigureDisplayMode(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ modeNumber: Int32) -> CGError

@_silgen_name("SLSConfigureDisplayEnabled")
func SLSConfigureDisplayEnabled(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

// MARK: - Models

struct DisplayModeItem: Identifiable, Hashable, Sendable {
    let modeNumber: UInt32
    let width: Int
    let height: Int
    let refreshRate: Int
    let isHiDPI: Bool

    var id: UInt32 { modeNumber }

    var resolutionKey: String { "\(width) × \(height)" }

    var displayName: String {
        if isHiDPI {
            return "\(width) × \(height) (HiDPI)"
        } else {
            return "\(width) × \(height)"
        }
    }
}

struct ManagedDisplay: Identifiable, Equatable {
    let displayID: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let vendorID: UInt32
    let productID: UInt32
    var currentMode: DisplayModeItem?
    var availableResolutions: [DisplayModeItem]
    var availableRefreshRates: [Int]

    var id: CGDirectDisplayID { displayID }
}

// MARK: - ResolutionController

@MainActor
final class ResolutionController: ObservableObject {
    static let shared = ResolutionController()

    @Published var displays: [ManagedDisplay] = []

    init() {
        refreshDisplays()
    }

    func refreshDisplays() {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displayIDs, &count) == .success else { return }

        var list: [ManagedDisplay] = []

        for did in displayIDs.prefix(Int(count)) {
            let isBuiltin = CGDisplayIsBuiltin(did) != 0
            let vendor = CGDisplayVendorNumber(did)
            let product = CGDisplayModelNumber(did)

            var name = isBuiltin ? "内建显示器" : "外接显示器"
            if !isBuiltin {
                if vendor == 0x4d67 || product == 0x2725 {
                    name = "H27T22S"
                } else if let dict = CoreDisplayDictionary(for: did) {
                    name = dict
                }
            }

            let allModes = fetchModes(for: did)
            let current = currentMode(for: did, allModes: allModes)

            // Distinct resolutions: prefer HiDPI mode, highest refresh
            var resolutionMap: [String: DisplayModeItem] = [:]
            for mode in allModes {
                let key = mode.resolutionKey
                if let existing = resolutionMap[key] {
                    if !existing.isHiDPI && mode.isHiDPI {
                        resolutionMap[key] = mode
                    } else if existing.isHiDPI == mode.isHiDPI && mode.refreshRate > existing.refreshRate {
                        resolutionMap[key] = mode
                    }
                } else {
                    resolutionMap[key] = mode
                }
            }

            let sortedResolutions = resolutionMap.values.sorted {
                if $0.width != $1.width { return $0.width > $1.width }
                return $0.height > $1.height
            }

            let currentWidth = current?.width ?? 1920
            let currentHeight = current?.height ?? 1080
            let matchingRates = allModes
                .filter { $0.width == currentWidth && $0.height == currentHeight }
                .map { $0.refreshRate }
            let distinctRates = Array(Set(matchingRates)).sorted()

            let isMain = CGDisplayIsMain(did) != 0

            list.append(ManagedDisplay(
                displayID: did,
                name: name,
                isBuiltin: isBuiltin,
                isMain: isMain,
                vendorID: vendor,
                productID: product,
                currentMode: current,
                availableResolutions: sortedResolutions,
                availableRefreshRates: distinctRates.isEmpty ? [60] : distinctRates
            ))
        }

        self.displays = list
    }

    func setMainDisplay(displayID: CGDirectDisplayID) {
        _ = ArrangementService.shared.setAsMainDisplay(targetID: displayID)
        refreshDisplays()
    }

    private func fetchModes(for displayID: CGDirectDisplayID) -> [DisplayModeItem] {
        var count: Int32 = 0
        guard CGSGetNumberOfDisplayModes(displayID, &count) == .success, count > 0 else { return [] }

        var items: [DisplayModeItem] = []
        for i in 0..<count {
            var desc = CGSDisplayModeDescription()
            guard CGSGetDisplayModeDescriptionOfLength(displayID, i, &desc, Int32(MemoryLayout<CGSDisplayModeDescription>.size)) == .success else { continue }
            // Filter unusable modes (bit 0x40000000)
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

    private func currentMode(for displayID: CGDirectDisplayID, allModes: [DisplayModeItem]) -> DisplayModeItem? {
        guard let currentCG = CGDisplayCopyDisplayMode(displayID) else { return nil }
        let currentID = UInt32(bitPattern: currentCG.ioDisplayModeID)
        if let exact = allModes.first(where: { $0.modeNumber == currentID }) {
            return exact
        }
        let w = currentCG.width
        let h = currentCG.height
        return allModes.first(where: { $0.width == w && $0.height == h })
    }

    func setMode(_ mode: DisplayModeItem, for displayID: CGDirectDisplayID) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }

        let err = CGSConfigureDisplayMode(cfg, displayID, Int32(mode.modeNumber))
        if err == .success {
            CGCompleteDisplayConfiguration(cfg, .permanently)
        } else {
            CGCancelDisplayConfiguration(cfg)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshDisplays()
        }
    }

    func setRefreshRate(_ refreshRate: Int, for displayID: CGDirectDisplayID) {
        guard let display = displays.first(where: { $0.displayID == displayID }),
              let current = display.currentMode else { return }

        let allModes = fetchModes(for: displayID)
        let candidates = allModes.filter {
            $0.width == current.width && $0.height == current.height && $0.refreshRate == refreshRate
        }
        // Prefer HiDPI if current is HiDPI
        let target = candidates.first(where: { $0.isHiDPI == current.isHiDPI }) ?? candidates.first
        if let target = target {
            setMode(target, for: displayID)
        }
    }


    private func CoreDisplayDictionary(for displayID: CGDirectDisplayID) -> String? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
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
            if let names = cfDict["DisplayProductName"] as? [String: String], let first = names.values.first {
                return first
            }
        }
        return nil
    }
}
