import SwiftUI

private let monitorAccent = Color(red: 0.15, green: 0.36, blue: 0.54)

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Monitor Switch")
                    .font(.system(size: 24, weight: .semibold))
                Text("KTC H27T22S 输入切换")
                    .foregroundStyle(.secondary)
            }

            Divider()

            InformationRow(title: "当前显示器", value: model.snapshot?.name ?? "等待扫描")
            InformationRow(title: "当前输入", value: model.currentInputText)

            HStack(spacing: 12) {
                NameField(title: "DP1 名称", text: $model.settings.windowsLabel)
                NameField(title: "HDMI1 名称", text: $model.settings.macLabel)
            }

            HStack(spacing: 10) {
                Button("扫描显示器") { model.scan() }
                    .disabled(model.isBusy)
                Button("切换到 Windows") { model.switchToWindows() }
                    .buttonStyle(.borderedProminent)
                    .tint(monitorAccent)
                    .disabled(model.isBusy)
            }
            .controlSize(.large)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("全局快捷键")
                    .font(.headline)

                HStack(spacing: 12) {
                    ModifierToggle(symbol: "⌘", title: "Command", selection: $model.settings.shortcutModifiers, value: .command)
                    ModifierToggle(symbol: "⌥", title: "Option", selection: $model.settings.shortcutModifiers, value: .option)
                    ModifierToggle(symbol: "⌃", title: "Control", selection: $model.settings.shortcutModifiers, value: .control)
                    ModifierToggle(symbol: "⇧", title: "Shift", selection: $model.settings.shortcutModifiers, value: .shift)
                }

                Picker("按键", selection: $model.settings.shortcutKey) {
                    ForEach((65...90).compactMap(UnicodeScalar.init).map(String.init), id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .frame(width: 150)

                Text("当前快捷键：\(model.settings.shortcutText)")
                    .foregroundStyle(.secondary)
            }

            Toggle("登录 macOS 时启动", isOn: $model.launchAtLogin)

            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("保存设置") { model.save() }
                    .buttonStyle(.borderedProminent)
                    .tint(monitorAccent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(monitorAccent)
    }
}

private struct NameField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct InformationRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .textSelection(.enabled)
        }
    }
}

private struct ModifierToggle: View {
    let symbol: String
    let title: String
    @Binding var selection: ShortcutModifiers
    let value: ShortcutModifiers

    var body: some View {
        Toggle(isOn: Binding(
            get: { selection.contains(value) },
            set: { enabled in
                if enabled { selection.insert(value) } else { selection.remove(value) }
            }
        )) {
            VStack(spacing: 2) {
                Text(symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption2)
            }
        }
        .toggleStyle(ModifierButtonToggleStyle())
        .help(title)
    }
}

private struct ModifierButtonToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .frame(minWidth: 58, minHeight: 48)
        }
        .buttonStyle(ModifierButtonStyle(selected: configuration.isOn))
    }
}

private struct ModifierButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? monitorAccent : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: selected ? 0 : 1)
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
