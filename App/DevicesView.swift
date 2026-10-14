import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var browser: TVBrowser
    @EnvironmentObject private var store: DeviceStore
    @EnvironmentObject private var session: TVSession
    @State private var showManual = false

    var body: some View {
        List {
            Section {
                if browser.devices.isEmpty {
                    emptyState
                } else {
                    ForEach(browser.devices) { tv in
                        Button {
                            openDiscovered(tv)
                        } label: {
                            deviceRow(
                                name: tv.name,
                                detail: tv.host ?? "Finding the address…",
                                enabled: tv.host != nil
                            )
                        }
                        .disabled(tv.host == nil)
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                }
            } header: {
                Text("On this network")
            } footer: {
                Text(browser.status)
            }

            if !store.devices.isEmpty {
                Section("Saved") {
                    ForEach(store.devices) { tv in
                        Button {
                            session.open(tv)
                        } label: {
                            deviceRow(name: tv.name, detail: tv.host, enabled: true)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                    .onDelete { offsets in
                        offsets.map { store.devices[$0] }.forEach(store.remove)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Room Remote")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showManual = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Enter an IP address")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    browser.restart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Search again")
            }
        }
        .sheet(isPresented: $showManual) {
            ManualAddressSheet()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(browser.localNetworkBlocked ? "Allow local network access" : "No TVs showed up")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(browser.localNetworkBlocked
                 ? "iOS blocked the search. Turn on local network access for Room Remote in Settings, then search again. You can also type the TV's IP address."
                 : "The TV needs to be on, and this iPhone has to be on the same Wi-Fi. If it still doesn't appear, type its IP address.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .listRowBackground(Theme.surface)
    }

    private func deviceRow(name: String, detail: String, enabled: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.title3)
                .foregroundStyle(Theme.brass)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            if enabled {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func openDiscovered(_ tv: DiscoveredTV) {
        guard let host = tv.host else { return }
        let saved = store.devices.first { $0.host == host && $0.commandPort == tv.commandPort }
        session.open(SavedTV(
            name: saved?.name ?? tv.name,
            host: host,
            commandPort: tv.commandPort,
            pairPort: tv.pairPort,
            paired: saved?.paired ?? false
        ))
    }
}

private struct ManualAddressSheet: View {
    @EnvironmentObject private var session: TVSession
    @EnvironmentObject private var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Living room"
    @State private var host = ""
    @State private var commandPort = "6466"
    @State private var pairPort = "6467"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("IP address", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                } footer: {
                    Text("Find the address on the TV under Settings, Network. The usual ports are 6466 for commands and 6467 for pairing.")
                }
                Section("Ports") {
                    TextField("Command port", text: $commandPort)
                        .keyboardType(.numberPad)
                    TextField("Pairing port", text: $pairPort)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Add a TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { connect() }
                        .disabled(!canConnect)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var canConnect: Bool {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains(" ") && UInt16(commandPort) != nil && UInt16(pairPort) != nil
    }

    private func connect() {
        guard let command = UInt16(commandPort), let pair = UInt16(pairPort) else { return }
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let alreadyPaired = store.devices.first { $0.host == trimmedHost && $0.commandPort == command }?.paired ?? false
        session.open(SavedTV(
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            commandPort: command,
            pairPort: pair,
            paired: alreadyPaired
        ))
        dismiss()
    }
}
