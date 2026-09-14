import AppKit
import Darwin

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
