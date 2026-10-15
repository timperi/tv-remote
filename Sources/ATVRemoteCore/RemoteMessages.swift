import Foundation

enum RemoteKey: Int, Equatable {
    case home = 3
    case back = 4
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case enter = 66
    case delete = 67
    case playPause = 85
    case mute = 164
    case channelUp = 166
    case channelDown = 167
    /// `KEY_TV` in `TvKeys.h`, so the virtual remote injects it. Live TV does not need an app link.
    case tv = 170
    /// `KEY_EPG` in `TvKeys.h` (`AKEYCODE_GUIDE`). The virtual remote injects this too.
    case guide = 172
    /// Not injected by the virtual remote. `TvKeys.h` has no SLEEP entry, so the service drops it.
    case sleep = 223
    /// Not injected by the virtual remote. `TvKeys.h` has no WAKEUP entry, so the service drops it.
    case wakeup = 224
}

enum KeyDirection: Int, Equatable {
    case startLong = 1
    case endLong = 2
    case short = 3
}

struct RemoteFeatures: OptionSet, Equatable {
    let rawValue: Int
    static let ping = RemoteFeatures(rawValue: 1 << 0)
    static let key = RemoteFeatures(rawValue: 1 << 1)
    static let ime = RemoteFeatures(rawValue: 1 << 2)
    static let voice = RemoteFeatures(rawValue: 1 << 3)
    static let power = RemoteFeatures(rawValue: 1 << 5)
    static let volume = RemoteFeatures(rawValue: 1 << 6)
    static let appLink = RemoteFeatures(rawValue: 1 << 9)

    /// Features this remote asks for. Voice is left off; v1 doesn't stream audio.
    static let requested: RemoteFeatures = [.ping, .key, .ime, .power, .volume, .appLink]
}

struct TVState: Equatable {
    var isOn: Bool?
    var currentApp: String?
    var volumeLevel: Int?
    var volumeMax: Int?
    var isMuted: Bool?
    var imeCounter: Int32 = 0
    var fieldCounter: Int32 = 0
    /// Latest text-field contents from `remote_ime_key_inject`, when the TV sent them.
    var fieldText: String?
    var activeFeatures: RemoteFeatures = .requested
    var manufacturer: String?
    var model: String?
    var lastError: String?
}

enum AppLink {
    static let youtube = "https://www.youtube.com"
    static let netflix = "netflix://"

    /// Package ids gain the `market://launch?id=` prefix used by androidtvremote2.
    /// Strings that already have a scheme are sent unchanged. Deep links are more
    /// reliable than package ids on current Google TV builds.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return trimmed }
        return "market://launch?id=\(trimmed)"
    }
}

enum RemoteMessages {
    static func configure(features: RemoteFeatures) -> Data {
        var info = ProtoWriter()
        info.writeInt(3, 1)
        info.writeString(4, "1")
        info.writeString(5, "atvremote")
        info.writeString(6, "1.0.0")
        var body = ProtoWriter()
        body.writeInt(1, features.rawValue)
        body.writeMessage(2, info.data)
        var outer = ProtoWriter()
        outer.writeMessage(1, body.data)
        return outer.data
    }

    static func setActive(features: RemoteFeatures) -> Data {
        var body = ProtoWriter()
        body.writeInt(1, features.rawValue)
        var outer = ProtoWriter()
        outer.writeMessage(2, body.data)
        return outer.data
    }

    static func pingResponse(_ value: Int) -> Data {
        var body = ProtoWriter()
        body.writeInt(1, value)
        var outer = ProtoWriter()
        outer.writeMessage(9, body.data)
        return outer.data
    }

    static func key(_ key: RemoteKey, direction: KeyDirection) -> Data {
        keyCode(key.rawValue, direction: direction)
    }

    static func keyCode(_ code: Int, direction: KeyDirection) -> Data {
        var body = ProtoWriter()
        body.writeInt(1, code, omitZero: false)
        body.writeInt(2, direction.rawValue, omitZero: false)
        var outer = ProtoWriter()
        outer.writeMessage(10, body.data)
        return outer.data
    }

    /// ASCII letter, digit, or space as a `RemoteKeyCode`, for when the IME feature is off.
    /// Uppercase uses the same letter code as lowercase. `TvKeys.h` has no shift key.
    /// Finnish letters have no code and return nil.
    static func asciiKeyCode(_ character: Character) -> Int? {
        guard let ascii = character.asciiValue else { return nil }
        switch Int(ascii) {
        case 97...122:
            return 29 + Int(ascii) - 97
        case 65...90:
            return 29 + Int(ascii) - 65
        case 48...57:
            return 7 + Int(ascii) - 48
        case 32:
            return 62
        default:
            return nil
        }
    }

    /// Power while the command channel is connected.
    ///
    /// The remote service injects keys through the virtual remote layout in
    /// AOSP `TvKeys.h`. That layout includes `KEYCODE_POWER` (26) and does
    /// not include `KEYCODE_SLEEP` (223), `KEYCODE_WAKEUP` (224), or
    /// `KEYCODE_TV_POWER` (177), so those codes are dropped even though the
    /// socket is up. Direction is `SHORT`: one tap, not a long-press pair.
    /// `KEYCODE_POWER` toggles. The reported on/off state must not pick a
    /// different code — sending SLEEP because the TV says it is on does nothing.
    static func powerButton() -> Data {
        key(.power, direction: .short)
    }

    /// Inserts text through the TV's input method.
    /// `start` and `end` follow Android's UTF-16 length, which matches Python's
    /// `len(text) - 1` for everyday characters. Counters come from the TV.
    static func text(_ text: String, imeCounter: Int32, fieldCounter: Int32) -> Data? {
        let units = text.utf16.count
        guard units > 0 else { return nil }
        let edge = units - 1
        var ime = ProtoWriter()
        ime.writeInt(1, edge)
        ime.writeInt(2, edge)
        ime.writeString(3, text)
        var edit = ProtoWriter()
        edit.writeInt(1, 1)
        edit.writeMessage(2, ime.data)
        var batch = ProtoWriter()
        batch.writeInt(1, Int(imeCounter))
        batch.writeInt(2, Int(fieldCounter))
        batch.writeMessage(3, edit.data)
        var outer = ProtoWriter()
        outer.writeMessage(21, batch.data)
        return outer.data
    }

    static func launch(_ link: String) -> Data {
        var body = ProtoWriter()
        body.writeString(1, AppLink.normalize(link))
        var outer = ProtoWriter()
        outer.writeMessage(90, body.data)
        return outer.data
    }
}

enum RemoteIncoming {
    case configure(features: RemoteFeatures, model: String?, vendor: String?)
    case setActive
    case ping(Int)
    case started(Bool)
    case volume(level: Int, max: Int, muted: Bool)
    /// `remote_ime_key_inject`. Counters here are the live ones.
    /// `imeCounter` and `fieldCounter` are nil when this message only names the foreground app.
    /// `value` is nil when no text-field status was attached. An empty string is a real empty field.
    case imeFocus(package: String?, imeCounter: Int32?, fieldCounter: Int32?, value: String?)
    /// `remote_ime_batch_edit` echoed by the TV. Its counters stay at a placeholder and are not live.
    case imeCounters(ime: Int32, field: Int32)
    case error
    case other

    static func parse(_ data: Data) -> RemoteIncoming? {
        guard let fields = try? Proto.parse(data) else { return nil }
        if let body = Proto.bytes(fields, 1) {
            let nested = (try? Proto.parse(body)) ?? []
            let features = RemoteFeatures(rawValue: Proto.int(nested, 1) ?? 0)
            var model: String?
            var vendor: String?
            if let info = Proto.bytes(nested, 2), let infoFields = try? Proto.parse(info) {
                model = Proto.string(infoFields, 1)
                vendor = Proto.string(infoFields, 2)
            }
            return .configure(features: features, model: model, vendor: vendor)
        }
        if Proto.has(fields, 2) { return .setActive }
        if Proto.has(fields, 3) { return .error }
        if let body = Proto.bytes(fields, 8) {
            let nested = (try? Proto.parse(body)) ?? []
            return .ping(Proto.int(nested, 1) ?? 0)
        }
        if let body = Proto.bytes(fields, 20) {
            let nested = (try? Proto.parse(body)) ?? []
            var package: String?
            var ime: Int32?
            if let app = Proto.bytes(nested, 1), let appFields = try? Proto.parse(app) {
                package = Proto.string(appFields, 12)
                if Proto.has(appFields, 1) {
                    ime = int32(Proto.int(appFields, 1) ?? 0)
                }
            }
            var field: Int32?
            var value: String?
            if let status = Proto.bytes(nested, 2) {
                let statusFields = (try? Proto.parse(status)) ?? []
                // A missing counter_field is proto3's zero. Zero is a real value:
                // the foreground app has no InputConnection, and the TV still
                // accepts text by turning it into key events.
                field = int32(Proto.int(statusFields, 1) ?? 0)
                value = Proto.string(statusFields, 2) ?? ""
                if ime == nil {
                    ime = 0
                }
            }
            return .imeFocus(package: package, imeCounter: ime, fieldCounter: field, value: value)
        }
        if let body = Proto.bytes(fields, 21) {
            let nested = (try? Proto.parse(body)) ?? []
            return .imeCounters(
                ime: int32(Proto.int(nested, 1) ?? 0),
                field: int32(Proto.int(nested, 2) ?? 0)
            )
        }
        if let body = Proto.bytes(fields, 40) {
            let nested = (try? Proto.parse(body)) ?? []
            return .started(Proto.bool(nested, 1))
        }
        if let body = Proto.bytes(fields, 50) {
            let nested = (try? Proto.parse(body)) ?? []
            return .volume(
                level: Proto.int(nested, 7) ?? 0,
                max: Proto.int(nested, 6) ?? 0,
                muted: Proto.bool(nested, 8)
            )
        }
        return .other
    }
}

private func int32(_ value: Int) -> Int32 {
    if value > Int(Int32.max) { return Int32.max }
    if value < Int(Int32.min) { return Int32.min }
    return Int32(value)
}
