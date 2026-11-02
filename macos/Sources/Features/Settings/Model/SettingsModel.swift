import AppKit
import Combine
import GhosttyKit
import SwiftUI

/// The C type of a configuration key as exposed through `ghostty_config_get`.
/// This is used to read the *effective* value of a key when it is not set
/// explicitly in the configuration file.
enum ConfigValueType {
    case bool
    case string
    case float
    case double
    case uint
    case color
}

/// The data model behind the Settings window.
///
/// The model edits the user's configuration file directly. Reads come from the
/// file when a key is set there, otherwise from the running (effective)
/// configuration so that defaults, themes and included files are reflected.
/// Writes are applied to an in-memory `ConfigDocument` immediately (so the UI
/// updates instantly) and are persisted after a short debounce, after which
/// the configuration is reloaded so changes take effect right away.
///
/// This must only be used from the main thread.
final class SettingsModel: ObservableObject {
    /// The configuration file being edited.
    let fileURL: URL

    /// The parsed configuration file, including any edits not yet saved.
    @Published private(set) var document: ConfigDocument

    /// The configuration currently in effect for the app.
    @Published private(set) var effective: Ghostty.Config

    /// The last error encountered saving the configuration file, if any.
    @Published var saveError: String?

    private weak var ghostty: Ghostty.App?

    /// Edits that have been applied to `document` but not yet written. They're
    /// stored as operations rather than as a document so that they can be
    /// replayed on top of the file's latest contents at save time. This avoids
    /// clobbering edits made in a text editor while the window is open.
    private var pending: [(inout ConfigDocument) -> Void] = []
    private var saveWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []
    private var cachedPalette: [String]?

    init(ghostty: Ghostty.App) {
        self.ghostty = ghostty
        self.fileURL = Self.configURL(for: ghostty)
        self.document = ConfigDocument(contents: Self.read(fileURL))
        self.effective = ghostty.config

        // Track the app configuration so that effective values (and the file,
        // if it was edited elsewhere and reloaded) stay current.
        ghostty.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in self?.configDidChange(config) }
            .store(in: &cancellables)

        // Don't lose edits that are still waiting for the save debounce.
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.save(reload: false) }
            .store(in: &cancellables)
    }

    /// Errors from the last configuration load.
    var configErrors: [String] { effective.errors }

    // MARK: Reading

    /// True if the key is explicitly set in the configuration file.
    func isSet(_ key: String) -> Bool {
        document.contains(key)
    }

    /// The raw value of a key as written in the configuration file.
    func fileValue(_ key: String) -> String? {
        guard let value = document.value(for: key), !value.isEmpty else { return nil }
        return value
    }

    /// The effective value of a key formatted the way it would be written in
    /// a configuration file, or nil if it can't be read via the C API.
    func effectiveValue(_ key: String, _ type: ConfigValueType) -> String? {
        switch type {
        case .bool: return effective.settingsBool(key).map { $0 ? "true" : "false" }
        case .string: return effective.settingsString(key)
        case .float: return effective.settingsFloat(key).map { Self.format(Double($0)) }
        case .double: return effective.settingsDouble(key).map { Self.format($0) }
        case .uint: return effective.settingsUInt(key).map { String($0) }
        case .color: return effective.settingsColor(key)
        }
    }

    /// The value to display for a key: the file value if set, otherwise the
    /// effective value, otherwise the given fallback.
    func value(_ key: String, _ type: ConfigValueType? = .string, default fallback: String = "") -> String {
        if let value = fileValue(key) { return value }
        if let type, let value = effectiveValue(key, type) { return value }
        return fallback
    }

    /// The effective palette, cached per configuration.
    var effectivePalette: [String] {
        if let cachedPalette { return cachedPalette }
        let palette = effective.settingsPalette ?? Array(repeating: "#000000", count: 256)
        cachedPalette = palette
        return palette
    }

    // MARK: Writing

    /// Apply an edit to the configuration file.
    func update(immediately: Bool = false, _ operation: @escaping (inout ConfigDocument) -> Void) {
        operation(&document)
        pending.append(operation)
        scheduleSave(after: immediately ? 0 : 0.35)
    }

    /// Set a single-valued key.
    func set(_ key: String, _ value: String) {
        update { $0.set(key, to: value) }
    }

    /// Set a key, or remove it if `value` is nil.
    func set(_ key: String, _ value: String?) {
        if let value {
            set(key, value)
        } else {
            reset(key)
        }
    }

    /// Remove a key from the configuration file so it reverts to its default.
    func reset(_ key: String) {
        guard isSet(key) else { return }
        update(immediately: true) { $0.remove(key) }
    }

    /// Write any pending edits to disk and (optionally) reload the configuration.
    func save(reload: Bool = true) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard !pending.isEmpty else { return }

        let original = Self.read(fileURL)
        var updated = ConfigDocument(contents: original)
        for operation in pending { operation(&updated) }
        pending.removeAll()
        document = updated

        guard updated.contents != original else { return }

        do {
            let target = fileURL.resolvingSymlinksInPath()
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(updated.contents.utf8).write(to: target, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            return
        }

        if reload { ghostty?.reloadConfig() }
    }

    /// Re-read the configuration file from disk unless we have unsaved edits.
    func reloadFromDisk() {
        guard pending.isEmpty else { return }
        let fresh = ConfigDocument(contents: Self.read(fileURL))
        if fresh != document { document = fresh }
    }

    /// Open the configuration file in the default editor.
    func openInEditor() {
        save()
        NSWorkspace.shared.open(fileURL)
    }

    /// Reload the configuration from disk.
    func reloadConfiguration() {
        save()
        reloadFromDisk()
        ghostty?.reloadConfig()
    }

    // MARK: Private

    private func scheduleSave(after delay: TimeInterval) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func configDidChange(_ config: Ghostty.Config) {
        effective = config
        cachedPalette = nil
        reloadFromDisk()
    }

    private static func configURL(for ghostty: Ghostty.App) -> URL {
        if let path = ghostty.configPath { return URL(fileURLWithPath: path) }
        let path = Ghostty.AllocatedString(ghostty_config_open_path()).string
        if !path.isEmpty { return URL(fileURLWithPath: path) }

        // This should never happen but fall back to the XDG location.
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty/config.ghostty")
    }

    private static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: Value Formatting

    /// Format a number the way a human would write it in a config file.
    static func format(_ value: Double, decimals: Int = 2) -> String {
        let scale = pow(10, Double(decimals))
        let rounded = (value * scale).rounded() / scale
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int(rounded))
        }

        var text = String(format: "%.\(decimals)f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Parse a boolean the same way Ghostty does.
    static func parseBool(_ value: String) -> Bool? {
        switch value {
        case "1", "t", "T", "true": return true
        case "0", "f", "F", "false": return false
        default: return nil
        }
    }
}

// MARK: - Bindings

extension SettingsModel {
    /// A binding for a boolean key.
    func bool(_ key: String, default fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { Self.parseBool(self.value(key, .bool, default: "")) ?? fallback },
            set: { self.set(key, $0 ? "true" : "false") })
    }

    /// A binding for a boolean key that is stored as one of two enum values
    /// (for example `visible`/`hidden`).
    func bool(_ key: String, on: String, off: String, default fallback: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let value = self.value(key, .string, default: fallback ? on : off)
                return value == on
            },
            set: { self.set(key, $0 ? on : off) })
    }

    /// A binding for an enum or string key.
    func string(_ key: String, _ type: ConfigValueType? = .string, default fallback: String = "") -> Binding<String> {
        Binding(
            get: { self.value(key, type, default: fallback) },
            set: { self.set(key, $0) })
    }

    /// A binding for an enum key where the empty string means "unset", which
    /// lets pickers offer a "Default" choice that removes the key.
    func optionalString(_ key: String, _ type: ConfigValueType? = .string) -> Binding<String> {
        Binding(
            get: { self.value(key, type, default: "") },
            set: { $0.isEmpty ? self.reset(key) : self.set(key, $0) })
    }

    /// A binding for a numeric key.
    func number(
        _ key: String,
        _ type: ConfigValueType,
        default fallback: Double,
        decimals: Int = 2
    ) -> Binding<Double> {
        Binding(
            get: { Double(self.value(key, type, default: "")) ?? fallback },
            set: { self.set(key, Self.format($0, decimals: decimals)) })
    }

    /// A binding for a single field of a packed-struct key (e.g.
    /// `bell-features`). The full value is always written explicitly so that
    /// it doesn't depend on the defaults.
    func flag(_ key: String, _ name: String, fields: [String], defaults: Set<String>) -> Binding<Bool> {
        Binding(
            get: { self.flags(key, fields: fields, defaults: defaults).contains(name) },
            set: { enabled in
                var current = self.flags(key, fields: fields, defaults: defaults)
                if enabled { current.insert(name) } else { current.remove(name) }
                let value = fields.map { current.contains($0) ? $0 : "no-\($0)" }.joined(separator: ",")
                self.set(key, value)
            })
    }

    /// The enabled fields of a packed-struct key.
    func flags(_ key: String, fields: [String], defaults: Set<String>) -> Set<String> {
        if let value = fileValue(key) {
            // Mirror `parsePackedStruct` in src/cli/args.zig.
            if let all = Self.parseBool(value) { return all ? Set(fields) : [] }
            var result = defaults
            for part in value.split(separator: ",") {
                let part = part.trimmingCharacters(in: .whitespaces)
                if part.hasPrefix("no-") {
                    result.remove(String(part.dropFirst(3)))
                } else {
                    result.insert(part)
                }
            }
            return result
        }

        if let bits = effective.settingsBits(key) {
            return Set(fields.enumerated().compactMap { index, field in
                bits & (1 << index) != 0 ? field : nil
            })
        }

        return defaults
    }

    /// A binding for a color key whose effective value can be read via the
    /// C API (e.g. `background`).
    func color(_ key: String, fallback: String = "#000000") -> Binding<Color> {
        Binding(
            get: {
                let value = self.fileValue(key) ?? ""
                if let color = SettingsColor.parse(value) { return color }
                return SettingsColor.parse(self.effectiveValue(key, .color) ?? fallback) ?? .black
            },
            set: { self.set(key, SettingsColor.hex($0)) })
    }
}
