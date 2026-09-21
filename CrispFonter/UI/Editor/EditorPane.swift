import SwiftUI

struct EditorPane: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    var undoManager: UndoManager?

    var body: some View {
        VStack(spacing: 0) {
            if editor.mode == .hint {
                HintBar(doc: doc, editor: editor, undoManager: undoManager)
                Divider()
            }
            GlyphCanvasRepresentable(doc: doc, editor: editor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            StatusBar(doc: doc, editor: editor)
        }
    }
}

private struct HintBar: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    var undoManager: UndoManager?

    var body: some View {
        HStack {
            Button("Auto-detect hint points") { autoDetect() }
            Button("Remove all") {
                doc.mutateGlyph(editor.currentScalar, "Remove Hints", undoManager: undoManager) { $0.hints = [:] }
                editor.hintMessage = "Hints removed — \u{2318}Z to undo"
            }
            Spacer()
            Text(editor.hintMessage).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func autoDetect() {
        var count = 0
        doc.mutateGlyph(editor.currentScalar, "Auto-detect Hints", undoManager: undoManager) { g in count = Hinting.autoDetect(&g) }
        editor.hintMessage = "\(count) hint point\(count == 1 ? "" : "s") assigned — \u{2318}Z to undo"
    }
}

private struct StatusBar: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState

    /// Derived straight from the document on every render — no imperative state to keep in sync,
    /// so there's nothing here that can publish a change while SwiftUI is mid-update.
    private var pathInfoText: String {
        let g = doc.project.glyph(for: editor.currentScalar)
        let nodeCount = g.paths.reduce(0) { $0 + $1.nodes.count }
        let hints = g.hints.count
        return "\(g.paths.count) path\(g.paths.count == 1 ? "" : "s") · \(nodeCount) nodes · \(hints) hint point\(hints == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(spacing: 14) {
            Toggle("Fill", isOn: $editor.showFill)
            Toggle("Skeleton", isOn: $editor.showSkel)
            HStack(spacing: 4) {
                Toggle("Pixel grid at", isOn: $editor.showPix)
                Slider(value: $editor.pixPpem, in: 6...18, step: 0.5).frame(width: 90)
                Text("\(editor.pixPpem, specifier: "%.1f") pt").monospacedDigit()
            }
            Spacer()
            Text(editor.cursorPosText).foregroundStyle(.secondary)
            Text(pathInfoText).foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .font(.caption)
    }
}
