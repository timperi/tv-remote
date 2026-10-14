import Foundation

struct SavedTV: Codable, Identifiable, Equatable {
    var id: String { "\(host):\(commandPort)" }
    var name: String
    var host: String
    var commandPort: UInt16
    var pairPort: UInt16
    var paired: Bool
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [SavedTV] = []
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: Key.devices),
           let decoded = try? JSONDecoder().decode([SavedTV].self, from: data) {
            devices = decoded
        }
        if defaults.object(forKey: Key.haptics) == nil {
            hapticsEnabled = true
        } else {
            hapticsEnabled = defaults.bool(forKey: Key.haptics)
        }
    }

    func upsert(_ device: SavedTV) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.insert(device, at: 0)
        }
        persist()
    }

    func remove(_ device: SavedTV) {
        devices.removeAll { $0.id == device.id }
        persist()
    }

    func markPaired(_ device: SavedTV) {
        var updated = device
        updated.paired = true
        upsert(updated)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Key.devices)
        }
    }

    private enum Key {
        static let devices = "savedTVs"
        static let haptics = "hapticsEnabled"
    }
}
