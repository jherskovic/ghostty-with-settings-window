import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        SettingsPane {
            Section("Startup") {
                Toggle("Open a new window when Ghostty starts", isOn: model.bool("initial-window", default: true))
                    .resettable(model, "initial-window")

                Picker("Restore windows on launch", selection: model.string("window-save-state", default: "default")) {
                    Text("Use System Setting").tag("default")
                    Text("Always").tag("always")
                    Text("Never").tag("never")
                }
                .resettable(model, "window-save-state")

                Toggle(
                    "Hide Ghostty from the Dock and App Switcher",
                    isOn: model.bool("macos-hidden", on: "always", off: "never", default: false))
                    .resettable(model, "macos-hidden")
            }

            Section("Closing") {
                Picker("Confirm before closing", selection: model.string("confirm-close-surface", default: "true")) {
                    Text("When a Process Is Running").tag("true")
                    Text("Always").tag("always")
                    Text("Never").tag("false")
                }
                .resettable(model, "confirm-close-surface")

                Toggle(
                    "Quit when the last window is closed",
                    isOn: model.bool("quit-after-last-window-closed", default: false))
                    .resettable(model, "quit-after-last-window-closed")
            }

            Section("New Terminals") {
                WorkingDirectoryRow()

                Toggle(
                    "New windows open in the current directory",
                    isOn: model.bool("window-inherit-working-directory", default: true))
                    .resettable(model, "window-inherit-working-directory")
                Toggle(
                    "New tabs open in the current directory",
                    isOn: model.bool("tab-inherit-working-directory", default: true))
                    .resettable(model, "tab-inherit-working-directory")
                Toggle(
                    "New splits open in the current directory",
                    isOn: model.bool("split-inherit-working-directory", default: true))
                    .resettable(model, "split-inherit-working-directory")
                Toggle(
                    "New windows use the current font size",
                    isOn: model.bool("window-inherit-font-size", default: true))
                    .resettable(model, "window-inherit-font-size")

                Picker("Open new tabs", selection: model.string("window-new-tab-position", default: "current")) {
                    Text("After the Current Tab").tag("current")
                    Text("At the End").tag("end")
                }
                .resettable(model, "window-new-tab-position")

                Picker(
                    "Files dropped on the Dock icon open in",
                    selection: model.string("macos-dock-drop-behavior", default: "new-tab")
                ) {
                    Text("A New Tab").tag("new-tab")
                    Text("A New Window").tag("new-window")
                }
                .resettable(model, "macos-dock-drop-behavior")
            }

            Section("Software Update") {
                Picker("Automatic updates", selection: model.optionalString("auto-update")) {
                    Text("Default").tag("")
                    Divider()
                    Text("Off").tag("off")
                    Text("Check Automatically").tag("check")
                    Text("Download and Install Automatically").tag("download")
                }

                Picker("Update channel", selection: model.optionalString("auto-update-channel")) {
                    Text("Default").tag("")
                    Divider()
                    Text("Stable Releases").tag("stable")
                    Text("Tip (Nightly Builds)").tag("tip")
                }
            }

            Section {
                Toggle(
                    "Turn on Secure Keyboard Entry at password prompts",
                    isOn: model.bool("macos-auto-secure-input", default: true))
                    .resettable(model, "macos-auto-secure-input")
                Toggle(
                    "Show an indicator while Secure Keyboard Entry is on",
                    isOn: model.bool("macos-secure-input-indication", default: true))
                    .resettable(model, "macos-secure-input-indication")
            } header: {
                Text("Security")
            } footer: {
                SettingsFootnote(
                    "Secure Keyboard Entry prevents other apps from reading what you type. " +
                    "Password prompts are detected automatically.")
            }
        }
    }
}

/// The `working-directory` setting: a default, special values, or a path.
private struct WorkingDirectoryRow: View {
    @EnvironmentObject private var model: SettingsModel

    private enum Choice: String {
        case automatic = ""
        case home
        case inherit
        case custom
    }

    private var value: String { model.fileValue("working-directory") ?? "" }

    private var choice: Choice {
        switch value {
        case "": return .automatic
        case "home": return .home
        case "inherit": return .inherit
        default: return .custom
        }
    }

    var body: some View {
        Picker("Working directory", selection: Binding(
            get: { choice },
            set: { newValue in
                switch newValue {
                case .automatic: model.reset("working-directory")
                case .home, .inherit: model.set("working-directory", newValue.rawValue)
                case .custom: chooseDirectory()
                }
            })
        ) {
            Text("Automatic").tag(Choice.automatic)
            Text("Home Folder").tag(Choice.home)
            Text("Inherit from Launching Process").tag(Choice.inherit)
            Divider()
            Text("Custom…").tag(Choice.custom)
        }

        if choice == .custom {
            PathField(
                placeholder: "/path/to/directory",
                path: Binding(
                    get: { value },
                    set: { model.set("working-directory", $0.isEmpty ? nil : $0) }),
                chooseDirectories: true)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
        model.set("working-directory", path)
    }
}
