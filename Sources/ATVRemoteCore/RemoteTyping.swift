import Foundation

/// Text the phone is sending to the TV's focused field.
///
/// Each letter, digit, space, symbol, or Finnish letter updates the whole
/// field through `RemoteImeBatchEdit` and is sent immediately. Backspace
/// sends that shorter field. Clearing the last character sends `KEYCODE_DEL`,
/// because the TV ignores an empty IME value. Enter sends `KEYCODE_ENTER`.
///
/// When the TV did not grant IME, ASCII falls back to key codes. å, ä, and ö
/// have no key code, so they still go through IME.
struct RemoteTyping: Equatable {
    var text = ""
    var imeCounter: Int32 = 0
    var fieldCounter: Int32 = 0
    var imeEnabled = true

    private var appliedRemote: String?

    enum Command: Equatable {
        case ime(Data)
        case key(RemoteKey)
        case keyCode(Int)
    }

    /// Copies a text-field report from `remote_ime_key_inject`.
    mutating func focus(imeCounter: Int32, fieldCounter: Int32, value: String?) {
        self.imeCounter = imeCounter
        self.fieldCounter = fieldCounter
        if let value {
            noteRemoteText(value)
        }
    }

    /// Applies the TV's copy of the field. A repeat of the same report does
    /// nothing. A shorter non-empty report is ignored while our text still
    /// starts with it, so a late echo cannot erase a character just typed.
    mutating func noteRemoteText(_ value: String) {
        if appliedRemote == value { return }
        appliedRemote = value
        if value == text { return }
        if !value.isEmpty, text.hasPrefix(value), text.count > value.count { return }
        text = value
    }

    mutating func insert(_ character: String) -> Command? {
        guard character.count == 1, let glyph = character.first else { return nil }
        text.append(glyph)
        if imeEnabled || RemoteMessages.asciiKeyCode(glyph) == nil {
            return imeCommand()
        }
        if let code = RemoteMessages.asciiKeyCode(glyph) {
            return .keyCode(code)
        }
        return imeCommand()
    }

    mutating func backspace() -> Command {
        guard imeEnabled, !text.isEmpty else {
            if !text.isEmpty { text.removeLast() }
            return .key(.delete)
        }
        text.removeLast()
        if text.isEmpty {
            return .key(.delete)
        }
        return imeCommand() ?? .key(.delete)
    }

    func enter() -> Command {
        .key(.enter)
    }

    private func imeCommand() -> Command? {
        guard let data = RemoteMessages.text(text, imeCounter: imeCounter, fieldCounter: fieldCounter) else {
            return nil
        }
        return .ime(data)
    }
}
