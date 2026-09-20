import Foundation

/// Builders for the individual sfnt tables. No hinting bytecode is emitted (see `TrueTypeGlyf`),
/// so `cvt `/`fpgm`/`prep` are omitted — they'd have nothing to do.
enum TrueTypeTables {
    static let appleEpoch = Date(timeIntervalSince1970: -2082844800) // 1904-01-01

    static func head(project: FontProject, glyf: TrueTypeGlyf.Built, indexToLocFormat: Int16) -> Data {
        var w = ByteWriter()
        let now = UInt32(Date().timeIntervalSince(appleEpoch))
        let m = project.metrics, upc = project.unitsPerCell
        w.u32(0x00010000); w.u32(0x00010000); w.u32(0) // version, fontRevision, checkSumAdjustment (fixed up later)
        w.u32(0x5F0F3CF5)
        w.u16(0x0003)
        w.u16(UInt16(project.unitsPerEm))
        w.u32(0); w.u32(now)
        w.u32(0); w.u32(now)
        w.i16(0); w.i16(Int16((Double(m.descender) * upc).rounded()))
        w.i16(Int16((Double(m.defaultAdvance) * upc).rounded())); w.i16(Int16((Double(m.ascender) * upc).rounded()))
        w.u16(0)
        w.u16(8)
        w.i16(2)
        w.i16(indexToLocFormat)
        w.i16(0)
        return w.data
    }

    static func hhea(project: FontProject, glyf: TrueTypeGlyf.Built) -> Data {
        var w = ByteWriter()
        let m = project.metrics, upc = project.unitsPerCell
        w.u32(0x00010000)
        w.i16(Int16((Double(m.ascender) * upc).rounded()))
        w.i16(Int16((Double(m.descender) * upc).rounded()))
        w.i16(Int16((Double(m.lineHeight - m.ascender + m.descender) * upc).rounded()))
        w.u16(UInt16(glyf.advances.max() ?? 0))
        w.i16(0); w.i16(0)
        w.i16(Int16((Double(m.defaultAdvance) * upc).rounded()))
        w.i16(1); w.i16(0); w.i16(0)
        w.i16(0); w.i16(0); w.i16(0); w.i16(0)
        w.i16(0)
        w.u16(UInt16(glyf.advances.count))
        return w.data
    }

    static func maxp(glyf: TrueTypeGlyf.Built) -> Data {
        var w = ByteWriter()
        w.u32(0x00010000)
        w.u16(UInt16(FontProject.glyphOrder.count))
        w.u16(UInt16(max(64, glyf.maxPoints))); w.u16(UInt16(max(8, glyf.maxContours)))
        w.u16(0); w.u16(0) // maxComponentPoints, maxComponentContours
        w.u16(1)           // maxZones: twilight zone unused, but 1 is the safe default
        w.u16(0)           // maxTwilightPoints
        w.u16(0); w.u16(0) // maxStorage, maxFunctionDefs (no fpgm functions)
        w.u16(0)           // maxInstructionDefs
        w.u16(32)          // maxStackElements: generous, our programs never nest deeply
        w.u16(UInt16(glyf.maxInstructionBytes))
        w.u16(0); w.u16(0) // maxComponentElements, maxComponentDepth
        return w.data
    }

    static func os2(project: FontProject, glyf: TrueTypeGlyf.Built) -> Data {
        var w = ByteWriter()
        let m = project.metrics, upc = project.unitsPerCell
        func px(_ v: Double) -> Int16 { Int16((v * upc).rounded()) }
        w.u16(4) // version
        w.i16(px(Double(m.defaultAdvance)))
        w.u16(400); w.u16(5); w.u16(0) // weight, width, fsType
        w.i16(px(0.6 * Double(m.defaultAdvance))); w.i16(px(0.7 * Double(m.capHeight))) // subscript size
        w.i16(0); w.i16(0) // subscript offset
        w.i16(px(0.6 * Double(m.defaultAdvance))); w.i16(px(0.7 * Double(m.capHeight))) // superscript size
        w.i16(0); w.i16(px(0.35 * Double(m.capHeight))) // superscript offset
        w.i16(px(0.05 * Double(m.capHeight))) // strikeout size
        w.i16(px(0.3 * Double(m.xHeight))) // strikeout position
        w.i16(0) // sFamilyClass
        for _ in 0..<10 { w.u8(0) } // panose
        w.u32(1); w.u32(0); w.u32(0); w.u32(0) // ulUnicodeRange 1-4 (bit 0 = Basic Latin)
        w.ascii("NONE", 4)
        w.u16(0x0040) // fsSelection: REGULAR
        w.u16(UInt16(FontProject.glyphOrder.dropFirst(2).min() ?? 0x20))
        w.u16(UInt16(FontProject.glyphOrder.max() ?? 0x7E))
        w.i16(px(Double(m.ascender)))
        w.i16(px(Double(m.descender)))
        w.i16(px(Double(m.lineHeight - m.ascender + m.descender)))
        w.u16(UInt16(px(Double(m.ascender))))
        w.u16(UInt16(max(0, -px(Double(m.descender)))))
        w.u32(1); w.u32(0) // codepage range 1-2
        w.i16(px(Double(m.xHeight)))
        w.i16(px(Double(m.capHeight)))
        w.u16(0); w.u16(0x20) // default char, break char
        w.u16(1) // max context
        return w.data
    }

    static func hmtx(glyf: TrueTypeGlyf.Built) -> Data {
        var w = ByteWriter()
        for (adv, lsb) in zip(glyf.advances, glyf.lsb) { w.u16(UInt16(max(0, adv))); w.i16(Int16(lsb)) }
        return w.data
    }

    static func loca(_ glyf: TrueTypeGlyf.Built) -> Data {
        var w = ByteWriter()
        for off in glyf.loca { w.u32(off) }
        return w.data
    }

    static func cmap() -> Data {
        let entries = FontProject.glyphOrder.enumerated().filter { $0.element != Glyph.notdefScalar }
            .map { (scalar: $0.element, index: $0.offset) }
            .sorted { $0.scalar < $1.scalar }

        var sub = ByteWriter()
        let segCount = entries.count + 1
        sub.u16(4)
        sub.u16(0) // length placeholder, fixed below
        sub.u16(0)
        sub.u16(UInt16(segCount * 2))
        let entrySelector = UInt16(log2(Double(segCount)).rounded(.down))
        sub.u16(entrySelector)
        sub.u16(UInt16(segCount * 2) - (UInt16(1) << entrySelector) * 2)
        for e in entries { sub.u16(UInt16(e.scalar)) } // endCode[]
        sub.u16(0xFFFF)                                 // endCode[] sentinel
        sub.u16(0)                                       // reservedPad
        for e in entries { sub.u16(UInt16(e.scalar)) }  // startCode[]
        sub.u16(0xFFFF)                                 // startCode[] sentinel
        for e in entries { sub.i16(Int16(truncatingIfNeeded: Int(e.index) - Int(e.scalar))) } // idDelta[]
        sub.i16(1)                                       // idDelta[] sentinel
        for _ in entries { sub.u16(0) }                  // idRangeOffset[]
        sub.u16(0)                                       // idRangeOffset[] sentinel

        var subData = sub.data
        let length = UInt16(subData.count)
        subData[2] = UInt8(length >> 8); subData[3] = UInt8(length & 0xFF)

        var w = ByteWriter()
        w.u16(0); w.u16(1)
        w.u16(3); w.u16(1); w.u32(12)
        w.append(subData)
        return w.data
    }

    static func name(_ options: ExportOptions) -> Data {
        let strings: [(UInt16, String)] = [
            (1, options.familyName), (2, options.styleName), (3, "\(options.familyName)-\(options.styleName);CrispFonter"),
            (4, "\(options.familyName) \(options.styleName)"), (5, "Version 1.0"), (6, "\(options.familyName)-\(options.styleName)".replacingOccurrences(of: " ", with: "")),
        ]
        var storage = Data()
        var records: [(UInt16, UInt16, UInt16)] = []
        for (id, s) in strings {
            let offset = UInt16(storage.count)
            let utf16 = Array(s.utf16)
            var bytes = Data()
            for u in utf16 { bytes.append(UInt8(u >> 8)); bytes.append(UInt8(u & 0xFF)) }
            storage.append(bytes)
            records.append((id, offset, UInt16(bytes.count)))
        }
        var w = ByteWriter()
        w.u16(0); w.u16(UInt16(records.count)); w.u16(UInt16(6 + records.count * 12))
        for (id, offset, len) in records {
            w.u16(3); w.u16(1); w.u16(0x0409)
            w.u16(id); w.u16(len); w.u16(offset)
        }
        w.append(storage)
        return w.data
    }

    static func post() -> Data {
        var w = ByteWriter()
        w.u32(0x00030000)
        w.u32(0)
        w.i16(0); w.i16(0)
        w.u32(1) // isFixedPitch: monospaced
        w.u32(0); w.u32(0); w.u32(0); w.u32(0)
        return w.data
    }

    static func gasp(_ options: ExportOptions) -> Data {
        var w = ByteWriter()
        w.u16(1); w.u16(2)
        w.u16(UInt16(max(0, options.gaspMonoThreshold))); w.u16(0x0001)
        w.u16(0xFFFF); w.u16(0x000F)
        return w.data
    }
}
