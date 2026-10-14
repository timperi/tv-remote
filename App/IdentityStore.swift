import Foundation
import Security

enum IdentityError: LocalizedError {
    case keyGeneration(String)
    case signature(String)
    case certificateRejected
    case keychain(OSStatus)
    case publicKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .keyGeneration(let detail):
            return "Couldn't create the pairing key. \(detail)"
        case .signature(let detail):
            return "Couldn't sign the pairing certificate. \(detail)"
        case .certificateRejected:
            return "iOS would not accept the pairing certificate."
        case .keychain(let status):
            return "The pairing key could not be saved (keychain status \(status))."
        case .publicKeyUnavailable:
            return "The pairing certificate has no RSA public key."
        }
    }
}

/// One RSA certificate for this iPhone, kept in the Keychain so pairing happens once.
enum IdentityStore {
    static let label = "Room Remote Client"
    static let commonName = "Room Remote"
    private static let tag = Data("personal.roomremote.client-key".utf8)

    static func loadOrCreate() throws -> SecIdentity {
        if let existing = copyIdentity() { return existing }
        return try create()
    }

    static func reset() {
        delete(kSecClassKey, kSecAttrApplicationTag, tag)
        delete(kSecClassCertificate, kSecAttrLabel, label)
        delete(kSecClassIdentity, kSecAttrLabel, label)
    }

    static func components(of identity: SecIdentity) throws -> (modulus: Data, exponent: Data) {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw IdentityError.keychain(status)
        }
        return try components(of: certificate)
    }

    static func components(certificateDER: Data) -> (modulus: Data, exponent: Data)? {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else { return nil }
        return try? components(of: certificate)
    }

    private static func components(of certificate: SecCertificate) throws -> (modulus: Data, exponent: Data) {
        guard
            let key = SecCertificateCopyKey(certificate),
            let external = SecKeyCopyExternalRepresentation(key, nil) as Data?,
            let parsed = RSAPublicKey.parse(external)
        else { throw IdentityError.publicKeyUnavailable }
        return parsed
    }

    private static func copyIdentity() -> SecIdentity? {
        queryIdentity(matchingLabel: true) ?? queryIdentity(matchingLabel: false)
    }

    private static func queryIdentity(matchingLabel: Bool) -> SecIdentity? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true
        ]
        if matchingLabel {
            query[kSecAttrLabel as String] = label
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return (item as! SecIdentity)
    }

    private static func create() throws -> SecIdentity {
        reset()
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrLabel as String: label,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as [String: Any]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw IdentityError.keyGeneration(describe(error))
        }
        guard
            let publicKey = SecKeyCopyPublicKey(privateKey),
            let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else {
            throw IdentityError.keyGeneration(describe(error))
        }

        let notBefore = Date().addingTimeInterval(-60 * 60)
        let notAfter = Date().addingTimeInterval(60 * 60 * 24 * 365 * 10)
        let tbs = X509Certificate.tbsCertificate(
            commonName: commonName,
            serial: 1000,
            notBefore: notBefore,
            notAfter: notAfter,
            pkcs1PublicKey: pkcs1
        )
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbs as CFData,
            &error
        ) as Data? else {
            throw IdentityError.signature(describe(error))
        }
        let der = X509Certificate.make(
            commonName: commonName,
            serial: 1000,
            notBefore: notBefore,
            notAfter: notAfter,
            pkcs1PublicKey: pkcs1,
            signature: signature
        )
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw IdentityError.certificateRejected
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw IdentityError.keychain(status) }
        guard let identity = copyIdentity() else { throw IdentityError.keychain(errSecItemNotFound) }
        return identity
    }

    private static func delete(_ secClass: CFString, _ attribute: CFString, _ value: Any) {
        let query: [String: Any] = [
            kSecClass as String: secClass,
            attribute as String: value
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func describe(_ error: Unmanaged<CFError>?) -> String {
        guard let error else { return "Unknown error." }
        return (error.takeRetainedValue() as Error).localizedDescription
    }
}
