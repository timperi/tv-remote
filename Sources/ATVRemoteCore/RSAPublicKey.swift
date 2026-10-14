import Foundation

/// Parses an RSA public key from Apple's `SecKeyCopyExternalRepresentation`
/// (PKCS#1) or from a SubjectPublicKeyInfo wrapper.
enum RSAPublicKey {
    static func parse(_ der: Data) -> (modulus: Data, exponent: Data)? {
        var reader = DERReader(bytes: [UInt8](der))
        guard let body = try? reader.tlv(tag: 0x30), reader.isAtEnd else { return nil }
        guard let first = body.first else { return nil }
        if first == 0x02 {
            return integers(body)
        }
        if first == 0x30 {
            return parseSubjectPublicKeyInfo(body)
        }
        return nil
    }

    private static func parseSubjectPublicKeyInfo(_ body: [UInt8]) -> (modulus: Data, exponent: Data)? {
        var reader = DERReader(bytes: body)
        guard (try? reader.tlv(tag: 0x30)) != nil else { return nil }
        guard let bitString = try? reader.tlv(tag: 0x03), reader.isAtEnd, !bitString.isEmpty else { return nil }
        // The first byte is the count of unused bits. A key uses none.
        guard bitString[0] == 0 else { return nil }
        return parse(Data(bitString.dropFirst()))
    }

    private static func integers(_ body: [UInt8]) -> (modulus: Data, exponent: Data)? {
        var reader = DERReader(bytes: body)
        guard
            let modulus = try? reader.tlv(tag: 0x02),
            let exponent = try? reader.tlv(tag: 0x02),
            reader.isAtEnd
        else { return nil }
        return (PairingSecret.normalizedInteger(Data(modulus)), PairingSecret.normalizedInteger(Data(exponent)))
    }
}

struct DERReader {
    let bytes: [UInt8]
    var index = 0

    var isAtEnd: Bool { index >= bytes.count }

    mutating func tlv(tag expected: UInt8) throws -> [UInt8] {
        guard index < bytes.count else { throw ProtoError.truncated }
        let tag = bytes[index]
        index += 1
        guard tag == expected else { throw ProtoError.unsupportedWire(Int(tag)) }
        let length = try length()
        guard index + length <= bytes.count else { throw ProtoError.truncated }
        let payload = Array(bytes[index..<(index + length)])
        index += length
        return payload
    }

    private mutating func length() throws -> Int {
        guard index < bytes.count else { throw ProtoError.truncated }
        let first = bytes[index]
        index += 1
        if first < 0x80 { return Int(first) }
        let count = Int(first & 0x7F)
        guard count > 0, count <= 3, index + count <= bytes.count else { throw ProtoError.overflow }
        var value = 0
        for _ in 0..<count {
            value = (value << 8) | Int(bytes[index])
            index += 1
        }
        return value
    }
}
