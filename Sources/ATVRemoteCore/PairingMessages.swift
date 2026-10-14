import Foundation

/// Pairing messages from polo.proto (proto2), OuterMessage protocol_version 2.
/// Field numbers follow the schema: service_name is 1, client_name is 2.
enum PairingMessages {
    static let serviceName = "atvremote"
    static let hexadecimal = 3
    static let roleInput = 1
    static let symbolLength = 6
    static let statusOK = 200

    static func request(clientName: String) -> Data {
        var outer = ProtoWriter()
        outer.writeInt(1, 2, omitZero: false)
        outer.writeInt(2, statusOK, omitZero: false)
        var body = ProtoWriter()
        body.writeString(1, serviceName)
        body.writeString(2, clientName)
        outer.writeMessage(10, body.data)
        return outer.data
    }

    static func options() -> Data {
        var outer = ProtoWriter()
        outer.writeInt(1, 2, omitZero: false)
        outer.writeInt(2, statusOK, omitZero: false)
        var encoding = ProtoWriter()
        encoding.writeInt(1, hexadecimal, omitZero: false)
        encoding.writeInt(2, symbolLength, omitZero: false)
        var body = ProtoWriter()
        body.writeMessage(1, encoding.data)
        body.writeInt(3, roleInput, omitZero: false)
        outer.writeMessage(20, body.data)
        return outer.data
    }

    static func configuration() -> Data {
        var outer = ProtoWriter()
        outer.writeInt(1, 2, omitZero: false)
        outer.writeInt(2, statusOK, omitZero: false)
        var encoding = ProtoWriter()
        encoding.writeInt(1, hexadecimal, omitZero: false)
        encoding.writeInt(2, symbolLength, omitZero: false)
        var body = ProtoWriter()
        body.writeMessage(1, encoding.data)
        body.writeInt(2, roleInput, omitZero: false)
        outer.writeMessage(30, body.data)
        return outer.data
    }

    static func secret(_ digest: Data) -> Data {
        var outer = ProtoWriter()
        outer.writeInt(1, 2, omitZero: false)
        outer.writeInt(2, statusOK, omitZero: false)
        var body = ProtoWriter()
        body.writeBytes(1, digest)
        outer.writeMessage(40, body.data)
        return outer.data
    }
}

struct PairingIncoming: Equatable {
    var status: Int
    var hasPairingRequestAck: Bool
    var hasOptions: Bool
    var hasConfigurationAck: Bool
    var hasSecretAck: Bool
    var serverName: String?

    static func parse(_ data: Data) -> PairingIncoming? {
        guard let fields = try? Proto.parse(data) else { return nil }
        let ack = Proto.bytes(fields, 11)
        var serverName: String?
        if let ack, let nested = try? Proto.parse(ack) {
            serverName = Proto.string(nested, 1)
        }
        return PairingIncoming(
            status: Proto.int(fields, 2) ?? 0,
            hasPairingRequestAck: Proto.has(fields, 11),
            hasOptions: Proto.has(fields, 20),
            hasConfigurationAck: Proto.has(fields, 31),
            hasSecretAck: Proto.has(fields, 41),
            serverName: serverName
        )
    }

    var statusDescription: String {
        switch status {
        case 200: return "OK"
        case 400: return "The TV rejected the pairing request."
        case 401: return "The TV rejected the pairing configuration."
        case 402: return "The TV rejected that code."
        default: return "The TV returned status \(status)."
        }
    }
}
