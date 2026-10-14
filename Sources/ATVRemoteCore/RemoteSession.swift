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
        case .imeApp(let package):
            if let package, !package.isEmpty {
                state.currentApp = package
            }
            return []
        case .imeCounters(let ime, let field):
            state.imeCounter = ime
            state.fieldCounter = field
            return []
        case .error:
            state.lastError = "The TV rejected the last command."
            return []
        case .other:
            return []
        }
    }
}
