import Foundation

/// A single `keybind` entry from the configuration file.
///
/// The syntax is `[flag:]...trigger=action`, see the `keybind` documentation
/// in `src/config/Config.zig` and the parser in `src/input/Binding.zig`.
struct Keybind: Equatable {
    /// Flags that may prefix a binding, in canonical order.
    static let knownFlags = ["global", "all", "unconsumed", "performable"]

    var flags: Set<String>
    var trigger: String
    var action: String

    init(flags: Set<String> = [], trigger: String, action: String) {
        self.flags = flags
        self.trigger = trigger
        self.action = action
    }

    /// Parse a binding. Returns nil for values that aren't simple
    /// `trigger=action` bindings (such as `clear`).
    init?(_ value: String) {
        var rest = Substring(value.trimmingCharacters(in: .whitespaces))
        var flags: Set<String> = []
        var matched = true
        while matched {
            matched = false
            for flag in Self.knownFlags where rest.hasPrefix(flag + ":") {
                flags.insert(flag)
                rest = rest.dropFirst(flag.count + 1)
                matched = true
            }
        }

        // Find the separator. An `=` followed by `+` or `=` is part of the
        // trigger (e.g. `ctrl+==ignore` binds ctrl and the `=` key).
        var separator: Substring.Index?
        var index = rest.startIndex
        while index < rest.endIndex {
            if rest[index] == "=" {
                let next = rest.index(after: index)
                if next < rest.endIndex && (rest[next] == "+" || rest[next] == "=") {
                    index = next
                    continue
                }
                separator = index
                break
            }
            index = rest.index(after: index)
        }

        guard let separator else { return nil }
        let trigger = rest[..<separator].trimmingCharacters(in: .whitespaces)
        let action = rest[rest.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty, !action.isEmpty else { return nil }

        self.flags = flags
        self.trigger = trigger
        self.action = action
    }

    /// The value to write to the configuration file.
    var configValue: String {
        let prefix = Self.knownFlags.filter { flags.contains($0) }.map { "\($0):" }.joined()
        return "\(prefix)\(trigger)=\(action)"
    }

    /// Common actions offered as suggestions when editing a binding. Any
    /// action supported by Ghostty may be typed in.
    static let suggestedActions = [
        "new_window", "new_tab", "close_surface", "close_tab", "close_window", "close_all_windows", "quit",
        "copy_to_clipboard", "paste_from_clipboard", "paste_from_selection", "select_all",
        "increase_font_size:1", "decrease_font_size:1", "reset_font_size",
        "clear_screen", "scroll_to_top", "scroll_to_bottom", "scroll_page_up", "scroll_page_down",
        "jump_to_prompt:-1", "jump_to_prompt:1",
        "previous_tab", "next_tab", "last_tab", "goto_tab:1", "move_tab:-1", "move_tab:1",
        "new_split:right", "new_split:down", "new_split:left", "new_split:up",
        "goto_split:previous", "goto_split:next", "goto_split:left", "goto_split:right",
        "goto_split:up", "goto_split:down", "toggle_split_zoom", "equalize_splits",
        "resize_split:up,10", "resize_split:down,10", "resize_split:left,10", "resize_split:right,10",
        "toggle_fullscreen", "toggle_maximize", "toggle_window_decorations", "toggle_window_float_on_top",
        "toggle_quick_terminal", "toggle_visibility", "toggle_command_palette", "toggle_secure_input",
        "toggle_background_opacity", "toggle_readonly", "toggle_mouse_reporting",
        "prompt_surface_title", "prompt_tab_title", "start_search", "search_selection",
        "inspector:toggle", "open_config", "reload_config", "check_for_updates", "undo", "redo",
        "write_scrollback_file:open", "write_screen_file:open",
        "text:", "csi:", "esc:", "ignore", "unbind",
    ]
}

extension SettingsModel {
    /// The `keybind` values in the configuration file, in order.
    var keybindValues: [String] {
        document.values(for: "keybind")
    }

    /// Replace the keybind entry at the given position among keybind entries.
    func replaceKeybind(at position: Int, with value: String) {
        update(immediately: true) { document in
            let indices = document.entryIndices(for: "keybind")
            guard indices.indices.contains(position) else { return }
            document.replaceLine(at: indices[position], key: "keybind", value: value)
        }
    }

    /// Remove the keybind entries at the given positions.
    func removeKeybinds(at positions: Set<Int>) {
        update(immediately: true) { document in
            let indices = document.entryIndices(for: "keybind")
            document.removeLines(at: positions.compactMap { indices[safe: $0] })
        }
    }

    /// Add a new keybind, grouped with any existing keybinds.
    func addKeybind(_ value: String) {
        update(immediately: true) { document in
            if let last = document.entryIndices(for: "keybind").last {
                document.insert("keybind", value: value, after: last)
            } else {
                document.append("keybind", value: value)
            }
        }
    }
}
