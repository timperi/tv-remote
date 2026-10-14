import Foundation

enum PairingSecretError: Error, Equatable {
    case invalidCode
    case checksumMismatch
}

/// Polo pairing secret used by Android TV Remote protocol v2.
///
/// `alpha` is SHA-256 of, in order:
/// client RSA modulus, client exponent, server modulus, server exponent, nonce.
/// Each integer is the big-endian magnitude with leading 0x00 bytes removed,
/// matching `PoloChallengeResponse.getAlpha` in AOSP's google-tv-pairing-protocol.
///
/// The TV shows a 6-digit hexadecimal code. The first byte is `alpha[0]` and the
/// other two bytes are the nonce. The value sent in `Secret` is the full 32-byte
/// digest. This is what `androidtvremote2` (pairing.py) sends; it is not the older
/// Polo "gamma" (digest prefix concatenated with the nonce).
enum PairingSecret {
    static func normalizedInteger(_ data: Data) -> Data {
        let stripped = Data(data.drop(while: { $0 == 0 }))
        return stripped.isEmpty ? Data([0]) : stripped
    }

    static func digest(
        clientModulus: Data,
        clientExponent: Data,
        serverModulus: Data,
        serverExponent: Data,
        nonce: Data
    ) -> Data {
        var material = Data()
        material.append(normalizedInteger(clientModulus))
        material.append(normalizedInteger(clientExponent))
        material.append(normalizedInteger(serverModulus))
        material.append(normalizedInteger(serverExponent))
        material.append(nonce)
        return SHA256Hash.digest(material)
    }

    /// `code` is the six hexadecimal characters shown on the TV.
    static func make(
        clientModulus: Data,
        clientExponent: Data,
        serverModulus: Data,
        serverExponent: Data,
        code: String
    ) throws -> Data {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit), let raw = Data(hex: cleaned) else {
            throw PairingSecretError.invalidCode
        }
        let nonce = raw.dropFirst()
        let hash = digest(
            clientModulus: clientModulus,
            clientExponent: clientExponent,
            serverModulus: serverModulus,
            serverExponent: serverExponent,
            nonce: Data(nonce)
        )
        guard hash.first == raw.first else { throw PairingSecretError.checksumMismatch }
        return hash
    }
}

extension Data {
    init?(hex: String) {
        let scalars = Array(hex)
        guard scalars.count.isMultiple(of: 2) else { return nil }
        var out = Data(capacity: scalars.count / 2)
        var index = 0
        while index < scalars.count {
            guard let byte = UInt8(String(scalars[index...index + 1]), radix: 16) else { return nil }
            out.append(byte)
            index += 2
        }
        self = out
    }

    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
