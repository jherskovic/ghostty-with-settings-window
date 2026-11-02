import AppKit
import SwiftUI

/// A sheet for browsing and choosing a color theme with a live preview.
struct ThemePickerSheet: View {
    let title: String
    let initial: String?
    let onChoose: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    @State private var filter: Filter = .all

    /// Selection tag for "no theme".
    private static let defaultTag = "\u{0}ghostty-default"

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case dark = "Dark"
        case light = "Light"

        var id: String { rawValue }
    }

    private var library: ThemeLibrary { .shared }

    private var themes: [ThemeInfo] {
        library.themes.filter { theme in
            if !query.isEmpty && !theme.name.localizedCaseInsensitiveContains(query) { return false }
            switch filter {
            case .all: return true
            case .dark: return library.colors(for: theme.name)?.isDark ?? true
            case .light: return !(library.colors(for: theme.name)?.isDark ?? true)
            }
        }
    }

    private var selectedName: String? {
        selection == Self.defaultTag ? nil : selection
    }

    private var previewColors: ThemeColors {
        guard let name = selectedName else { return .ghosttyDefault }
        return library.colors(for: name) ?? .ghosttyDefault
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TextField("Search \(library.themes.count) Themes", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .padding(8)
                    themeList
                }
                .frame(width: 250)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedName ?? "Ghostty Default")
                        .font(.title3.weight(.semibold))
                    TerminalPreview(colors: previewColors)
                    if let name = selectedName,
                       let theme = library.themes.first(where: { $0.name == name }),
                       theme.isUserTheme {
                        Label("Installed in your themes folder", systemImage: "person.crop.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                Button("Open Themes Folder") { openUserThemesFolder() }
                    .help("Add your own themes to this folder to use them in Ghostty.")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose") { choose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding()
        }
        .frame(width: 640, height: 500)
        .onAppear { selection = initial ?? Self.defaultTag }
    }

    private var themeList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                if query.isEmpty && filter == .all {
                    HStack {
                        ThemeSwatch(colors: .ghosttyDefault)
                        Text("Ghostty Default").italic()
                    }
                    .tag(Self.defaultTag)
                    .id(Self.defaultTag)
                }

                ForEach(themes) { theme in
                    ThemeListRow(theme: theme)
                        .tag(theme.name)
                        .id(theme.name)
                }
            }
            .contextMenu(forSelectionType: String.self, menu: { _ in EmptyView() }, primaryAction: { _ in choose() })
            .onAppear {
                if let initial { proxy.scrollTo(initial, anchor: .center) }
            }
        }
    }

    private func choose() {
        guard selection != nil else { return }
        onChoose(selectedName)
        dismiss()
    }

    private func openUserThemesFolder() {
        guard let dir = library.userThemesDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

private struct ThemeListRow: View {
    let theme: ThemeInfo

    var body: some View {
        HStack {
            if let colors = ThemeLibrary.shared.colors(for: theme.name) {
                ThemeSwatch(colors: colors)
            }
            Text(theme.name)
            Spacer()
            if theme.isUserTheme {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                    .help("Installed in your themes folder")
            }
        }
    }
}
