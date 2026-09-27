import SwiftUI
import AppKit

struct EditorPane: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    var undoManager: UndoManager?

    /// The AppKit-backed canvas is a layer-backed `NSView` composited into the SwiftUI hierarchy
    /// via `NSViewRepresentable`; declared as a plain VStack sibling, its layer could end up
    /// compositing above the neighboring bars, leaving their text/controls invisible even though
    /// they were still there (tab-focusable, just not painted). Filling the whole pane with the
    /// canvas first and layering the bars on top in a ZStack — each with an explicitly opaque
    /// background — guarantees they draw after (and above) it.
    var body: some View {
        ZStack(alignment: .top) {
            GlyphCanvasRepresentable(doc: doc, editor: editor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                ExportFieldsBar(doc: doc, undoManager: undoManager)
                    .background(Color(nsColor: .windowBackgroundColor))
                Divider()
                // Always present (with a fixed-height row) rather than only in Hint mode, so the
                // canvas below sits at the same vertical position and size in every mode —
                // otherwise Hint mode's extra toolbar row pushed the glyph view out of alignment
                // with Metrics/Draw.
                HintBar(doc: doc, editor: editor, undoManager: undoManager)
                    .background(Color(nsColor: .windowBackgroundColor))
                Divider()
                Spacer(minLength: 0)
                Divider()
                StatusBar(doc: doc, editor: editor)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Font name/style/monospace — moved here from the old export sheet, since they're really glyph-
/// canvas-adjacent metadata you set once and forget, not a per-export dialog. "Export…" (in the
/// toolbar) goes straight to a standard save panel using whatever's set here; "Preview" instead
/// does a throwaway export straight to Font Book, for a quick real-world look without saving anywhere.
private struct ExportFieldsBar: View {
    @ObservedObject var doc: ProjectDocument
    var undoManager: UndoManager?
    private let stylePresets = ["Light", "Regular", "Bold"]

    var body: some View {
        HStack(spacing: 8) {
            TextField("Font name", text: Binding(
                get: { doc.project.export.familyName },
                set: { v in doc.mutate(undoManager: undoManager) { $0.export.familyName = v } }
            ))
            .frame(width: 150)

            HStack(spacing: 4) {
                TextField("Style", text: Binding(
                    get: { doc.project.export.styleName },
                    set: { v in doc.mutate(undoManager: undoManager) { $0.export.styleName = v } }
                ))
                .frame(width: 80)
                // Default (bordered) Menu style, not `.borderlessButton` — that rendered with no
                // visible chrome at all here, just an SF Symbol with nothing marking it clickable.
                Menu {
                    ForEach(stylePresets, id: \.self) { preset in
                        Button(preset) { doc.mutate(undoManager: undoManager) { $0.export.styleName = preset } }
                    }
                } label: { Image(systemName: "chevron.down") }
                .frame(width: 28)
            }

            Toggle("Monospace", isOn: Binding(
                get: { doc.project.export.monospace },
                set: { v in doc.mutate(undoManager: undoManager) { $0.export.monospace = v } }
            ))
            Toggle("Simplify paths", isOn: Binding(
                get: { doc.project.export.simplifyPaths },
                set: { v in doc.mutate(undoManager: undoManager) { $0.export.simplifyPaths = v } }
            ))
            .help("Thin redundant points from curve-flattened outlines on export — mainly helps non-straight open-stroke end caps")

            Spacer()

            Button("Preview") { preview() }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minHeight: 28)
    }

    /// A quick, throwaway export straight to a temp file, opened in whatever app handles .ttf
    /// (Font Book, by default on a stock Mac) — no save panel, nothing kept around deliberately.
    private func preview() {
        let data = TrueTypeWriter.write(project: doc.project)
        let base = "\(doc.project.export.familyName)-\(doc.project.export.styleName)"
            .replacingOccurrences(of: " ", with: "")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(base).ttf")
        do {
            try data.write(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            CrashLogger.breadcrumb("preview export failed: \(error)")
            NSAlert(error: error).runModal()
        }
    }
}

private struct HintBar: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    var undoManager: UndoManager?

    var body: some View {
        HStack {
            if editor.mode == .hint {
                Button("Auto-detect hint points") { autoDetect() }
                Button("Remove all") {
                    doc.mutateGlyph(editor.currentScalar, "Remove Hints", undoManager: undoManager) { $0.hints = [:] }
                    editor.hintMessage = "Hints removed — \u{2318}Z to undo"
                }
                Spacer()
                Text(editor.hintMessage).font(.caption).foregroundStyle(.secondary)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minHeight: 28)
    }

    /// Holding ⌥ while clicking uses round-outward instead of round-nearest, same as every other
    /// "nearest"-setting hint action.
    private func autoDetect() {
        var count = 0
        let mode: SnapMode = NSEvent.modifierFlags.contains(.option) ? .outward : .nearest
        doc.mutateGlyph(editor.currentScalar, "Auto-detect Hints", undoManager: undoManager) { g in count = Hinting.autoDetect(&g, mode: mode) }
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
            Toggle("Skeleton", isOn: $editor.showSkel)
            Toggle("Reference (⌃Space)", isOn: $editor.showReferenceGlyph)
            HStack(spacing: 4) {
                Toggle("Pixel grid at", isOn: $editor.showPix)
                Text("\(editor.pixPpem, specifier: "%.1f") pt").monospacedDigit()
            }
            ColorPicker("Fill color", selection: $editor.fillColor, supportsOpacity: false)
            Toggle("Fill", isOn: $editor.showFill)
            Spacer()
            Text(editor.cursorPosText).foregroundStyle(.secondary)
            Text(pathInfoText).foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .font(.caption)
    }
}
