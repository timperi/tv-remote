import Foundation
import Network
import Security

/// TLS socket to one Android TV Remote v2 port. The TV uses a self-signed
/// certificate, and this phone presents the Keychain client identity.
final class ATVSocket {
    var onReady: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    var onClosed: ((String?) -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let certificates: CertCapture
    private var decoder = FrameDecoder()
    private var didStart = false
    private var finished = false

    var serverCertificateDER: Data? { certificates.copy() }

    init(host: String, port: UInt16, identity: SecIdentity) {
        let queue = DispatchQueue(label: "personal.roomremote.socket")
        let certificates = CertCapture()
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
               let leaf = chain.first {
                certificates.store(SecCertificateCopyData(leaf) as Data)
            }
            complete(true)
        }, queue)

        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
            sec_protocol_options_set_challenge_block(tls.securityProtocolOptions, { _, complete in
                complete(secIdentity)
            }, queue)
        }

        let endpointPort = NWEndpoint.Port(integerLiteral: port)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: NWParameters(tls: tls)
        )
        self.queue = queue
        self.certificates = certificates
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
        connection.start(queue: queue)
    }

    func send(_ message: Data) {
        connection.send(content: FrameDecoder.frame(message), completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.queue.async {
                self.finish(Self.describe(error))
            }
        })
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.finished = true
            self.connection.cancel()
        }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            guard !didStart else { return }
            didStart = true
            onReady?()
            receive()
        case .failed(let error):
            finish(Self.describe(error))
        case .cancelled:
            finish(nil)
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    let messages = try self.decoder.feed(data)
                    for message in messages {
                        self.onMessage?(message)
                    }
                } catch {
                    self.finish("The TV sent a message this app couldn't read.")
                    return
                }
            }
            if let error {
                self.finish(Self.describe(error))
                return
            }
            if isComplete {
                self.finish(nil)
                return
            }
            self.receive()
        }
    }

    private func finish(_ message: String?) {
        guard !finished else { return }
        finished = true
        connection.cancel()
        onClosed?(message)
    }

    static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED:
                return "The TV refused the connection. Turn it on, and check that Android TV Remote Service is installed."
            case .ETIMEDOUT:
                return "The TV didn't answer in time."
            case .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN:
                return "Can't reach the TV. The iPhone and the TV need to be on the same Wi-Fi."
            case .ECONNRESET:
                return "The TV closed the connection."
            default:
                return "The connection failed (\(code))."
            }
        case .tls:
            return "The secure connection was rejected."
        case .dns:
            return "Couldn't look up that address."
        @unknown default:
            return "The connection failed."
        }
    }

    /// True when the failure looks like "this certificate is not paired" rather than "TV is off".
    static func needsPairing(_ message: String?) -> Bool {
        guard let message else { return true }
        let lowered = message.lowercased()
        return lowered.contains("secure") || lowered.contains("closed") || lowered.contains("rejected")
    }
}

private final class CertCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var der: Data?

    func store(_ data: Data) {
        lock.lock()
        der = data
        lock.unlock()
    }

    func copy() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return der
    }
}
