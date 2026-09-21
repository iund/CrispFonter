import SwiftUI

private let monospacedFamilies: [String] = {
    NSFontManager.shared.availableFontFamilies.filter { name in
        guard let font = NSFont(name: name, size: 12) else { return false }
        return font.isFixedPitch
    }.sorted()
}()

struct SidebarView: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    var undoManager: UndoManager?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlyphGridView(doc: doc, editor: editor)

                Section("Metrics (grid units)") {
                    metricRow("Ascender", \.ascender, range: 0...20)
                    metricRow("Cap height", \.capHeight, range: 0...20)
                    metricRow("x-height", \.xHeight, range: 0...20)
                    metricRow("Descender", \.descender, range: -10...0)
                    metricRow("Advance width", \.defaultAdvance, range: 1...20)
                    metricRow("Line height", \.lineHeight, range: 0...30)
                }

                Section("Pixels per em") {
                    HStack {
                        Slider(value: $editor.pixPpem, in: 6...18, step: 0.5)
                        Text("\(editor.pixPpem, specifier: "%.1f") pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }

                Section("Vertical alignment bias") {
                    HStack {
                        Slider(value: verticalBiasBinding, in: -2...2, step: biasStep)
                        Text(String(format: "%.2f", doc.project.verticalBias))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    Toggle("Snap to pixel grid (\(Int(editor.pixPpem)) pt)", isOn: $editor.snapBiasToPixel)
                        .font(.caption)
                    Text("Shifts every glyph up/down without touching its points — previews and export reflect it too.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Section("Reference font") {
                    Picker("", selection: Binding(
                        get: { doc.project.referenceFontName },
                        set: { v in doc.mutate(undoManager: undoManager) { $0.referenceFontName = v } }
                    )) {
                        ForEach(["Menlo", "SF Mono", "Monaco", "Consolas", "Courier New"], id: \.self) { Text($0).tag($0) }
                        ForEach(monospacedFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }

                Section("Rendering model") {
                    HStack {
                        Text("1-bit below")
                        Stepper(value: Binding(
                            get: { doc.project.export.gaspMonoThreshold },
                            set: { v in doc.mutate(undoManager: undoManager) { $0.export.gaspMonoThreshold = v } }
                        ), in: 0...99) {
                            Text("\(doc.project.export.gaspMonoThreshold)")
                        }
                    }
                    Text("Greyscale only; FreeType/GDI switch to 1-bit under this size.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func metricRow(_ label: String, _ key: WritableKeyPath<Metrics, Int>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 96, alignment: .leading)
            Slider(value: Binding(
                get: { Double(doc.project.metrics[keyPath: key]) },
                set: { v in doc.mutate("Metrics", undoManager: undoManager) { $0.metrics[keyPath: key] = Int(v.rounded()) } }
            ), in: range, step: 1)
            Text("\(doc.project.metrics[keyPath: key])").monospacedDigit().frame(width: 26, alignment: .trailing)
        }
    }

    /// 1 pixel at the editor's current pixel-grid ppem, in grid units — the slider's step when
    /// "snap to pixel grid" is on, so the bias always lands exactly on a pixel boundary.
    private var biasStep: Double {
        editor.snapBiasToPixel ? Double(doc.project.gridDivisions) / editor.pixPpem : 0.05
    }
    private var verticalBiasBinding: Binding<Double> {
        Binding(
            get: { doc.project.verticalBias },
            set: { v in doc.mutate("Vertical Bias", undoManager: undoManager) { $0.verticalBias = v } }
        )
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2).foregroundStyle(.tertiary)
            content
        }
    }
}

struct GlyphGridView: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GLYPHS · DOUBLE-CLICK = COMPLETE").font(.caption2).foregroundStyle(.tertiary)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(FontProject.glyphOrder, id: \.self) { scalar in
                    GlyphCell(scalar: scalar, doc: doc, editor: editor)
                }
            }
        }
    }
}

private struct GlyphCell: View {
    let scalar: UInt32
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState

    var glyph: Glyph { doc.project.glyph(for: scalar) }

    var body: some View {
        Text(glyph.label)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(background)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(editor.currentScalar == scalar ? Color.accentColor : .clear, lineWidth: 2))
            .foregroundStyle(foreground)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                doc.mutateGlyph(scalar, undoManager: nil) { $0.complete.toggle() }
            }
            .onTapGesture(count: 1) { editor.selectGlyph(scalar) }
            .help(title)
    }

    private var title: String {
        scalar == Glyph.notdefScalar ? ".notdef (invalid character)" :
        scalar == 0x20 ? "space  U+0020" :
        "\(glyph.label)  U+\(String(format: "%04X", scalar))"
    }
    private var background: Color {
        if glyph.complete { return .green.opacity(0.18) }
        if glyph.isDrawn { return .secondary.opacity(0.12) }
        return .clear
    }
    private var foreground: Color {
        if glyph.complete { return .green }
        if glyph.isDrawn { return .primary }
        return .secondary.opacity(0.6)
    }
}
