import AppKit
import SwiftUI

struct TextSettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        SettingsPane {
            fontSection
            metricsSection
            cursorSection
        }
    }

    // MARK: Font

    private var fontFamily: String { model.primaryFontFamily }

    private var fontSize: Double {
        Double(model.value("font-size", .float, default: "13")) ?? 13
    }

    @ViewBuilder
    private var fontSection: some View {
        Section("Font") {
            Picker("Font", selection: Binding(
                get: { fontFamily },
                set: { model.setPrimaryFontFamily($0) })
            ) {
                Text("\(FontLibrary.defaultFamily) (Default)").tag("")
                Divider()
                if !fontFamily.isEmpty && !FontLibrary.monospacedFamilies.contains(fontFamily) {
                    Text(fontFamily).tag(fontFamily)
                }
                ForEach(FontLibrary.monospacedFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .resettable(model, "font-family")

            LabeledContent("Size") {
                HStack(spacing: 4) {
                    TextField(
                        "",
                        value: model.number("font-size", .float, default: 13, decimals: 1),
                        format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                        .frame(width: 56)
                    Stepper(
                        "",
                        value: model.number("font-size", .float, default: 13, decimals: 1),
                        in: 4...200,
                        step: 1)
                        .labelsHidden()
                    Text("pt").foregroundStyle(.secondary)
                }
            }
            .resettable(model, "font-size")

            Toggle("Use ligatures", isOn: Binding(
                get: { model.ligaturesEnabled },
                set: { model.setLigatures($0) }))

            Toggle("Thicken font strokes", isOn: model.bool("font-thicken", default: false))
                .resettable(model, "font-thicken")

            if model.bool("font-thicken", default: false).wrappedValue {
                LabeledContent("Thickness") {
                    Slider(
                        value: model.number("font-thicken-strength", .uint, default: 255, decimals: 0),
                        in: 0...255
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Light").font(.caption)
                    } maximumValueLabel: {
                        Text("Heavy").font(.caption)
                    }
                    .labelsHidden()
                }
                .resettable(model, "font-thicken-strength")
            }

            TerminalPreview(
                colors: model.effectiveColors,
                font: Font(FontLibrary.previewFont(
                    family: fontFamily.isEmpty ? FontLibrary.defaultFamily : fontFamily,
                    size: fontSize,
                    ligatures: model.ligaturesEnabled)),
                showsPalette: false,
                sample: ligatureSample)
                .padding(.vertical, 4)
        }
    }

    private let ligatureSample = "-> != === <= ::"

    // MARK: Metrics

    private var metricsSection: some View {
        Section {
            MetricRow(title: "Line height", key: "adjust-cell-height")
            MetricRow(title: "Character width", key: "adjust-cell-width")
            MetricRow(title: "Baseline", key: "adjust-font-baseline")
        } header: {
            Text("Spacing")
        } footer: {
            SettingsFootnote(
                "Adjust the size of each terminal cell. Use a percentage (e.g. 10%) " +
                "or a number of pixels (e.g. 2). Negative values are allowed.")
        }
    }

    // MARK: Cursor

    private var cursorSection: some View {
        Section {
            Picker("Style", selection: model.string("cursor-style", default: "block")) {
                Label("Block", systemImage: "rectangle.fill").tag("block")
                Label("Bar", systemImage: "poweron").tag("bar")
                Label("Underline", systemImage: "minus").tag("underline")
                Label("Hollow Block", systemImage: "rectangle").tag("block_hollow")
            }
            .resettable(model, "cursor-style")

            Picker("Blink", selection: model.optionalString("cursor-style-blink", .bool)) {
                Text("Default").tag("")
                Divider()
                Text("On").tag("true")
                Text("Off").tag("false")
            }

            LabeledContent("Opacity") {
                HStack {
                    let binding = model.number("cursor-opacity", .double, default: 1)
                    Slider(value: binding, in: 0...1)
                        .labelsHidden()
                    Text("\(Int((binding.wrappedValue * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .resettable(model, "cursor-opacity")
        } header: {
            Text("Cursor")
        } footer: {
            SettingsFootnote(
                "Programs can change the cursor style while they run. With shell integration, " +
                "the cursor becomes a bar at the prompt (see Terminal settings).")
        }
    }
}

/// A row for a metric modifier such as `adjust-cell-height` (`10%` or `2`).
private struct MetricRow: View {
    @EnvironmentObject private var model: SettingsModel
    let title: String
    let key: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                CommittingTextField(
                    placeholder: "Default",
                    text: Binding(
                        get: { model.fileValue(key) ?? "" },
                        set: { model.set(key, $0.isEmpty ? nil : $0) }))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Stepper("", onIncrement: { step(1) }, onDecrement: { step(-1) })
                    .labelsHidden()
            }
        }
        .resettable(model, key)
    }

    /// Step the value, preserving its unit. Percentages move in 5% steps.
    private func step(_ direction: Int) {
        let current = model.fileValue(key) ?? ""
        let isPercent = current.isEmpty || current.hasSuffix("%")
        let number = Int(current.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) ?? 0
        let next = number + direction * (isPercent ? 5 : 1)
        if next == 0 {
            model.reset(key)
        } else {
            model.set(key, isPercent ? "\(next)%" : "\(next)")
        }
    }
}

// MARK: - Font Helpers

extension SettingsModel {
    /// The primary font family. `font-family` is repeatable to configure
    /// fallbacks and an empty value resets the list, so the primary family is
    /// the first value after the last reset.
    var primaryFontFamily: String {
        let values = document.values(for: "font-family")
        let afterReset = values.lastIndex(of: "").map { Array(values[($0 + 1)...]) } ?? values
        return afterReset.first ?? ""
    }

    /// Set the primary font family, keeping any fallbacks. An empty family
    /// restores the default by removing all `font-family` entries.
    func setPrimaryFontFamily(_ family: String) {
        update { document in
            guard !family.isEmpty else {
                document.remove("font-family")
                return
            }

            let indices = document.entryIndices(for: "font-family")
            let values = document.values(for: "font-family")
            let start = values.lastIndex(of: "").map { $0 + 1 } ?? 0
            if start < indices.count {
                document.replaceLine(at: indices[start], key: "font-family", value: family)
            } else {
                document.append("font-family", value: family)
            }
        }
    }

    private static let ligatureFeatures: Set<String> = ["-calt", "-liga", "-dlig", "calt=0", "liga=0", "dlig=0"]

    /// Whether programming ligatures are enabled. They're on by default and
    /// are disabled by turning off the `calt`, `liga` and `dlig` features.
    var ligaturesEnabled: Bool {
        !document.values(for: "font-feature").contains { Self.ligatureFeatures.contains($0.replacingOccurrences(of: " ", with: "")) }
    }

    func setLigatures(_ enabled: Bool) {
        update { document in
            document.removeValues(for: "font-feature") {
                Self.ligatureFeatures.contains($0.replacingOccurrences(of: " ", with: ""))
            }
            if !enabled {
                for feature in ["-calt", "-liga", "-dlig"] {
                    document.append("font-feature", value: feature)
                }
            }
        }
    }
}
