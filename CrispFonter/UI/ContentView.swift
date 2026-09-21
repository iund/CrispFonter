import SwiftUI

struct ContentView: View {
    @ObservedObject var doc: ProjectDocument
    @StateObject private var editor = EditorState()
    @Environment(\.undoManager) private var undoManager
    @State private var showExport = false

    var body: some View {
        HSplitView {
            SidebarView(doc: doc, editor: editor, undoManager: undoManager)
                .frame(minWidth: 190, idealWidth: 200, maxWidth: 260)
                .focusable()
            EditorPane(doc: doc, editor: editor, undoManager: undoManager)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            RightPanelView(doc: doc, editor: editor)
                .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
                .focusable()
        }
        .background(GlobalShortcuts(doc: doc, editor: editor, undoManager: undoManager))
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: Binding(get: { editor.mode }, set: { editor.setMode($0) })) {
                    Text("Metrics").tag(EditorMode.metrics)
                    Text("Skeleton").tag(EditorMode.skeleton)
                    Text("Thicken").tag(EditorMode.thicken)
                    Text("Hint").tag(EditorMode.hint)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                HStack(spacing: 4) {
                    Text("Weight")
                    Slider(value: Binding(
                        get: { doc.project.defaultWeight },
                        set: { v in doc.mutate("Weight", undoManager: undoManager) { $0.defaultWeight = v } }
                    ), in: 0.5...4, step: 0.25)
                    .frame(width: 100)
                    Text(String(format: "%.2f", doc.project.defaultWeight)).monospacedDigit().frame(width: 34)
                }

                Text("Grid \(doc.project.gridDivisions)/em").foregroundStyle(.secondary)

                Toggle("½-grid snap", isOn: $editor.halfSnap)

                Button("Undo") { undoManager?.undo() }
                Button("Clear glyph") {
                    doc.mutateGlyph(editor.currentScalar, "Clear Glyph", undoManager: undoManager) { g in
                        g.paths = []; g.hints = [:]
                    }
                }
                Button("Export…") { showExport = true }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheetView(doc: doc)
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
            Button("") { setModeAndFocus(.skeleton) }.keyboardShortcut("2", modifiers: .command)
            Button("") { setModeAndFocus(.thicken) }.keyboardShortcut("3", modifiers: .command)
            Button("") { setModeAndFocus(.hint) }.keyboardShortcut("4", modifiers: .command)
            Button("") { adjustWeight(0.25) }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("") { adjustWeight(-0.25) }.keyboardShortcut(.downArrow, modifiers: .command)
            Button("") { adjustPixelGrid(0.5) }.keyboardShortcut(.rightArrow, modifiers: .command)
            Button("") { adjustPixelGrid(-0.5) }.keyboardShortcut(.leftArrow, modifiers: .command)
            Button("") { editor.canvasView?.zoomToFit() }.keyboardShortcut("0", modifiers: .command)
            Button("") { editor.canvasView?.zoomBy(1.25) }.keyboardShortcut("=", modifiers: .command)
            Button("") { editor.canvasView?.zoomBy(0.8) }.keyboardShortcut("-", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    /// ⌘1–4 switch the tool, then hand keyboard focus straight to the canvas — otherwise the
    /// mode's own shortcuts (space, arrows, etc.) go nowhere until the user clicks it first.
    private func setModeAndFocus(_ m: EditorMode) {
        editor.setMode(m)
        if let canvas = editor.canvasView { canvas.window?.makeFirstResponder(canvas) }
    }

    private func adjustWeight(_ delta: Double) {
        let v = min(4, max(0.5, doc.project.defaultWeight + delta))
        doc.mutate("Weight", undoManager: undoManager) { $0.defaultWeight = v }
    }

    private func adjustPixelGrid(_ delta: Double) {
        editor.pixPpem = min(18, max(6, editor.pixPpem + delta))
    }
}
