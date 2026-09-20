import Foundation

/// Builds the `glyf` and `loca` tables. Outlines are emitted as plain on-curve polygons (the
/// "simplest acceptable version" the build spec allows for §5.4); hinting bytecode comes from
/// `HintedGlyphBuilder` (see Export/TrueType).
enum TrueTypeGlyf {
    struct Built {
        var glyf = Data()
        var loca: [UInt32] = [0]
        var advances: [Int] = []
        var lsb: [Int] = []
        var maxInstructionBytes = 0
        var maxPoints = 0
        var maxContours = 0
    }

    static func build(project: FontProject, cvt: CVTTable) -> Built {
        var out = Built()
        for scalar in FontProject.glyphOrder {
            let glyph = project.glyph(for: scalar)
            let hinted = HintedGlyphBuilder.build(glyph: glyph, project: project, cvt: cvt)
            let entry = glyphData(hinted)
            out.glyf.append(entry)
            out.loca.append(out.loca.last! + UInt32(entry.count))
            out.advances.append(project.advance(of: glyph))
            out.lsb.append(0)
            out.maxInstructionBytes = max(out.maxInstructionBytes, hinted.instructions.count)
            out.maxPoints = max(out.maxPoints, hinted.contours.reduce(0) { $0 + $1.count })
            out.maxContours = max(out.maxContours, hinted.contours.count)
        }
        return out
    }

    private static func glyphData(_ hinted: HintedGlyph) -> Data {
        let contours = hinted.contours.filter { !$0.isEmpty }
        guard !contours.isEmpty else { return Data() }

        var xs: [Int] = [], ys: [Int] = []
        var endPts: [UInt16] = []
        var running = -1
        for c in contours { running += c.count; endPts.append(UInt16(running)); for p in c { xs.append(p.x); ys.append(p.y) } }

        var w = ByteWriter()
        w.i16(Int16(contours.count))
        w.i16(Int16(xs.min() ?? 0)); w.i16(Int16(ys.min() ?? 0))
        w.i16(Int16(xs.max() ?? 0)); w.i16(Int16(ys.max() ?? 0))
        for e in endPts { w.u16(e) }
        w.u16(UInt16(hinted.instructions.count))
        w.append(hinted.instructions)
        // On-curve point, full 16-bit deltas (no short-vector / repeat compression, for simplicity).
        let onCurveOverlap: UInt8 = 0x01 | 0x40 // ON_CURVE_POINT | OVERLAP_SIMPLE (harmless when only one contour)
        for i in 0..<xs.count { w.u8(i == 0 ? onCurveOverlap : 0x01) }
        var prevX = 0
        for x in xs { w.i16(Int16(x - prevX)); prevX = x }
        var prevY = 0
        for y in ys { w.i16(Int16(y - prevY)); prevY = y }
        w.pad(to: 2)
        return w.data
    }
}
