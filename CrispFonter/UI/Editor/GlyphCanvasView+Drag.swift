import AppKit

extension GlyphCanvasView {
    enum HandleKey { case cIn, cOut }
    enum Side { case left, right }

    /// A draggable metric line in Metrics mode: the four horizontal guides, or the advance-width
    /// (right sidebearing) vertical. The left sidebearing and baseline are fixed reference points,
    /// not adjustable.
    enum MetricsGuide: CaseIterable { case ascender, capHeight, xHeight, descender, advance }

    enum Drag {
        case pen(pathID: UUID, nodeID: UUID, start: GridPoint)
        case moveNode(pathID: UUID, nodeID: UUID)
        case handle(pathID: UUID, nodeID: UUID, key: HandleKey, alt: Bool)
        case thickness(pathID: UUID, nodeID: UUID, side: Side, dir: GridPoint, both: Bool)
        case angle(pathID: UUID, nodeID: UUID, dir0: GridPoint)
        case cap(pathID: UUID, nodeID: UUID, dir0: GridPoint)
        case hint(pathID: UUID, nodeID: UUID, index: Int, start: CGPoint, was: HintPoint?, inserted: Bool, moved: Bool)
        case metric(MetricsGuide)
        /// ⇧-drag from empty space in Skeleton mode: a selection rectangle, in view pixels.
        case marquee(start: CGPoint)
    }

    /// The two thickness handle positions for a node: left and right of its cross-section.
    struct ThicknessHandle { var pathID: UUID; var node: Node; var side: Side; var pos: GridPoint; var dir: GridPoint; var dir0: GridPoint }

    func thicknessHandles(_ path: SkeletonPath) -> [ThicknessHandle] {
        var res: [ThicknessHandle] = []
        for (i, nd) in path.nodes.enumerated() {
            let t = Hinting.tangentAt(path, i)
            let left0 = GridPoint(-t.y, t.x)
            let left = left0.rotated(degrees: nd.angle)
            let hl = SkeletonGeometry.halfL(nd, weight: weight), hr = SkeletonGeometry.halfR(nd, weight: weight)
            res.append(ThicknessHandle(pathID: path.id, node: nd, side: .left,
                pos: GridPoint(nd.p.x + left.x * hl, nd.p.y + left.y * hl), dir: left, dir0: left0))
            res.append(ThicknessHandle(pathID: path.id, node: nd, side: .right,
                pos: GridPoint(nd.p.x - left.x * hr, nd.p.y - left.y * hr), dir: GridPoint(-left.x, -left.y), dir0: GridPoint(-left0.x, -left0.y)))
        }
        return res
    }

    /// Cap handles sit at the *visual* tip of an open-path end — the midpoint of its cross-section
    /// edges, pushed out by `cap` — not at the skeleton node. Anchoring it at the node (as the
    /// original spec's formula does, `node + tangent×cap`) leaves the handle buried inside the
    /// stroke's fill whenever `cap` is small relative to the weight, disconnected from where the
    /// stroke actually appears to end. `dir0` is the *un*rotated outward tangent — the reference
    /// direction a drag's angle is measured against, the same way a thickness handle's `dir0` works.
    struct CapHandle { var pathID: UUID; var node: Node; var out: GridPoint; var dir0: GridPoint; var pos: GridPoint }

    /// The midpoint between a node's left/right cross-section edges — the center of the stroke at
    /// that point, which for an end node is the base the cap handle sits out from.
    func capAnchor(_ path: SkeletonPath, _ index: Int) -> GridPoint {
        let (e1, e2) = Hinting.edgesAt(path, index, weight: weight)
        return GridPoint((e1.x + e2.x) / 2, (e1.y + e2.y) / 2)
    }

    func capHandles(_ path: SkeletonPath) -> [CapHandle] {
        guard !path.closed, path.nodes.count >= 2 else { return [] }
        var res: [CapHandle] = []
        let n = path.nodes
        for (i, sign) in [(0, -1.0), (n.count - 1, 1.0)] {
            let t = Hinting.tangentAt(path, i)
            let dir0 = GridPoint(t.x * sign, t.y * sign)
            let out = dir0.rotated(degrees: n[i].angle)
            let anchor = capAnchor(path, i)
            res.append(CapHandle(pathID: path.id, node: n[i], out: out, dir0: dir0, pos: GridPoint(anchor.x + out.x * n[i].cap, anchor.y + out.y * n[i].cap)))
        }
        return res
    }
}
