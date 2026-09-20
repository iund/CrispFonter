import AppKit

extension GlyphCanvasView {
    enum HandleKey { case cIn, cOut }
    enum Side { case left, right }

    enum Drag {
        case pen(pathID: UUID, nodeID: UUID, start: GridPoint)
        case moveNode(pathID: UUID, nodeID: UUID)
        case handle(pathID: UUID, nodeID: UUID, key: HandleKey, alt: Bool)
        case thickness(pathID: UUID, nodeID: UUID, side: Side, dir: GridPoint, both: Bool)
        case angle(pathID: UUID, nodeID: UUID, dir0: GridPoint)
        case cap(pathID: UUID, nodeID: UUID, out: GridPoint)
        case hint(pathID: UUID, nodeID: UUID, index: Int, start: CGPoint, was: HintPoint?, inserted: Bool, moved: Bool)
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

    /// Cap handles sit on the outward tangent of each open-path end.
    struct CapHandle { var pathID: UUID; var node: Node; var out: GridPoint; var pos: GridPoint }

    func capHandles(_ path: SkeletonPath) -> [CapHandle] {
        guard !path.closed, path.nodes.count >= 2 else { return [] }
        var res: [CapHandle] = []
        let n = path.nodes
        for (i, sign) in [(0, -1.0), (n.count - 1, 1.0)] {
            let t = Hinting.tangentAt(path, i)
            let out = GridPoint(t.x * sign, t.y * sign).rotated(degrees: n[i].angle)
            res.append(CapHandle(pathID: path.id, node: n[i], out: out, pos: GridPoint(n[i].p.x + out.x * n[i].cap, n[i].p.y + out.y * n[i].cap)))
        }
        return res
    }
}
