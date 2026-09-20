import Foundation

/// Port of the prototype's `flatten` / `offsetSide` / `capPoints` / `outline` functions.
/// All geometry here is in grid units, y up. See the build spec §5.
enum SkeletonGeometry {

    /// A flattened sample point on a skeleton path, with the interpolated half-widths and angle.
    /// `nodeID` is set only when this sample sits exactly on a skeleton node (not an in-between
    /// curve sample) — the TrueType hint compiler uses it to find a node's outline points.
    struct Sample {
        var p: GridPoint
        var halfL: Double
        var halfR: Double
        var angle: Double
        var nodeID: UUID?
    }

    enum Side { case left, right }
    /// Which skeleton node (and which offset side) produced an outline point.
    struct PointTag { var nodeID: UUID; var side: Side }

    static func halfL(_ n: Node, weight: Double) -> Double { (n.left ?? 1) * weight / 2 }
    static func halfR(_ n: Node, weight: Double) -> Double { (n.right ?? 1) * weight / 2 }

    static func bezier(_ p0: GridPoint, _ p1: GridPoint, _ p2: GridPoint, _ p3: GridPoint, _ t: Double) -> GridPoint {
        let mt = 1 - t
        let x = mt*mt*mt*p0.x + 3*mt*mt*t*p1.x + 3*mt*t*t*p2.x + t*t*t*p3.x
        let y = mt*mt*mt*p0.y + 3*mt*mt*t*p1.y + 3*mt*t*t*p2.y + t*t*t*p3.y
        return GridPoint(x, y)
    }

    /// Flatten a path to samples: lines -> 2 samples, cubics -> 25 samples (t = 0...1 in 24 steps).
    /// halfL/halfR/angle are linearly interpolated between the segment's end nodes.
    static func flatten(_ path: SkeletonPath, weight: Double) -> [Sample] {
        let n = path.nodes
        guard n.count >= 2 else { return [] }
        let count = path.closed ? n.count : n.count - 1
        var out: [Sample] = []
        for i in 0..<count {
            let a = n[i], b = n[(i + 1) % n.count]
            let isLine = a.cOut == nil && b.cIn == nil
            let steps = isLine ? 1 : 24
            let c1 = a.cOut ?? a.p, c2 = b.cIn ?? b.p
            let sStart = i == 0 ? 0 : 1
            for s in sStart...steps {
                let t = Double(s) / Double(steps)
                let p = isLine ? GridPoint(a.p.x + (b.p.x - a.p.x) * t, a.p.y + (b.p.y - a.p.y) * t) : bezier(a.p, c1, c2, b.p, t)
                let hl = halfL(a, weight: weight) + (halfL(b, weight: weight) - halfL(a, weight: weight)) * t
                let hr = halfR(a, weight: weight) + (halfR(b, weight: weight) - halfR(a, weight: weight)) * t
                let ang = a.angle + (b.angle - a.angle) * t
                let nodeID: UUID? = (i == 0 && s == 0) ? a.id : (s == steps ? b.id : nil)
                out.append(Sample(p: p, halfL: hl, halfR: hr, angle: ang, nodeID: nodeID))
            }
        }
        if path.closed && out.count > 1 { out.removeLast() }
        return out
    }

    /// Offset a flattened polyline on one side. `side`: +1 = left, -1 = right.
    static func offsetSide(_ pts: [Sample], closed: Bool, side: Double) -> [GridPoint] {
        let N = pts.count
        guard N > 0 else { return [] }
        var res: [GridPoint] = []
        func dir(_ i: Int) -> GridPoint {
            let a = pts[i].p, b = pts[(i + 1) % N].p
            return GridPoint(b.x - a.x, b.y - a.y).normalized
        }
        for i in 0..<N {
            let d = side > 0 ? pts[i].halfL : pts[i].halfR
            var n1: GridPoint? = nil, n2: GridPoint? = nil
            if closed || i > 0 {
                let t = dir((i - 1 + N) % N)
                n1 = GridPoint(-t.y * side, t.x * side)
            }
            if closed || i < N - 1 {
                let t = dir(i)
                n2 = GridPoint(-t.y * side, t.x * side)
            }
            if n1 == nil { n1 = n2 }
            if n2 == nil { n2 = n1 }
            guard let nn1 = n1, let nn2 = n2 else { res.append(pts[i].p); continue }
            var m = GridPoint(nn1.x + nn2.x, nn1.y + nn2.y)
            let ml = m.length
            var scale: Double
            if ml < 1e-6 { m = nn2; scale = 1 } else {
                m = m.normalized
                scale = min(1 / max(0.2, m.dot(nn1)), 3)
            }
            if pts[i].angle != 0 { m = m.rotated(degrees: pts[i].angle) }
            res.append(GridPoint(pts[i].p.x + m.x * d * scale, pts[i].p.y + m.y * d * scale))
        }
        return res
    }

    /// Cap from edge point A to edge point B, bulging `ext` grid units along dirOut (0 = flat, no extra points).
    static func capPoints(_ A: GridPoint, _ B: GridPoint, dirOut: GridPoint, ext: Double) -> [GridPoint] {
        guard ext > 0 else { return [] }
        var pts: [GridPoint] = []
        let steps = 8
        let mid = GridPoint((A.x + B.x) / 2, (A.y + B.y) / 2)
        let half = GridPoint((A.x - B.x) / 2, (A.y - B.y) / 2)
        for i in 1..<steps {
            let a = Double.pi * Double(i) / Double(steps)
            pts.append(GridPoint(mid.x + half.x * cos(a) + dirOut.x * ext * sin(a), mid.y + half.y * cos(a) + dirOut.y * ext * sin(a)))
        }
        return pts
    }

    /// Build the filled outline (polygon contours) for a glyph at the given stroke weight.
    static func outline(of glyph: Glyph, weight: Double) -> Outline { outlineWithTags(of: glyph, weight: weight).outline }

    /// Same as `outline(of:weight:)`, but also reports which skeleton node (and offset side)
    /// produced each outline point — parallel to `outline.contours[i].allPoints`. Used by the
    /// TrueType hint compiler to find a hinted node's outline point indices.
    static func outlineWithTags(of glyph: Glyph, weight: Double) -> (outline: Outline, tags: [[PointTag?]]) {
        var contours: [Contour] = []
        var tags: [[PointTag?]] = []
        for path in glyph.paths {
            guard path.nodes.count >= 2 else { continue }
            let pts = flatten(path, weight: weight)
            guard !pts.isEmpty else { continue }
            let L = offsetSide(pts, closed: path.closed, side: 1)
            let R = offsetSide(pts, closed: path.closed, side: -1)
            let Ltags = pts.map { s in s.nodeID.map { PointTag(nodeID: $0, side: .left) } }
            let Rtags = pts.map { s in s.nodeID.map { PointTag(nodeID: $0, side: .right) } }
            if path.closed {
                if let c = contour(from: L) { contours.append(c); tags.append(Ltags) }
                if let c = contour(from: R.reversed()) { contours.append(c); tags.append(Rtags.reversed()) }
            } else {
                let N = pts.count
                let first = path.nodes[0], last = path.nodes[path.nodes.count - 1]
                let dEnd = GridPoint(pts[N-1].p.x - pts[N-2].p.x, pts[N-1].p.y - pts[N-2].p.y).normalized.rotated(degrees: last.angle)
                let dStart = GridPoint(pts[0].p.x - pts[1].p.x, pts[0].p.y - pts[1].p.y).normalized.rotated(degrees: first.angle)
                let endCap = capPoints(L[N-1], R[N-1], dirOut: dEnd, ext: last.cap)
                let startCap = capPoints(R[0], L[0], dirOut: dStart, ext: first.cap)
                var poly = L; poly += endCap; poly += R.reversed(); poly += startCap
                var polyTags = Ltags
                polyTags += Array(repeating: nil, count: endCap.count)
                polyTags += Rtags.reversed()
                polyTags += Array(repeating: nil, count: startCap.count)
                if let c = contour(from: poly) { contours.append(c); tags.append(polyTags) }
            }
        }
        return (Outline(contours: contours), tags)
    }

    private static func contour(from pts: [GridPoint]) -> Contour? {
        guard let first = pts.first else { return nil }
        let segs = pts.dropFirst().map { Contour.Segment.line($0) }
        return Contour(start: first, segments: Array(segs))
    }
}
