import Foundation

/// Port of the prototype's hinting derivation: tangents, defaultHint, edgesAt, derivedHints.
/// Build spec §6.
enum Hinting {

    /// Hints every node whose incoming or outgoing tangent is near-vertical/horizontal, at its
    /// default (nearest) hint. Shared by the Hint-mode toolbar button and its ⇧⏎ shortcut.
    /// Returns the number of nodes hinted.
    @discardableResult
    static func autoDetect(_ g: inout Glyph, mode: SnapMode = .nearest) -> Int {
        var count = 0
        for path in g.paths {
            for (i, nd) in path.nodes.enumerated() {
                let t = tangents(path, i)
                func straight(_ v: GridPoint?) -> Bool { guard let v else { return false }; return abs(v.x) < 0.35 || abs(v.y) < 0.35 }
                if straight(t.tin) || straight(t.tout) { g.hints[nd.id] = defaultHint(path, i, mode: mode); count += 1 }
            }
        }
        return count
    }

    struct Tangents { var tin: GridPoint?; var tout: GridPoint? }

    static func tangents(_ path: SkeletonPath, _ i: Int) -> Tangents {
        let n = path.nodes
        let nd = n[i]
        let prev: Node? = (path.closed || i > 0) ? n[(i - 1 + n.count) % n.count] : nil
        let next: Node? = (path.closed || i < n.count - 1) ? n[(i + 1) % n.count] : nil
        let tin: GridPoint?
        if let c = nd.cIn { tin = GridPoint(nd.p.x - c.x, nd.p.y - c.y).normalized }
        else if let p = prev { tin = GridPoint(nd.p.x - p.p.x, nd.p.y - p.p.y).normalized }
        else { tin = nil }
        let tout: GridPoint?
        if let c = nd.cOut { tout = GridPoint(c.x - nd.p.x, c.y - nd.p.y).normalized }
        else if let nx = next { tout = GridPoint(nx.p.x - nd.p.x, nx.p.y - nd.p.y).normalized }
        else { tout = nil }
        return Tangents(tin: tin, tout: tout)
    }

    static func tangentAt(_ path: SkeletonPath, _ i: Int) -> GridPoint {
        let t = tangents(path, i)
        if let tin = t.tin, let tout = t.tout {
            let d = GridPoint(tin.x + tout.x, tin.y + tout.y)
            return d.length < 1e-6 ? tout : d.normalized
        }
        return t.tin ?? t.tout ?? GridPoint(1, 0)
    }

    /// x = "nearest" if any adjacent tangent is within ~20 deg of vertical; y likewise for horizontal.
    /// Neither -> both nearest.
    static func defaultHint(_ path: SkeletonPath, _ i: Int, mode: SnapMode = .nearest) -> HintPoint {
        let t = tangents(path, i)
        var x = false, y = false
        for tt in [t.tin, t.tout] {
            guard let tt else { continue }
            if abs(tt.x) < 0.35 { x = true }
            if abs(tt.y) < 0.35 { y = true }
        }
        if !x && !y { x = true; y = true }
        return HintPoint(x: x ? mode : nil, y: y ? mode : nil)
    }

    /// The two stroke edges at a node, in grid units — its explicit fill points if set, else the
    /// derived (perpendicular-offset) position, exactly what's actually rendered there.
    static func edgesAt(_ path: SkeletonPath, _ i: Int, weight: Double) -> (GridPoint, GridPoint) {
        let nd = path.nodes[i]
        let e1 = SkeletonGeometry.fillPoint(of: nd, path: path, index: i, side: .left, weight: weight).point
        let e2 = SkeletonGeometry.fillPoint(of: nd, path: path, index: i, side: .right, weight: weight).point
        return (e1, e2)
    }

    struct Stem { var lo: Double; var hi: Double; var mode: SnapMode }
    struct PointAnchor { var at: Double; var mode: SnapMode }
    struct Derived {
        var v: [Stem] = []   // vertical stems (hinted on x)
        var h: [Stem] = []   // horizontal stems (hinted on y)
        var px: [PointAnchor] = []
        var py: [PointAnchor] = []
    }

    /// Derive stems / single anchors from every hinted node in a glyph.
    static func derivedHints(_ glyph: Glyph, weight: Double) -> Derived {
        var r = Derived()
        for path in glyph.paths {
            for (i, nd) in path.nodes.enumerated() {
                guard let hint = glyph.hints[nd.id] else { continue }
                let (e1, e2) = edgesAt(path, i, weight: weight)
                if let mode = hint.x {
                    if abs(e1.x - e2.x) > 0.1 { r.v.append(Stem(lo: min(e1.x, e2.x), hi: max(e1.x, e2.x), mode: mode)) }
                    else { r.px.append(PointAnchor(at: nd.p.x, mode: mode)) }
                }
                if let mode = hint.y {
                    if abs(e1.y - e2.y) > 0.1 { r.h.append(Stem(lo: min(e1.y, e2.y), hi: max(e1.y, e2.y), mode: mode)) }
                    else { r.py.append(PointAnchor(at: nd.p.y, mode: mode)) }
                }
            }
        }
        return r
    }

    /// Round a pixel coordinate by mode: nearest, or forced toward negative / positive. `.outward`
    /// only has meaning for a stem's *pair* of edges (see `GridFitting.stemAnchors`) — for a lone
    /// point anchor there's no "away from center" to round toward, so it falls back to nearest.
    static func snapPx(_ v: Double, _ mode: SnapMode) -> Double {
        switch mode {
        case .positive: return (v - 1e-4).rounded(.up)
        case .negative: return (v + 1e-4).rounded(.down)
        case .nearest, .outward: return v.rounded()
        }
    }
}
