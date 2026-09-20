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
            EditorPane(doc: doc, editor: editor, undoManager: undoManager)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            RightPanelView(doc: doc, editor: editor)
                .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Mode", selection: Binding(get: { editor.mode }, set: { editor.setMode($0) })) {
                    Text("Skeleton").tag(EditorMode.skeleton)
                    Text("Thicken").tag(EditorMode.thicken)
                    Text("Hint").tag(EditorMode.hint)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

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
