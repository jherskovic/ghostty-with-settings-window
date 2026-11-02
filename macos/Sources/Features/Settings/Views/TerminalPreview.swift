import SwiftUI

/// A small, static rendering of a terminal session used to preview colors
/// and fonts in the settings window.
struct TerminalPreview: View {
    let colors: ThemeColors
    var font: Font = .system(size: 12, design: .monospaced)
    var showsPalette = true

    /// An optional extra line, e.g. to demonstrate ligatures.
    var sample: String?

    /// A run of text in a single color.
    private struct Run {
        let text: String
        let color: Color
        var bold = false
    }

    private func c(_ hex: String?) -> Color {
        SettingsColor.parse(hex ?? "") ?? .gray
    }

    private func ansi(_ index: Int) -> Color {
        c(colors.palette[safe: index])
    }

    private var fg: Color { c(colors.foreground) }

    private func line(_ runs: [Run]) -> Text {
        var string = AttributedString()
        for run in runs {
            var part = AttributedString(run.text)
            part.swiftUI.foregroundColor = run.color
            if run.bold { part.inlinePresentationIntent = .stronglyEmphasized }
            string.append(part)
        }
        return Text(string)
    }

    private var prompt: [Run] {
        [
            Run(text: "~/ghostty", color: ansi(6)),
            Run(text: " main", color: ansi(5)),
            Run(text: " ❯ ", color: ansi(2)),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line(prompt + [Run(text: "ls", color: fg)])
            line([
                Run(text: "README.md  build.zig  ", color: fg),
                Run(text: "macos/  src/  ", color: ansi(4), bold: true),
                Run(text: "run.sh", color: ansi(2), bold: true),
            ])
            line(prompt + [Run(text: "git status --short", color: fg)])
            line([Run(text: " M ", color: ansi(1)), Run(text: "src/main.zig", color: fg)])
            line([Run(text: "?? ", color: ansi(1)), Run(text: "notes.txt", color: fg)])
            if let sample {
                line(prompt + [Run(text: "echo '", color: fg), Run(text: sample, color: ansi(3)), Run(text: "'", color: fg)])
            }
            HStack(spacing: 0) {
                line(prompt)
                line([Run(text: " ", color: fg)])
                    .background(c(colors.cursor ?? colors.foreground))
            }

            if showsPalette {
                VStack(spacing: 3) {
                    paletteRow(0..<8)
                    paletteRow(8..<16)
                }
                .padding(.top, 6)
            }
        }
        .font(font)
        .lineLimit(1)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c(colors.background))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func paletteRow(_ range: Range<Int>) -> some View {
        HStack(spacing: 3) {
            ForEach(range, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(ansi(index))
                    .frame(height: 10)
            }
        }
    }
}

/// A compact strip of a theme's colors, used in lists.
struct ThemeSwatch: View {
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(SettingsColor.parse(colors.background) ?? .black)
                .overlay(
                    Text("A")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(SettingsColor.parse(colors.foreground) ?? .white))
                .frame(width: 16)
            ForEach(1..<7, id: \.self) { index in
                Rectangle().fill(SettingsColor.parse(colors.palette[safe: index] ?? "") ?? .gray)
                    .frame(width: 7)
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
    }
}
