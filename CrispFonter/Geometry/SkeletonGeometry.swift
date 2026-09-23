import Foundation

/// Builds a glyph's filled outline from its skeleton paths. All geometry here is in grid units,
/// y up. See the build spec §5.
///
/// Each stroke has two fill-boundary "lines" — outer (left) and inner (right) — one point per
/// skeleton node. A line's point is either explicit (the user has nudged it, or given it its own
/// curve handles) or, until then, simply derived: the node's position offset perpendicular to the
/// local skeleton tangent by its thickness ratio × weight/2. There is no rotation anywhere in this
/// model — a fill line is just an ordinary path of its own, shaped directly rather than derived
/// from an angle.
enum SkeletonGeometry {

    typealias Side = ThicknessSide
    /// Which skeleton node (and which fill-boundary side) produced an outline point.
    struct PointTag { var nodeID: UUID; var side: Side }

    static func halfL(_ n: Node, weight: Double) -> Double { (n.left ?? 1) * weight / 2 }
    static func halfR(_ n: Node, weight: Double) -> Double { (n.right ?? 1) * weight / 2 }

    /// The derived (not-yet-touched) position of a node's fill-boundary point on one side, at
    /// `weight`: the node offset perpendicular to the local skeleton tangent. Shared by the
    /// editor's handle placement and by `NodeAnchor` resolution, so both agree exactly on where
    /// "the fill edge" is until the user starts shaping it explicitly.
    static func thicknessEdge(of node: Node, path: SkeletonPath, index: Int, side: Side, weight: Double) -> GridPoint {
        let t = Hinting.tangentAt(path, index)
        let left = GridPoint(-t.y, t.x)
        switch side {
        case .left:
            let hl = halfL(node, weight: weight)
            return GridPoint(node.p.x + left.x * hl, node.p.y + left.y * hl)
        case .right:
            let hr = halfR(node, weight: weight)
            return GridPoint(node.p.x - left.x * hr, node.p.y - left.y * hr)
        }
    }

    static func bezier(_ p0: GridPoint, _ p1: GridPoint, _ p2: GridPoint, _ p3: GridPoint, _ t: Double) -> GridPoint {
        let mt = 1 - t
        let x = mt*mt*mt*p0.x + 3*mt*mt*t*p1.x + 3*mt*t*t*p2.x + t*t*t*p3.x
        let y = mt*mt*mt*p0.y + 3*mt*mt*t*p1.y + 3*mt*t*t*p2.y + t*t*t*p3.y
        return GridPoint(x, y)
    }

    /// The current fill-boundary point for `side` and its curve handles — always: explicit ones
    /// where the user has set them, or else a derived fallback that still "follows the parameters
    /// of its skeleton node" (per the reset-to-auto behavior elsewhere).
    ///
    /// The point itself is a plain ratio of weight/2, same as always. Its curve handles are a
    /// linear interpolation between the skeleton's own `cIn`/`cOut` (the "at rest" shape, when the
    /// fill point sits exactly on the skeleton node — weight 0) and a reference handle position —
    /// the *explicit* `cIn`/`cOut` if the user set one, else the skeleton's handle translated by
    /// this side's offset *at the canonical weight of 2* — with weight/2 itself as the
    /// interpolation parameter: at weight 0 the handle sits exactly on the skeleton's own, at
    /// weight 2 exactly on the reference, and beyond weight 2 it keeps extrapolating outward along
    /// the same line. So moving the point toward the skeleton node (weight shrinking) pulls its
    /// curve handle toward the skeleton's own handle, and moving away stretches it further past the
    /// reference — a plain geometric relationship instead of an algorithmic curvature estimate.
    static func fillPoint(of node: Node, path: SkeletonPath, index: Int, side: Side, weight: Double) -> (point: GridPoint, cIn: GridPoint?, cOut: GridPoint?) {
        let scale = weight / 2
        let point: GridPoint
        let refCIn: GridPoint?
        let refCOut: GridPoint?
        if let fh = node.fillHandle(side) {
            point = GridPoint(node.p.x + fh.offset.x * scale, node.p.y + fh.offset.y * scale)
            refCIn = fh.cIn.map { GridPoint(node.p.x + $0.x, node.p.y + $0.y) }
            refCOut = fh.cOut.map { GridPoint(node.p.x + $0.x, node.p.y + $0.y) }
        } else {
            point = thicknessEdge(of: node, path: path, index: index, side: side, weight: weight)
            let refPoint = thicknessEdge(of: node, path: path, index: index, side: side, weight: 2)
            let refOffset = GridPoint(refPoint.x - node.p.x, refPoint.y - node.p.y)
            refCIn = node.cIn.map { GridPoint($0.x + refOffset.x, $0.y + refOffset.y) }
            refCOut = node.cOut.map { GridPoint($0.x + refOffset.x, $0.y + refOffset.y) }
        }
        func liveHandle(_ ref: GridPoint?, restingAt skeletonHandle: GridPoint?) -> GridPoint? {
            guard let ref else { return nil }
            let anchor = skeletonHandle ?? node.p
            return GridPoint(anchor.x + (ref.x - anchor.x) * scale, anchor.y + (ref.y - anchor.y) * scale)
        }
        return (point, liveHandle(refCIn, restingAt: node.cIn), liveHandle(refCOut, restingAt: node.cOut))
    }

    /// Builds one side's fill-boundary line: one point per skeleton node (`fillPoint`), connected
    /// node-to-node by a straight line or, where either endpoint has a curve handle facing that
    /// segment, a proper cubic curve — exactly the same shape a skeleton path's own `cIn`/`cOut`
    /// produce, just for this offset line instead of the centerline.
    static func fillBoundary(_ path: SkeletonPath, side: Side, weight: Double) -> (points: [GridPoint], tags: [PointTag?]) {
        let n = path.nodes
        let segCount = path.closed ? n.count : n.count - 1
        var pts: [GridPoint] = []
        var tags: [PointTag?] = []
        for i in 0..<segCount {
            let a = n[i]
            let bIndex = (i + 1) % n.count
            let b = n[bIndex]
            let aFill = fillPoint(of: a, path: path, index: i, side: side, weight: weight)
            let bFill = fillPoint(of: b, path: path, index: bIndex, side: side, weight: weight)
            let c1 = aFill.cOut ?? aFill.point
            let c2 = bFill.cIn ?? bFill.point
            let isLine = aFill.cOut == nil && bFill.cIn == nil
            let steps = isLine ? 1 : 24
            let sStart = i == 0 ? 0 : 1
            for s in sStart...steps {
                let t = Double(s) / Double(steps)
                let p = isLine
                    ? GridPoint(aFill.point.x + (bFill.point.x - aFill.point.x) * t, aFill.point.y + (bFill.point.y - aFill.point.y) * t)
                    : bezier(aFill.point, c1, c2, bFill.point, t)
                pts.append(p)
                let nodeID: UUID? = (i == 0 && s == 0) ? a.id : (s == steps ? b.id : nil)
                tags.append(nodeID.map { PointTag(nodeID: $0, side: side) })
            }
        }
        if path.closed && pts.count > 1 { pts.removeLast(); tags.removeLast() }
        return (pts, tags)
    }

    /// A single-node "dot" path's radius: the length of its outer (or, if that's untouched, inner)
    /// fill handle's offset vector, so ⌘R/⌘L-arrow — the same nudge that moves a normal fill point
    /// — resizes a dot by however far it's pushed, in whatever direction; only the *distance*
    /// matters, since the dot is always centered on its node regardless of which way it was nudged.
    /// Falls back to the old ratio-based `left` field for a node neither handle has touched.
    static func dotRadius(of node: Node, weight: Double) -> Double {
        let scale = weight / 2
        if let fh = node.outer { return GridPoint(fh.offset.x * scale, fh.offset.y * scale).length }
        if let fh = node.inner { return GridPoint(fh.offset.x * scale, fh.offset.y * scale).length }
        return halfL(node, weight: weight)
    }

    /// Build the filled outline (polygon contours) for a glyph at the given stroke weight.
    static func outline(of glyph: Glyph, weight: Double) -> Outline { outlineWithTags(of: glyph, weight: weight).outline }

    /// Same as `outline(of:weight:)`, but also reports which skeleton node (and fill-boundary
    /// side) produced each outline point — parallel to `outline.contours[i].allPoints`. Used by
    /// the TrueType hint compiler to find a hinted node's outline point indices.
    static func outlineWithTags(of rawGlyph: Glyph, weight: Double) -> (outline: Outline, tags: [[PointTag?]]) {
        let glyph = rawGlyph.resolvingAnchors(weight: weight)
        var contours: [Contour] = []
        var tags: [[PointTag?]] = []
        for path in glyph.paths {
            // A stroke left with a single node — no segment to draw at all — instead draws as a
            // filled dot, for punctuation and diacritics (the dot on i/j, ".", ":", etc) — see
            // `dotRadius`.
            if path.nodes.count == 1 {
                let nd = path.nodes[0]
                if let c = circleContour(center: nd.p, radius: dotRadius(of: nd, weight: weight)) {
                    contours.append(c)
                    tags.append(Array(repeating: PointTag(nodeID: nd.id, side: .left), count: c.allPoints.count))
                }
                continue
            }
            guard path.nodes.count >= 2 else { continue }
            let (L, Ltags) = fillBoundary(path, side: .left, weight: weight)
            let (R, Rtags) = fillBoundary(path, side: .right, weight: weight)
            guard !L.isEmpty, !R.isEmpty else { continue }
            if path.closed {
                if let c = contour(from: L) { contours.append(c); tags.append(Ltags) }
                if let c = contour(from: R.reversed()) { contours.append(c); tags.append(Rtags.reversed()) }
            } else {
                // Open stroke: outer forward, straight across to the inner line's matching end,
                // inner backward, straight back to the outer line's start — closing the loop into
                // one contour. No bulge formula — a "cap" is just this plain join, so the user is
                // free to shape it however they like by giving the outer/inner line's own end
                // point a cIn/cOut, exactly as anywhere else along the line.
                var poly = L; poly += R.reversed()
                var polyTags = Ltags; polyTags += Rtags.reversed()
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

    /// A circle flattened to a many-sided polygon — the rest of the pipeline (`GridFitting`,
    /// `Rasterizer`) reads a contour's `allPoints` as straight polygon vertices, so a low-point
    /// Bézier circle rendered that way draws as a visible N-gon instead of a smooth circle.
    private static func circleContour(center: GridPoint, radius: Double) -> Contour? {
        guard radius > 0.01 else { return nil }
        let steps = 32
        let pts = (0..<steps).map { i -> GridPoint in
            let a = 2 * Double.pi * Double(i) / Double(steps)
            return GridPoint(center.x + radius * cos(a), center.y + radius * sin(a))
        }
        return contour(from: pts)
    }
}
