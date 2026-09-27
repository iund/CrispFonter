import SwiftUI

struct SidebarView: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    var undoManager: UndoManager?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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

                Section("Export") {
                    Toggle("Include hints", isOn: Binding(
                        get: { doc.project.export.includeHints },
                        set: { v in doc.mutate(undoManager: undoManager) { $0.export.includeHints = v } }
                    ))
                    HStack {
                        Text("Hint cut-off")
                        Stepper(value: Binding(
                            get: { doc.project.export.hintCutoffPPEM },
                            set: { v in doc.mutate(undoManager: undoManager) { $0.export.hintCutoffPPEM = v } }
                        ), in: 1...400) {
                            Text("\(doc.project.export.hintCutoffPPEM) ppem")
                        }
                    }
                    Text("Above this size the exported font's prep program switches instructions off.")
                        .font(.caption).foregroundStyle(.secondary)

                    Toggle("Hint side bearings", isOn: Binding(
                        get: { doc.project.export.hintSideBearings },
                        set: { v in doc.mutate(undoManager: undoManager) { $0.export.hintSideBearings = v } }
                    ))
                    .help("Rounds each glyph's leftmost edge to a whole pixel so ink starts at a consistent offset.")

                    Toggle("Suppress overshoot", isOn: Binding(
                        get: { doc.project.export.suppressOvershoot },
                        set: { v in doc.mutate(undoManager: undoManager) { $0.export.suppressOvershoot = v } }
                    ))
                    .help("Snaps a hinted point near a zone flush to it, even with deliberate design overshoot.")

                    Toggle("Hint diagonal stems", isOn: Binding(
                        get: { doc.project.export.hintDiagonalStems },
                        set: { v in doc.mutate(undoManager: undoManager) { $0.export.hintDiagonalStems = v } }
                    ))
                    .help("Grid-fits a diagonal edge's endpoints instead of (mis-)treating it as an axis-aligned stem.")

                    HStack {
                        Text("Stem darken")
                        Slider(value: Binding(
                            get: { doc.project.export.stemDarkenAmount },
                            set: { v in doc.mutate(undoManager: undoManager) { $0.export.stemDarkenAmount = v } }
                        ), in: 0...1, step: 0.1)
                        Text(String(format: "%.1f", doc.project.export.stemDarkenAmount)).monospacedDigit().frame(width: 28)
                    }
                    .help("Bumps thin hinted stems' cvt width — helps grid-fit and ClearType, invisible on macOS (it ignores hint bytecode).")
                }

                GlyphGridView(doc: doc, editor: editor)
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
    @FocusState private var gridFocused: Bool
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 6)
    private static let columnCount = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GLYPHS · DOUBLE-CLICK = COMPLETE").font(.caption2).foregroundStyle(.tertiary)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(FontProject.glyphOrder, id: \.self) { scalar in
                    GlyphCell(scalar: scalar, doc: doc, editor: editor)
                }
            }
        }
        .padding(4)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(gridFocused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 2))
        // One tab stop for the whole grid, rather than one per glyph — once it has focus, arrow
        // keys move the current glyph selection (the accent-colored cell) instead.
        .contentShape(Rectangle())
        .focusable()
        .focused($gridFocused)
        .onKeyPress(.leftArrow) { moveSelection(by: -1) }
        .onKeyPress(.rightArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -Self.columnCount) }
        .onKeyPress(.downArrow) { moveSelection(by: Self.columnCount) }
    }

    /// Sets `currentScalar` directly rather than going through `selectGlyph`, which also hands
    /// keyboard focus to the canvas — that would end arrow-key navigation after a single step.
    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard let idx = FontProject.glyphOrder.firstIndex(of: editor.currentScalar) else { return .ignored }
        let newIdx = idx + delta
        guard FontProject.glyphOrder.indices.contains(newIdx) else { return .handled }
        editor.currentScalar = FontProject.glyphOrder[newIdx]
        return .handled
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
