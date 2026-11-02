import AppKit
import ApplicationServices
import SwiftUI

struct QuickTerminalSettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    /// The position among keybinds and the parsed binding of the global
    /// quick terminal hotkey, if one is configured.
    private var hotkey: (position: Int, keybind: Keybind)? {
        for (position, raw) in model.keybindValues.enumerated().reversed() {
            if let keybind = Keybind(raw), keybind.action == "toggle_quick_terminal" {
                return (position, keybind)
            }
        }
        return nil
    }

    var body: some View {
        SettingsPane {
            Section {
                LabeledContent("Keyboard shortcut") {
                    HStack {
                        KeyRecorder(
                            trigger: Binding(
                                get: { hotkey?.keybind.trigger ?? "" },
                                set: setHotkey),
                            placeholder: "Record Shortcut")
                        if hotkey != nil {
                            ResetButton { setHotkey("") }
                        }
                    }
                }

                if let hotkey, hotkey.keybind.flags.contains("global"), !accessibilityTrusted {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Global shortcuts need Accessibility permission to work while Ghostty is in the background.")
                            .font(.callout)
                        Spacer()
                        Button("Open Settings…", action: openAccessibilitySettings)
                    }
                }
            } header: {
                Text("Quick Terminal")
            } footer: {
                SettingsFootnote(
                    "The quick terminal drops down from the edge of the screen when you press the shortcut, " +
                    "even when Ghostty is in the background.")
            }

            Section {
                Picker("Position", selection: model.string("quick-terminal-position", default: "top")) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                    Text("Center").tag("center")
                }
                .resettable(model, "quick-terminal-position")

                Picker("Screen", selection: model.string("quick-terminal-screen", default: "main")) {
                    Text("Screen with Focused Window").tag("main")
                    Text("Screen with Mouse Pointer").tag("mouse")
                    Text("Screen with Menu Bar").tag("macos-menu-bar")
                }
                .resettable(model, "quick-terminal-screen")

                QuickTerminalSizeRow()

                LabeledContent("Animation duration") {
                    HStack {
                        let binding = model.number("quick-terminal-animation-duration", .double, default: 0.2)
                        Slider(value: binding, in: 0...1, step: 0.05)
                            .labelsHidden()
                        Text(binding.wrappedValue == 0 ? "Off" : String(format: "%.2fs", binding.wrappedValue))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .resettable(model, "quick-terminal-animation-duration")

                Toggle(
                    "Hide when Ghostty loses focus",
                    isOn: model.bool("quick-terminal-autohide", default: true))
                    .resettable(model, "quick-terminal-autohide")

                Picker("When switching Spaces", selection: model.string("quick-terminal-space-behavior", default: "move")) {
                    Text("Move to the Active Space").tag("move")
                    Text("Stay on Its Original Space").tag("remain")
                }
                .resettable(model, "quick-terminal-space-behavior")
            } header: {
                Text("Appearance and Behavior")
            } footer: {
                SettingsFootnote("Changing the position takes effect after restarting Ghostty.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }

    private func setHotkey(_ trigger: String) {
        if let hotkey {
            if trigger.isEmpty {
                model.removeKeybinds(at: [hotkey.position])
            } else {
                var keybind = hotkey.keybind
                keybind.trigger = trigger
                model.replaceKeybind(at: hotkey.position, with: keybind.configValue)
            }
        } else if !trigger.isEmpty {
            let keybind = Keybind(flags: ["global"], trigger: trigger, action: "toggle_quick_terminal")
            model.addKeybind(keybind.configValue)
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

/// `quick-terminal-size`: common sizes along the primary axis, or a custom
/// value such as `600px` or `50%,800px`.
private struct QuickTerminalSizeRow: View {
    @EnvironmentObject private var model: SettingsModel

    private static let presets = ["25%", "33%", "50%", "75%", "100%"]
    private static let customTag = "custom"

    private var value: String { model.fileValue("quick-terminal-size") ?? "" }

    @State private var showsCustom = false

    private var isCustom: Bool {
        showsCustom || !(value.isEmpty || Self.presets.contains(value))
    }

    var body: some View {
        Picker("Size", selection: Binding(
            get: { isCustom ? Self.customTag : value },
            set: { tag in
                if tag == Self.customTag {
                    showsCustom = true
                } else {
                    showsCustom = false
                    model.set("quick-terminal-size", tag.isEmpty ? nil : tag)
                }
            })
        ) {
            Text("Default").tag("")
            Divider()
            Text("A Quarter of the Screen").tag("25%")
            Text("A Third of the Screen").tag("33%")
            Text("Half of the Screen").tag("50%")
            Text("Three Quarters of the Screen").tag("75%")
            Text("The Whole Screen").tag("100%")
            Divider()
            Text("Custom…").tag(Self.customTag)
        }
        .resettable(model, "quick-terminal-size")

        if isCustom {
            LabeledContent("Custom size") {
                CommittingTextField(
                    placeholder: "e.g. 600px or 50%,800px",
                    text: Binding(
                        get: { value },
                        set: { model.set("quick-terminal-size", $0.isEmpty ? nil : $0) }),
                    monospaced: true)
                    .frame(width: 200)
            }
        }
    }
}
