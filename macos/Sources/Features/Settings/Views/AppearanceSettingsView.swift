import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    /// Which theme slot the theme chooser is editing.
    private enum ThemeSlot: String, Identifiable {
        case single
        case light
        case dark

        var id: String { rawValue }
    }

    @State private var choosingTheme: ThemeSlot?
    @State private var confirmingColorReset = false

    private static let colorKeys = [
        "background", "foreground", "cursor-color", "cursor-text",
        "selection-background", "selection-foreground", "bold-color",
    ]

    var body: some View {
        SettingsPane {
            themeSection
            colorsSection
            paletteSection
            transparencySection
            AppIconSection()
        }
        .sheet(item: $choosingTheme) { slot in
            ThemePickerSheet(
                title: title(for: slot),
                initial: currentTheme(for: slot),
                onChoose: { apply($0, to: slot) })
        }
    }

    // MARK: Theme

    @ViewBuilder
    private var themeSection: some View {
        let selection = model.themeSelection
        Section {
            Toggle("Use different themes for Light and Dark mode", isOn: Binding(
                get: { selection?.isPair ?? false },
                set: { separate in
                    if separate {
                        let current = selection?.light
                        model.set("theme", ThemeLibrary.Selection(
                            light: current ?? "Builtin Light",
                            dark: current ?? "Builtin Dark",
                            isPair: true).configValue)
                    } else if let selection {
                        let name = selection.name(dark: model.prefersDarkAppearance)
                        model.set("theme", ThemeLibrary.Selection(single: name).configValue)
                    }
                }))

            if let selection, selection.isPair {
                themeRow("Light mode", name: selection.light, slot: .light)
                themeRow("Dark mode", name: selection.dark, slot: .dark)
            } else {
                themeRow("Theme", name: selection?.light, slot: .single)
            }

            TerminalPreview(colors: model.effectiveColors)
                .padding(.vertical, 4)
        } header: {
            Text("Theme")
        } footer: {
            SettingsFootnote("Colors set below override the colors of the theme.")
        }
    }

    private func themeRow(_ title: String, name: String?, slot: ThemeSlot) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if let name, let colors = ThemeLibrary.shared.colors(for: name) {
                    ThemeSwatch(colors: colors)
                }
                Text(name ?? "Ghostty Default")
                    .foregroundStyle(name == nil ? .secondary : .primary)
                Button("Choose…") { choosingTheme = slot }
            }
        }
        .contextMenu {
            Button("Use Ghostty Default") { model.reset("theme") }
                .disabled(!model.isSet("theme"))
        }
    }

    private func title(for slot: ThemeSlot) -> String {
        switch slot {
        case .single: return "Choose a Theme"
        case .light: return "Choose a Theme for Light Mode"
        case .dark: return "Choose a Theme for Dark Mode"
        }
    }

    private func currentTheme(for slot: ThemeSlot) -> String? {
        guard let selection = model.themeSelection else { return nil }
        switch slot {
        case .single, .light: return selection.light
        case .dark: return selection.dark
        }
    }

    private func apply(_ name: String?, to slot: ThemeSlot) {
        guard let name else {
            model.reset("theme")
            return
        }

        var selection = model.themeSelection ?? ThemeLibrary.Selection(single: name)
        switch slot {
        case .single: selection = ThemeLibrary.Selection(single: name)
        case .light: selection.light = name
        case .dark: selection.dark = name
        }
        model.set("theme", selection.configValue)
    }

    // MARK: Colors

    private var colorsSection: some View {
        Section {
            ColorSettingRow(
                title: "Background",
                color: model.color("background", fallback: model.activeThemeColors.background),
                isSet: model.isSet("background"),
                reset: { model.reset("background") })
            ColorSettingRow(
                title: "Foreground",
                color: model.color("foreground", fallback: model.activeThemeColors.foreground),
                isSet: model.isSet("foreground"),
                reset: { model.reset("foreground") })
            optionalColorRow("Cursor", key: "cursor-color") { model.effectiveColors.foreground }
            optionalColorRow("Text under cursor", key: "cursor-text") { model.effectiveColors.background }
            optionalColorRow("Selection background", key: "selection-background") { model.effectiveColors.foreground }
            optionalColorRow("Selection text", key: "selection-foreground") { model.effectiveColors.background }

            Picker("Bold text", selection: model.optionalString("bold-color", nil)) {
                Text("Same Color as Text").tag("")
                Text("Use Bright Colors").tag("bright")
                // Preserve a custom color set in the configuration file.
                if let custom = model.fileValue("bold-color"), custom != "bright" {
                    Text("Custom (\(custom))").tag(custom)
                }
            }

            LabeledContent("Minimum contrast") {
                HStack {
                    Slider(value: model.number("minimum-contrast", .double, default: 1, decimals: 1), in: 1...21) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Off").font(.caption)
                    } maximumValueLabel: {
                        Text("Max").font(.caption)
                    }
                    .labelsHidden()
                    Text(SettingsModel.format(Double(model.value("minimum-contrast", .double, default: "1")) ?? 1, decimals: 1))
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }
            .resettable(model, "minimum-contrast")
        } header: {
            Text("Colors")
        } footer: {
            HStack {
                SettingsFootnote("Right-click a setting to reset it to the theme's value.")
                Spacer()
                Button("Reset All Colors…") { confirmingColorReset = true }
                    .confirmationDialog(
                        "Reset all colors to the theme's values?",
                        isPresented: $confirmingColorReset
                    ) {
                        Button("Reset Colors", role: .destructive, action: resetAllColors)
                    } message: {
                        Text("This removes all color overrides from your configuration file.")
                    }
            }
        }
    }

    private func optionalColorRow(_ title: String, key: String, fallback: @escaping () -> String) -> some View {
        let fromTheme = !model.isSet(key) && model.optionalColorValue(key) != nil
        return ColorSettingRow(
            title: title,
            color: model.optionalColor(key, fallback: fallback),
            isSet: model.isSet(key),
            note: fromTheme ? "Theme" : "Automatic",
            reset: { model.reset(key) })
    }

    private func resetAllColors() {
        model.update(immediately: true) { document in
            for key in Self.colorKeys + ["palette"] { document.remove(key) }
        }
    }

    // MARK: Palette

    private static let colorNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

    private var paletteSection: some View {
        Section {
            paletteRow("Normal", range: 0..<8)
            paletteRow("Bright", range: 8..<16)
        } header: {
            Text("ANSI Colors")
        } footer: {
            SettingsFootnote("Overridden colors are marked with a dot. Right-click a color to reset it.")
        }
    }

    private func paletteRow(_ title: String, range: Range<Int>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                ForEach(range, id: \.self) { index in
                    VStack(spacing: 2) {
                        ColorPicker("", selection: model.paletteColor(index), supportsOpacity: false)
                            .labelsHidden()
                        Circle()
                            .fill(model.isPaletteSet(index) ? Color.accentColor : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .help("\(title) \(Self.colorNames[index % 8]) (palette \(index))")
                    .contextMenu {
                        Button("Reset to Theme Color") { model.resetPalette(index) }
                            .disabled(!model.isPaletteSet(index))
                    }
                }
            }
        }
    }

    // MARK: Transparency

    private var transparencySection: some View {
        Section("Transparency") {
            percentSlider("Background opacity", key: "background-opacity", range: 0...1)

            BlurRow()

            percentSlider("Unfocused split opacity", key: "unfocused-split-opacity", range: 0.15...1, default: 0.7)
        }
    }

    private func percentSlider(
        _ title: String,
        key: String,
        range: ClosedRange<Double>,
        default fallback: Double = 1
    ) -> some View {
        let binding = model.number(key, .double, default: fallback)
        return LabeledContent(title) {
            HStack {
                Slider(value: binding, in: range)
                    .labelsHidden()
                Text("\(Int((binding.wrappedValue * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .resettable(model, key)
    }
}

// MARK: - Blur

private struct BlurRow: View {
    @EnvironmentObject private var model: SettingsModel

    private enum Mode: String {
        case off
        case blur
        case glassRegular = "macos-glass-regular"
        case glassClear = "macos-glass-clear"
    }

    /// The current blur as (mode, radius).
    private var current: (Mode, Int) {
        if let value = model.fileValue("background-blur") {
            switch value {
            case "macos-glass-regular": return (.glassRegular, 20)
            case "macos-glass-clear": return (.glassClear, 20)
            default:
                if let bool = SettingsModel.parseBool(value) { return bool ? (.blur, 20) : (.off, 20) }
                if let radius = Int(value) { return radius > 0 ? (.blur, radius) : (.off, 20) }
            }
        }

        switch model.effective.settingsInt16("background-blur") ?? 0 {
        case 0: return (.off, 20)
        case -1: return (.glassRegular, 20)
        case -2: return (.glassClear, 20)
        case let radius: return (.blur, Int(radius))
        }
    }

    var body: some View {
        let (mode, radius) = current

        Picker("Background blur", selection: Binding(
            get: { mode },
            set: { newMode in
                switch newMode {
                case .off: model.set("background-blur", "false")
                case .blur: model.set("background-blur", String(radius))
                case .glassRegular, .glassClear: model.set("background-blur", newMode.rawValue)
                }
            })
        ) {
            Text("Off").tag(Mode.off)
            Text("Blur").tag(Mode.blur)
            if #available(macOS 26.0, *) {
                Divider()
                Text("Liquid Glass").tag(Mode.glassRegular)
                Text("Liquid Glass (Clear)").tag(Mode.glassClear)
            }
        }
        .resettable(model, "background-blur")

        if mode == .blur {
            LabeledContent("Blur radius") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(radius) },
                            set: { model.set("background-blur", String(Int($0.rounded()))) }),
                        in: 1...64)
                        .labelsHidden()
                    Text("\(radius)")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - App Icon

private struct AppIconSection: View {
    @EnvironmentObject private var model: SettingsModel

    private static let icons: [(Ghostty.MacOSIcon, String)] = [
        (.official, "Official"),
        (.blueprint, "Blueprint"),
        (.chalkboard, "Chalkboard"),
        (.microchip, "Microchip"),
        (.glass, "Glass"),
        (.holographic, "Holographic"),
        (.paper, "Paper"),
        (.retro, "Retro"),
        (.xray, "X-Ray"),
    ]

    var body: some View {
        let current = model.value("macos-icon", .string, default: "official")
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(Self.icons, id: \.0.rawValue) { icon, name in
                    Button {
                        model.set("macos-icon", icon.rawValue)
                    } label: {
                        VStack(spacing: 4) {
                            Image(icon.assetName ?? "AppIconImage")
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 52, height: 52)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(current == icon.rawValue ? .primary : .secondary)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(current == icon.rawValue ? Color.accentColor.opacity(0.2) : .clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(current == icon.rawValue ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name) icon")
                    .accessibilityAddTraits(current == icon.rawValue ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("App Icon")
        } footer: {
            if current == "custom" || current == "custom-style" {
                SettingsFootnote("A custom icon is configured in your configuration file.")
            }
        }
    }
}
