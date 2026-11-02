import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pane

/// The standard container for a settings pane: a grouped form that scrolls.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(minWidth: 660, idealWidth: 700, minHeight: 360)
    }
}

/// Secondary explanatory text shown under a setting.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Reset

extension View {
    /// Adds a "Reset to Default" context menu item that removes the given
    /// keys from the configuration file.
    func resettable(_ model: SettingsModel, _ keys: String...) -> some View {
        contextMenu {
            Button("Reset to Default") {
                for key in keys { model.reset(key) }
            }
            .disabled(!keys.contains { model.isSet($0) })
        }
    }
}

/// A small inline button that resets a setting to its default value.
struct ResetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Reset to Default")
    }
}

// MARK: - Colors

/// A color well bound to a configuration key with an optional reset button.
struct ColorSettingRow: View {
    let title: String
    @Binding var color: Color
    let isSet: Bool
    var note: String?
    let reset: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let note, !isSet {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if isSet { ResetButton(action: reset) }
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: - Paths

/// A text field for a file system path with a "Choose…" button.
struct PathField: View {
    let placeholder: String
    @Binding var path: String
    var chooseDirectories = false
    var allowedTypes: [UTType] = []

    var body: some View {
        HStack {
            CommittingTextField(placeholder: placeholder, text: $path)
            Button("Choose…", action: choose)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !chooseDirectories
        panel.canChooseDirectories = chooseDirectories
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = chooseDirectories
        if !allowedTypes.isEmpty { panel.allowedContentTypes = allowedTypes }
        if !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            panel.directoryURL = chooseDirectories ? url : url.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Prefer `~/` paths since Ghostty expands them and they're portable.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home + "/") {
            path = "~" + url.path.dropFirst(home.count)
        } else {
            path = url.path
        }
    }
}

// MARK: - Text Fields

/// A text field that only commits its value when editing ends, so that we
/// don't write partial values (and reload the configuration) on every
/// keystroke.
struct CommittingTextField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = false

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text(placeholder))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .focused($focused)
            .onAppear { draft = text }
            .onChange(of: text) { newValue in
                if !focused { draft = newValue }
            }
            .onChange(of: focused) { isFocused in
                if !isFocused { commit() }
            }
            .onSubmit(commit)
    }

    private func commit() {
        if draft != text { text = draft }
    }
}

// MARK: - Combo Box

/// A native, editable combo box. SwiftUI doesn't provide one on macOS.
struct ComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]
    var placeholder: String = ""

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = false
        box.completes = true
        box.numberOfVisibleItems = 16
        box.delegate = context.coordinator
        box.placeholderString = placeholder
        box.addItems(withObjectValues: items)
        box.stringValue = text
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if box.stringValue != text && box.currentEditor() == nil {
            box.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ComboBox

        init(_ parent: ComboBox) {
            self.parent = parent
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox,
                  let value = box.objectValueOfSelectedItem as? String else { return }
            parent.text = value
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            parent.text = box.stringValue
        }
    }
}

// MARK: - Fonts

/// Information about the fonts available for the terminal.
enum FontLibrary {
    /// The font Ghostty uses when `font-family` is not set. It is embedded
    /// in Ghostty itself and so may not be installed on the system.
    static let defaultFamily = "JetBrains Mono"

    /// All installed font families that are monospaced.
    static let monospacedFamilies: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."),
                  let members = manager.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let name = first.first as? String,
                  let font = NSFont(name: name, size: 12) else { return false }
            return font.isFixedPitch || family.localizedCaseInsensitiveContains("mono")
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    /// A font for previewing a family. Falls back to the system monospaced
    /// font when the family isn't installed (e.g. the embedded default).
    static func previewFont(family: String, size: CGFloat, ligatures: Bool) -> NSFont {
        let size = max(6, min(size, 48))
        var descriptor: NSFontDescriptor
        if let font = NSFont(name: family, size: size) ?? familyFont(family, size: size) {
            descriptor = font.fontDescriptor
        } else {
            descriptor = NSFont.monospacedSystemFont(ofSize: size, weight: .regular).fontDescriptor
        }

        if !ligatures {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [
                    [
                        NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                        NSFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector,
                    ],
                    [
                        NSFontDescriptor.FeatureKey.typeIdentifier: kContextualAlternatesType,
                        NSFontDescriptor.FeatureKey.selectorIdentifier: kContextualAlternatesOffSelector,
                    ],
                ],
            ])
        }

        return NSFont(descriptor: descriptor, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func familyFont(_ family: String, size: CGFloat) -> NSFont? {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }
}

// MARK: - Key Recorder

/// A control that records a keyboard shortcut and produces a Ghostty trigger
/// string (e.g. `cmd+shift+t`). Click it, then press the desired keys.
struct KeyRecorder: View {
    @Binding var trigger: String
    var placeholder: String = "Click to record shortcut"
    var width: CGFloat = 180

    var body: some View {
        KeyRecorderRepresentable(trigger: $trigger, placeholder: placeholder)
            .frame(width: width, height: KeyRecorderView.height)
            // Align our text with the row's label like a native control.
            .alignmentGuide(.firstTextBaseline) { _ in KeyRecorderView.baselineFromTop }
            .alignmentGuide(.lastTextBaseline) { _ in KeyRecorderView.baselineFromTop }
    }
}

private struct KeyRecorderRepresentable: NSViewRepresentable {
    @Binding var trigger: String
    var placeholder: String

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.placeholder = placeholder
        view.onChange = { trigger = $0 }
        view.trigger = trigger
        return view
    }

    func updateNSView(_ view: KeyRecorderView, context: Context) {
        view.onChange = { trigger = $0 }
        view.placeholder = placeholder
        if !view.isRecording { view.trigger = trigger }
    }
}

final class KeyRecorderView: NSView {
    var onChange: ((String) -> Void)?
    var placeholder = ""
    var trigger = "" { didSet { needsDisplay = true } }
    private(set) var isRecording = false { didSet { needsDisplay = true } }
    private var liveModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: Self.height) }

    static let height: CGFloat = 24
    fileprivate static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    /// The distance from the top of the view to the baseline of its text.
    static var baselineFromTop: CGFloat {
        (height - (font.ascender - font.descender)) / 2 + font.ascender
    }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    /// Focus is separate from recording (like the shortcut fields in System
    /// Settings) so that the control doesn't start capturing keys just because
    /// it became the initial first responder of a window or sheet.
    private func startRecording() {
        guard window?.makeFirstResponder(self) ?? false else { return }
        isRecording = true
    }

    private func stopRecording() {
        isRecording = false
        liveModifiers = []
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Keyboard shortcut" }
    override func accessibilityHelp() -> String? { "Press to record a new shortcut" }

    override func accessibilityValue() -> Any? {
        trigger.isEmpty ? "None" : GhosttyTrigger.displayString(trigger)
    }

    override func accessibilityPerformPress() -> Bool {
        startRecording()
        return isRecording
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        liveModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Capture shortcuts (e.g. cmd+w) before the menu sees them.
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        guard isRecording else {
            // When focused via the keyboard, space or return starts recording.
            if mods.isEmpty && (event.keyCode == 0x31 || event.keyCode == 0x24) {
                startRecording()
            } else {
                super.keyDown(with: event)
            }
            return
        }

        // Plain escape cancels and plain delete clears, like other macOS recorders.
        if mods.isEmpty && event.keyCode == 0x35 {
            stopRecording()
            return
        }
        if mods.isEmpty && (event.keyCode == 0x33 || event.keyCode == 0x75) {
            trigger = ""
            onChange?("")
            stopRecording()
            return
        }

        guard let key = GhosttyTrigger.keyName(for: event) else {
            NSSound.beep()
            return
        }

        let value = GhosttyTrigger.format(key: key, modifiers: mods)
        trigger = value
        onChange?(value)
        stopRecording()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            let mods = GhosttyTrigger.symbols(for: liveModifiers)
            text = mods.isEmpty ? "Type shortcut…" : mods
            color = .secondaryLabelColor
        } else if trigger.isEmpty {
            text = placeholder
            color = .tertiaryLabelColor
        } else {
            text = GhosttyTrigger.displayString(trigger)
            color = .labelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        text.draw(at: point, withAttributes: attrs)
    }
}

/// Helpers for converting between AppKit key events and Ghostty triggers.
enum GhosttyTrigger {
    /// Special keys by virtual key code, named as Ghostty expects (W3C names).
    private static let specialKeys: [UInt16: String] = [
        0x24: "enter", 0x4C: "numpad_enter", 0x30: "tab", 0x31: "space", 0x33: "backspace",
        0x75: "delete", 0x35: "escape", 0x73: "home", 0x77: "end", 0x74: "page_up",
        0x79: "page_down", 0x7E: "arrow_up", 0x7D: "arrow_down", 0x7B: "arrow_left",
        0x7C: "arrow_right", 0x72: "insert",
        0x7A: "f1", 0x78: "f2", 0x63: "f3", 0x76: "f4", 0x60: "f5", 0x61: "f6", 0x62: "f7",
        0x64: "f8", 0x65: "f9", 0x6D: "f10", 0x67: "f11", 0x6F: "f12", 0x69: "f13",
        0x6B: "f14", 0x71: "f15", 0x6A: "f16", 0x40: "f17", 0x4F: "f18", 0x50: "f19", 0x5A: "f20",
    ]

    /// The Ghostty key name for an event, or nil if it can't be represented.
    static func keyName(for event: NSEvent) -> String? {
        if let special = specialKeys[event.keyCode] { return special }
        guard let chars = event.characters(byApplyingModifiers: []),
              chars.count == 1,
              let scalar = chars.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        // Unicode triggers match the unmodified, case-folded character.
        return chars.lowercased()
    }

    /// Build a trigger string from a key and modifiers.
    static func format(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("super") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// The modifier symbols (⌃⌥⇧⌘) for a set of flags.
    static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    private static let keySymbols: [String: String] = [
        "enter": "↩", "return": "↩", "numpad_enter": "⌤", "tab": "⇥", "space": "Space",
        "backspace": "⌫", "delete": "⌦", "escape": "⎋", "home": "↖", "end": "↘",
        "page_up": "⇞", "page_down": "⇟", "arrow_up": "↑", "up": "↑", "arrow_down": "↓",
        "down": "↓", "arrow_left": "←", "left": "←", "arrow_right": "→", "right": "→",
        "equal": "=", "plus": "+", "minus": "-", "comma": ",", "period": ".", "slash": "/",
        "backslash": "\\", "semicolon": ";", "quote": "'", "backquote": "`", "grave_accent": "`",
        "bracket_left": "[", "bracket_right": "]", "greater": ">",
    ]

    /// A human-friendly rendering of a trigger, e.g. `super+shift+t` → `⇧⌘T`.
    /// Sequences (`a>b`) are rendered with spaces between each step.
    static func displayString(_ trigger: String) -> String {
        trigger.split(separator: ">").map { step -> String in
            var mods: NSEvent.ModifierFlags = []
            var key = ""
            for part in step.split(separator: "+", omittingEmptySubsequences: false) {
                switch part.lowercased() {
                case "ctrl", "control": mods.insert(.control)
                case "alt", "opt", "option": mods.insert(.option)
                case "shift": mods.insert(.shift)
                case "super", "cmd", "command": mods.insert(.command)
                case "": key = "+"
                default: key = String(part)
                }
            }

            let lower = key.lowercased()
            let display: String
            if let symbol = keySymbols[lower] {
                display = symbol
            } else if lower.hasPrefix("key_") && lower.count == 5 {
                display = String(lower.dropFirst(4)).uppercased()
            } else if lower.hasPrefix("digit_") && lower.count == 7 {
                display = String(lower.dropFirst(6))
            } else if lower.count == 1 {
                display = lower.uppercased()
            } else {
                display = key.uppercased()
            }
            return symbols(for: mods) + display
        }.joined(separator: " ")
    }
}
