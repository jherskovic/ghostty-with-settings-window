import AppKit
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        SettingsPane {
            configurationSection
            renderingSection
            automationSection
            notificationsSection
        }
    }

    // MARK: Configuration File

    private var displayPath: String {
        let path = model.fileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private var configurationSection: some View {
        Section {
            LabeledContent("Location") {
                Text(displayPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Button("Open in Editor") { model.openInEditor() }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.fileURL.resolvingSymlinksInPath()])
                }
                Spacer()
                Button("Reload Configuration") { model.reloadConfiguration() }
            }

            if let error = model.saveError {
                Label("Couldn't save settings: \(error)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            let errors = model.configErrors
            if !errors.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errors, id: \.self) { error in
                            Text(error)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label(
                        "^[\(errors.count) problem](inflect: true) found in the configuration",
                        systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Configuration File")
        } footer: {
            SettingsFootnote(
                "Settings are saved to this file and applied immediately. Comments and settings that aren't " +
                "shown here are kept as they are. Some settings only affect new windows or terminals.")
        }
    }

    // MARK: Rendering

    private var renderingSection: some View {
        Section("Rendering") {
            Picker("Color space", selection: model.string("window-colorspace", default: "srgb")) {
                Text("sRGB").tag("srgb")
                Text("Display P3").tag("display-p3")
            }
            .resettable(model, "window-colorspace")

            Toggle("Synchronize drawing with the display (VSync)", isOn: model.bool("window-vsync", default: true))
                .resettable(model, "window-vsync")
        }
    }

    // MARK: Automation

    private var automationSection: some View {
        Section {
            Toggle("Allow control with AppleScript", isOn: model.bool("macos-applescript", default: true))
                .resettable(model, "macos-applescript")

            Picker("Allow control with Shortcuts", selection: model.string("macos-shortcuts", default: "ask")) {
                Text("Ask").tag("ask")
                Text("Allow").tag("allow")
                Text("Deny").tag("deny")
            }
            .resettable(model, "macos-shortcuts")
        } header: {
            Text("Automation")
        } footer: {
            SettingsFootnote("Changes to AppleScript access take effect after restarting Ghostty.")
        }
    }

    // MARK: In-App Notifications

    private var notificationsSection: some View {
        Section("In-App Notifications") {
            Toggle("Show a notification when text is copied", isOn: appNotification("clipboard-copy"))
            Toggle("Show a notification when the configuration reloads", isOn: appNotification("config-reload"))
        }
        .resettable(model, "app-notifications")
    }

    private func appNotification(_ name: String) -> Binding<Bool> {
        model.flag(
            "app-notifications",
            name,
            fields: ["clipboard-copy", "config-reload"],
            defaults: ["clipboard-copy", "config-reload"])
    }
}
