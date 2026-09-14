import AppKit
import SwiftUI

final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class AutoSizingHostingView<Content: View>: NSHostingView<Content> {
    var onFittingSizeChanged: ((CGSize) -> Void)?
    private var lastFittingSize: CGSize = .zero

    override func layout() {
        super.layout()
        let fit = fittingSize
        if fit.height > 50 && (abs(fit.height - lastFittingSize.height) > 1 || abs(fit.width - lastFittingSize.width) > 1) {
            lastFittingSize = fit
            Task { @MainActor [weak self] in
                self?.onFittingSizeChanged?(fit)
            }
        }
    }
}

@MainActor
final class MenuPanelController {
    private var panel: MenuPanel?
    private var outsideClickMonitor: Any?
    private(set) var isShown = false
    private weak var currentStatusButton: NSStatusBarButton?

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    func toggle(for statusItem: NSStatusItem, model: AppModel) {
        if isShown {
            close()
        } else {
            show(for: statusItem, model: model)
        }
    }

    func show(for statusItem: NSStatusItem, model: AppModel) {
        guard let button = statusItem.button else { return }
        currentStatusButton = button

        // Refresh external display resolutions, states, and arrangements
        ResolutionController.shared.refreshDisplays()
        DisplayControlService.shared.refreshAll()
        ArrangementService.shared.refresh()

        if panel == nil {
            let p = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200))
            p.onCancel = { [weak self] in
                self?.close()
            }
            panel = p
        }

        guard let p = panel else { return }

        let rootView = ControlCenterPanelView(
            appModel: model,
            onOpenSettings: { [weak self] in
                self?.close()
                self?.onOpenSettings?()
            },
            onQuit: { [weak self] in
                self?.close()
                self?.onQuit?()
            },
            onSizeChange: { [weak self] newSize in
                Task { @MainActor in
                    self?.adjustPanelSize(newSize, animated: true)
                }
            }
        )

        let hostingView = AutoSizingHostingView(rootView: rootView)
        hostingView.onFittingSizeChanged = { [weak self] fitSize in
            self?.adjustPanelSize(fitSize, animated: true)
        }

        let initialSize = hostingView.fittingSize

        // Frosted glass shell container
        let shellView = NSView(frame: NSRect(origin: .zero, size: initialSize))
        shellView.wantsLayer = true
        shellView.layer?.cornerRadius = 18
        shellView.layer?.masksToBounds = true
        shellView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        shellView.layer?.borderWidth = 0.5
        shellView.autoresizingMask = [.width, .height]

        let effectView = NSVisualEffectView(frame: shellView.bounds)
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        shellView.addSubview(effectView)

        hostingView.frame = shellView.bounds
        hostingView.autoresizingMask = [.width, .height]
        shellView.addSubview(hostingView)

        p.contentView = shellView

        adjustPanelSize(initialSize, animated: false)

        p.orderFrontRegardless()
        p.makeKey()
        isShown = true

        // Install outside-click monitor
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    func adjustPanelSize(_ newSize: CGSize, animated: Bool) {
        guard let p = panel, let button = currentStatusButton else { return }
        guard let btnWindow = button.window else { return }
        let btnFrame = btnWindow.frame
        let screen = btnWindow.screen ?? NSScreen.main ?? NSScreen.screens.first

        let targetWidth = max(newSize.width, 320)
        let targetHeight = max(ceil(newSize.height), 100)

        // Top edge of the panel: 4pt below status bar button
        let topY = btnFrame.minY - 4
        var bottomY = topY - targetHeight
        var x = btnFrame.midX - targetWidth / 2

        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX + 8), vis.maxX - targetWidth - 8)
            bottomY = max(vis.minY + 8, bottomY)
        }

        let targetFrame = NSRect(x: x, y: bottomY, width: targetWidth, height: targetHeight)

        // If the frame is already matching, ignore
        if abs(p.frame.width - targetFrame.width) < 1 &&
           abs(p.frame.height - targetFrame.height) < 1 &&
           abs(p.frame.origin.y - targetFrame.origin.y) < 1 &&
           abs(p.frame.origin.x - targetFrame.origin.x) < 1 {
            return
        }

        if animated && isShown {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                p.animator().setFrame(targetFrame, display: true)
            }
        } else {
            p.setFrame(targetFrame, display: true)
        }
    }

    func close() {
        guard isShown else { return }
        panel?.orderOut(nil)
        isShown = false
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
