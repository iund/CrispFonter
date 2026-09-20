import Foundation
import Testing
@testable import CrispFonter

struct GeometryTests {
    @Test func straightVerticalStrokeEdges() {
        var g = Glyph(scalar: UInt32(Character("|").asciiValue!))
        g.paths = [SkeletonPath(nodes: [Node(GridPoint(4, 0)), Node(GridPoint(4, 8))], closed: false)]
        let outline = SkeletonGeometry.outline(of: g, weight: 2)
        let xs = outline.contours.flatMap(\.allPoints).map(\.x)
        #expect(xs.allSatisfy { abs($0 - 3) < 1e-6 || abs($0 - 5) < 1e-6 })
    }

    @Test func leftZeroPinsEdgeToSkeleton() {
        // An open 2-node stroke's contour is [leftEdge0, leftEdge1, rightEdge1, rightEdge0];
        // with left = 0 on both nodes the first two (left-side) points sit on the skeleton at x=4.
        var g = Glyph(scalar: UInt32(Character("|").asciiValue!))
        var a = Node(GridPoint(4, 0)); a.left = 0
        var b = Node(GridPoint(4, 8)); b.left = 0
        g.paths = [SkeletonPath(nodes: [a, b], closed: false)]
        let outline = SkeletonGeometry.outline(of: g, weight: 2)
        let leftXs = outline.contours[0].allPoints.prefix(2).map(\.x)
        #expect(leftXs.allSatisfy { abs($0 - 4) < 1e-6 })
    }

    @Test func fontProjectRoundTrips() throws {
        var project = FontProject()
        SampleGlyphs.seed(into: &project)
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(FontProject.self, from: data)
        #expect(decoded == project)
    }
}

struct GridFittingTests {
    @Test func stemNearestRoundsBothEdges() {
        let anchors = GridFitting.stemAnchors([Hinting.Stem(lo: 3.2, hi: 4.7, mode: .nearest)], s: 1, zoneAnchors: nil)
        #expect(anchors.map(\.dst) == [3, 5])
    }
    @Test func stemPositivePushesHighEdge() {
        let anchors = GridFitting.stemAnchors([Hinting.Stem(lo: 3.2, hi: 4.7, mode: .positive)], s: 1, zoneAnchors: nil)
        #expect(anchors.map(\.dst) == [3, 5])
    }
    @Test func narrowStemNearest() {
        let anchors = GridFitting.stemAnchors([Hinting.Stem(lo: 3.4, hi: 4.1, mode: .nearest)], s: 1, zoneAnchors: nil)
        #expect(anchors.map(\.dst) == [3, 4])
    }
    @Test func narrowStemPositive() {
        let anchors = GridFitting.stemAnchors([Hinting.Stem(lo: 3.4, hi: 4.1, mode: .positive)], s: 1, zoneAnchors: nil)
        #expect(anchors.map(\.dst) == [4, 5])
    }
    @Test func narrowStemNegative() {
        let anchors = GridFitting.stemAnchors([Hinting.Stem(lo: 3.4, hi: 4.1, mode: .negative)], s: 1, zoneAnchors: nil)
        #expect(anchors.map(\.dst) == [3, 4])
    }
}

struct TrueTypeWriterTests {
    @Test func exportedFontReparses() {
        var project = FontProject()
        SampleGlyphs.seed(into: &project)
        let data = TrueTypeWriter.write(project: project)
        #expect(data.count > 12)

        let numTables = Int(data[4]) << 8 | Int(data[5])
        #expect(numTables > 0)
        var tags: Set<String> = []
        for i in 0..<numTables {
            let base = 12 + i * 16
            let tag = String(bytes: data[base..<base + 4], encoding: .ascii) ?? ""
            let offset = Int(data[base + 8]) << 24 | Int(data[base + 9]) << 16 | Int(data[base + 10]) << 8 | Int(data[base + 11])
            let length = Int(data[base + 12]) << 24 | Int(data[base + 13]) << 16 | Int(data[base + 14]) << 8 | Int(data[base + 15])
            tags.insert(tag)
            #expect(offset + length <= data.count)
        }
        #expect(tags.isSuperset(of: ["head", "hhea", "maxp", "OS/2", "hmtx", "cmap", "loca", "glyf", "name", "post", "gasp"]))
    }
}
