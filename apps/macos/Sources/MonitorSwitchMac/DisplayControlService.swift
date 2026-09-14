import AppKit
import AppleSiliconDDC
import CoreGraphics
import Foundation

// MARK: - DisplayServices & SkyLight Bindings

private let _DSSetBrightness: (@convention(c) (CGDirectDisplayID, Float) -> Int32)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
          let sym = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)
}()

private let _DSGetBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
          let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
}()

private let _SLSGetAppearanceTheme: (@convention(c) () -> Bool)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let sym = dlsym(h, "SLSGetAppearanceThemeLegacy") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) () -> Bool).self)
}()

private let _SLSSetAppearanceThemeNotifying: (@convention(c) (Bool, Bool) -> Void)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let sym = dlsym(h, "SLSSetAppearanceThemeNotifying") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (Bool, Bool) -> Void).self)
}()

// MARK: - DisplayControlService

@MainActor
final class DisplayControlService: ObservableObject {
    static let shared = DisplayControlService()

    @Published var externalBrightness: Double = 75
    @Published var externalVolume: Double = 50
    @Published var internalBrightness: Double = 80

    @Published var isDarkMode: Bool = false
    @Published var isNightShift: Bool = false
    @Published var isTrueTone: Bool = false

    private var blueLightClient: NSObject?
    private var trueToneClient: NSObject?

    private var externalBrightnessWorkItem: DispatchWorkItem?
    private var externalVolumeWorkItem: DispatchWorkItem?

    private init() {
        initSystemClients()
        refreshAll()
    }

    private func initSystemClients() {
        if dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil {
            if let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
                blueLightClient = cls.init()
            }
            if let cls = NSClassFromString("CBTrueToneClient") as? NSObject.Type {
                trueToneClient = cls.init()
            }
        }
    }

    func refreshAll() {
        // Read internal brightness
        var b: Float = 0
        if let getFn = _DSGetBrightness {
            _ = getFn(1, &b)
            internalBrightness = Double(b * 100)
        }

        // Read dark mode
        if let getDark = _SLSGetAppearanceTheme {
            isDarkMode = getDark()
        }

        // Read night shift & true tone
        if let bClient = blueLightClient {
            let sel = NSSelectorFromString("getBlueLightStatus:")
            if bClient.responds(to: sel) {
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
                buf.initialize(repeating: 0, count: 64)
                defer {
                    buf.deinitialize(count: 64)
                    buf.deallocate()
                }
                let imp = bClient.method(for: sel)
                typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
                let fn = unsafeBitCast(imp, to: Fn.self)
                if fn(bClient, sel, buf) {
                    isNightShift = (buf[0] != 0) || (buf[2] != 0)
                }
            }
        }

        if let tClient = trueToneClient {
            let sel = NSSelectorFromString("enabled")
            if tClient.responds(to: sel) {
                let imp = tClient.method(for: sel)
                typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
                let fn = unsafeBitCast(imp, to: Fn.self)
                isTrueTone = fn(tClient, sel)
            }
        }
    }

    // MARK: - Internal Brightness

    func setInternalBrightness(_ value: Double) {
        internalBrightness = value
        let fraction = Float(max(0, min(100, value)) / 100.0)
        _ = _DSSetBrightness?(1, fraction)
    }

    // MARK: - External Brightness & Volume (DDC)

    func setExternalBrightness(_ value: Double) {
        externalBrightness = value
        externalBrightnessWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.writeExternalDDC(command: 0x10, value: UInt16(value))
        }
        externalBrightnessWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func setExternalVolume(_ value: Double) {
        externalVolume = value
        externalVolumeWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.writeExternalDDC(command: 0x62, value: UInt16(value))
        }
        externalVolumeWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func writeExternalDDC(command: UInt8, value: UInt16) {
        let displays = AppleSiliconDDC.getIoregServicesForMatching().filter { display in
            display.service != nil && (!display.productName.isEmpty || !display.edidUUID.isEmpty)
        }
        guard let first = displays.first else { return }
        _ = AppleSiliconDDC.write(
            service: first.service,
            command: command,
            value: value,
            numOfWriteCycles: 1,
            numOfRetryAttemps: 1
        )
    }

    // MARK: - System Toggles

    func toggleDarkMode() {
        let newMode = !isDarkMode
        isDarkMode = newMode
        _SLSSetAppearanceThemeNotifying?(newMode, true)
    }

    func toggleNightShift() {
        guard let client = blueLightClient else { return }
        let newEnabled = !isNightShift
        isNightShift = newEnabled
        let sel = NSSelectorFromString("setEnabled:")
        if client.responds(to: sel) {
            let imp = client.method(for: sel)
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
            let fn = unsafeBitCast(imp, to: Fn.self)
            _ = fn(client, sel, newEnabled)
        }
    }

    func toggleTrueTone() {
        guard let client = trueToneClient else { return }
        let newEnabled = !isTrueTone
        isTrueTone = newEnabled
        let sel = NSSelectorFromString("setEnabled:")
        if client.responds(to: sel) {
            let imp = client.method(for: sel)
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(client, sel, newEnabled)
        }
    }
}
