import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var doc: ProjectDocument
    @StateObject private var editor = EditorState()
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HSplitView {
            SidebarView(doc: doc, editor: editor, undoManager: undoManager)
                .frame(minWidth: 190, idealWidth: 200, maxWidth: 260)
                .focusable()
            EditorPane(doc: doc, editor: editor, undoManager: undoManager)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            RightPanelView(doc: doc, editor: editor)
                .frame(minWidth: 340, idealWidth: 400, maxWidth: .infinity)
                .focusable()
        }
        .background(GlobalShortcuts(doc: doc, editor: editor, undoManager: undoManager))
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: Binding(get: { editor.mode }, set: { editor.setMode($0) })) {
                    Text("Metrics").tag(EditorMode.metrics)
                    Text("Draw").tag(EditorMode.combo)
                    Text("Hint").tag(EditorMode.hint)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                HStack(spacing: 2) {
                    Button { undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .help("Undo (⌘Z)")
                    Button { undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .help("Redo (⇧⌘Z)")
                    Button { editor.canvasView?.cutSelection() } label: { Image(systemName: "scissors") }
                        .help("Cut selected node(s) (⌘X)")
                    Button { editor.canvasView?.copySelection() } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy selected node(s) (⌘C)")
                    Button { editor.canvasView?.pasteSelection() } label: { Image(systemName: "doc.on.clipboard") }
                        .help("Paste (⌘V)")
                }

                HStack(spacing: 2) {
                    Button { editor.canvasView?.transformSelection(.rotateCCW) } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }.help("Rotate selected node(s) 90° counterclockwise (⌥,)")
                    Button { editor.canvasView?.transformSelection(.rotateCW) } label: {
                        Image(systemName: "arrow.clockwise")
                    }.help("Rotate selected node(s) 90° clockwise (⌥.)")
                    Button { editor.canvasView?.transformSelection(.flipHorizontal) } label: {
                        Image(systemName: "flip.horizontal")
                    }.help("Flip selected node(s) horizontally (⌥;)")
                    Button { editor.canvasView?.transformSelection(.flipVertical) } label: {
                        Image(systemName: "flip.horizontal").rotationEffect(.degrees(90))
                    }.help("Flip selected node(s) vertically (⌥')")
                }

                HStack(spacing: 4) {
                    Text("Weight")
                    Slider(value: Binding(
                        get: { doc.project.defaultWeight },
                        set: { v in doc.mutate("Weight", undoManager: undoManager) { $0.defaultWeight = v } }
                    ), in: 0.5...4, step: 0.25)
                    .frame(width: 100)
                    Text(String(format: "%.2f", doc.project.defaultWeight)).monospacedDigit().frame(width: 34)
                }

                HStack(spacing: 4) {
                    Text("Grid")
                    Slider(value: Binding(
                        get: { Double(doc.project.gridDivisions) },
                        set: { v in doc.mutate("Grid Divisions", undoManager: undoManager) { $0.gridDivisions = Int(v.rounded()) } }
                    ), in: 2...32, step: 1)
                    .frame(width: 90)
                    Text("\(doc.project.gridDivisions)/em").monospacedDigit().frame(width: 46)
                }

                HStack(spacing: 4) {
                    Text("Snap")
                    // Slider runs 32nd (finest, left) to whole (coarsest, right) — shown as its
                    // plain denominator (32 16 8 4 2 1), not a fraction, per the layout it steps
                    // through. ⌘,/⌘. (below) step it one notch at a time without touching the mouse.
                    Slider(value: Binding(
                        get: { Double(editor.snapStepIndex) },
                        set: { v in editor.snapStepIndex = Int(v.rounded()) }
                    ), in: 0...Double(EditorState.snapDenominators.count - 1), step: 1)
                    .frame(width: 90)
                    Text("\(editor.snapDenominator)").monospacedDigit().frame(width: 24)
                }

                Button {
                    doc.mutateGlyph(editor.currentScalar, "Clear Glyph", undoManager: undoManager) { g in
                        g.paths = []; g.hints = [:]
                    }
                } label: { Image(systemName: "trash") }
                    .help("Clear glyph")
                Button { exportToFile() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Export…")
            }
        }
    }

    /// Font name/style/monospace live at the top of the canvas now (`EditorPane`'s
    /// `ExportFieldsBar`) — this just goes straight to the standard save panel with them already set.
    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ttf") ?? .data]
        panel.nameFieldStringValue = "\(doc.project.export.familyName)-\(doc.project.export.styleName).ttf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        CrashLogger.breadcrumb("export start: \(doc.project.glyphs.count) glyphs, includeHints=\(doc.project.export.includeHints)")
        let data = TrueTypeWriter.write(project: doc.project)
        CrashLogger.breadcrumb("export TrueTypeWriter.write done: \(data.count) bytes")
        do {
            try data.write(to: url)
            CrashLogger.breadcrumb("export write to disk done")
        } catch {
            CrashLogger.breadcrumb("export write to disk failed: \(error)")
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

/// Window-wide keyboard shortcuts that don't need the canvas focused: mode switching, weight, and
/// pixel-grid size. Implemented as invisible buttons because SwiftUI keyboard shortcuts on a
/// `Button` are handled window-wide via `performKeyEquivalent`, ahead of a focused NSView's plain
/// `keyDown` — unlike the per-mode editing shortcuts, which only make sense (and are only
/// implemented) while the canvas itself has focus. (Pane-to-pane focus cycling isn't handled here:
/// ⌃Tab already does it, via AppKit's standard key-view loop.)
private struct GlobalShortcuts: View {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState
    var undoManager: UndoManager?

    var body: some View {
        Group {
            Button("") { setModeAndFocus(.metrics) }.keyboardShortcut("1", modifiers: .command)
            Button("") { setModeAndFocus(.combo) }.keyboardShortcut("2", modifiers: .command)
            Button("") { setModeAndFocus(.hint) }.keyboardShortcut("3", modifiers: .command)
            // Fn+arrow: on real keyboards Fn+Left/Right/Up/Down is intercepted by macOS itself and
            // delivered as Home/End/Page Up/Page Down — not as an arrow keyCode with a "function"
            // modifier flag — so that's what's bound here, not literal Fn+arrow.
            Button("") { adjustWeight(0.25) }.keyboardShortcut(.pageUp, modifiers: [])
            Button("") { adjustWeight(-0.25) }.keyboardShortcut(.pageDown, modifiers: [])
            Button("") { adjustPixelGrid(0.5) }.keyboardShortcut(.end, modifiers: [])
            Button("") { adjustPixelGrid(-0.5) }.keyboardShortcut(.home, modifiers: [])
            // ⌘, steps the snap slider left (finer, toward 32nd); ⌘. steps it right (coarser,
            // toward whole) — matching the slider's own left-to-right layout.
            Button("") { adjustSnap(-1) }.keyboardShortcut(",", modifiers: .command)
            Button("") { adjustSnap(1) }.keyboardShortcut(".", modifiers: .command)
            Button("") { editor.canvasView?.zoomToFit() }.keyboardShortcut("0", modifiers: .command)
            Button("") { editor.canvasView?.zoomBy(1.25) }.keyboardShortcut("=", modifiers: .command)
            Button("") { editor.canvasView?.zoomBy(0.8) }.keyboardShortcut("-", modifiers: .command)
            Button("") { toggleGlyphComplete() }.keyboardShortcut(.return, modifiers: .shift)
            // ⌥Tab/⇧⌥Tab (cycle editor modes) is NOT bound here — Tab's key equivalent doesn't
            // reliably intercept before the canvas's own keyDown (see GlyphCanvasView+Mouse.swift,
            // where it's actually handled), unlike every other shortcut in this list.
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    /// ⌘1–3 switch the tool, then hand keyboard focus straight to the canvas — otherwise the
    /// mode's own shortcuts (space, arrows, etc.) go nowhere until the user clicks it first.
    private func setModeAndFocus(_ m: EditorMode) {
        editor.setMode(m)
        if let canvas = editor.canvasView { canvas.window?.makeFirstResponder(canvas) }
    }

    private func toggleGlyphComplete() {
        doc.mutateGlyph(editor.currentScalar, "Toggle Complete", undoManager: undoManager) { $0.complete.toggle() }
    }

    private func adjustWeight(_ delta: Double) {
        let v = min(4, max(0.5, doc.project.defaultWeight + delta))
        doc.mutate("Weight", undoManager: undoManager) { $0.defaultWeight = v }
    }

    private func adjustPixelGrid(_ delta: Double) {
        editor.pixPpem = min(18, max(6, editor.pixPpem + delta))
    }

    private func adjustSnap(_ delta: Int) {
        editor.snapStepIndex = min(EditorState.snapDenominators.count - 1, max(0, editor.snapStepIndex + delta))
    }
}
