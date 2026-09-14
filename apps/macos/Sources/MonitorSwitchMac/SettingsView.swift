import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    private var activeInput: UInt8? {
        model.snapshot?.currentInput ?? model.lastTargetInput
    }

    private var isWindowsActive: Bool {
        activeInput == model.settings.windowsInput
    }

    private var isMacActive: Bool {
        if let active = activeInput {
            return active == model.settings.macInput
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Lumen")
                        .font(.system(size: 16, weight: .bold))
                    Text("显示器 DDC/CI 输入源控制")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 2)

            // Section 1: 设备与实时状态
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "显示器与状态")

                SettingsCard {
                    CardRow {
                        HStack(spacing: 8) {
                            Image(systemName: "display")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.snapshot?.name ?? model.settings.monitorHint)
                                    .font(.system(size: 13, weight: .medium))
                                Text(model.currentInputText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } trailing: {
                        HStack(spacing: 6) {
                            Button("扫描") { model.scan() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(model.isBusy)

                            switchButton(title: "切到 \(model.settings.windowsLabel)", isActive: isWindowsActive) {
                                model.switchToWindows()
                            }

                            switchButton(title: "切到 \(model.settings.macLabel)", isActive: isMacActive) {
                                model.switchToMac()
                            }
                        }
                    }
                }
            }

            // Section 2: 设备端口与别名映射
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "设备端口与别名映射")

                SettingsCard {
                    CardRow {
                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            TextField("别名", text: $model.settings.windowsLabel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                        }
                    } trailing: {
                        Picker("", selection: $model.settings.windowsInput) {
                            ForEach(InputSourceCatalog.availablePorts) { port in
                                Text(port.name).tag(port.value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    Divider()
                        .padding(.leading, 38)

                    CardRow {
                        HStack(spacing: 8) {
                            Image(systemName: "laptopcomputer")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            TextField("别名", text: $model.settings.macLabel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                        }
                    } trailing: {
                        Picker("", selection: $model.settings.macInput) {
                            ForEach(InputSourceCatalog.availablePorts) { port in
                                Text(port.name).tag(port.value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
            }

            // Section 3: 控制与快捷键
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "控制与快捷键")

                SettingsCard {
                    CardRow {
                        Text("双向切换快捷键")
                            .font(.system(size: 13))
                    } trailing: {
                        HStack(spacing: 4) {
                            CompactModifierToggle(symbol: "⌃", selection: $model.settings.shortcutModifiers, value: .control)
                            CompactModifierToggle(symbol: "⌥", selection: $model.settings.shortcutModifiers, value: .option)
                            CompactModifierToggle(symbol: "⇧", selection: $model.settings.shortcutModifiers, value: .shift)
                            CompactModifierToggle(symbol: "⌘", selection: $model.settings.shortcutModifiers, value: .command)

                            Picker("", selection: $model.settings.shortcutKey) {
                                ForEach((65...90).compactMap(UnicodeScalar.init).map(String.init), id: \.self) { key in
                                    Text(key).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 50)
                        }
                    }



                    Divider()
                        .padding(.leading, 14)

                    CardRow {
                        Text("登录 macOS 时自动启动")
                            .font(.system(size: 13))
                    } trailing: {
                        Toggle("", isOn: $model.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            // Footer
            HStack(alignment: .center) {
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                Button("保存设置") { model.save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func switchButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        if isActive {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.isBusy)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isBusy)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }
}

private struct CompactModifierToggle: View {
    let symbol: String
    @Binding var selection: ShortcutModifiers
    let value: ShortcutModifiers

    var isSelected: Bool { selection.contains(value) }

    var body: some View {
        Button {
            if isSelected {
                selection.remove(value)
            } else {
                selection.insert(value)
            }
        } label: {
            Text(symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
