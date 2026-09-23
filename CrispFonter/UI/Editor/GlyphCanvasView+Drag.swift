import AppKit

extension GlyphCanvasView {
    enum HandleKey { case cIn, cOut }
    typealias Side = ThicknessSide

    /// A draggable metric line in Metrics mode: the four horizontal guides, or the advance-width
    /// (right sidebearing) vertical. The left sidebearing and baseline are fixed reference points,
    /// not adjustable.
    enum MetricsGuide: CaseIterable { case ascender, capHeight, xHeight, descender, advance }

    enum Drag {
        case pen(pathID: UUID, nodeID: UUID, start: GridPoint)
        case moveNode(pathID: UUID, nodeID: UUID)
        case handle(pathID: UUID, nodeID: UUID, key: HandleKey, alt: Bool)
        /// Dragging a fill-boundary point (outer/left or inner/right) straight to the cursor.
        case fillHandle(pathID: UUID, nodeID: UUID, side: Side)
        /// ⌃-drag a node itself: on release, either anchors it to whichever fill handle it's
        /// dropped on, or (dropped elsewhere) moves it plainly and clears any existing anchor.
        case anchorNode(pathID: UUID, nodeID: UUID)
        case hint(pathID: UUID, nodeID: UUID, index: Int, start: CGPoint, was: HintPoint?, inserted: Bool, moved: Bool)
        case metric(MetricsGuide)
        /// A drag from empty space in Combo mode: a selection rectangle, in view pixels. `additive`
        /// (⌘ held) adds to the existing selection instead of replacing it.
        case marquee(start: CGPoint, additive: Bool)
        /// A right-click (real right button, or ⌃-click as the traditional substitute) that isn't
        /// on a node/fill handle: drag becomes a (replacing) marquee select; a plain click-and-
        /// release instead copies the selection (then deselects) or, with nothing selected, pastes
        /// near the pointer.
        case rightClick(start: CGPoint)
    }

    /// The two fill-handle positions for a node: left (outer) and right (inner).
    struct ThicknessHandle { var pathID: UUID; var node: Node; var side: Side; var pos: GridPoint }

    func thicknessHandles(_ path: SkeletonPath) -> [ThicknessHandle] {
        // A single-node path draws as a dot (see `SkeletonGeometry.dotRadius`) — both handles are
        // still offered, sitting on opposite sides of the node; either one's distance from the
        // node sets the dot's radius (outer wins if both happen to be set).
        var res: [ThicknessHandle] = []
        func pos(_ nd: Node, _ i: Int, _ side: Side) -> GridPoint {
            SkeletonGeometry.fillPoint(of: nd, path: path, index: i, side: side, weight: weight).point
        }
        for (i, nd) in path.nodes.enumerated() {
            res.append(ThicknessHandle(pathID: path.id, node: nd, side: .left, pos: pos(nd, i, .left)))
            res.append(ThicknessHandle(pathID: path.id, node: nd, side: .right, pos: pos(nd, i, .right)))
        }
        return res
    }
}
