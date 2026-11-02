import Foundation

/// An editable, line-preserving representation of a Ghostty configuration file.
///
/// The Ghostty configuration syntax is simple: every non-blank line that does
/// not start with `#` is `key = value`. Values may optionally be wrapped in
/// double quotes. For most keys the last value wins, while some keys (such as
/// `keybind`, `palette` or `font-family`) are repeatable and accumulate.
///
/// The settings UI uses this type to read and update individual keys while
/// leaving everything else in the file (comments, ordering, unknown keys,
/// formatting of untouched lines) exactly as the user wrote it.
struct ConfigDocument: Equatable {
    /// A single line of a configuration file.
    enum Line: Equatable {
        /// A blank line, a comment, or anything else we don't interpret. The
        /// original text is preserved verbatim.
        case raw(String)

        /// A `key = value` entry. `original` holds the original text so that
        /// untouched lines round-trip byte-for-byte.
        case entry(key: String, value: String, original: String)
    }

    /// Keys that Ghostty still accepts under an older name. When reading or
    /// writing the canonical key we also consider the legacy spelling so that
    /// we never end up with two conflicting lines.
    static let aliases: [String: [String]] = [
        "scrollback-limit-bytes": ["scrollback-limit"],
        "background-blur": ["background-blur-radius"],
    ]

    private(set) var lines: [Line]

    /// Whether the original contents ended with a newline. We preserve this
    /// so that a no-op edit produces an identical file.
    private var endsWithNewline: Bool

    init(contents: String = "") {
        var lines: [Line] = []
        var parts = contents.components(separatedBy: "\n")
        let endsWithNewline = contents.hasSuffix("\n")
        if endsWithNewline { parts.removeLast() }
        if contents.isEmpty { parts = [] }

        for text in parts {
            lines.append(Self.parse(line: text))
        }

        self.lines = lines
        self.endsWithNewline = endsWithNewline || contents.isEmpty
    }

    /// The serialized contents of the document.
    var contents: String {
        let text = lines.map { line -> String in
            switch line {
            case .raw(let text): return text
            case .entry(_, _, let original): return original
            }
        }.joined(separator: "\n")

        if lines.isEmpty { return "" }
        return endsWithNewline ? text + "\n" : text
    }

    // MARK: Reading

    /// All the values for the given key in file order.
    func values(for key: String) -> [String] {
        entryIndices(for: key).compactMap { index in
            if case .entry(_, let value, _) = lines[index] { return value }
            return nil
        }
    }

    /// The effective (last) value of a key in this file, if it is set.
    func value(for key: String) -> String? {
        values(for: key).last
    }

    /// True if the key is set anywhere in this document.
    func contains(_ key: String) -> Bool {
        !entryIndices(for: key).isEmpty
    }

    /// The indices into `lines` of the entries for a key (including legacy
    /// aliases) in file order.
    func entryIndices(for key: String) -> [Int] {
        let keys = Set([key] + (Self.aliases[key] ?? []))
        return lines.indices.filter { index in
            if case .entry(let k, _, _) = lines[index] { return keys.contains(k) }
            return false
        }
    }

    // MARK: Writing

    /// Set a single-valued key. The last existing entry for the key is
    /// updated in place (so that it keeps its position in the file next to any
    /// comments the user wrote). If the key is not present it is appended.
    mutating func set(_ key: String, to value: String) {
        if let index = entryIndices(for: key).last {
            lines[index] = Self.entry(key: key, value: value)
        } else {
            append(key, value: value)
        }
    }

    /// Remove every entry for a key, reverting it to the default value.
    mutating func remove(_ key: String) {
        removeLines(at: entryIndices(for: key))
    }

    /// Append a new entry at the end of the document.
    mutating func append(_ key: String, value: String) {
        lines.append(Self.entry(key: key, value: value))
        endsWithNewline = true
    }

    /// Insert a new entry directly after an existing line.
    mutating func insert(_ key: String, value: String, after index: Int) {
        lines.insert(Self.entry(key: key, value: value), at: index + 1)
    }

    /// Replace the line at the given index with a new entry.
    mutating func replaceLine(at index: Int, key: String, value: String) {
        lines[index] = Self.entry(key: key, value: value)
    }

    /// Remove the lines at the given indices.
    mutating func removeLines(at indices: [Int]) {
        for index in indices.sorted(by: >) {
            lines.remove(at: index)
        }
    }

    /// Remove every entry for a key whose value matches the predicate.
    mutating func removeValues(for key: String, where predicate: (String) -> Bool) {
        let indices = entryIndices(for: key).filter { index in
            if case .entry(_, let value, _) = lines[index] { return predicate(value) }
            return false
        }
        removeLines(at: indices)
    }

    /// Replace every value of a repeatable key with the given list. The new
    /// entries are placed where the first existing entry was, or appended.
    mutating func setValues(_ key: String, _ values: [String]) {
        let indices = entryIndices(for: key)
        guard let first = indices.first else {
            for value in values { append(key, value: value) }
            return
        }

        removeLines(at: Array(indices.dropFirst()))
        lines.remove(at: first)
        for (offset, value) in values.enumerated() {
            lines.insert(Self.entry(key: key, value: value), at: first + offset)
        }
    }

    // MARK: Parsing & Formatting

    /// Parse a single line using the same rules as Ghostty's own config loader
    /// (see `LineIterator` in `src/cli/args.zig`).
    static func parse(line text: String) -> Line {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return .raw(text) }
        guard let eq = trimmed.firstIndex(of: "=") else { return .raw(text) }

        let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return .raw(text) }
        let value = unquote(trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces))
        return .entry(key: key, value: value, original: text)
    }

    /// Ghostty strips one pair of surrounding double quotes from values.
    static func unquote(_ value: String) -> String {
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Format a value so that it reads back as exactly the same value.
    static func format(value: String) -> String {
        let needsQuotes = value != value.trimmingCharacters(in: .whitespaces) ||
            (value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\""))
        return needsQuotes ? "\"\(value)\"" : value
    }

    static func entry(key: String, value: String) -> Line {
        let formatted = format(value: value)
        let original = formatted.isEmpty ? "\(key) =" : "\(key) = \(formatted)"
        return .entry(key: key, value: value, original: original)
    }
}

// MARK: - Repeatable Key Helpers

extension ConfigDocument {
    /// Parse a `palette` value (`N=COLOR`) into its index and color.
    static func paletteEntry(_ value: String) -> (index: Int, color: String)? {
        guard let eq = value.firstIndex(of: "=") else { return nil }
        let indexText = value[..<eq].trimmingCharacters(in: .whitespaces)
        let index: Int?
        if indexText.lowercased().hasPrefix("0x") {
            index = Int(indexText.dropFirst(2), radix: 16)
        } else {
            index = Int(indexText)
        }
        guard let index, (0...255).contains(index) else { return nil }
        let color = value[value.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        return (index, color)
    }

    /// The palette color override for an index set in this file, if any.
    func paletteValue(at index: Int) -> String? {
        values(for: "palette")
            .compactMap(Self.paletteEntry)
            .last { $0.index == index }?
            .color
    }

    /// Set or remove (when `color` is nil) a palette override.
    mutating func setPalette(_ index: Int, to color: String?) {
        let matching = entryIndices(for: "palette").filter { line in
            if case .entry(_, let value, _) = lines[line] {
                return Self.paletteEntry(value)?.index == index
            }
            return false
        }

        guard let color else {
            removeLines(at: matching)
            return
        }

        let value = "\(index)=\(color)"
        if let last = matching.last {
            replaceLine(at: last, key: "palette", value: value)
            removeLines(at: Array(matching.dropLast()))
        } else if let lastPalette = entryIndices(for: "palette").last {
            // Keep palette entries grouped together for readability.
            insert("palette", value: value, after: lastPalette)
        } else {
            append("palette", value: value)
        }
    }
}
