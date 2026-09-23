import Foundation

/// A few pre-drawn glyphs (ported from the prototype) so a new document isn't empty air.
enum SampleGlyphs {
    private static func n(_ x: Double, _ y: Double, kind: NodeKind = .corner, cIn: GridPoint? = nil, cOut: GridPoint? = nil) -> Node {
        Node(GridPoint(x, y), kind: kind, cIn: cIn, cOut: cOut)
    }

    private static func hint(_ spec: String) -> HintPoint {
        var h = HintPoint(x: nil, y: nil)
        for part in spec.split(separator: " ") {
            let bits = part.split(separator: ":")
            let axis = String(bits[0])
            let mode: SnapMode = bits.count > 1 ? SnapMode(shortName: String(bits[1])) : .nearest
            if axis == "x" { h.x = mode } else if axis == "y" { h.y = mode }
        }
        return h
    }

    /// Builds a glyph from paths and a list of (pathIndex, nodeIndex, hintSpec).
    private static func glyph(_ scalar: UInt32, _ paths: [SkeletonPath], _ hints: [(Int, Int, String)]) -> Glyph {
        var g = Glyph(scalar: scalar, paths: paths)
        for (pi, ni, spec) in hints { g.hints[paths[pi].nodes[ni].id] = hint(spec) }
        return g
    }

    static func seed(into project: inout FontProject) {
        let a = glyph(UInt32(Character("a").asciiValue!), [
            SkeletonPath(nodes: [
                n(1, 6, kind: .smooth, cOut: GridPoint(1, 7.1)),
                n(4, 8, kind: .smooth, cIn: GridPoint(2.3, 8), cOut: GridPoint(5.7, 8)),
                n(7, 6, kind: .smooth, cIn: GridPoint(7, 7.1), cOut: GridPoint(7, 5)),
                n(7, 0),
            ], closed: false),
            SkeletonPath(nodes: [
                n(7, 3.5),
                n(3, 3.5, kind: .smooth, cIn: GridPoint(5, 3.5), cOut: GridPoint(1.8, 3.5)),
                n(1, 1.75, kind: .smooth, cIn: GridPoint(1, 2.6), cOut: GridPoint(1, 0.9)),
                n(3, 0, kind: .smooth, cIn: GridPoint(1.8, 0), cOut: GridPoint(5, 0)),
                n(7, 1),
            ], closed: true),
        ], [(0, 1, "y"), (0, 2, "x"), (0, 3, "x"), (1, 1, "y"), (1, 2, "x"), (1, 3, "y")])

        let nGlyph = glyph(UInt32(Character("n").asciiValue!), [
            SkeletonPath(nodes: [n(1, 0), n(1, 8)], closed: false),
            SkeletonPath(nodes: [
                n(1, 5.5, kind: .smooth, cOut: GridPoint(1, 7.4)),
                n(4, 8, kind: .smooth, cIn: GridPoint(2.2, 8), cOut: GridPoint(5.2, 8)),
                n(6.4, 7, kind: .smooth, cIn: GridPoint(5.9, 7.6), cOut: GridPoint(6.8, 6.5)),
                n(7, 5.5, kind: .smooth, cIn: GridPoint(7, 6.1)),
                n(7, 0),
            ], closed: false),
        ], [(0, 0, "x"), (0, 1, "x y"), (1, 1, "y"), (1, 2, "x:pos y:pos"), (1, 4, "x")])

        let l = glyph(UInt32(Character("l").asciiValue!), [
            SkeletonPath(nodes: [n(2, 12), n(4, 12), n(4, 0)], closed: false),
            SkeletonPath(nodes: [n(1.5, 0), n(6.5, 0)], closed: false),
        ], [(0, 0, "y"), (0, 1, "x y"), (0, 2, "x y"), (1, 0, "y"), (1, 1, "y")])

        let c = glyph(UInt32(Character("c").asciiValue!), [
            SkeletonPath(nodes: [
                n(6.5, 6.25, kind: .smooth, cOut: GridPoint(5.8, 7.6)),
                n(4, 8, kind: .smooth, cIn: GridPoint(5.5, 8), cOut: GridPoint(2.2, 8)),
                n(1, 4, kind: .smooth, cIn: GridPoint(1, 6.2), cOut: GridPoint(1, 1.8)),
                n(4, 0, kind: .smooth, cIn: GridPoint(2.2, 0), cOut: GridPoint(5.5, 0)),
                n(6.5, 1.75, kind: .smooth, cIn: GridPoint(5.8, 0.4)),
            ], closed: false),
        ], [(0, 1, "y"), (0, 2, "x"), (0, 3, "y")])

        let notdef = glyph(Glyph.notdefScalar, [
            SkeletonPath(nodes: [n(1.5, 0), n(1.5, 11), n(6.5, 11), n(6.5, 0)], closed: true),
        ], [(0, 0, "x y"), (0, 1, "x y"), (0, 2, "x y"), (0, 3, "x y")])

        var space = Glyph(scalar: 0x20)
        space.complete = true

        project.glyphs[a.scalar] = a
        project.glyphs[nGlyph.scalar] = nGlyph.with { $0.complete = true }
        project.glyphs[l.scalar] = l
        project.glyphs[c.scalar] = c
        project.glyphs[notdef.scalar] = notdef.with { $0.complete = true }
        project.glyphs[space.scalar] = space
    }
}

extension SnapMode {
    init(shortName: String) {
        switch shortName {
        case "pos": self = .positive
        case "neg": self = .negative
        default: self = .nearest
        }
    }
}

extension Node {
    func with(_ body: (inout Node) -> Void) -> Node { var n = self; body(&n); return n }
}
extension Glyph {
    func with(_ body: (inout Glyph) -> Void) -> Glyph { var g = self; body(&g); return g }
}
