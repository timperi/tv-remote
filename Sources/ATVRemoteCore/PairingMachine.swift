import Foundation

enum PairingPhase: Equatable {
    case awaitingAck
    case awaitingOptions
    case awaitingConfigAck
    case awaitingCode
    case awaitingSecretAck
    case success
    case failed
}

enum PairingStep: Equatable {
    case send(Data)
    case promptForCode
    case paired
    case failed(String)
}

/// Drives the pairing handshake independently of the socket.
/// The phone is the input device: the TV displays a hexadecimal code, the user types it here.
struct PairingMachine {
    private(set) var phase: PairingPhase = .awaitingAck
    let clientName: String

    init(clientName: String) {
        self.clientName = clientName
    }

    func openingMessage() -> Data {
        PairingMessages.request(clientName: clientName)
    }

    mutating func handle(_ payload: Data) -> PairingStep {
        guard let message = PairingIncoming.parse(payload) else {
            phase = .failed
            return .failed("The TV sent a pairing message this app couldn't read.")
        }
        guard message.status == PairingMessages.statusOK else {
            phase = .failed
            return .failed(message.statusDescription)
        }
        switch phase {
        case .awaitingAck:
            guard message.hasPairingRequestAck else { return unexpected() }
            phase = .awaitingOptions
            return .send(PairingMessages.options())
        case .awaitingOptions:
            guard message.hasOptions else { return unexpected() }
            phase = .awaitingConfigAck
            return .send(PairingMessages.configuration())
        case .awaitingConfigAck:
            guard message.hasConfigurationAck else { return unexpected() }
            phase = .awaitingCode
            return .promptForCode
        case .awaitingSecretAck:
            guard message.hasSecretAck else { return unexpected() }
            phase = .success
            return .paired
        case .awaitingCode, .success, .failed:
            return .failed("Pairing received a message at the wrong time.")
        }
    }

    mutating func submit(
        code: String,
        clientModulus: Data,
        clientExponent: Data,
        serverModulus: Data,
        serverExponent: Data
    ) -> PairingStep {
        guard phase == .awaitingCode else {
            return .failed("Wait until the code is on the TV, then enter it.")
        }
        do {
            let digest = try PairingSecret.make(
                clientModulus: clientModulus,
                clientExponent: clientExponent,
                serverModulus: serverModulus,
                serverExponent: serverExponent,
                code: code
            )
            phase = .awaitingSecretAck
            return .send(PairingMessages.secret(digest))
        } catch PairingSecretError.checksumMismatch {
            return .failed("That code doesn't match the TV. Check the six characters and try again.")
        } catch {
            return .failed("Enter the six-character code shown on the TV. Use digits and A through F.")
        }
    }

    private mutating func unexpected() -> PairingStep {
        phase = .failed
        return .failed("The TV sent an unexpected pairing message.")
    }
}
