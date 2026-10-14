import Foundation

/// Builds a minimal self-signed X.509 certificate.
///
/// The shape matches the certificate `androidtvremote2` generates with the
/// `cryptography` library: version 3, SHA-256 with RSA, UTF-8 common name,
/// a CA basic constraint with path length 0, and a DNS subject alternative name.
/// The caller supplies the PKCS#1 public key and the RSA signature over the
/// TBS bytes. On iPhone that signature comes from `SecKeyCreateSignature`.
enum X509Certificate {
    static func make(
        commonName: String,
        serial: UInt64,
        notBefore: Date,
        notAfter: Date,
        pkcs1PublicKey: Data,
        signature: Data
    ) -> Data {
        let tbs = tbsCertificate(
            commonName: commonName,
            serial: serial,
            notBefore: notBefore,
            notAfter: notAfter,
            pkcs1PublicKey: pkcs1PublicKey
        )
        return DER.sequence([tbs, sha256WithRSAEncryption, DER.bitString(signature)])
    }

    static func tbsCertificate(
        commonName: String,
        serial: UInt64,
        notBefore: Date,
        notAfter: Date,
        pkcs1PublicKey: Data
    ) -> Data {
        let name = distinguishedName(commonName)
        let validity = DER.sequence([time(notBefore), time(notAfter)])
        let extensions = DER.context(3, DER.sequence([basicConstraints, subjectAlternativeName(commonName)]))
        return DER.sequence([
            DER.context(0, DER.integer(2)),
            DER.integer(serial),
            sha256WithRSAEncryption,
            name,
            validity,
            name,
            subjectPublicKeyInfo(pkcs1PublicKey),
            extensions
        ])
    }

    private static func distinguishedName(_ commonName: String) -> Data {
        let attribute = DER.sequence([
            Data([0x06, 0x03, 0x55, 0x04, 0x03]),
            DER.tag(0x0C, Data(commonName.utf8))
        ])
        return DER.sequence([DER.tag(0x31, attribute)])
    }

    private static func subjectPublicKeyInfo(_ pkcs1: Data) -> Data {
        DER.sequence([rsaEncryption, DER.bitString(pkcs1)])
    }

    private static var basicConstraints: Data {
        // SEQUENCE { BOOLEAN TRUE, INTEGER 0 }, not critical.
        let value = Data([0x30, 0x06, 0x01, 0x01, 0xFF, 0x02, 0x01, 0x00])
        return DER.sequence([
            Data([0x06, 0x03, 0x55, 0x1D, 0x13]),
            DER.tag(0x04, value)
        ])
    }

    private static func subjectAlternativeName(_ dns: String) -> Data {
        let generalName = DER.tag(0x82, Data(dns.utf8))
        return DER.sequence([
            Data([0x06, 0x03, 0x55, 0x1D, 0x11]),
            DER.tag(0x04, DER.sequence([generalName]))
        ])
    }

    private static func time(_ date: Date) -> Data {
        let calendar = utcCalendar
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        if year >= 2050 || year < 1950 {
            let text = String(format: "%04d%02d%02d%02d%02d%02dZ", year, month, day, hour, minute, second)
            return DER.tag(0x18, Data(text.utf8))
        }
        let text = String(format: "%02d%02d%02d%02d%02d%02dZ", year % 100, month, day, hour, minute, second)
        return DER.tag(0x17, Data(text.utf8))
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()

    /// OID 1.2.840.113549.1.1.11
    private static let sha256WithRSAEncryption = DER.sequence([
        Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]),
        Data([0x05, 0x00])
    ])

    /// OID 1.2.840.113549.1.1.1
    private static let rsaEncryption = DER.sequence([
        Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]),
        Data([0x05, 0x00])
    ])
}

enum DER {
    static func tag(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    static func sequence(_ parts: [Data]) -> Data {
        tag(0x30, concat(parts))
    }

    static func context(_ number: UInt8, _ content: Data) -> Data {
        tag(0xA0 | number, content)
    }

    static func bitString(_ payload: Data) -> Data {
        tag(0x03, Data([0x00]) + payload)
    }

    static func integer(_ value: UInt64) -> Data {
        if value == 0 { return Data([0x02, 0x01, 0x00]) }
        var bytes = [UInt8]()
        var rest = value
        while rest > 0 {
            bytes.insert(UInt8(rest & 0xFF), at: 0)
            rest >>= 8
        }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return tag(0x02, Data(bytes))
    }

    static func length(_ value: Int) -> Data {
        if value < 128 { return Data([UInt8(value)]) }
        var rest = value
        var bytes = [UInt8]()
        while rest > 0 {
            bytes.insert(UInt8(rest & 0xFF), at: 0)
            rest >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    private static func concat(_ parts: [Data]) -> Data {
        var out = Data()
        for part in parts { out.append(part) }
        return out
    }
}
