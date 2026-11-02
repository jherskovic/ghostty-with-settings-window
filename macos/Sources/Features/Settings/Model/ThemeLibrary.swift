import AppKit
import SwiftUI

/// Helpers for converting between SwiftUI colors and Ghostty color strings.
enum SettingsColor {
    /// Parse a `#rrggbb`, `rrggbb`, `#rgb` or `rgb` string.
    static func rgb(_ value: String) -> (r: Double, g: Double, b: Double)? {
        var hex = value.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let int = UInt32(hex, radix: 16) else { return nil }
        return (
            Double((int >> 16) & 0xFF) / 255,
            Double((int >> 8) & 0xFF) / 255,
            Double(int & 0xFF) / 255
        )
    }

    /// Parse a hex color string into a SwiftUI color.
    static func parse(_ value: String) -> Color? {
        guard let (r, g, b) = rgb(value) else { return nil }
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    /// Format a SwiftUI color as `#rrggbb`.
    static func hex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

/// The colors defined by a theme (or by Ghostty's built-in defaults).
struct ThemeColors: Equatable {
    var background: String
    var foreground: String
    var cursor: String?
    var cursorText: String?
    var selectionBackground: String?
    var selectionForeground: String?
    var palette: [String]

    /// Ghostty's built-in colors (see `src/terminal/color.zig` and the
    /// `background`/`foreground` defaults in `src/config/Config.zig`).
    static let ghosttyDefault = ThemeColors(
        background: "#282c34",
        foreground: "#ffffff",
        palette: [
            "#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#c5c8c6",
            "#666666", "#d54e53", "#b9ca4a", "#e7c547", "#7aa6da", "#c397d8", "#70c0b1", "#eaeaea",
        ])

    /// Parse the colors from the contents of a theme file. Themes are regular
    /// configuration files so we reuse the config parser.
    init(themeFile contents: String) {
        let document = ConfigDocument(contents: contents)
        let fallback = Self.ghosttyDefault
        func color(_ key: String) -> String? {
            guard let value = document.value(for: key), SettingsColor.rgb(value) != nil else { return nil }
            return value
        }

        background = color("background") ?? fallback.background
        foreground = color("foreground") ?? fallback.foreground
        cursor = color("cursor-color")
        cursorText = color("cursor-text")
        selectionBackground = color("selection-background")
        selectionForeground = color("selection-foreground")
        palette = fallback.palette
        for index in 0..<16 {
            if let value = document.paletteValue(at: index), SettingsColor.rgb(value) != nil {
                palette[index] = value
            }
        }
    }

    init(
        background: String,
        foreground: String,
        cursor: String? = nil,
        cursorText: String? = nil,
        selectionBackground: String? = nil,
        selectionForeground: String? = nil,
        palette: [String]
    ) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.palette = palette
    }

    /// True if the background is dark, used to group themes.
    var isDark: Bool {
        guard let (r, g, b) = SettingsColor.rgb(background) else { return true }
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
    }
}

/// A theme that can be selected in the settings window.
struct ThemeInfo: Identifiable, Hashable {
    let name: String
    let url: URL
    let isUserTheme: Bool

    var id: String { name }
}

/// Discovers the themes available to Ghostty and parses their colors.
///
/// Themes are looked up the same way the core does (see `src/config/theme.zig`):
/// first in `$XDG_CONFIG_HOME/ghostty/themes`, then in the bundled resources.
final class ThemeLibrary {
    static let shared = ThemeLibrary()

    private var cache: [String: ThemeColors] = [:]
    private var themeList: [ThemeInfo]?

    /// The `theme` value used in pairs: `light:NAME,dark:NAME`.
    struct Selection: Equatable {
        var light: String
        var dark: String

        /// Whether separate light and dark themes are configured.
        var isPair: Bool

        init(light: String, dark: String, isPair: Bool) {
            self.light = light
            self.dark = dark
            self.isPair = isPair
        }

        init(single name: String) {
            self.init(light: name, dark: name, isPair: false)
        }

        /// Parse a `theme` configuration value.
        init?(_ value: String) {
            let value = value.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }

            if value.contains(",") || value.contains(":") || value.contains("=") {
                var light = ""
                var dark = ""
                for part in value.split(separator: ",") {
                    let pieces = part.split(separator: ":", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    guard pieces.count == 2 else { continue }
                    switch pieces[0] {
                    case "light": light = pieces[1]
                    case "dark": dark = pieces[1]
                    default: break
                    }
                }
                guard !light.isEmpty || !dark.isEmpty else { return nil }
                self.light = light.isEmpty ? dark : light
                self.dark = dark.isEmpty ? light : dark
                self.isPair = true
            } else {
                light = value
                dark = value
                isPair = false
            }
        }

        /// The configuration value for this selection.
        var configValue: String {
            isPair ? "light:\(light),dark:\(dark)" : light
        }

        /// The theme in effect for the given appearance.
        func name(dark isDark: Bool) -> String {
            isDark ? dark : light
        }
    }

    /// All themes, sorted by name. User themes take precedence over bundled
    /// themes of the same name.
    var themes: [ThemeInfo] {
        if let themeList { return themeList }

        var byName: [String: ThemeInfo] = [:]
        for (dir, isUser) in [(resourcesThemesDir, false), (userThemesDir, true)] {
            guard let dir else { continue }
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])) ?? []
            for url in urls {
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                guard isFile else { continue }
                byName[url.lastPathComponent] = ThemeInfo(name: url.lastPathComponent, url: url, isUserTheme: isUser)
            }
        }

        let sorted = byName.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        themeList = sorted
        return sorted
    }

    /// Clear cached data so new user themes are picked up.
    func invalidate() {
        themeList = nil
        cache.removeAll()
    }

    /// The colors for a theme by name (or absolute path).
    func colors(for name: String) -> ThemeColors? {
        if let cached = cache[name] { return cached }

        let url: URL?
        if name.hasPrefix("/") || name.hasPrefix("~/") {
            url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath)
        } else {
            url = themes.first { $0.name == name }?.url
        }

        guard let url, let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let colors = ThemeColors(themeFile: contents)
        cache[name] = colors
        return colors
    }

    /// The directory for user-installed themes.
    var userThemesDir: URL? {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent("ghostty/themes", isDirectory: true)
    }

    /// The directory for themes bundled with Ghostty.
    private var resourcesThemesDir: URL? {
        if let dir = ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("themes", isDirectory: true)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("ghostty/themes", isDirectory: true)
    }
}
