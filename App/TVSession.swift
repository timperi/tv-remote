import Foundation
import os

@MainActor
final class TVSession: ObservableObject {
    enum Route: Equatable {
        case devices
        case pairing
        case remote
    }

    @Published var route: Route = .devices
    @Published var deviceName = ""
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var offerPairing = false
    @Published var awaitingCode = false
    @Published var isReady = false
    @Published var isWorking = false
    @Published var isOn: Bool?
    @Published var currentApp: String?
    @Published var volumeLevel: Int?
    @Published var volumeMax: Int?
    @Published var isMuted: Bool?

    private let store: DeviceStore
    private let log = Logger(subsystem: "personal.roomremote", category: "session")
    private var device: SavedTV?
    private var socket: ATVSocket?
    private var machine: PairingMachine?
    private var tv = TVState()
    private var identity: SecIdentity?
    private var clientKey: (modulus: Data, exponent: Data)?
    private var timeout: Task<Void, Never>?
    private var generation = 0

    init(store: DeviceStore) {
        self.store = store
    }

    func open(_ device: SavedTV) {
        self.device = device
        deviceName = device.name
        errorMessage = nil
        offerPairing = false
        isReady = false
        isOn = nil
        currentApp = nil
        store.upsert(device)
        if device.paired {
            route = .remote
            connect(port: device.commandPort, pairing: false)
        } else {
            beginPairing()
        }
    }

    func beginPairing() {
        guard var device else { return }
        device.paired = false
        self.device = device
        store.upsert(device)
        route = .pairing
        awaitingCode = false
        status = "Contacting the TV…"
        machine = PairingMachine(clientName: IdentityStore.commonName)
        connect(port: device.pairPort, pairing: true)
    }

    func submit(code: String) {
        guard var machine, let clientKey, let serverDER = socket?.serverCertificateDER,
              let server = IdentityStore.components(certificateDER: serverDER) else {
            errorMessage = "The TV's certificate wasn't available. Try pairing again."
            return
        }
        let step = machine.submit(
            code: code,
            clientModulus: clientKey.modulus,
            clientExponent: clientKey.exponent,
            serverModulus: server.modulus,
            serverExponent: server.exponent
        )
        self.machine = machine
        apply(step)
    }

    func press(_ key: RemoteKey, direction: KeyDirection) {
        guard isReady else { return }
        socket?.send(RemoteMessages.key(key, direction: direction))
    }

    func power() {
        guard isReady else { return }
        socket?.send(RemoteMessages.powerButton())
    }

    func sendText(_ text: String) {
        guard isReady, let payload = RemoteMessages.text(text, imeCounter: tv.imeCounter, fieldCounter: tv.fieldCounter) else { return }
        socket?.send(payload)
    }

    func launch(_ link: String) {
        guard isReady else { return }
        socket?.send(RemoteMessages.launch(link))
    }

    func reconnect() {
        guard let device else { return }
        open(device)
    }

    func closeToList() {
        teardown()
        route = .devices
        isReady = false
        awaitingCode = false
        errorMessage = nil
    }

    func forget() {
        if let device { store.remove(device) }
        closeToList()
    }

    func resetCertificate() {
        IdentityStore.reset()
        identity = nil
        clientKey = nil
        if var device {
            device.paired = false
            self.device = device
            store.upsert(device)
        }
        beginPairing()
    }

    private func connect(port: UInt16, pairing: Bool) {
        teardown()
        generation += 1
        let token = generation
        isWorking = true
        errorMessage = nil
        status = pairing ? "Contacting the TV…" : "Connecting…"
        do {
            let identity = try ensureIdentity()
            guard let device else { return }
            let socket = ATVSocket(host: device.host, port: port, identity: identity)
            socket.onReady = { [weak self] in
                Task { @MainActor in self?.ready(token: token, pairing: pairing) }
            }
            socket.onMessage = { [weak self] data in
                Task { @MainActor in self?.receive(data, token: token, pairing: pairing) }
            }
            socket.onClosed = { [weak self] message in
                Task { @MainActor in self?.closed(message, token: token, pairing: pairing) }
            }
            self.socket = socket
            socket.start()
            armTimeout(token: token, pairing: pairing)
            let mode = pairing ? "pairing" : "command"
        log.info("Opening \(mode, privacy: .public) port \(port, privacy: .public)")
        } catch {
            isWorking = false
            errorMessage = error.localizedDescription
            status = "Couldn't prepare pairing."
        }
    }

    private func ensureIdentity() throws -> SecIdentity {
        if let identity { return identity }
        let created = try IdentityStore.loadOrCreate()
        identity = created
        clientKey = try IdentityStore.components(of: created)
        return created
    }

    private func ready(token: Int, pairing: Bool) {
        guard token == generation else { return }
        if pairing {
            guard let machine else { return }
            status = "Starting pairing…"
            socket?.send(machine.openingMessage())
        } else {
            status = "Waiting for the TV…"
        }
    }

    private func receive(_ data: Data, token: Int, pairing: Bool) {
        guard token == generation else { return }
        if pairing {
            guard var machine else { return }
            let step = machine.handle(data)
            self.machine = machine
            apply(step)
        } else {
            let replies = RemoteSession.handle(data, state: &tv)
            for reply in replies {
                socket?.send(reply)
            }
            isOn = tv.isOn
            currentApp = tv.currentApp
            volumeLevel = tv.volumeLevel
            volumeMax = tv.volumeMax
            isMuted = tv.isMuted
            if let lastError = tv.lastError {
                errorMessage = lastError
                tv.lastError = nil
            }
            if tv.isOn != nil && !isReady {
                timeout?.cancel()
                isReady = true
                isWorking = false
                status = "Connected"
                offerPairing = false
                errorMessage = nil
                if var device {
                    device.paired = true
                    self.device = device
                    store.markPaired(device)
                }
            }
        }
    }

    private func apply(_ step: PairingStep) {
        switch step {
        case .send(let data):
            if machine?.phase == .awaitingSecretAck {
                isWorking = true
                status = "Checking the code…"
            }
            socket?.send(data)
        case .promptForCode:
            timeout?.cancel()
            awaitingCode = true
            isWorking = false
            status = "Enter the code on the TV."
        case .paired:
            log.info("Paired")
            guard let device else { return }
            var paired = device
            paired.paired = true
            self.device = paired
            store.markPaired(paired)
            route = .remote
            connect(port: paired.commandPort, pairing: false)
        case .failed(let message):
            errorMessage = message
            isWorking = false
            if machine?.phase == .failed {
                status = "Pairing stopped."
            }
        }
    }

    private func closed(_ message: String?, token: Int, pairing: Bool) {
        guard token == generation else { return }
        timeout?.cancel()
        isWorking = false
        isReady = false
        let detail = message ?? "no error"
        log.error("Closed: \(detail, privacy: .public)")
        if pairing && machine?.phase == .success {
            return
        }
        if pairing {
            errorMessage = message ?? "The TV ended pairing."
            status = "Pairing stopped."
            return
        }
        let text = message ?? "The TV closed the connection."
        errorMessage = text
        status = "Not connected"
        offerPairing = ATVSocket.needsPairing(message)
    }

    private func armTimeout(token: Int, pairing: Bool) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.timedOut(token: token, pairing: pairing)
        }
    }

    private func timedOut(token: Int, pairing: Bool) {
        guard token == generation, !isReady, machine?.phase != .awaitingCode else { return }
        generation += 1
        socket?.cancel()
        isWorking = false
        isReady = false
        errorMessage = "The TV didn't answer. Check that it's on and on this Wi-Fi."
        status = pairing ? "Pairing stopped." : "Not connected"
        offerPairing = !pairing
    }

    private func teardown() {
        timeout?.cancel()
        socket?.cancel()
        socket = nil
        tv = TVState()
    }
}
