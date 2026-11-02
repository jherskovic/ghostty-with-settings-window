import Foundation
import GhosttyKit

/// Generic, typed accessors for configuration values used by the settings UI.
///
/// The settings window needs to show the *effective* value of many keys (the
/// value after defaults, themes, included files and CLI flags are applied).
/// `ghostty_config_get` supports a fixed set of C-compatible types; these
/// helpers wrap it so that callers only need to know the type of the key as
/// defined in `src/config/Config.zig`.
extension Ghostty.Config {
    private func get<T>(_ key: String, _ value: inout T) -> Bool {
        guard let config = self.config else { return false }
        return withUnsafeMutablePointer(to: &value) { ptr in
            ghostty_config_get(config, ptr, key, UInt(key.lengthOfBytes(using: .utf8)))
        }
    }

    /// `bool` (and `?bool`, which returns nil when unset).
    func settingsBool(_ key: String) -> Bool? {
        var v = false
        return get(key, &v) ? v : nil
    }

    /// Enums (returned as their tag name) and `?[:0]const u8` strings.
    func settingsString(_ key: String) -> String? {
        var v: UnsafePointer<Int8>?
        guard get(key, &v), let v else { return nil }
        return String(cString: v)
    }

    /// `f32` keys.
    func settingsFloat(_ key: String) -> Float? {
        var v: Float = 0
        return get(key, &v) ? v : nil
    }

    /// `f64` keys.
    func settingsDouble(_ key: String) -> Double? {
        var v: Double = 0
        return get(key, &v) ? v : nil
    }

    /// `u8` and `u32` keys.
    func settingsUInt(_ key: String) -> UInt32? {
        var v: CUnsignedInt = 0
        return get(key, &v) ? UInt32(v) : nil
    }

    /// `i16` keys (and types whose C value is an `i16`, like `background-blur`).
    func settingsInt16(_ key: String) -> Int16? {
        var v: Int16 = 0
        return get(key, &v) ? v : nil
    }

    /// Packed structs of booleans, returned as their bit representation where
    /// bit N corresponds to the Nth field of the struct.
    func settingsBits(_ key: String) -> UInt32? {
        settingsUInt(key)
    }

    /// `Duration` keys, in milliseconds.
    func settingsDurationMilliseconds(_ key: String) -> UInt? {
        var v: UInt = 0
        return get(key, &v) ? v : nil
    }

    /// `Color` and `?Color` keys as a `#rrggbb` string.
    func settingsColor(_ key: String) -> String? {
        var v = ghostty_config_color_s()
        guard get(key, &v) else { return nil }
        return String(format: "#%02x%02x%02x", v.r, v.g, v.b)
    }

    /// The full 256-color palette as `#rrggbb` strings.
    var settingsPalette: [String]? {
        var v = ghostty_config_palette_s()
        guard get("palette", &v) else { return nil }
        return withUnsafeBytes(of: &v.colors) { raw in
            let colors = raw.bindMemory(to: ghostty_config_color_s.self)
            return colors.map { String(format: "#%02x%02x%02x", $0.r, $0.g, $0.b) }
        }
    }
}
