import Darwin
import Foundation
import Network

struct DiscoveredTV: Identifiable, Equatable {
    var id: String
    var name: String
    var host: String?
    var commandPort: UInt16
    var pairPort: UInt16
}

@MainActor
final class TVBrowser: ObservableObject {
    @Published private(set) var devices: [DiscoveredTV] = []
    @Published private(set) var status = "Looking for Google TVs…"
    @Published private(set) var localNetworkBlocked = false

    private var browser: NWBrowser?
    private var resolvers: [String: ServiceResolver] = [:]

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_androidtvremote2._tcp", domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.apply(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let services: [(name: String, type: String, domain: String)] = results.compactMap { result in
                guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                return (name, type, domain)
            }
            Task { @MainActor in
                self?.apply(services)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.stop() }
        resolvers.removeAll()
    }

    private func apply(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            localNetworkBlocked = false
            if devices.isEmpty {
                status = "Looking for Google TVs…"
            }
        case .waiting:
            localNetworkBlocked = true
            status = "Local network access is off."
        case .failed(let error):
            status = "Search failed. \(ATVSocket.describe(error))"
        case .cancelled:
            break
        default:
            break
        }
    }

    private func apply(_ services: [(name: String, type: String, domain: String)]) {
        let ids = Set(services.map { "\($0.name)|\($0.domain)" })
        devices.removeAll { !ids.contains($0.id) }
        for id in resolvers.keys where !ids.contains(id) {
            resolvers[id]?.stop()
            resolvers[id] = nil
        }
        for service in services {
            let id = "\(service.name)|\(service.domain)"
            guard !devices.contains(where: { $0.id == id }) else { continue }
            devices.append(DiscoveredTV(id: id, name: service.name, host: nil, commandPort: 6466, pairPort: 6467))
            let resolver = ServiceResolver(name: service.name, type: service.type, domain: service.domain)
            resolver.onResolve = { [weak self] host, port in
                Task { @MainActor in
                    self?.resolved(id: id, host: host, port: port)
                }
            }
            resolvers[id] = resolver
            resolver.start()
        }
        devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if devices.isEmpty && !localNetworkBlocked {
            status = "No Google TVs yet."
        } else if !devices.isEmpty {
            status = devices.count == 1 ? "1 TV on this network" : "\(devices.count) TVs on this network"
        }
    }

    private func resolved(id: String, host: String, port: UInt16) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let pair = port == 6467 ? UInt16(6467) : port &+ 1
        devices[index].host = host
        devices[index].commandPort = port == 6467 ? 6466 : port
        devices[index].pairPort = port == 6467 ? 6467 : pair
    }
}

final class ServiceResolver: NSObject, NetServiceDelegate {
    var onResolve: ((String, UInt16) -> Void)?
    private let service: NetService

    init(name: String, type: String, domain: String) {
        service = NetService(domain: domain, type: type, name: name)
        super.init()
        service.delegate = self
    }

    func start() {
        service.resolve(withTimeout: 8)
    }

    func stop() {
        service.stop()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let port = UInt16(clamping: sender.port)
        guard port > 0, let host = Self.host(from: sender) else { return }
        onResolve?(host, port)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}

    private static func host(from service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        var ipv6: String?
        for address in addresses {
            guard let parsed = parse(address) else { continue }
            if parsed.family == AF_INET { return parsed.host }
            if ipv6 == nil { ipv6 = parsed.host }
        }
        return ipv6
    }

    private static func parse(_ data: Data) -> (family: Int32, host: String)? {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count >= MemoryLayout<sockaddr>.size else { return nil }
            let family = Int32(base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family)
            if family == AF_INET, raw.count >= MemoryLayout<sockaddr_in>.size {
                var address = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return (family, String(cString: buffer))
            }
            if family == AF_INET6, raw.count >= MemoryLayout<sockaddr_in6>.size {
                var address = base.assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                return (family, String(cString: buffer))
            }
            return nil
        }
    }
}
