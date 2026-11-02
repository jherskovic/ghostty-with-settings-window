import SwiftUI
import UniformTypeIdentifiers

struct TerminalSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        SettingsPane {
            shellSection
            scrollbackSection
            bellSection
            notificationsSection
            clipboardSection
        }
    }

    // MARK: Shell

    private static let shellFeatures = ["cursor", "sudo", "title", "ssh-env", "ssh-terminfo", "path"]
    private static let shellFeatureDefaults: Set<String> = ["cursor", "title", "path"]

    private func shellFeature(_ name: String) -> Binding<Bool> {
        model.flag("shell-integration-features", name, fields: Self.shellFeatures, defaults: Self.shellFeatureDefaults)
    }

    private var shellSection: some View {
        Section {
            LabeledContent("Command") {
                CommittingTextField(
                    placeholder: "Default login shell",
                    text: Binding(
                        get: { model.fileValue("command") ?? "" },
                        set: { model.set("command", $0.isEmpty ? nil : $0) }),
                    monospaced: true)
            }
            .resettable(model, "command")

            Picker("Shell integration", selection: model.string("shell-integration", default: "detect")) {
                Text("Detect Automatically").tag("detect")
                Text("Off").tag("none")
                Divider()
                Text("Bash").tag("bash")
                Text("Elvish").tag("elvish")
                Text("Fish").tag("fish")
                Text("Nushell").tag("nushell")
                Text("Zsh").tag("zsh")
            }
            .resettable(model, "shell-integration")

            LabeledContent("Integration features") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Use a bar cursor at the prompt", isOn: shellFeature("cursor"))
                    Toggle("Set the window title", isOn: shellFeature("title"))
                    Toggle("Add Ghostty to PATH", isOn: shellFeature("path"))
                    Toggle("Preserve terminfo with sudo", isOn: shellFeature("sudo"))
                    Toggle("Forward terminal environment over SSH", isOn: shellFeature("ssh-env"))
                    Toggle("Install terminfo on SSH hosts", isOn: shellFeature("ssh-terminfo"))
                }
                .toggleStyle(.checkbox)
            }
            .resettable(model, "shell-integration-features")
            .disabled(model.value("shell-integration", .string, default: "detect") == "none")

            Toggle(
                "Keep the terminal open after the command exits",
                isOn: model.bool("wait-after-command", default: false))
                .resettable(model, "wait-after-command")

            LabeledContent("Report terminal as") {
                CommittingTextField(
                    placeholder: "xterm-ghostty",
                    text: Binding(
                        get: { model.fileValue("term") ?? "" },
                        set: { model.set("term", $0.isEmpty ? nil : $0) }),
                    monospaced: true)
            }
            .resettable(model, "term")
        } header: {
            Text("Shell")
        } footer: {
            SettingsFootnote(
                "Leave the command empty to use your login shell. Changes apply to new terminals.")
        }
    }

    // MARK: Scrollback

    private var scrollbackSection: some View {
        Section("Scrollback") {
            ScrollbackLimitRow()

            Toggle(
                "Show scroll bar",
                isOn: model.bool("scrollbar", on: "system", off: "never", default: true))
                .resettable(model, "scrollbar")

            LabeledContent("Scroll to the bottom on") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Keystroke", isOn: model.flag(
                        "scroll-to-bottom", "keystroke",
                        fields: ["keystroke", "output"], defaults: ["keystroke"]))
                    Toggle("New output", isOn: model.flag(
                        "scroll-to-bottom", "output",
                        fields: ["keystroke", "output"], defaults: ["keystroke"]))
                }
                .toggleStyle(.checkbox)
            }
            .resettable(model, "scroll-to-bottom")
        }
    }

    // MARK: Bell

    private static let bellFields = ["system", "audio", "attention", "title", "border"]
    private static let bellDefaults: Set<String> = ["attention", "title"]

    private func bellFeature(_ name: String) -> Binding<Bool> {
        model.flag("bell-features", name, fields: Self.bellFields, defaults: Self.bellDefaults)
    }

    private var bellSection: some View {
        Section("Bell") {
            LabeledContent("When the bell rings") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Play the system alert sound", isOn: bellFeature("system"))
                    Toggle("Play a custom sound", isOn: bellFeature("audio"))
                    Toggle("Bounce the Dock icon", isOn: bellFeature("attention"))
                    Toggle("Show a bell in the title", isOn: bellFeature("title"))
                    Toggle("Flash the window border", isOn: bellFeature("border"))
                }
                .toggleStyle(.checkbox)
            }
            .resettable(model, "bell-features")

            if bellFeature("audio").wrappedValue {
                LabeledContent("Sound") {
                    PathField(
                        placeholder: "Choose a sound file",
                        path: Binding(
                            get: { model.fileValue("bell-audio-path") ?? "" },
                            set: { model.set("bell-audio-path", $0.isEmpty ? nil : $0) }),
                        allowedTypes: [.audio])
                }
                .resettable(model, "bell-audio-path")

                LabeledContent("Volume") {
                    Slider(value: model.number("bell-audio-volume", .double, default: 0.5), in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .labelsHidden()
                }
                .resettable(model, "bell-audio-volume")
            }
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(
                "Allow programs to show notifications",
                isOn: model.bool("desktop-notifications", default: true))
                .resettable(model, "desktop-notifications")

            Picker(
                "Notify when a command finishes",
                selection: model.string("notify-on-command-finish", default: "never")
            ) {
                Text("Never").tag("never")
                Text("When Ghostty Is Not Focused").tag("unfocused")
                Text("Always").tag("always")
            }
            .resettable(model, "notify-on-command-finish")

            if model.value("notify-on-command-finish", .string, default: "never") != "never" {
                LabeledContent("Notify by") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Ringing the bell", isOn: model.flag(
                            "notify-on-command-finish-action", "bell",
                            fields: ["bell", "notify"], defaults: ["bell"]))
                        Toggle("Showing a notification", isOn: model.flag(
                            "notify-on-command-finish-action", "notify",
                            fields: ["bell", "notify"], defaults: ["bell"]))
                    }
                    .toggleStyle(.checkbox)
                }
                .resettable(model, "notify-on-command-finish-action")

                CommandDurationRow()
            }
        } header: {
            Text("Notifications")
        } footer: {
            SettingsFootnote("Command notifications require shell integration.")
        }
    }

    // MARK: Clipboard

    private func accessPicker(_ title: String, key: String, default fallback: String) -> some View {
        Picker(title, selection: model.string(key, default: fallback)) {
            Text("Ask").tag("ask")
            Text("Allow").tag("allow")
            Text("Deny").tag("deny")
        }
        .resettable(model, key)
    }

    private var clipboardSection: some View {
        Section {
            accessPicker("Programs can read the clipboard", key: "clipboard-read", default: "ask")
            accessPicker("Programs can write to the clipboard", key: "clipboard-write", default: "allow")

            Toggle(
                "Confirm before pasting text that could run commands",
                isOn: model.bool("clipboard-paste-protection", default: true))
                .resettable(model, "clipboard-paste-protection")
            Toggle(
                "Trust pastes into programs that support bracketed paste",
                isOn: model.bool("clipboard-paste-bracketed-safe", default: true))
                .resettable(model, "clipboard-paste-bracketed-safe")
                .disabled(!model.bool("clipboard-paste-protection", default: true).wrappedValue)
            Toggle(
                "Remove trailing spaces when copying",
                isOn: model.bool("clipboard-trim-trailing-spaces", default: true))
                .resettable(model, "clipboard-trim-trailing-spaces")
        } header: {
            Text("Clipboard")
        } footer: {
            SettingsFootnote(
                "Programs running in the terminal (including over SSH) can access the clipboard " +
                "using escape sequences (OSC 52).")
        }
    }
}

/// `scrollback-limit-bytes`, shown in megabytes with an "unlimited" option.
private struct ScrollbackLimitRow: View {
    @EnvironmentObject private var model: SettingsModel

    private static let defaultBytes = 50_000_000.0
    private static let megabyte = 1_000_000.0

    private var value: String { model.fileValue("scrollback-limit-bytes") ?? "" }
    private var isUnlimited: Bool { value == "unlimited" }

    private var megabytes: Double {
        guard let bytes = Double(value) else { return Self.defaultBytes / Self.megabyte }
        return bytes / Self.megabyte
    }

    var body: some View {
        LabeledContent("Scrollback limit") {
            HStack(spacing: 6) {
                TextField(
                    "",
                    value: Binding(
                        get: { megabytes },
                        set: { model.set("scrollback-limit-bytes", String(Int(max(0, $0) * Self.megabyte))) }),
                    format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .frame(width: 70)
                    .disabled(isUnlimited)
                Text("MB per terminal").foregroundStyle(.secondary)
                Spacer()
                Toggle("Unlimited", isOn: Binding(
                    get: { isUnlimited },
                    set: { model.set("scrollback-limit-bytes", $0 ? "unlimited" : String(Int(Self.defaultBytes))) }))
                    .toggleStyle(.checkbox)
            }
        }
        .resettable(model, "scrollback-limit-bytes")
    }
}

/// `notify-on-command-finish-after`, shown in seconds.
private struct CommandDurationRow: View {
    @EnvironmentObject private var model: SettingsModel

    private var seconds: Double {
        if let value = model.fileValue("notify-on-command-finish-after"), let parsed = Self.parse(value) {
            return parsed
        }
        if let ms = model.effective.settingsDurationMilliseconds("notify-on-command-finish-after") {
            return Double(ms) / 1000
        }
        return 5
    }

    var body: some View {
        let binding = Binding<Double>(
            get: { seconds },
            set: { model.set("notify-on-command-finish-after", "\(Int(max(0, $0.rounded())))s") })

        LabeledContent("Only for commands longer than") {
            HStack(spacing: 4) {
                TextField("", value: binding, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .frame(width: 56)
                Stepper("", value: binding, in: 0...86_400, step: 1)
                    .labelsHidden()
                Text("seconds").foregroundStyle(.secondary)
            }
        }
        .resettable(model, "notify-on-command-finish-after")
    }

    /// Parse a Ghostty duration such as `5s`, `1m30s` or `500ms` into seconds.
    static func parse(_ value: String) -> Double? {
        let units: [(String, Double)] = [
            ("ms", 0.001), ("us", 0.000_001), ("µs", 0.000_001), ("ns", 0.000_000_001),
            ("s", 1), ("m", 60), ("h", 3600), ("d", 86_400), ("w", 604_800), ("y", 31_536_000),
        ]
        var remaining = Substring(value.replacingOccurrences(of: " ", with: ""))
        var total = 0.0
        var matched = false
        while !remaining.isEmpty {
            let digits = remaining.prefix { $0.isNumber || $0 == "." }
            guard let number = Double(digits), !digits.isEmpty else { return nil }
            remaining = remaining.dropFirst(digits.count)
            guard let unit = units.first(where: { remaining.hasPrefix($0.0) }) else { return nil }
            remaining = remaining.dropFirst(unit.0.count)
            total += number * unit.1
            matched = true
        }
        return matched ? total : nil
    }
}
