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

    /// Nearest point on any segment, for inserting a node in Hint mode.
    func hitSegment(_ px: CGPoint) -> SegmentHit? {
        var best: (hit: SegmentHit, dist: CGFloat)?
        for path in glyph.paths {
            let n = path.nodes
            let count = path.closed ? n.count : n.count - 1
            guard count > 0 else { continue }
            for i in 0..<count {
                let a = n[i], b = n[(i + 1) % n.count]
                let isLine = a.cOut == nil && b.cIn == nil
                let c1 = a.cOut ?? a.p, c2 = b.cIn ?? b.p
                for s in 1..<32 {
                    let t = Double(s) / 32
                    let p = isLine ? GridPoint(a.p.x + (b.p.x - a.p.x) * t, a.p.y + (b.p.y - a.p.y) * t) : SkeletonGeometry.bezier(a.p, c1, c2, b.p, t)
                    let d = dist(toPx(p), px)
                    if d < hitRadius, best == nil || d < best!.dist {
                        best = (SegmentHit(pathID: path.id, index: i, t: t, isLine: isLine), d)
                    }
                }
            }
        }
        return best?.hit
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
