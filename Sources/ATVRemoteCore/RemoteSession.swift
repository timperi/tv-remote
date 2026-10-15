import Foundation

/// Applies one remote-protocol message to `state` and returns the replies to send.
/// The TV speaks first: configure, set-active, then a start message and pings.
enum RemoteSession {
    static func handle(_ payload: Data, state: inout TVState) -> [Data] {
        guard let message = RemoteIncoming.parse(payload) else { return [] }
        switch message {
        case .configure(let supported, let model, let vendor):
            state.model = model
            state.manufacturer = vendor
            state.activeFeatures = RemoteFeatures.requested.intersection(supported)
            return [RemoteMessages.configure(features: state.activeFeatures)]
        case .setActive:
            return [RemoteMessages.setActive(features: state.activeFeatures)]
        case .ping(let value):
            return [RemoteMessages.pingResponse(value)]
        case .started(let on):
            state.isOn = on
            return []
        case .volume(let level, let max, let muted):
            state.volumeLevel = level
            state.volumeMax = max
            state.isMuted = muted
            return []
        case .imeFocus(let package, let ime, let field, let value):
            if let package, !package.isEmpty {
                state.currentApp = package
            }
            // Live counters ride on key-inject. The batch-edit echo is a stale
            // placeholder (often 1, 1); copying it makes the TV drop the edit.
            if let ime { state.imeCounter = ime }
            if let field { state.fieldCounter = field }
            if let value { state.fieldText = value }
            return []
        case .imeCounters:
            return []
        case .error:
            state.lastError = "The TV rejected the last command."
            return []
        case .other:
            return []
        }
    }
}
