import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    private var activeStatusText: String {
        if let input = model.snapshot?.currentInput ?? model.lastTargetInput {
            return "已连接 · \(InputSourceCatalog.connectorName(for: input))"
        } else {
            return "已连接"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header - Compact Native Header
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Lumen 设置")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Text("DDC/CI 输入源配置")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            // Section 1: 设备与检测
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "显示器与状态")

                SettingsCard {
                    CardRow {
                        HStack(spacing: 9) {
                            Image(systemName: "display")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                let displayName: String = {
                                    if let name = model.snapshot?.name, !name.isEmpty {
                                        return name
                                    }
                                    if !model.settings.monitorHint.isEmpty {
                                        return model.settings.monitorHint
                                    }
                                    return "自动检测显示器"
                                }()
                                Text(displayName)
                                    .font(.system(size: 13, weight: .medium))

                                HStack(spacing: 4.5) {
                                    Circle()
                                        .fill(model.snapshot?.isDDCSupported == false ? Color.orange : Color.green)
                                        .frame(width: 5.5, height: 5.5)

                                    let statusText: String = {
                                        if model.snapshot?.isDDCSupported == false {
                                            return "线材不支持状态回读"
                                        }
                                        return activeStatusText
                                    }()
                                    Text(statusText)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } trailing: {
                        Button("重新检测") {
                            model.scan()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isBusy)
                    }

                    if let snap = model.snapshot, snap.nativeWidth > 0 && snap.nativeHeight > 0 {
                        Divider()
                            .padding(.leading, 38)

                        CardRow {
                            HStack(spacing: 9) {
                                Image(systemName: "rectangle.inset.filled")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("显示规格")
                                        .font(.system(size: 12))
                                    Text("原生 \(snap.nativeResolutionText) · \(snap.logicalModeText)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } trailing: {
                            Text("\(snap.refreshRate) Hz")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    let externalMonitors = DisplayDiscoveryService.shared.discoverMonitors().filter { !$0.isBuiltin }
                    if externalMonitors.count > 1 {
                        Divider()
                            .padding(.leading, 38)

                        CardRow {
                            Text("目标显示器")
                                .font(.system(size: 12))
                        } trailing: {
                            Picker("", selection: Binding(
                                get: { model.settings.selectedMonitorId ?? externalMonitors.first?.id ?? "" },
                                set: { newId in
                                    model.settings.selectedMonitorId = newId
                                    model.save()
                                    model.scan()
                                }
                            )) {
                                ForEach(externalMonitors) { mon in
                                    Text(mon.name).tag(mon.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                    }
                }
            }

            // Section 2: 设备端口映射 (隐藏十六进制，优化输入框)
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "输入源映射")

                SettingsCard {
                    CardRow {
                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            TextField("别名", text: $model.settings.windowsLabel)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                                }
                                .frame(width: 105)
                                .onSubmit { model.save() }
                        }
                    } trailing: {
                        Picker("", selection: $model.settings.windowsInput) {
                            ForEach(InputSourceCatalog.availablePorts) { port in
                                Text(InputSourceCatalog.connectorName(for: port.value)).tag(port.value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .onChange(of: model.settings.windowsInput) {
                            model.save()
                        }
                    }

                    Divider()
                        .padding(.leading, 38)

                    CardRow {
                        HStack(spacing: 8) {
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            TextField("别名", text: $model.settings.macLabel)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                                }
                                .frame(width: 105)
                                .onSubmit { model.save() }
                        }
                    } trailing: {
                        Picker("", selection: $model.settings.macInput) {
                            ForEach(InputSourceCatalog.availablePorts) { port in
                                Text(InputSourceCatalog.connectorName(for: port.value)).tag(port.value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .onChange(of: model.settings.macInput) {
                            model.save()
                        }
                    }
                }
            }

            // Section 3: 控制与快捷键 (即时保存，快捷键指示)
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "快捷键与自启")

                SettingsCard {
                    CardRow {
                        Text("双向切换快捷键")
                            .font(.system(size: 12.5))
                    } trailing: {
                        HStack(spacing: 4) {
                            CompactModifierToggle(symbol: "⌃", selection: $model.settings.shortcutModifiers, value: .control) { model.save() }
                            CompactModifierToggle(symbol: "⌥", selection: $model.settings.shortcutModifiers, value: .option) { model.save() }
                            CompactModifierToggle(symbol: "⇧", selection: $model.settings.shortcutModifiers, value: .shift) { model.save() }
                            CompactModifierToggle(symbol: "⌘", selection: $model.settings.shortcutModifiers, value: .command) { model.save() }

                            Picker("", selection: $model.settings.shortcutKey) {
                                ForEach((65...90).compactMap(UnicodeScalar.init).map(String.init), id: \.self) { key in
                                    Text(key).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 48)
                            .onChange(of: model.settings.shortcutKey) {
                                model.save()
                            }
                        }
                    }

                    Divider()
                        .padding(.leading, 14)

                    CardRow {
                        Text("登录 macOS 时自动启动")
                            .font(.system(size: 12.5))
                    } trailing: {
                        Toggle("", isOn: $model.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: model.launchAtLogin) {
                                model.save()
                            }
                    }

                    Divider()
                        .padding(.leading, 14)

                    CardRow {
                        Text("自动检查更新")
                            .font(.system(size: 12.5))
                    } trailing: {
                        Toggle("", isOn: $model.settings.automaticallyChecksForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: model.settings.automaticallyChecksForUpdates) {
                                model.save()
                            }
                    }
                }
            }

            UpdateSettingsSection(service: model.updateService)

            // Footer - Transient status & auto-saved note
            HStack(alignment: .center) {
                if !model.statusText.isEmpty {
                    Text(model.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("修改即时生效")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct UpdateSettingsSection: View {
    @ObservedObject var service: UpdateService

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader(title: "软件更新")

            if service.availableRelease != nil {
                UpdateBannerView(service: service)
            } else {
                SettingsCard {
                    CardRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lumen \(service.currentVersion)")
                                .font(.system(size: 12.5, weight: .medium))
                            Text(service.statusText.isEmpty ? "从 GitHub Releases 获取版本信息" : service.statusText)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } trailing: {
                        Button(service.isChecking ? "正在检查…" : "检查更新") {
                            service.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(service.isChecking)
                    }
                }
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        }
    }
}

private struct CardRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 3)
    }
}

private struct CompactModifierToggle: View {
    let symbol: String
    @Binding var selection: ShortcutModifiers
    let value: ShortcutModifiers
    var onToggle: () -> Void = {}

    var isSelected: Bool { selection.contains(value) }

    var body: some View {
        Button {
            if isSelected {
                selection.remove(value)
            } else {
                selection.insert(value)
            }
            onToggle()
        } label: {
            Text(symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 20)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
