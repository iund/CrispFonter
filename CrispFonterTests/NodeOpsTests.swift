import Foundation
import Testing
@testable import CrispFonter

struct NodeOpsTests {
    @Test func toggleNodeKindGrowsAndClearsHandles() {
        var g = Glyph(scalar: UInt32(Character("z").asciiValue!))
        let a = Node(GridPoint(0, 0)), b = Node(GridPoint(4, 0)), c = Node(GridPoint(8, 0))
        let path = SkeletonPath(nodes: [a, b, c], closed: false)
        g.paths = [path]

        g.toggleNodeKind(path.id, b.id)
        let toggled = g.paths[0].nodes[1]
        #expect(toggled.kind == .smooth)
        #expect(toggled.cIn != nil && toggled.cOut != nil)

        g.toggleNodeKind(path.id, b.id)
        let backToCorner = g.paths[0].nodes[1]
        #expect(backToCorner.kind == .corner)
        #expect(backToCorner.cIn == nil && backToCorner.cOut == nil)
    }

    /// Toggling a node to corner must also clear the *neighbors'* handles on the segments shared
    /// with it — clearing only the node's own cIn/cOut leaves those segments curved with a
    /// degenerate endpoint, distorting the curve and the tangent used for cap/thickness handles.
    @Test func toggleToCornerStraightensBothAdjacentSegments() {
        var g = Glyph(scalar: UInt32(Character("z").asciiValue!))
        var a = Node(GridPoint(0, 0), kind: .smooth, cOut: GridPoint(1, 1))
        var b = Node(GridPoint(4, 4), kind: .smooth, cIn: GridPoint(3, 5), cOut: GridPoint(5, 3))
        var c = Node(GridPoint(8, 0), kind: .smooth, cIn: GridPoint(7, 1))
        let path = SkeletonPath(nodes: [a, b, c], closed: false)
        g.paths = [path]

        g.toggleNodeKind(path.id, b.id)

        let nodes = g.paths[0].nodes
        a = nodes[0]; b = nodes[1]; c = nodes[2]
        #expect(b.kind == .corner && b.cIn == nil && b.cOut == nil)
        #expect(a.cOut == nil, "neighbor's handle into the toggled node must also clear")
        #expect(c.cIn == nil, "neighbor's handle into the toggled node must also clear")
    }

    @Test func endpointIsLastDetectsBothEndsAndMiddle() {
        var g = Glyph(scalar: UInt32(Character("z").asciiValue!))
        let a = Node(GridPoint(0, 0)), b = Node(GridPoint(4, 0)), c = Node(GridPoint(8, 0))
        let path = SkeletonPath(nodes: [a, b, c], closed: false)
        g.paths = [path]

        #expect(g.endpointIsLast(path.id, a.id) == false)
        #expect(g.endpointIsLast(path.id, c.id) == true)
        #expect(g.endpointIsLast(path.id, b.id) == nil)
    }

    @Test func endpointIsLastNilForClosedPath() {
        var g = Glyph(scalar: UInt32(Character("z").asciiValue!))
        let a = Node(GridPoint(0, 0)), b = Node(GridPoint(4, 0)), c = Node(GridPoint(4, 4))
        let path = SkeletonPath(nodes: [a, b, c], closed: true)
        g.paths = [path]

        #expect(g.endpointIsLast(path.id, a.id) == nil)
        #expect(g.endpointIsLast(path.id, c.id) == nil)
    }

    @Test func joinDrawingPathAppendsAtTargetsLastEndpointReversed() {
        var g = Glyph(scalar: UInt32(Character("z").asciiValue!))
        let t0 = Node(GridPoint(0, 0)), t1 = Node(GridPoint(2, 0))
        let target = SkeletonPath(nodes: [t0, t1], closed: false)
        let d0 = Node(GridPoint(10, 0)), d1 = Node(GridPoint(8, 0)), d2 = Node(GridPoint(2, 0)) // drawn toward target.last
        let drawing = SkeletonPath(nodes: [d0, d1, d2], closed: false)
        g.paths = [target, drawing]

        g.joinDrawingPath(drawing.id, intoEndpointOf: target.id, isLastEndpoint: true)

        #expect(g.paths.count == 1)
        let merged = g.paths[0].nodes.map(\.id)
        #expect(merged == [t0.id, t1.id, d2.id, d1.id, d0.id])
    }

    @Test func joinDrawingPathInsertsAtTargetsFirstEndpoint() {
        var g = Glyph(scalar: UInt32(Character("z").asciiValue!))
        let t0 = Node(GridPoint(2, 0)), t1 = Node(GridPoint(4, 0))
        let target = SkeletonPath(nodes: [t0, t1], closed: false)
        let d0 = Node(GridPoint(-4, 0)), d1 = Node(GridPoint(-2, 0)), d2 = Node(GridPoint(2, 0)) // drawn toward target.first
        let drawing = SkeletonPath(nodes: [d0, d1, d2], closed: false)
        g.paths = [target, drawing]

        g.joinDrawingPath(drawing.id, intoEndpointOf: target.id, isLastEndpoint: false)

        #expect(g.paths.count == 1)
        let merged = g.paths[0].nodes.map(\.id)
        #expect(merged == [d0.id, d1.id, d2.id, t0.id, t1.id])
    }
}
