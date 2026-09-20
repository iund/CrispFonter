import SwiftUI

struct GlyphCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var doc: ProjectDocument
    @ObservedObject var editor: EditorState

    func makeNSView(context: Context) -> GlyphCanvasView {
        let view = GlyphCanvasView()
        view.doc = doc
        view.editor = editor
        return view
    }

    func updateNSView(_ view: GlyphCanvasView, context: Context) {
        view.doc = doc
        view.editor = editor
        view.needsDisplay = true
    }
}
