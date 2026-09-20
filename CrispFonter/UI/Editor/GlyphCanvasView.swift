import AppKit

/// The one custom view in the app: the glyph editor canvas. Pen tool (skeleton), thickness/cap
/// handles (thicken), and hint points (hint). Port of the prototype's canvas interaction code.
final class GlyphCanvasView: NSView {
    var doc: ProjectDocument!
    var editor: EditorState!

    /// A path currently being drawn (persists across the multiple click gestures of the pen tool).
    var drawingPathID: UUID?
    /// Selected node, for delete / skeleton highlighting.
    var selection: (pathID: UUID, nodeID: UUID)?
    var hover: GridPoint?
    var drag: Drag?
    /// Uncommitted edits for the in-progress gesture; committed to `doc` on mouseUp.
    var working: Glyph?

    var cell: CGFloat = 30
    var originX: CGFloat = 0
    var originY: CGFloat = 0
    let hitRadius: CGFloat = 8

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Glyph access

    var glyph: Glyph { working ?? doc.project.glyph(for: editor.currentScalar) }
    var weight: Double { doc.project.defaultWeight }

    func mutateWorking(_ body: (inout Glyph) -> Void) {
        var g = working ?? doc.project.glyph(for: editor.currentScalar)
        body(&g)
        working = g
        needsDisplay = true
    }

    func commit(_ actionName: String) {
        guard let g = working else { return }
        working = nil
        doc.mutateGlyph(editor.currentScalar, actionName, undoManager: undoManager) { $0 = g }
    }

    // MARK: - Layout / transform

    override func layout() {
        super.layout()
        updateTransform()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self))
    }

    func updateTransform() {
        guard doc != nil else { return }
        let m = doc.project.metrics
        let spanY = CGFloat(m.ascender - m.descender) + 4
        let spanX = CGFloat(doc.project.advance(of: glyph)) + 6
        let w = bounds.width, h = bounds.height
        cell = max(10, min((h - 20) / max(spanY, 1), (w - 20) / max(spanX, 1)))
        originX = ((w - CGFloat(doc.project.advance(of: glyph)) * cell) / 2).rounded()
        originY = (h / 2 + CGFloat(m.ascender + m.descender) / 2 * cell).rounded()
    }

    func toPx(_ p: GridPoint) -> CGPoint { CGPoint(x: originX + CGFloat(p.x) * cell, y: originY - CGFloat(p.y) * cell) }
    func toGrid(_ px: CGPoint) -> GridPoint { GridPoint(Double((px.x - originX) / cell), Double((originY - px.y) / cell)) }
    func snap(_ p: GridPoint, fine: Bool) -> GridPoint {
        let q: Double = fine || editor.halfSnap ? 2 : 1
        return GridPoint((p.x * q).rounded() / q, (p.y * q).rounded() / q)
    }
}
