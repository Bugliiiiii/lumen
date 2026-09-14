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

private typealias SLSConfigureDisplayEnabledFunc = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError
private typealias SLSGetDisplayListFunc = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>) -> CGError

@MainActor
private enum SkyLight {
    private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    }()

    private static let _configureDisplayEnabled: SLSConfigureDisplayEnabledFunc? = {
        guard let handle = handle, let sym = dlsym(handle, "SLSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(sym, to: SLSConfigureDisplayEnabledFunc.self)
    }()

    private static let _getDisplayList: SLSGetDisplayListFunc? = {
        guard let handle = handle, let sym = dlsym(handle, "SLSGetDisplayList") else { return nil }
        return unsafeBitCast(sym, to: SLSGetDisplayListFunc.self)
    }()

    static func configureDisplayEnabled(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError {
        guard let fn = _configureDisplayEnabled else { return .cannotComplete }
        return fn(config, display, enabled)
    }

    static func getDisplayList(_ count: UInt32, _ displays: UnsafeMutablePointer<CGDirectDisplayID>?, _ outCount: UnsafeMutablePointer<UInt32>) -> CGError {
        guard let fn = _getDisplayList else { return .cannotComplete }
        return fn(count, displays, outCount)
    }
}

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

struct RecommendedMode: Identifiable, Hashable, Sendable {
    let mode: DisplayModeItem
    let badge: String       // e.g. "最佳推荐", "宽广工作区", "原生点对点"
    let systemImage: String // e.g. "star.fill", "arrow.left.and.right", "display"
    let subtitle: String    // e.g. "舒适且清晰", "更多工作空间", "1:1 像素映射"
    var id: UInt32 { mode.modeNumber }
}

struct ManagedDisplay: Identifiable, Equatable {
    let displayID: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    var isMirrored: Bool = false
    var mirrorMasterID: CGDirectDisplayID? = nil
    var isDisconnected: Bool = false
    let vendorID: UInt32
    let productID: UInt32
    var currentMode: DisplayModeItem?
    var recommendedModes: [RecommendedMode]
    var standardModes: [DisplayModeItem]
    var fineTuningModes: [DisplayModeItem]
    var availableResolutions: [DisplayModeItem]
    var availableRefreshRates: [Int]

    var id: CGDirectDisplayID { displayID }

    var topRecommendedMode: DisplayModeItem? {
        recommendedModes.first?.mode
    }

    var isAtTopRecommended: Bool {
        guard let cur = currentMode, let top = topRecommendedMode else { return false }
        return cur.width == top.width && cur.height == top.height && cur.isHiDPI == top.isHiDPI
    }
}

// MARK: - ResolutionController

@MainActor
final class ResolutionController: ObservableObject {
    static let shared = ResolutionController()

    @Published var displays: [ManagedDisplay] = []
    @Published var disconnectedDisplays: [CGDirectDisplayID: ManagedDisplay] = [:]
    private var savedExtendedModes: [CGDirectDisplayID: DisplayModeItem] = [:]

    var activeDisplayCount: Int {
        displays.filter { !$0.isDisconnected }.count
    }

    var hasDisconnectedDisplays: Bool {
        !disconnectedDisplays.isEmpty
    }

    private static let standardAspectPairs: Set<String> = [
        // 16:9
        "3840 × 2160", "2560 × 1440", "2048 × 1152", "1920 × 1080", "1600 × 900", "1366 × 768", "1280 × 720",
        // 16:10
        "2560 × 1600", "1920 × 1200", "1680 × 1050", "1440 × 900", "1280 × 800",
        // Apple Retina Displays
        "1800 × 1169", "1710 × 1112", "1710 × 1107", "1536 × 960", "1512 × 982", "1728 × 1117", "1470 × 956", "1352 × 878", "1280 × 832", "1024 × 665",
        // 21:9 UltraWide
        "5120 × 2160", "3440 × 1440", "2580 × 1080", "2560 × 1080"
    ]

    init() {
        refreshDisplays()
    }

    func refreshDisplays() {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displayIDs, &count) == .success else { return }

        // Clean up disconnectedDisplays if physically unplugged (not present in SLSGetDisplayList)
        var slsCount: UInt32 = 0
        if SkyLight.getDisplayList(0, nil, &slsCount) == .success, slsCount > 0 {
            var slsList = [CGDirectDisplayID](repeating: 0, count: Int(slsCount))
            if SkyLight.getDisplayList(slsCount, &slsList, &slsCount) == .success {
                let slsSet = Set(slsList)
                disconnectedDisplays = disconnectedDisplays.filter { slsSet.contains($0.key) }
            }
        }

        var list: [ManagedDisplay] = []

        for did in displayIDs.prefix(Int(count)) {
            disconnectedDisplays.removeValue(forKey: did)

            let isBuiltin = CGDisplayIsBuiltin(did) != 0
            let vendor = CGDisplayVendorNumber(did)
            let product = CGDisplayModelNumber(did)
            let isMirrored = CGDisplayMirrorsDisplay(did) != 0 || CGDisplayIsInMirrorSet(did) != 0
            let mirrorMaster = CGDisplayMirrorsDisplay(did) != 0 ? CGDisplayMirrorsDisplay(did) : nil

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

            // Identify Recommended Modes
            var recList: [RecommendedMode] = []
            if isBuiltin {
                if let cur = current {
                    recList.append(RecommendedMode(mode: cur, badge: "最佳推荐", systemImage: "star.fill", subtitle: "原厂视网膜"))
                }
                let presets: [(key: String, badge: String, icon: String, sub: String)] = [
                    ("1710 × 1112", "宽广工作区", "arrow.left.and.right", "更多工作空间"),
                    ("1710 × 1107", "宽广工作区", "arrow.left.and.right", "更多工作空间"),
                    ("1470 × 956", "舒适缩放", "star.fill", "舒适且清晰"),
                    ("1512 × 982", "舒适缩放", "star.fill", "舒适且清晰"),
                    ("1280 × 832", "大字体", "textformat.size.larger", "清晰易读")
                ]
                for p in presets {
                    if let m = resolutionMap[p.key], m.width != current?.width || m.height != current?.height {
                        recList.append(RecommendedMode(mode: m, badge: p.badge, systemImage: p.icon, subtitle: p.sub))
                    }
                }
                if recList.isEmpty, let firstHiDPI = sortedResolutions.first(where: { $0.isHiDPI }) {
                    recList.append(RecommendedMode(mode: firstHiDPI, badge: "最佳推荐", systemImage: "star.fill", subtitle: "视网膜推荐缩放"))
                }
            } else {
                let isKnown2K = (vendor == 0x4d67 || product == 0x2725 || name.contains("H27T22S") || name.contains("2K") || name.contains("QHD"))
                let isUltraWide = resolutionMap["3440 × 1440"] != nil || resolutionMap["2560 × 1080"] != nil
                let hasReal4K = !isKnown2K && resolutionMap["3840 × 2160"] != nil && resolutionMap["3840 × 2160"]?.isHiDPI == false

                if isUltraWide {
                    if let m = resolutionMap["2580 × 1080"] ?? resolutionMap["2560 × 1080"], m.isHiDPI {
                        recList.append(RecommendedMode(mode: m, badge: "最佳推荐", systemImage: "star.fill", subtitle: "视网膜超宽清晰度"))
                    }
                    if let m = resolutionMap["3440 × 1440"] {
                        recList.append(RecommendedMode(mode: m, badge: "原生点对点", systemImage: "display", subtitle: "1:1 像素映射"))
                    }
                } else if isKnown2K || !hasReal4K {
                    // 2K Display (like H27T22S 2560x1440)
                    if let m = resolutionMap["1920 × 1080"], m.isHiDPI {
                        recList.append(RecommendedMode(mode: m, badge: "最佳推荐", systemImage: "star.fill", subtitle: "舒适且清晰"))
                    }
                    if let m = resolutionMap["2048 × 1152"], m.isHiDPI {
                        recList.append(RecommendedMode(mode: m, badge: "宽广工作区", systemImage: "arrow.left.and.right", subtitle: "更多工作空间"))
                    }
                    if let m = resolutionMap["2560 × 1440"] {
                        recList.append(RecommendedMode(mode: m, badge: "原生点对点", systemImage: "display", subtitle: "1:1 像素映射"))
                    }
                } else {
                    // Real 4K Monitor
                    if let m = resolutionMap["2560 × 1440"], m.isHiDPI {
                        recList.append(RecommendedMode(mode: m, badge: "最佳推荐", systemImage: "star.fill", subtitle: "舒适且清晰"))
                    }
                    if let m = resolutionMap["1920 × 1080"], m.isHiDPI {
                        recList.append(RecommendedMode(mode: m, badge: "大字体", systemImage: "textformat.size.larger", subtitle: "清晰易读"))
                    }
                    if let m = resolutionMap["3840 × 2160"] {
                        recList.append(RecommendedMode(mode: m, badge: "原生 4K", systemImage: "display", subtitle: "1:1 像素映射"))
                    }
                }
            }

            let recKeySet = Set(recList.map { $0.mode.resolutionKey })
            let standardModes = sortedResolutions.filter { m in
                let k = m.resolutionKey
                return Self.standardAspectPairs.contains(k) && !recKeySet.contains(k)
            }
            let fineTuningModes = sortedResolutions.filter { m in
                let k = m.resolutionKey
                return !Self.standardAspectPairs.contains(k) && !recKeySet.contains(k)
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
                isMirrored: isMirrored,
                mirrorMasterID: mirrorMaster,
                isDisconnected: false,
                vendorID: vendor,
                productID: product,
                currentMode: current,
                recommendedModes: recList,
                standardModes: standardModes,
                fineTuningModes: fineTuningModes,
                availableResolutions: sortedResolutions,
                availableRefreshRates: distinctRates.isEmpty ? [60] : distinctRates
            ))
        }

        // Include disconnected displays
        for (_, disDisplay) in disconnectedDisplays {
            list.append(disDisplay)
        }

        self.displays = list
    }

    func setMainDisplay(displayID: CGDirectDisplayID) {
        _ = ArrangementService.shared.setAsMainDisplay(targetID: displayID)
        refreshDisplays()
    }

    func disconnectDisplay(_ display: ManagedDisplay) {
        let activeCount = displays.filter { !$0.isDisconnected }.count
        guard activeCount > 1 else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }
        let err = SkyLight.configureDisplayEnabled(cfg, display.displayID, false)
        if err == .success {
            CGCompleteDisplayConfiguration(cfg, .forSession)
            var saved = display
            saved.isDisconnected = true
            disconnectedDisplays[display.displayID] = saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.refreshDisplays()
                ArrangementService.shared.refresh()
            }
        } else {
            CGCancelDisplayConfiguration(cfg)
        }
    }

    func reconnectDisplay(_ displayID: CGDirectDisplayID) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }
        let err = SkyLight.configureDisplayEnabled(cfg, displayID, true)
        if err == .success {
            CGCompleteDisplayConfiguration(cfg, .forSession)
            disconnectedDisplays.removeValue(forKey: displayID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.refreshDisplays()
                ArrangementService.shared.refresh()
            }
        } else {
            CGCancelDisplayConfiguration(cfg)
        }
    }

    func setMirror(for displayID: CGDirectDisplayID, masterID: CGDirectDisplayID?) {
        guard let display = displays.first(where: { $0.displayID == displayID }) else { return }

        // 1. Guard against no-op reconfigurations (which cause unnecessary screen resets/flickering)
        if masterID == nil && !display.isMirrored {
            return
        }
        if let master = masterID, display.isMirrored && display.mirrorMasterID == master {
            return
        }

        // 2. If entering mirror mode, record current non-mirrored mode
        if masterID != nil {
            if let cur = display.currentMode {
                savedExtendedModes[displayID] = cur
            }
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else { return }

        if let master = masterID {
            CGConfigureDisplayMirrorOfDisplay(cfg, displayID, master)
        } else {
            CGConfigureDisplayMirrorOfDisplay(cfg, displayID, kCGNullDirectDisplay)
            // Explicitly restore previous extended mode or top recommended native mode (e.g. 2560x1440)
            // to avoid macOS defaulting to a 4K pseudo-downsampled mode (3840x2160) that overloads HDMI bandwidth and flickers!
            let restoreMode = savedExtendedModes[displayID] ?? display.topRecommendedMode
            if let target = restoreMode {
                _ = CGSConfigureDisplayMode(cfg, displayID, Int32(target.modeNumber))
            }
        }

        let result = CGCompleteDisplayConfiguration(cfg, .forSession)
        if result == .success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.refreshDisplays()
                ArrangementService.shared.refresh()
            }
        } else {
            CGCancelDisplayConfiguration(cfg)
        }
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
