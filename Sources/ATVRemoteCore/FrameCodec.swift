import Foundation

enum FrameError: Error, Equatable {
    case badLength
    case messageTooLarge
}

/// Android TV Remote v2 frames each protobuf message with a protobuf varint length.
struct FrameDecoder {
    static let maximumMessageLength = 256 * 1024

    private var buffer = Data()

    mutating func feed(_ chunk: Data) throws -> [Data] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)
        var messages: [Data] = []
        while true {
            guard let (length, header) = try Self.peekLength(buffer) else { break }
            guard length <= Self.maximumMessageLength else {
                buffer.removeAll()
                throw FrameError.messageTooLarge
            }
            let total = header + length
            guard buffer.count >= total else { break }
            messages.append(buffer.subdata(in: header..<total))
            buffer.removeSubrange(0..<total)
        }
        return messages
    }

    static func frame(_ message: Data) -> Data {
        var writer = ProtoWriter()
        writer.writeVarint(UInt64(message.count))
        writer.append(message)
        return writer.data
    }

    /// Returns nil when the varint, or the body it describes, is not fully buffered yet.
    private static func peekLength(_ data: Data) throws -> (length: Int, header: Int)? {
        let bytes = [UInt8](data)
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = 0
        while index < bytes.count && index < 5 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                guard value <= UInt64(Int.max) else { throw FrameError.badLength }
                return (Int(value), index)
            }
            shift += 7
        }
        if index >= 5 { throw FrameError.badLength }
        return nil
    }
}
