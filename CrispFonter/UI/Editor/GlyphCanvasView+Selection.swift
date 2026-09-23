import AppKit

/// Keyboard node selection, shared by Skeleton/Thicken/Hint mode (Metrics mode cycles guides
/// instead — see GlyphCanvasView+Metrics.swift).
extension GlyphCanvasView {
    private func allNodeRefs() -> [(pathID: UUID, nodeID: UUID)] {
        glyph.paths.flatMap { path in path.nodes.map { (path.id, $0.id) } }
    }

    /// Tab cycles forward through every node in the current glyph, then to "no selection", then
    /// wraps to the first node again; ⇧-Tab reverses. Collapses a multi-selection down to a single
    /// node first — a stroke just finished drawing (or a marquee) leaves every one of its nodes
    /// selected, and Tab/⇧-Tab step off that group one node at a time rather than ignoring it.
    func cycleSelection(backward: Bool) {
        multiSelection = []
        let refs = allNodeRefs()
        guard !refs.isEmpty else { selection = nil; needsDisplay = true; return }
        if let sel = selection, let idx = refs.firstIndex(where: { $0.pathID == sel.pathID && $0.nodeID == sel.nodeID }) {
            let next = backward ? idx - 1 : idx + 1
            selection = (next < 0 || next >= refs.count) ? nil : refs[next]
        } else {
            selection = backward ? refs.last : refs.first
        }
        needsDisplay = true
    }
}
