import AppKit
import SwiftUI

// MARK: - Design Tokens & Styles

struct QuietSegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LiquidGlassPanel<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.32))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

struct SettingDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }
}

// MARK: - Control Center Panel View

struct ControlCenterPanelView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var resController = ResolutionController.shared
    @ObservedObject var controlService = DisplayControlService.shared
    @ObservedObject var hidpiService = HiDPIService.shared
    @ObservedObject var arrangementService = ArrangementService.shared

    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 1. Dual-Machine Signal Switcher (Segmented Glass Control)
            signalSwitchSection

            // 2. Connected Displays (Liquid Glass Panels)
            ForEach(resController.displays) { display in
                displaySection(for: display)
            }

            // 3. Screen Arrangement (Displays Layout Canvas)
            if arrangementService.placements.count >= 2 {
                screenArrangementSection
            }

            // 4. Quick Toggles (Segmented Glass Control)
            systemQuickToggles

            // 5. Minimal Footer
            footerSection
        }
        .padding(10)
        .frame(width: 320)
        .background(Color.clear)
    }

    // MARK: - 1. Signal Switch Section

    private var signalSwitchSection: some View {
        LiquidGlassPanel(padding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("输入源")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)

                    Spacer()

                    Text(appModel.settings.shortcutText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                let activeInput = appModel.snapshot?.currentInput ?? appModel.lastTargetInput
                let isWindowsActive = activeInput == appModel.settings.windowsInput
                let isMacActive = activeInput == appModel.settings.macInput

                HStack(spacing: 3) {
                    inputSegment(
                        title: appModel.settings.windowsLabel,
                        connector: InputSourceCatalog.connectorName(for: appModel.settings.windowsInput),
                        icon: "desktopcomputer",
                        isActive: isWindowsActive
                    ) {
                        appModel.switchToWindows()
                    }

                    inputSegment(
                        title: appModel.settings.macLabel,
                        connector: InputSourceCatalog.connectorName(for: appModel.settings.macInput),
                        icon: "laptopcomputer",
                        isActive: isMacActive
                    ) {
                        appModel.switchToMac()
                    }
                }
                .padding(2.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private func inputSegment(
        title: String,
        connector: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.7))

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(title)
                        .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(Color.primary)
                    Text(connector)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
            }
        }
        .buttonStyle(QuietSegmentButtonStyle())
    }

    // MARK: - 2. Display Section

    @ViewBuilder
    private func displaySection(for display: ManagedDisplay) -> some View {
        LiquidGlassPanel(padding: 9) {
            VStack(alignment: .leading, spacing: 7) {
                // Header: Icon + Name + Spec
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 1.5) {
                        HStack(spacing: 5) {
                            Text(display.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.primary)

                            if display.isAtTopRecommended {
                                Text("推荐")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                            }
                        }

                        if let cur = display.currentMode {
                            let hidpiSuffix = cur.isHiDPI ? " · HiDPI" : ""
                            Text("\(cur.width) × \(cur.height) · \(cur.refreshRate) Hz\(hidpiSuffix)")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                                .contextMenu {
                                    if !display.isBuiltin && hidpiService.isHiDPIInstalled(vendor: display.vendorID, product: display.productID) {
                                        Button(role: .destructive) {
                                            Task {
                                                hidpiService.isWorking = true
                                                let err = await hidpiService.disableHiDPI(vendor: display.vendorID, product: display.productID)
                                                hidpiService.statusError = err
                                                hidpiService.isWorking = false
                                            }
                                        } label: {
                                            Label("移除 2K HiDPI 渲染配置...", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }

                    Spacer()

                    if !display.isAtTopRecommended, let top = display.topRecommendedMode {
                        Button {
                            resController.setMode(top, for: display.displayID)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                Text("恢复推荐")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(QuietSegmentButtonStyle())
                    }
                }

                // Sliders
                if display.isBuiltin {
                    RefinedSlider(
                        value: $controlService.internalBrightness,
                        range: 0...100,
                        leftIcon: "sun.min",
                        rightIcon: "sun.max"
                    ) { val in
                        controlService.setInternalBrightness(val)
                    }
                } else {
                    VStack(spacing: 4) {
                        RefinedSlider(
                            value: $controlService.externalBrightness,
                            range: 0...100,
                            leftIcon: "sun.min",
                            rightIcon: "sun.max"
                        ) { val in
                            controlService.setExternalBrightness(val)
                        }

                        RefinedSlider(
                            value: $controlService.externalVolume,
                            range: 0...100,
                            leftIcon: "speaker.wave.1",
                            rightIcon: "speaker.wave.3"
                        ) { val in
                            controlService.setExternalVolume(val)
                        }
                    }
                }

                // Setting Rows with thin native dividers
                VStack(spacing: 0) {
                    mainDisplayRow(for: display)

                    SettingDivider()

                    resolutionPickerRow(for: display)

                    if !display.isBuiltin {
                        SettingDivider()

                        refreshRatePickerRow(for: display)

                        if !hidpiService.isHiDPIInstalled(vendor: display.vendorID, product: display.productID) {
                            SettingDivider()

                            hidpiRow(for: display)
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func mainDisplayRow(for display: ManagedDisplay) -> some View {
        HStack {
            Label("主显示器", systemImage: "m.circle")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.primary)
            Spacer()
            if display.isMain {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("当前主屏幕")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Button("设为主显示器") {
                    resController.setMainDisplay(displayID: display.displayID)
                }
                .font(.system(size: 10.5))
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func resolutionPickerRow(for display: ManagedDisplay) -> some View {
        HStack {
            Label("分辨率", systemImage: "rectangle.inset.filled")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.primary)
            Spacer()
            Menu {
                if !display.recommendedModes.isEmpty {
                    Section("⭐ 推荐最佳分辨率") {
                        ForEach(display.recommendedModes) { rec in
                            Button {
                                resController.setMode(rec.mode, for: display.displayID)
                            } label: {
                                HStack {
                                    Text("\(rec.badge)  \(rec.mode.displayName) · \(rec.subtitle)")
                                    if display.currentMode?.width == rec.mode.width && display.currentMode?.height == rec.mode.height && display.currentMode?.isHiDPI == rec.mode.isHiDPI {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !display.standardModes.isEmpty {
                    Section("常用标准分辨率") {
                        ForEach(display.standardModes) { mode in
                            Button {
                                resController.setMode(mode, for: display.displayID)
                            } label: {
                                HStack {
                                    Text(mode.displayName)
                                    if display.currentMode?.width == mode.width && display.currentMode?.height == mode.height && display.currentMode?.isHiDPI == mode.isHiDPI {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !display.fineTuningModes.isEmpty {
                    Menu("更多微调分辨率 (\(display.fineTuningModes.count)+)...") {
                        ForEach(display.fineTuningModes) { mode in
                            Button {
                                resController.setMode(mode, for: display.displayID)
                            } label: {
                                HStack {
                                    Text(mode.displayName)
                                    if display.currentMode?.width == mode.width && display.currentMode?.height == mode.height {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(display.currentMode?.displayName ?? "选择")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func refreshRatePickerRow(for display: ManagedDisplay) -> some View {
        HStack {
            Label("刷新率", systemImage: "waveform.path.ecg")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.primary)
            Spacer()
            Menu {
                ForEach(display.availableRefreshRates, id: \.self) { rate in
                    Button {
                        resController.setRefreshRate(rate, for: display.displayID)
                    } label: {
                        HStack {
                            Text("\(rate) Hz")
                            if display.currentMode?.refreshRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(display.currentMode?.refreshRate ?? 60) Hz")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func hidpiRow(for display: ManagedDisplay) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0.5) {
                Label("2K HiDPI 锐利渲染", systemImage: "sparkles")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.primary)
                Text("点击注入 2K HiDPI 缩放")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button("开启") {
                Task {
                    hidpiService.isWorking = true
                    let err = await hidpiService.enableHiDPI(vendor: display.vendorID, product: display.productID)
                    hidpiService.statusError = err
                    hidpiService.isWorking = false
                }
            }
            .font(.system(size: 10.5))
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(hidpiService.isWorking)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    // MARK: - 3. Screen Arrangement Section

    private var screenArrangementSection: some View {
        LiquidGlassPanel(padding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Label("屏幕排列", systemImage: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)

                    Spacer()

                    // Main Display Switcher Dropdown
                    Menu {
                        ForEach(arrangementService.placements) { p in
                            Button {
                                arrangementService.setAsMainDisplay(targetID: p.id)
                                resController.refreshDisplays()
                            } label: {
                                HStack {
                                    Text(p.name)
                                    if p.isMain {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        let mainP = arrangementService.placements.first(where: { $0.isMain })
                        let mainName = mainP?.name ?? "主屏"
                        let shortName = mainName.contains("内建") ? "内建" : (mainName.components(separatedBy: " ").first ?? "外接")
                        Text("主屏: \(shortName)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Visual Arrangement Canvas with live dragging
                ArrangementMiniCanvas(service: arrangementService)
                    .frame(height: 80)
                    .background(Color.primary.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
            }
        }
    }

    // MARK: - 4. Quick Toggles (Segmented Glass Control)

    private var systemQuickToggles: some View {
        LiquidGlassPanel(padding: 3) {
            HStack(spacing: 2.5) {
                modeSegment(
                    title: "深色模式",
                    icon: controlService.isDarkMode ? "moon.fill" : "moon",
                    isActive: controlService.isDarkMode,
                    tint: Color.blue
                ) {
                    controlService.toggleDarkMode()
                }

                modeSegment(
                    title: "护眼模式",
                    icon: controlService.isNightShift ? "sun.max.fill" : "sun.max",
                    isActive: controlService.isNightShift,
                    tint: Color.orange
                ) {
                    controlService.toggleNightShift()
                }

                modeSegment(
                    title: "原彩显示",
                    icon: controlService.isTrueTone ? "circle.lefthalf.filled" : "circle",
                    isActive: controlService.isTrueTone,
                    tint: Color.teal
                ) {
                    controlService.toggleTrueTone()
                }
            }
        }
    }

    @ViewBuilder
    private func modeSegment(
        title: String,
        icon: String,
        isActive: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? tint : Color.secondary)

                Text(title)
                    .font(.system(size: 10.5, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? tint.opacity(0.12) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? tint.opacity(0.28) : Color.clear, lineWidth: 0.5)
            }
        }
        .buttonStyle(QuietSegmentButtonStyle())
    }

    // MARK: - 5. Footer

    private var footerSection: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10.5))
                    Text("设置…")
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onQuit()
            } label: {
                Text("退出")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
    }
}

// MARK: - Refined Slider

struct RefinedSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let leftIcon: String
    let rightIcon: String
    var onChanged: (Double) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: leftIcon)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.secondary.opacity(0.85))
                .frame(width: 12)

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let percent = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                let clampedPercent = max(0, min(1, percent))
                let fillWidth = totalWidth * clampedPercent
                let knobX = min(max(fillWidth, 6), totalWidth - 6)

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.primary.opacity(0.09))
                        .frame(height: 3.5)

                    // Track fill
                    Capsule()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: fillWidth, height: 3.5)

                    // Circular Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 0.8)
                        .position(x: knobX, y: geo.size.height / 2)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let newPercent = max(0, min(1, gesture.location.x / totalWidth))
                            let newValue = range.lowerBound + Double(newPercent) * (range.upperBound - range.lowerBound)
                            value = newValue
                            onChanged(newValue)
                        }
                )
            }
            .frame(height: 16)

            Image(systemName: rightIcon)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.secondary.opacity(0.85))
                .frame(width: 12)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Arrangement Mini Canvas

struct ArrangementMiniCanvas: View {
    @ObservedObject var service: ArrangementService

    var body: some View {
        GeometryReader { geo in
            let placements = service.placements
            if placements.isEmpty {
                Color.clear
            } else {
                let layout = computeLayout(canvasSize: geo.size, placements: placements)
                let scale = layout.scale

                ZStack {
                    ForEach(placements) { p in
                        if let rect = layout.rects[p.id] {
                            let isDragged = service.draggedID == p.id
                            let offsetX = isDragged ? service.dragOffset.width : 0
                            let offsetY = isDragged ? service.dragOffset.height : 0

                            thumbnail(for: p, rect: rect, isDragged: isDragged)
                                .frame(width: max(rect.width, 52), height: max(rect.height, 34))
                                .position(x: rect.midX + offsetX, y: rect.midY + offsetY)
                                .zIndex(isDragged ? 10 : 1)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                         .onChanged { gesture in
                                             service.draggedID = p.id
                                             service.dragOffset = gesture.translation
                                         }
                                         .onEnded { gesture in
                                             let moved = abs(gesture.translation.width) + abs(gesture.translation.height)
                                             if moved > 4 {
                                                 _ = service.applyDrag(for: p.id, translation: gesture.translation, scale: scale)
                                             }
                                             service.draggedID = nil
                                             service.dragOffset = .zero
                                         }
                                 )
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for p: DisplayPlacement, rect: CGRect, isDragged: Bool) -> some View {
        ZStack {
            // Monitor Frame
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    isDragged
                        ? Color.accentColor.opacity(0.18)
                        : (p.isMain ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.05))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            isDragged
                                ? Color.accentColor
                                : (p.isMain ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.18)),
                            lineWidth: isDragged ? 1.2 : (p.isMain ? 0.9 : 0.5)
                        )
                }
                .shadow(color: Color.black.opacity(isDragged ? 0.15 : 0.04), radius: isDragged ? 4 : 1.5, x: 0, y: isDragged ? 2 : 0.5)

            // Main Menu Bar Stripe
            if p.isMain {
                VStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.85))
                        .frame(height: 2.5)
                        .padding(.horizontal, 2.5)
                        .padding(.top, 2)
                    Spacer()
                }
            }

            // Monitor Icon & Text
            VStack(spacing: 1.5) {
                Image(systemName: p.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 11))
                    .foregroundStyle(p.isMain ? Color.accentColor : Color.primary.opacity(0.8))

                Text(p.isBuiltin ? "内建" : (p.name.components(separatedBy: " ").first ?? "外接"))
                    .font(.system(size: 9, weight: p.isMain ? .semibold : .medium))
                    .foregroundStyle(p.isMain ? Color.accentColor : Color.primary)
                    .lineLimit(1)
            }
            .padding(3)
        }
        .scaleEffect(isDragged ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isDragged)
    }

    private struct LayoutResult {
        let rects: [CGDirectDisplayID: CGRect]
        let scale: CGFloat
    }

    private func computeLayout(canvasSize: CGSize, placements: [DisplayPlacement]) -> LayoutResult {
        guard !placements.isEmpty else { return LayoutResult(rects: [:], scale: 1) }

        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity

        for p in placements {
            minX = min(minX, p.bounds.minX)
            minY = min(minY, p.bounds.minY)
            maxX = max(maxX, p.bounds.maxX)
            maxY = max(maxY, p.bounds.maxY)
        }

        let totalW = max(1, maxX - minX)
        let totalH = max(1, maxY - minY)

        let margin: CGFloat = 10
        let availW = canvasSize.width - margin * 2
        let availH = canvasSize.height - margin * 2

        let scale = min(availW / totalW, availH / totalH) * 0.85

        let renderedW = totalW * scale
        let renderedH = totalH * scale

        let offsetX = (canvasSize.width - renderedW) / 2
        let offsetY = (canvasSize.height - renderedH) / 2

        var result: [CGDirectDisplayID: CGRect] = [:]
        for p in placements {
            let x = offsetX + (p.bounds.minX - minX) * scale
            let y = offsetY + (p.bounds.minY - minY) * scale
            let w = max(52, p.bounds.width * scale)
            let h = max(34, p.bounds.height * scale)
            result[p.id] = CGRect(x: x, y: y, width: w, height: h)
        }
        return LayoutResult(rects: result, scale: scale)
    }
}
