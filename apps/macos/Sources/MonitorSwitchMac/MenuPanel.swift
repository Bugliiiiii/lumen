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

@MainActor
final class MenuPanelController {
    private var panel: MenuPanel?
    private var outsideClickMonitor: Any?
    private(set) var isShown = false

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

        // Refresh external display resolutions, states, and arrangements
        ResolutionController.shared.refreshDisplays()
        DisplayControlService.shared.refreshAll()
        ArrangementService.shared.refresh()

        if panel == nil {
            let p = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 400))
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
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        let naturalSize = hostingView.fittingSize

        // Frosted glass shell container
        let shellView = NSView(frame: NSRect(origin: .zero, size: naturalSize))
        shellView.wantsLayer = true
        shellView.layer?.cornerRadius = 18
        shellView.layer?.masksToBounds = true
        shellView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        shellView.layer?.borderWidth = 0.5

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
        p.setContentSize(naturalSize)

        // Position under status bar button
        guard let btnWindow = button.window else { return }
        let btnFrame = btnWindow.frame
        let screen = btnWindow.screen ?? NSScreen.main ?? NSScreen.screens.first

        let panelSize = hostingView.fittingSize
        var x = btnFrame.midX - panelSize.width / 2
        var y = btnFrame.minY - panelSize.height - 4

        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX + 8), vis.maxX - panelSize.width - 8)
            y = max(vis.minY + 8, y)
        }

        p.setFrameOrigin(NSPoint(x: x, y: y))
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
