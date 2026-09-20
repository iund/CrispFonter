import Foundation

/// The font-wide `cvt ` table: one entry per alignment zone height and per distinct stem width
/// (build spec §6). Shared by every glyph's hint program so identical stems snap identically.
struct CVTTable {
    private(set) var values: [Int] = [] // font units
    private var zoneIndex: [Int: Int] = [:]  // zone height (grid units) -> cvt index
    private var widthIndex: [Int: Int] = [:] // stem width (grid units, rounded) -> cvt index

    mutating func addZone(_ gridHeight: Int, unitsPerCell: Double) {
        guard zoneIndex[gridHeight] == nil else { return }
        zoneIndex[gridHeight] = values.count
        values.append(Int((Double(gridHeight) * unitsPerCell).rounded()))
    }
    mutating func addWidth(_ gridWidth: Int, unitsPerCell: Double) {
        guard widthIndex[gridWidth] == nil else { return }
        widthIndex[gridWidth] = values.count
        values.append(Int((Double(gridWidth) * unitsPerCell).rounded()))
    }
    func zoneCVTIndex(_ gridHeight: Int) -> Int? { zoneIndex[gridHeight] }
    func widthCVTIndex(_ gridWidth: Int) -> Int? { widthIndex[gridWidth] }

    var tableData: Data {
        var w = ByteWriter()
        for v in values { w.i16(Int16(clamping: v)) }
        return w.data
    }
}

enum CVTBuilder {
    /// Scans every glyph's derived stems (§6) once, up front, so all glyph programs can share one
    /// `cvt ` table built from real hint data.
    static func build(project: FontProject) -> CVTTable {
        var table = CVTTable()
        for z in project.metrics.zones { table.addZone(Int(z.rounded()), unitsPerCell: project.unitsPerCell) }
        for scalar in FontProject.glyphOrder {
            let glyph = project.glyph(for: scalar)
            let d = Hinting.derivedHints(glyph, weight: project.defaultWeight)
            for st in d.v + d.h { table.addWidth(roundedWidth(st), unitsPerCell: project.unitsPerCell) }
        }
        return table
    }

    private static func roundedWidth(_ st: Hinting.Stem) -> Int { max(1, Int((st.hi - st.lo).rounded())) }
}
