import AppKit

extension GlyphCanvasView {
    struct NodeHit { var pathID: UUID; var nodeID: UUID; var index: Int }

    func hitNode(_ px: CGPoint) -> NodeHit? {
        for path in glyph.paths {
            for (i, nd) in path.nodes.enumerated() {
                if dist(toPx(nd.p), px) < hitRadius { return NodeHit(pathID: path.id, nodeID: nd.id, index: i) }
            }
        }
        return nil
    }

    struct HandleHit { var pathID: UUID; var nodeID: UUID; var key: HandleKey }

    func hitHandle(_ px: CGPoint) -> HandleHit? {
        for path in glyph.paths {
            for nd in path.nodes {
                if let c = nd.cIn, dist(toPx(c), px) < hitRadius { return HandleHit(pathID: path.id, nodeID: nd.id, key: .cIn) }
                if let c = nd.cOut, dist(toPx(c), px) < hitRadius { return HandleHit(pathID: path.id, nodeID: nd.id, key: .cOut) }
            }
        }
        return nil
    }

    func hitThickness(_ px: CGPoint) -> ThicknessHandle? {
        for path in glyph.paths {
            for th in thicknessHandles(path) where dist(toPx(th.pos), px) < hitRadius { return th }
        }
        return nil
    }

    func hitCap(_ px: CGPoint) -> CapHandle? {
        for path in glyph.paths {
            for ch in capHandles(path) where dist(toPx(ch.pos), px) < hitRadius { return ch }
        }
        return nil
    }

    struct SegmentHit { var pathID: UUID; var index: Int; var t: Double; var isLine: Bool }

    /// Nearest point on any segment, for inserting a node (skeleton double-click, hint-mode click).
    /// Straight segments use an exact point-to-line projection rather than sampling — a fixed
    /// sample count can space samples farther apart than the hit radius on a long line, making a
    /// click in the middle of it miss entirely.
    func hitSegment(_ px: CGPoint) -> SegmentHit? {
        var best: (hit: SegmentHit, dist: CGFloat)?
        func consider(_ pathID: UUID, _ index: Int, _ t: Double, _ isLine: Bool, _ p: GridPoint) {
            let d = dist(toPx(p), px)
            if d < hitRadius, best == nil || d < best!.dist {
                best = (SegmentHit(pathID: pathID, index: index, t: t, isLine: isLine), d)
            }
        }
        for path in glyph.paths {
            let n = path.nodes
            let count = path.closed ? n.count : n.count - 1
            guard count > 0 else { continue }
            for i in 0..<count {
                let a = n[i], b = n[(i + 1) % n.count]
                let isLine = a.cOut == nil && b.cIn == nil
                if isLine {
                    let pa = toPx(a.p), pb = toPx(b.p)
                    let dx = pb.x - pa.x, dy = pb.y - pa.y
                    let lenSq = dx * dx + dy * dy
                    guard lenSq > 1e-6 else { continue }
                    let t = min(max(((px.x - pa.x) * dx + (px.y - pa.y) * dy) / lenSq, 0.02), 0.98)
                    consider(path.id, i, Double(t), true, GridPoint(a.p.x + (b.p.x - a.p.x) * Double(t), a.p.y + (b.p.y - a.p.y) * Double(t)))
                } else {
                    let c1 = a.cOut ?? a.p, c2 = b.cIn ?? b.p
                    for s in 1..<64 {
                        let t = Double(s) / 64
                        consider(path.id, i, t, false, SkeletonGeometry.bezier(a.p, c1, c2, b.p, t))
                    }
                }
            }
        }
        return best?.hit
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
