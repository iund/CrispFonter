import Foundation

/// A tiny TrueType instruction assembler — just the opcodes the build spec's hint compiler needs
/// (§6): PUSHB/PUSHW/NPUSHB, SVTCA, SRP0/1/2, MDAP, MIAP, MDRP, MIRP, ALIGNRP, SHP, IUP, RTG,
/// RUTG, RDTG, MPPEM, GT, IF/EIF, INSTCTRL, SCANCTRL, SCANTYPE. Byte values are from the OpenType
/// TrueType instruction set reference.
struct Program {
    private(set) var bytes: [UInt8] = []
    var data: Data { Data(bytes) }

    private mutating func raw(_ b: UInt8) { bytes.append(b) }

    /// Pushes a list of non-negative 16-bit values (point numbers, cvt indices), picking the most
    /// compact PUSHB/PUSHW form.
    mutating func push(_ values: [Int]) {
        guard !values.isEmpty else { return }
        let asBytes = values.allSatisfy { $0 >= 0 && $0 <= 0xFF }
        if values.count <= 8 {
            raw((asBytes ? 0xB0 : 0xB8) + UInt8(values.count - 1))
        } else {
            raw(asBytes ? 0x40 : 0x41) // NPUSHB / NPUSHW
            raw(UInt8(values.count))
        }
        for v in values {
            if asBytes { raw(UInt8(v)) } else { raw(UInt8((v >> 8) & 0xFF)); raw(UInt8(v & 0xFF)) }
        }
    }
    mutating func push(_ value: Int) { push([value]) }

    // MARK: Opcodes used by the hint compiler

    mutating func svtca(y: Bool) { raw(y ? 0x00 : 0x01) }
    mutating func srp0() { raw(0x10) }
    mutating func srp1() { raw(0x11) }
    mutating func srp2() { raw(0x12) }
    mutating func rtg() { raw(0x18) }
    mutating func rutg() { raw(0x7C) }
    mutating func rdtg() { raw(0x7D) }
    mutating func mdap(round: Bool) { raw(round ? 0x2F : 0x2E) }
    mutating func miap(round: Bool) { raw(round ? 0x3F : 0x3E) }
    mutating func iup(y: Bool) { raw(y ? 0x30 : 0x31) }
    mutating func alignrp() { raw(0x3C) }
    /// SHP[a]: shift a point to align with rp2 (a = true) or rp1 (a = false).
    mutating func shp(useRp2: Bool) { raw(useRp2 ? 0x32 : 0x33) }
    mutating func mppem() { raw(0x4B) }
    mutating func gt() { raw(0x52) }
    mutating func ifOp() { raw(0x58) }
    mutating func eif() { raw(0x59) }
    mutating func scanctrl() { raw(0x85) }
    mutating func scantype() { raw(0x8D) }
    mutating func instctrl() { raw(0x8E) }

    /// MDRP[abcde]: move a point relative to rp0, distance taken from the outline itself.
    mutating func mdrp(setRp0: Bool = false, minimum: Bool = true, round: Bool = true, distanceType: UInt8 = 1) {
        raw(0xC0 | flags(setRp0, minimum, round, distanceType))
    }
    /// MIRP[abcde]: move a point relative to rp0, distance taken from a cvt entry.
    mutating func mirp(setRp0: Bool = true, minimum: Bool = true, round: Bool = true, distanceType: UInt8 = 1) {
        raw(0xE0 | flags(setRp0, minimum, round, distanceType))
    }
    private func flags(_ a: Bool, _ b: Bool, _ c: Bool, _ de: UInt8) -> UInt8 {
        (a ? 0x10 : 0) | (b ? 0x08 : 0) | (c ? 0x04 : 0) | (de & 0x03)
    }
}
