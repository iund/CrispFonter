import Foundation

/// Maps a hinted node to the outline point index(es) it produced (left/right offset side).
typealias NodePointIndex = [UUID: (left: Int?, right: Int?)]

/// Compiles one glyph's TrueType hinting program (build spec §6): for every hinted node, anchor
/// its edge with MIAP (zone-anchored) or MDAP (plain round, wrapped in RUTG/RDTG for a forced
/// push direction), then tie stem widths together with MIRP to the stem's `cvt ` entry. Whatever
/// isn't explicitly touched is left to IUP.
enum GlyphHintProgram {
    static func compile(glyph: Glyph, project: FontProject, cvt: CVTTable, pointForNode: NodePointIndex) -> Data {
        guard !glyph.hints.isEmpty else { return Data() }
        var p = Program()
        compileAxis(&p, glyph: glyph, project: project, cvt: cvt, pointForNode: pointForNode, y: true)
        compileAxis(&p, glyph: glyph, project: project, cvt: cvt, pointForNode: pointForNode, y: false)
        return p.data
    }

    private static func compileAxis(_ p: inout Program, glyph: Glyph, project: FontProject, cvt: CVTTable, pointForNode: NodePointIndex, y: Bool) {
        p.svtca(y: y)
        p.rtg()
        var touchedAny = false
        for path in glyph.paths {
            for (i, node) in path.nodes.enumerated() {
                guard let hint = glyph.hints[node.id], let mode = y ? hint.y : hint.x else { continue }
                guard let idx = pointForNode[node.id] else { continue }
                let (e1, e2) = Hinting.edgesAt(path, i, weight: project.defaultWeight)
                let v1 = y ? e1.y : e1.x, v2 = y ? e2.y : e2.x
                if abs(v1 - v2) > 0.1 {
                    touchedAny = touchStem(&p, left: idx.left, right: idx.right, v1: v1, v2: v2, mode: mode, y: y, cvt: cvt, project: project) || touchedAny
                } else {
                    for point in [idx.left, idx.right].compactMap({ $0 }) {
                        touchPoint(&p, index: point, at: v1, mode: mode, y: y, cvt: cvt, project: project)
                        touchedAny = true
                    }
                }
            }
        }
        if touchedAny { p.iup(y: y) }
    }

    /// Anchor a single point: MIAP to a zone's cvt entry if it sits on an alignment zone (y only),
    /// otherwise MDAP, its rounding wrapped in RUTG/RDTG for a forced push direction.
    private static func touchPoint(_ p: inout Program, index: Int, at v: Double, mode: SnapMode, y: Bool, cvt: CVTTable, project: FontProject) {
        if y, let zoneIdx = zoneCVTIndex(v, project: project, cvt: cvt) {
            p.push([index, zoneIdx]); p.miap(round: true)
            return
        }
        wrapRounding(&p, mode: mode) { p in p.push(index); p.mdap(round: true) }
    }

    /// Anchor one edge of a stem, then MIRP the other edge to the stem's width in `cvt `.
    private static func touchStem(_ p: inout Program, left: Int?, right: Int?, v1: Double, v2: Double, mode: SnapMode, y: Bool, cvt: CVTTable, project: FontProject) -> Bool {
        guard let left, let right else { return false }
        let width = max(1, Int((abs(v2 - v1)).rounded()))
        guard let widthCvt = cvt.widthCVTIndex(width) else { return false }

        let anchorIsV1: Bool
        switch mode {
        case .positive: anchorIsV1 = v1 > v2   // push the high edge outward; it's the anchor
        case .negative: anchorIsV1 = v1 < v2   // push the low edge outward; it's the anchor
        case .nearest:
            if y, zoneCVTIndex(v1, project: project, cvt: cvt) != nil { anchorIsV1 = true }
            else if y, zoneCVTIndex(v2, project: project, cvt: cvt) != nil { anchorIsV1 = false }
            else { anchorIsV1 = v1 <= v2 }
        }
        let anchorIdx = anchorIsV1 ? left : right, otherIdx = anchorIsV1 ? right : left
        let anchorV = anchorIsV1 ? v1 : v2

        if y, let zoneIdx = zoneCVTIndex(anchorV, project: project, cvt: cvt) {
            p.push([anchorIdx, zoneIdx]); p.miap(round: true)
        } else {
            wrapRounding(&p, mode: mode) { p in p.push(anchorIdx); p.mdap(round: true) }
        }
        // MDAP/MIAP already set rp0 to the anchor point, so MIRP can use it directly.
        p.push([otherIdx, widthCvt]); p.mirp(setRp0: true, minimum: true, round: true, distanceType: 1)
        return true
    }

    private static func wrapRounding(_ p: inout Program, mode: SnapMode, _ body: (inout Program) -> Void) {
        switch mode {
        case .positive: p.rutg(); body(&p); p.rtg()
        case .negative: p.rdtg(); body(&p); p.rtg()
        case .nearest: body(&p)
        }
    }

    private static func zoneCVTIndex(_ gridValue: Double, project: FontProject, cvt: CVTTable) -> Int? {
        for z in project.metrics.zones where abs(z - gridValue) < 0.05 { return cvt.zoneCVTIndex(Int(z.rounded())) }
        return nil
    }
}
