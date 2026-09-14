import AppKit
import SwiftUI

struct ControlCenterPanelView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var resController = ResolutionController.shared
    @ObservedObject var controlService = DisplayControlService.shared
    @ObservedObject var hidpiService = HiDPIService.shared
    @ObservedObject var arrangementService = ArrangementService.shared

    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // 1. Dual-Machine Signal Switch Card (King Feature)
            signalSwitchSection

            // 2. Connected Displays
            VStack(spacing: 10) {
                ForEach(resController.displays) { display in
                    displaySection(for: display)
                }
            }

            // 3. Screen Arrangement Card (Displays Layout)
            if arrangementService.placements.count >= 2 {
                screenArrangementSection
            }

            // 4. System Quick Toggles (Dark Mode, Eye Comfort, Ambient Adaptation)
            systemQuickToggles

            // 5. Footer Tools
            footerSection
        }
        .padding(12)
        .frame(width: 330)
        .background(Color.clear)
    }

    // MARK: - Signal Switch Hero Section

    private var signalSwitchSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("输入源切换")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Text(appModel.settings.shortcutText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                let activeInput = appModel.snapshot?.currentInput ?? appModel.lastTargetInput
                let isWindowsActive = activeInput == appModel.settings.windowsInput
                let isMacActive = activeInput == appModel.settings.macInput

                HStack(spacing: 8) {
                    // Windows Button
                    Button {
                        appModel.switchToWindows()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appModel.settings.windowsLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(InputSourceCatalog.connectorName(for: appModel.settings.windowsInput))
                                    .font(.system(size: 9))
                                    .opacity(0.8)
                            }
                            Spacer()
                            if isWindowsActive {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(isWindowsActive ? Color.accentColor : Color.primary.opacity(0.05))
                        .foregroundStyle(isWindowsActive ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isWindowsActive ? Color.clear : Color.white.opacity(0.12), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)

                    // Mac Button
                    Button {
                        appModel.switchToMac()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appModel.settings.macLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(InputSourceCatalog.connectorName(for: appModel.settings.macInput))
                                    .font(.system(size: 9))
                                    .opacity(0.8)
                            }
                            Spacer()
                            if isMacActive {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(isMacActive ? Color.accentColor : Color.primary.opacity(0.05))
                        .foregroundStyle(isMacActive ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isMacActive ? Color.clear : Color.white.opacity(0.12), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Display Section

    @ViewBuilder
    private func displaySection(for display: ManagedDisplay) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                // Display Title & Subtitle
                HStack(spacing: 8) {
                    Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(display.name)
                                .font(.system(size: 13, weight: .semibold))
                            if display.isAtTopRecommended {
                                Text("⭐ 最佳")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundStyle(Color.orange)
                                    .clipShape(Capsule())
                            }
                        }

                        if let cur = display.currentMode {
                            Text("\(cur.width) × \(cur.height) @ \(cur.refreshRate)Hz\(cur.isHiDPI ? " (HiDPI)" : "")")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !display.isAtTopRecommended, let top = display.topRecommendedMode {
                        Button {
                            resController.setMode(top, for: display.displayID)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                                Text("恢复最佳")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Sliders
                if display.isBuiltin {
                    // Internal Brightness Slider
                    CapsuleSlider(
                        value: $controlService.internalBrightness,
                        range: 0...100,
                        leftIcon: "sun.min",
                        rightIcon: "sun.max",
                        onChanged: { val in
                            controlService.setInternalBrightness(val)
                        }
                    )

                    // Options for Built-in
                    VStack(spacing: 4) {
                        mainDisplayRow(for: display)
                        resolutionPickerRow(for: display)
                    }
                } else {
                    // External Brightness Slider (DDC 0x10)
                    CapsuleSlider(
                        value: $controlService.externalBrightness,
                        range: 0...100,
                        leftIcon: "sun.min",
                        rightIcon: "sun.max",
                        onChanged: { val in
                            controlService.setExternalBrightness(val)
                        }
                    )

                    // External Volume Slider (DDC 0x62)
                    CapsuleSlider(
                        value: $controlService.externalVolume,
                        range: 0...100,
                        leftIcon: "speaker.wave.1",
                        rightIcon: "speaker.wave.3",
                        onChanged: { val in
                            controlService.setExternalVolume(val)
                        }
                    )

                    // Options List (Main Display, Resolution, Refresh Rate, HiDPI)
                    VStack(spacing: 4) {
                        // Main Display Setting Row
                        mainDisplayRow(for: display)

                        // Resolution Picker
                        resolutionPickerRow(for: display)

                        // Refresh Rate Picker
                        HStack {
                            Label("刷新率", systemImage: "waveform.path.ecg")
                                .font(.system(size: 12))
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
                                    .font(.system(size: 11))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // HiDPI Smooth Scaling Injector
                        let isHiDPIInstalled = hidpiService.isHiDPIInstalled(vendor: display.vendorID, product: display.productID)

                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Label("2K HiDPI 锐利渲染", systemImage: "sparkles")
                                    .font(.system(size: 12))
                                Text(isHiDPIInstalled ? "已注入原生视网膜配置" : "点击注入 2K HiDPI 缩放")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(isHiDPIInstalled ? "已开启" : "开启") {
                                Task {
                                    hidpiService.isWorking = true
                                    let err = await hidpiService.enableHiDPI(vendor: display.vendorID, product: display.productID)
                                    hidpiService.statusError = err
                                    hidpiService.isWorking = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isHiDPIInstalled || hidpiService.isWorking)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mainDisplayRow(for display: ManagedDisplay) -> some View {
        HStack {
            Label("主显示器", systemImage: "m.circle")
                .font(.system(size: 12))
            Spacer()
            if display.isMain {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text("当前主屏幕")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Button("设为主显示器") {
                    resController.setMainDisplay(displayID: display.displayID)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func resolutionPickerRow(for display: ManagedDisplay) -> some View {
        HStack {
            Label("分辨率", systemImage: "rectangle.inset.filled")
                .font(.system(size: 12))
            Spacer()
            Menu {
                if !display.recommendedModes.isEmpty {
                    Section("⭐ 推荐分辨率") {
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
                HStack(spacing: 4) {
                    Text(display.currentMode?.displayName ?? "选择")
                        .font(.system(size: 11))
                    if display.isAtTopRecommended {
                        Text("最佳")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Screen Arrangement Section

    private var screenArrangementSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Label("屏幕排列", systemImage: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("· 拖动方块调整")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.8))

                    Spacer()

                    // Main Display Menu
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
                        HStack(spacing: 3) {
                            let mainP = arrangementService.placements.first(where: { $0.isMain })
                            let mainName = mainP?.name ?? "主屏"
                            let shortName = mainName.contains("内建") ? "内建" : (mainName.components(separatedBy: " ").first ?? "外接")
                            Text("主屏: \(shortName)")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .menuStyle(.borderlessButton)
                }

                // Visual Arrangement Canvas with live dragging
                ArrangementMiniCanvas(service: arrangementService)
                    .frame(height: 92)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
        }
    }

    // MARK: - Quick Toggles

    private var systemQuickToggles: some View {
        GlassCard {
            HStack(spacing: 8) {
                // 1. 深色模式
                toggleButton(
                    title: "深色模式",
                    icon: controlService.isDarkMode ? "moon.fill" : "moon",
                    isActive: controlService.isDarkMode,
                    activeColor: .blue
                ) {
                    controlService.toggleDarkMode()
                }

                // 2. 护眼模式 (原 夜览)
                toggleButton(
                    title: "护眼模式",
                    icon: controlService.isNightShift ? "sun.max.fill" : "sun.max",
                    isActive: controlService.isNightShift,
                    activeColor: .orange
                ) {
                    controlService.toggleNightShift()
                }

                // 3. 环境色自适应 (原 原彩显示)
                toggleButton(
                    title: "环境色自适应",
                    icon: controlService.isTrueTone ? "circle.lefthalf.filled" : "circle",
                    isActive: controlService.isTrueTone,
                    activeColor: .cyan
                ) {
                    controlService.toggleTrueTone()
                }
            }
        }
    }

    @ViewBuilder
    private func toggleButton(
        title: String,
        icon: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isActive ? activeColor : Color.primary)

                Text(title)
                    .font(.system(size: 10, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isActive ? activeColor.opacity(0.12) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? activeColor.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("设置…")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onQuit()
            } label: {
                Text("退出")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Glass Card Container

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.40))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
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
                                .frame(width: max(rect.width, 56), height: max(rect.height, 38))
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isDragged
                        ? Color.accentColor.opacity(0.25)
                        : (p.isMain ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isDragged
                                ? Color.accentColor
                                : (p.isMain ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.25)),
                            lineWidth: isDragged ? 1.5 : (p.isMain ? 1 : 0.5)
                        )
                }
                .shadow(color: Color.black.opacity(isDragged ? 0.2 : 0.05), radius: isDragged ? 6 : 2, x: 0, y: isDragged ? 3 : 1)

            // Main Menu Bar Stripe
            if p.isMain {
                VStack {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.9))
                        .frame(height: 3)
                        .padding(.horizontal, 3)
                        .padding(.top, 2.5)
                    Spacer()
                }
            }

            // Monitor Icon & Text
            VStack(spacing: 2) {
                Image(systemName: p.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 12))
                    .foregroundStyle(p.isMain ? Color.accentColor : Color.primary.opacity(0.85))

                Text(p.isBuiltin ? "内建" : (p.name.components(separatedBy: " ").first ?? "外接"))
                    .font(.system(size: 10, weight: p.isMain ? .bold : .medium))
                    .foregroundStyle(p.isMain ? Color.accentColor : Color.primary)
                    .lineLimit(1)
            }
            .padding(4)
        }
        .scaleEffect(isDragged ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragged)
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

        let margin: CGFloat = 12
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
            let w = max(56, p.bounds.width * scale)
            let h = max(38, p.bounds.height * scale)
            result[p.id] = CGRect(x: x, y: y, width: w, height: h)
        }
        return LayoutResult(rects: result, scale: scale)
    }
}

// MARK: - CapsuleSlider

struct CapsuleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let leftIcon: String
    let rightIcon: String
    var onChanged: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let percent = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let fillWidth = max(0, min(totalWidth, totalWidth * percent))

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                // Filled portion
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: fillWidth)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                // Icons overlay
                HStack {
                    Image(systemName: leftIcon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(percent > 0.12 ? Color.black.opacity(0.8) : Color.primary.opacity(0.6))
                        .padding(.leading, 10)

                    Spacer()

                    Image(systemName: rightIcon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(percent > 0.88 ? Color.black.opacity(0.8) : Color.primary.opacity(0.6))
                        .padding(.trailing, 10)
                }
            }
            .frame(height: 26)
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
        .frame(height: 26)
    }
}
