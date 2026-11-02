import SwiftUI

struct WindowSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        SettingsPane {
            titleBarSection
            sizeSection
            paddingSection
            fullScreenSection
            resizeSection
        }
    }

    // MARK: Title Bar

    private var titleBarSection: some View {
        Section("Title Bar") {
            Picker("Title bar style", selection: model.string("macos-titlebar-style", default: "transparent")) {
                Text("Transparent").tag("transparent")
                Text("Native").tag("native")
                Text("Tabs in Title Bar").tag("tabs")
                Text("Hidden").tag("hidden")
            }
            .resettable(model, "macos-titlebar-style")

            Picker("Window theme", selection: model.string("window-theme", default: "auto")) {
                Text("Match Terminal Background").tag("auto")
                Text("Match System Appearance").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("Ghostty").tag("ghostty")
            }
            .resettable(model, "window-theme")

            Toggle(
                "Show proxy icon in the title bar",
                isOn: model.bool("macos-titlebar-proxy-icon", on: "visible", off: "hidden", default: true))
                .resettable(model, "macos-titlebar-proxy-icon")

            Toggle(
                "Show window buttons",
                isOn: model.bool("macos-window-buttons", on: "visible", off: "hidden", default: true))
                .resettable(model, "macos-window-buttons")

            Toggle("Show window shadow", isOn: model.bool("macos-window-shadow", default: true))
                .resettable(model, "macos-window-shadow")
        }
    }

    // MARK: Size

    private var sizeSection: some View {
        Section {
            LabeledContent("Initial size") {
                HStack(spacing: 6) {
                    cellCountField("window-width")
                    Text("columns").foregroundStyle(.secondary)
                    Text("×").foregroundStyle(.secondary)
                    cellCountField("window-height")
                    Text("rows").foregroundStyle(.secondary)
                }
            }
            .resettable(model, "window-width", "window-height")

            Toggle("Maximize new windows", isOn: model.bool("maximize", default: false))
                .resettable(model, "maximize")

            Toggle("Resize in whole rows and columns", isOn: model.bool("window-step-resize", default: false))
                .resettable(model, "window-step-resize")
        } header: {
            Text("Size")
        } footer: {
            SettingsFootnote("Leave the size empty to let Ghostty choose. The minimum is 10 columns by 4 rows.")
        }
    }

    private func cellCountField(_ key: String) -> some View {
        CommittingTextField(
            placeholder: "Auto",
            text: Binding(
                get: {
                    let value = model.fileValue(key) ?? ""
                    return value == "0" ? "" : value
                },
                set: { text in
                    let digits = text.filter(\.isNumber)
                    model.set(key, digits.isEmpty || digits == "0" ? nil : digits)
                }))
            .multilineTextAlignment(.trailing)
            .frame(width: 60)
    }

    // MARK: Padding

    private var paddingSection: some View {
        Section {
            paddingRow("Horizontal padding", key: "window-padding-x")
            paddingRow("Vertical padding", key: "window-padding-y")

            Picker("Balance padding", selection: model.string("window-padding-balance", default: "false")) {
                Text("Off").tag("false")
                Text("Balanced").tag("true")
                Text("Equal on All Sides").tag("equal")
            }
            .resettable(model, "window-padding-balance")

            Picker("Padding color", selection: model.string("window-padding-color", default: "background")) {
                Text("Background Color").tag("background")
                Text("Extend Nearest Cell").tag("extend")
                Text("Always Extend Nearest Cell").tag("extend-always")
            }
            .resettable(model, "window-padding-color")
        } header: {
            Text("Padding")
        } footer: {
            SettingsFootnote("Space between the edge of the window and the text, in points.")
        }
    }

    private func paddingRow(_ title: String, key: String) -> some View {
        // Padding may be a single value or a pair like `2,4`. We edit a single
        // value; if a pair is set, we show and adjust the first value.
        let binding = Binding<Double>(
            get: {
                let value = model.fileValue(key) ?? "2"
                let first = value.split(separator: ",").first.map(String.init) ?? value
                return Double(first.trimmingCharacters(in: .whitespaces)) ?? 2
            },
            set: { model.set(key, String(Int($0.rounded()))) })

        return LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: binding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .frame(width: 56)
                Stepper("", value: binding, in: 0...200, step: 1)
                    .labelsHidden()
                Text("pt").foregroundStyle(.secondary)
            }
        }
        .resettable(model, key)
    }

    // MARK: Full Screen

    private var fullScreenSection: some View {
        Section("Full Screen") {
            Picker("Full screen style", selection: model.string("macos-non-native-fullscreen", default: "false")) {
                Text("Native (Separate Space)").tag("false")
                Text("Non-Native (Faster)").tag("true")
                Text("Non-Native, Keep Menu Bar Visible").tag("visible-menu")
                Text("Non-Native, Avoid the Notch").tag("padded-notch")
            }
            .resettable(model, "macos-non-native-fullscreen")

            Toggle(
                "Open new windows in full screen",
                isOn: Binding(
                    get: { (model.value("fullscreen", .string, default: "false")) != "false" },
                    set: { model.set("fullscreen", $0 ? "true" : "false") }))
                .resettable(model, "fullscreen")
        }
    }

    // MARK: Resize

    private var resizeSection: some View {
        Section("Resizing") {
            Picker("Show size while resizing", selection: model.string("resize-overlay", default: "after-first")) {
                Text("After the First Resize").tag("after-first")
                Text("Always").tag("always")
                Text("Never").tag("never")
            }
            .resettable(model, "resize-overlay")

            Picker("Size overlay position", selection: model.string("resize-overlay-position", default: "center")) {
                Text("Center").tag("center")
                Divider()
                Text("Top Left").tag("top-left")
                Text("Top Center").tag("top-center")
                Text("Top Right").tag("top-right")
                Divider()
                Text("Bottom Left").tag("bottom-left")
                Text("Bottom Center").tag("bottom-center")
                Text("Bottom Right").tag("bottom-right")
            }
            .resettable(model, "resize-overlay-position")
            .disabled(model.value("resize-overlay", .string, default: "after-first") == "never")
        }
    }
}
