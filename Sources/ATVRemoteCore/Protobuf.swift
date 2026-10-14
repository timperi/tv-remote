import Foundation

enum ProtoError: Error, Equatable {
    case truncated
    case overflow
    case unsupportedWire(Int)
}

struct ProtoField: Equatable {
    var number: Int
    var varint: UInt64?
    var bytes: Data?
}

/// Minimal protobuf codec for the two Android TV Remote v2 schemas.
/// Numeric zero, false, and empty strings are omitted, matching proto3.
/// Callers that need an explicitly present empty message use `writeMessage`.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func append(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func writeVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    mutating func writeTag(field: Int, wire: Int) {
        writeVarint(UInt64((field << 3) | wire))
    }

    mutating func writeInt(_ field: Int, _ value: Int, omitZero: Bool = true) {
        if omitZero && value == 0 { return }
        writeTag(field: field, wire: 0)
        if value < 0 {
            // Protobuf int32/int64 values are sign-extended to 64 bits.
            writeVarint(UInt64(bitPattern: Int64(value)))
        } else {
            writeVarint(UInt64(value))
        }
    }

    mutating func writeBool(_ field: Int, _ value: Bool) {
        guard value else { return }
        writeTag(field: field, wire: 0)
        writeVarint(1)
    }

    mutating func writeString(_ field: Int, _ value: String) {
        let bytes = Data(value.utf8)
        guard !bytes.isEmpty else { return }
        writeBytes(field, bytes)
    }

    mutating func writeBytes(_ field: Int, _ value: Data) {
        writeTag(field: field, wire: 2)
        writeVarint(UInt64(value.count))
        data.append(value)
    }

    /// Writes a length-delimited submessage, including a zero-length one.
    mutating func writeMessage(_ field: Int, _ body: Data) {
        writeBytes(field, body)
    }
}

enum Proto {
    static func parse(_ data: Data) throws -> [ProtoField] {
        var reader = Reader(bytes: [UInt8](data))
        var fields: [ProtoField] = []
        while !reader.isAtEnd {
            let key = try reader.varint()
            let field = Int(key >> 3)
            let wire = Int(key & 0x07)
            switch wire {
            case 0:
                let value = try reader.varint()
                fields.append(ProtoField(number: field, varint: value, bytes: nil))
            case 1:
                _ = try reader.take(8)
            case 2:
                let length = try reader.varint()
                guard length <= UInt64(Int.max) else { throw ProtoError.overflow }
                let payload = try reader.take(Int(length))
                fields.append(ProtoField(number: field, varint: nil, bytes: Data(payload)))
            case 5:
                _ = try reader.take(4)
            default:
                throw ProtoError.unsupportedWire(wire)
            }
        }
        return fields
    }

    static func int(_ fields: [ProtoField], _ number: Int) -> Int? {
        guard let raw = fields.first(where: { $0.number == number })?.varint else { return nil }
        guard raw <= UInt64(Int.max) else { return nil }
        return Int(raw)
    }

    static func bool(_ fields: [ProtoField], _ number: Int) -> Bool {
        (fields.first(where: { $0.number == number })?.varint ?? 0) != 0
    }

    static func bytes(_ fields: [ProtoField], _ number: Int) -> Data? {
        fields.first(where: { $0.number == number })?.bytes
    }

    static func string(_ fields: [ProtoField], _ number: Int) -> String? {
        guard let data = bytes(fields, number) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func has(_ fields: [ProtoField], _ number: Int) -> Bool {
        fields.contains { $0.number == number }
    }
}

private struct Reader {
    let bytes: [UInt8]
    var index = 0

    var isAtEnd: Bool { index >= bytes.count }

    mutating func byte() throws -> UInt8 {
        guard index < bytes.count else { throw ProtoError.truncated }
        let value = bytes[index]
        index += 1
        return value
    }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, index + count <= bytes.count else { throw ProtoError.truncated }
        let slice = Array(bytes[index..<(index + count)])
        index += count
        return slice
    }

    mutating func varint() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            let byte = try byte()
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        throw ProtoError.overflow
    }
}
