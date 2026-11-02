import SwiftUI

struct MouseSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        SettingsPane {
            pointerSection
            selectionSection
            linksSection
        }
    }

    private var pointerSection: some View {
        Section("Pointer") {
            Toggle(
                "Hide the pointer while typing",
                isOn: model.bool("mouse-hide-while-typing", default: false))
                .resettable(model, "mouse-hide-while-typing")

            Toggle(
                "Focus follows mouse between splits",
                isOn: model.bool("focus-follows-mouse", default: false))
                .resettable(model, "focus-follows-mouse")

            Toggle(
                "Click in the prompt to move the cursor",
                isOn: model.bool("cursor-click-to-move", default: true))
                .resettable(model, "cursor-click-to-move")

            Toggle(
                "Allow programs to use the mouse",
                isOn: model.bool("mouse-reporting", default: true))
                .resettable(model, "mouse-reporting")

            Picker("Right-click", selection: model.string("right-click-action", default: "context-menu")) {
                Text("Shows the Context Menu").tag("context-menu")
                Text("Pastes").tag("paste")
                Text("Copies the Selection").tag("copy")
                Text("Copies or Pastes").tag("copy-or-paste")
                Text("Does Nothing").tag("ignore")
            }
            .resettable(model, "right-click-action")

            Picker("Middle-click", selection: model.string("middle-click-action", default: "primary-paste")) {
                Text("Pastes the Selection").tag("primary-paste")
                Text("Pastes the Clipboard").tag("clipboard-paste")
                Text("Does Nothing").tag("ignore")
            }
            .resettable(model, "middle-click-action")
        }
    }

    private var selectionSection: some View {
        Section("Selection") {
            Toggle("Copy text to the clipboard when selected", isOn: Binding(
                get: {
                    // `true` and `both` copy to the system clipboard on macOS
                    // while `primary` has no effect here.
                    let value = model.value("copy-on-select", .string, default: "none")
                    return ["true", "clipboard", "both"].contains(value)
                },
                set: { model.set("copy-on-select", $0 ? "clipboard" : "none") }))
                .resettable(model, "copy-on-select")

            Toggle(
                "Clear the selection when typing",
                isOn: model.bool("selection-clear-on-typing", default: true))
                .resettable(model, "selection-clear-on-typing")

            Toggle(
                "Clear the selection after copying",
                isOn: model.bool("selection-clear-on-copy", default: false))
                .resettable(model, "selection-clear-on-copy")
        }
    }

    private var linksSection: some View {
        Section {
            Toggle("Detect links in text", isOn: model.bool("link-url", default: true))
                .resettable(model, "link-url")

            Picker("Show link destination on hover", selection: model.string("link-previews", default: "true")) {
                Text("For All Links").tag("true")
                Text("Only for Hyperlinks (OSC 8)").tag("osc8")
                Text("Never").tag("false")
            }
            .resettable(model, "link-previews")
        } header: {
            Text("Links")
        } footer: {
            SettingsFootnote("Hold ⌘ and click a link to open it.")
        }
    }
}
