import AppKit
import SwiftUI

extension SettingsModel {
    /// The parsed `theme` setting, if any.
    var themeSelection: ThemeLibrary.Selection? {
        ThemeLibrary.Selection(fileValue("theme") ?? "")
    }

    /// True if the app is currently using a dark appearance. Light/dark theme
    /// pairs follow the system appearance.
    var prefersDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The colors of the theme currently in effect (or Ghostty's defaults).
    var activeThemeColors: ThemeColors {
        guard let selection = themeSelection else { return .ghosttyDefault }
        return ThemeLibrary.shared.colors(for: selection.name(dark: prefersDarkAppearance)) ?? .ghosttyDefault
    }

    /// A color value from the file if it is a hex color, otherwise the
    /// effective value. Used for keys readable via the C API.
    func colorValue(_ key: String, fallback: String) -> String {
        if let value = fileValue(key), SettingsColor.rgb(value) != nil { return value }
        return effectiveValue(key, .color) ?? fallback
    }

    /// An optional terminal color (e.g. `cursor-color`). These can't be read
    /// via the C API so we use the file, then the active theme.
    func optionalColorValue(_ key: String) -> String? {
        if let value = fileValue(key), SettingsColor.rgb(value) != nil { return value }
        let theme = activeThemeColors
        switch key {
        case "cursor-color": return theme.cursor
        case "cursor-text": return theme.cursorText
        case "selection-background": return theme.selectionBackground
        case "selection-foreground": return theme.selectionForeground
        default: return nil
        }
    }

    /// A binding for an optional terminal color. The getter falls back to the
    /// given color when neither the file nor the theme sets one.
    func optionalColor(_ key: String, fallback: @escaping () -> String) -> Binding<Color> {
        Binding(
            get: { SettingsColor.parse(self.optionalColorValue(key) ?? fallback()) ?? .gray },
            set: { self.set(key, SettingsColor.hex($0)) })
    }

    /// The effective palette color at an index.
    func paletteValue(_ index: Int) -> String {
        if let value = document.paletteValue(at: index), SettingsColor.rgb(value) != nil { return value }
        return effectivePalette[safe: index] ?? "#000000"
    }

    /// True if a palette index is overridden in the configuration file.
    func isPaletteSet(_ index: Int) -> Bool {
        document.paletteValue(at: index) != nil
    }

    /// A binding for a palette color.
    func paletteColor(_ index: Int) -> Binding<Color> {
        Binding(
            get: { SettingsColor.parse(self.paletteValue(index)) ?? .black },
            set: { color in
                let hex = SettingsColor.hex(color)
                self.update { $0.setPalette(index, to: hex) }
            })
    }

    /// Remove a palette override.
    func resetPalette(_ index: Int) {
        guard isPaletteSet(index) else { return }
        update(immediately: true) { $0.setPalette(index, to: nil) }
    }

    /// The colors currently in effect, including overrides. Used for previews.
    var effectiveColors: ThemeColors {
        let background = colorValue("background", fallback: activeThemeColors.background)
        let foreground = colorValue("foreground", fallback: activeThemeColors.foreground)
        return ThemeColors(
            background: background,
            foreground: foreground,
            cursor: optionalColorValue("cursor-color"),
            cursorText: optionalColorValue("cursor-text"),
            selectionBackground: optionalColorValue("selection-background"),
            selectionForeground: optionalColorValue("selection-foreground"),
            palette: (0..<16).map { paletteValue($0) })
    }
}
