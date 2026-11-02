import AppKit
import SwiftUI

struct KeyboardSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        SettingsPane {
            Section {
                Picker("Use Option as Alt", selection: model.optionalString("macos-option-as-alt")) {
                    Text("Automatic").tag("")
                    Divider()
                    Text("Both Option Keys").tag("true")
                    Text("Left Option Key Only").tag("left")
                    Text("Right Option Key Only").tag("right")
                    Text("Neither (Type Special Characters)").tag("false")
                }
            } header: {
                Text("Option Key")
            } footer: {
                SettingsFootnote(
                    "When Option acts as Alt, shortcuts such as Alt+B work in terminal programs, but Option " +
                    "can't be used to type special characters like “é”. Automatic uses Alt for U.S. keyboard layouts.")
            }

            KeyBindingsSection()
        }
    }
}

/// The table of custom key bindings with add, edit and remove controls.
private struct KeyBindingsSection: View {
    @EnvironmentObject private var model: SettingsModel

    @State private var selection: Set<Int> = []
    @State private var editing: EditRequest?

    /// A request to edit (or add, when `position` is nil) a binding.
    private struct EditRequest: Identifiable {
        let id = UUID()
        let position: Int?
        let keybind: Keybind
    }

    private struct Row: Identifiable {
        let id: Int
        let raw: String
        let keybind: Keybind?
    }

    private var rows: [Row] {
        model.keybindValues.enumerated().map { Row(id: $0.offset, raw: $0.element, keybind: Keybind($0.element)) }
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                Table(rows, selection: $selection) {
                    TableColumn("Shortcut") { row in
                        if let keybind = row.keybind {
                            Text(GhosttyTrigger.displayString(keybind.trigger))
                                .help(keybind.trigger)
                        } else {
                            Text(row.raw).foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 90, ideal: 120)

                    TableColumn("Action") { row in
                        Text(row.keybind?.action ?? (row.raw == "clear" ? "Remove all default bindings" : ""))
                            .font(.system(.body, design: .monospaced))
                    }

                    TableColumn("Options") { row in
                        Text(options(for: row.keybind))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 90)
                }
                .contextMenu(forSelectionType: Int.self) { positions in
                    Button("Edit…") { edit(positions.first) }
                        .disabled(!canEdit(positions))
                    Button("Delete") { model.removeKeybinds(at: positions) }
                } primaryAction: { positions in
                    edit(positions.first)
                }
                .frame(minHeight: 180)

                Divider()

                HStack(spacing: 0) {
                    Button {
                        editing = EditRequest(position: nil, keybind: Keybind(trigger: "", action: ""))
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .help("Add a key binding")
                    .accessibilityLabel("Add Key Binding")
                    Divider().frame(height: 16)
                    Button {
                        model.removeKeybinds(at: selection)
                        selection = []
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(selection.isEmpty)
                    .help("Remove the selected key bindings")
                    .accessibilityLabel("Remove Key Bindings")
                    Spacer()
                    Button("Edit…") { edit(selection.first) }
                        .disabled(!canEdit(selection))
                        .controlSize(.small)
                        .padding(.trailing, 6)
                }
                .buttonStyle(.borderless)
                .padding(2)
            }
        } header: {
            Text("Key Bindings")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                SettingsFootnote(
                    "These bindings are added to Ghostty's defaults. Bind a key to “unbind” to remove a default binding.")
                Spacer()
                Link("Documentation", destination: URL(string: "https://ghostty.org/docs/config/keybind")!)
                    .font(.callout)
            }
        }
        .sheet(item: $editing) { request in
            KeybindEditor(keybind: request.keybind, isNew: request.position == nil) { result in
                if let position = request.position {
                    model.replaceKeybind(at: position, with: result.configValue)
                } else {
                    model.addKeybind(result.configValue)
                }
            }
        }
    }

    private func options(for keybind: Keybind?) -> String {
        guard let keybind else { return "" }
        var parts: [String] = []
        if keybind.flags.contains("global") { parts.append("Global") }
        if keybind.flags.contains("all") { parts.append("All Terminals") }
        if keybind.flags.contains("unconsumed") { parts.append("Pass Through") }
        if keybind.flags.contains("performable") { parts.append("Performable") }
        return parts.joined(separator: ", ")
    }

    /// Only simple `trigger=action` bindings can be edited in the sheet.
    /// Others (such as `clear`) can still be removed.
    private func canEdit(_ positions: Set<Int>) -> Bool {
        guard positions.count == 1, let position = positions.first,
              let raw = model.keybindValues[safe: position] else { return false }
        return Keybind(raw) != nil
    }

    private func edit(_ position: Int?) {
        guard let position,
              let raw = model.keybindValues[safe: position],
              let keybind = Keybind(raw) else { return }
        editing = EditRequest(position: position, keybind: keybind)
    }
}

/// A sheet for adding or editing a key binding.
struct KeybindEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keybind: Keybind
    let isNew: Bool
    let onSave: (Keybind) -> Void

    init(keybind: Keybind, isNew: Bool, onSave: @escaping (Keybind) -> Void) {
        _keybind = State(initialValue: keybind)
        self.isNew = isNew
        self.onSave = onSave
    }

    private func flag(_ name: String) -> Binding<Bool> {
        Binding(
            get: { keybind.flags.contains(name) },
            set: { enabled in
                if enabled { keybind.flags.insert(name) } else { keybind.flags.remove(name) }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "Add Key Binding" : "Edit Key Binding")
                .font(.headline)
                .padding([.top, .horizontal], 20)

            Form {
                LabeledContent("Shortcut") {
                    KeyRecorder(trigger: $keybind.trigger, width: 200)
                }
                LabeledContent("Trigger") {
                    TextField("Trigger", text: $keybind.trigger, prompt: Text("e.g. super+shift+t or ctrl+a>n"))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Action") {
                    ComboBox(text: $keybind.action, items: Keybind.suggestedActions, placeholder: "e.g. new_tab")
                        .frame(minWidth: 240)
                }

                Section {
                    Toggle("Works when Ghostty is in the background (global)", isOn: flag("global"))
                    Toggle("Applies to all terminals at once", isOn: flag("all"))
                    Toggle("Also send the key to the running program", isOn: flag("unconsumed"))
                } footer: {
                    if keybind.flags.contains("global") {
                        SettingsFootnote(
                            "Global shortcuts require Accessibility permission in System Settings " +
                            "→ Privacy & Security.")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Link("Available actions", destination: URL(string: "https://ghostty.org/docs/config/keybind/reference")!)
                    .font(.callout)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    onSave(keybind)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keybind.trigger.isEmpty || keybind.action.isEmpty)
            }
            .padding()
        }
        .frame(width: 520)
    }
}
