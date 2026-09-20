import Foundation

/// Assembles the sfnt table directory and writes a `.ttf` file. Build spec §7.
enum TrueTypeWriter {
    static func write(project: FontProject) -> Data {
        let cvt = CVTBuilder.build(project: project)
        let glyf = TrueTypeGlyf.build(project: project, cvt: cvt)
        var tables: [(String, Data)] = [
            ("head", TrueTypeTables.head(project: project, glyf: glyf, indexToLocFormat: 1)),
            ("hhea", TrueTypeTables.hhea(project: project, glyf: glyf)),
            ("maxp", TrueTypeTables.maxp(glyf: glyf)),
            ("OS/2", TrueTypeTables.os2(project: project, glyf: glyf)),
            ("hmtx", TrueTypeTables.hmtx(glyf: glyf)),
            ("cmap", TrueTypeTables.cmap()),
            ("loca", TrueTypeTables.loca(glyf)),
            ("glyf", glyf.glyf),
            ("name", TrueTypeTables.name(project.export)),
            ("post", TrueTypeTables.post()),
            ("gasp", TrueTypeTables.gasp(project.export)),
        ]
        if project.export.includeHints {
            tables.append(("cvt ", cvt.tableData))
            tables.append(("prep", PrepProgram.compile(project: project)))
        }
        tables.sort { $0.0 < $1.0 }
        return assemble(tables)
    }

    private static func assemble(_ tables: [(String, Data)]) -> Data {
        let numTables = tables.count
        var pow2 = 1, log2n = 0
        while pow2 * 2 <= numTables { pow2 *= 2; log2n += 1 }
        let searchRange = UInt16(pow2 * 16)
        let entrySelector = UInt16(log2n)
        let rangeShift = UInt16(numTables * 16) - searchRange

        var dir = ByteWriter()
        dir.u32(0x00010000)
        dir.u16(UInt16(numTables)); dir.u16(searchRange); dir.u16(entrySelector); dir.u16(rangeShift)

        var body = Data()
        var offset = UInt32(12 + numTables * 16)
        var headOffset: Int? = nil
        for (tagName, data) in tables {
            var padded = data
            while padded.count % 4 != 0 { padded.append(0) }
            if tagName == "head" { headOffset = 12 + numTables * 16 + body.count }
            dir.tag(tagName); dir.u32(data.ttfChecksum); dir.u32(offset); dir.u32(UInt32(data.count))
            body.append(padded)
            offset += UInt32(padded.count)
        }

        var file = dir.data
        file.append(body)

        // head.checkSumAdjustment = 0xB1B0AFBA - checksum(whole file with that field zeroed).
        if let headOffset {
            let adjustmentOffset = headOffset + 8
            file[adjustmentOffset] = 0; file[adjustmentOffset + 1] = 0; file[adjustmentOffset + 2] = 0; file[adjustmentOffset + 3] = 0
            let checksum = file.ttfChecksum
            let adjustment = 0xB1B0AFBA &- checksum
            file[adjustmentOffset] = UInt8(adjustment >> 24)
            file[adjustmentOffset + 1] = UInt8((adjustment >> 16) & 0xFF)
            file[adjustmentOffset + 2] = UInt8((adjustment >> 8) & 0xFF)
            file[adjustmentOffset + 3] = UInt8(adjustment & 0xFF)
        }
        return file
    }
}
