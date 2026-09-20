import Foundation

/// Minimal big-endian byte writer, the only primitive the TrueType tables need.
struct ByteWriter {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { data.append(UInt8(v >> 8)); data.append(UInt8(v & 0xFF)) }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func u32(_ v: UInt32) { data.append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    /// A 4-byte tag, e.g. "head".
    mutating func tag(_ s: String) { data.append(contentsOf: Array(s.utf8.prefix(4))) }
    /// Fixed-length ASCII, padded/truncated to `len` bytes.
    mutating func ascii(_ s: String, _ len: Int) {
        var bytes = Array(s.utf8.prefix(len))
        while bytes.count < len { bytes.append(0) }
        data.append(contentsOf: bytes)
    }
    mutating func pad(to alignment: Int) { while data.count % alignment != 0 { u8(0) } }
    mutating func append(_ other: Data) { data.append(other) }
}

extension Data {
    /// TrueType table checksum: sum of the table's bytes as big-endian UInt32 words, padded with zero bytes.
    var ttfChecksum: UInt32 {
        var sum: UInt32 = 0
        var padded = self
        while padded.count % 4 != 0 { padded.append(0) }
        var i = padded.startIndex
        while i < padded.endIndex {
            let word = (UInt32(padded[i]) << 24) | (UInt32(padded[i + 1]) << 16) | (UInt32(padded[i + 2]) << 8) | UInt32(padded[i + 3])
            sum = sum &+ word
            i = padded.index(i, offsetBy: 4)
        }
        return sum
    }
}
