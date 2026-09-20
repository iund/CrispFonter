import Foundation
import Testing
@testable import CrispFonter

struct CVTTableTests {
    @Test func zonesAndWidthsDedupe() {
        var project = FontProject()
        SampleGlyphs.seed(into: &project)
        let cvt = CVTBuilder.build(project: project)
        // 5 zone heights, all distinct for the default metrics.
        let zoneValues = project.metrics.zones.map { Int((Double($0) * project.unitsPerCell).rounded()) }
        for z in zoneValues { #expect(cvt.values.contains(z)) }
        // Adding the same zone/width again must not grow the table.
        var t = cvt
        let before = t.values.count
        t.addZone(Int(project.metrics.zones[0]), unitsPerCell: project.unitsPerCell)
        #expect(t.values.count == before)
    }
}

struct GlyphHintProgramTests {
    @Test func hintedGlyphProducesInstructions() {
        var project = FontProject()
        SampleGlyphs.seed(into: &project)
        let cvt = CVTBuilder.build(project: project)
        let nScalar = UInt32(Character("n").asciiValue!)
        let glyph = project.glyph(for: nScalar)
        #expect(!glyph.hints.isEmpty)
        let hinted = HintedGlyphBuilder.build(glyph: glyph, project: project, cvt: cvt)
        #expect(!hinted.instructions.isEmpty)
        // Every instruction byte must be a real opcode/push-count byte, not garbage; spot-check
        // the program starts with SVTCA[y] (0x00) as §6 specifies.
        #expect(hinted.instructions.first == 0x00)
    }

    @Test func unhintedGlyphHasNoInstructions() {
        var project = FontProject()
        var glyph = Glyph(scalar: UInt32(Character("z").asciiValue!))
        glyph.paths = [SkeletonPath(nodes: [Node(GridPoint(1, 0)), Node(GridPoint(1, 8))], closed: false)]
        let cvt = CVTBuilder.build(project: project)
        let hinted = HintedGlyphBuilder.build(glyph: glyph, project: project, cvt: cvt)
        #expect(hinted.instructions.isEmpty)
    }

    @Test func excludingHintsOmitsInstructions() {
        var project = FontProject()
        SampleGlyphs.seed(into: &project)
        project.export.includeHints = false
        let cvt = CVTBuilder.build(project: project)
        let glyph = project.glyph(for: UInt32(Character("n").asciiValue!))
        let hinted = HintedGlyphBuilder.build(glyph: glyph, project: project, cvt: cvt)
        #expect(hinted.instructions.isEmpty)
    }
}

struct TrueTypeHintedExportTests {
    @Test func exportWithHintsIncludesCvtAndPrep() {
        var project = FontProject()
        SampleGlyphs.seed(into: &project)
        let data = TrueTypeWriter.write(project: project)
        let tags = tableTags(in: data)
        #expect(tags.contains("cvt "))
        #expect(tags.contains("prep"))
    }

    @Test func exportWithoutHintsOmitsCvtAndPrep() {
        var project = FontProject()
        SampleGlyphs.seed(into: &project)
        project.export.includeHints = false
        let data = TrueTypeWriter.write(project: project)
        let tags = tableTags(in: data)
        #expect(!tags.contains("cvt "))
        #expect(!tags.contains("prep"))
    }

    private func tableTags(in data: Data) -> Set<String> {
        let numTables = Int(data[4]) << 8 | Int(data[5])
        var tags: Set<String> = []
        for i in 0..<numTables {
            let base = 12 + i * 16
            tags.insert(String(bytes: data[base..<base + 4], encoding: .ascii) ?? "")
        }
        return tags
    }
}
