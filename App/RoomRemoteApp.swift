import SwiftUI

@main
struct RoomRemoteApp: App {
    @StateObject private var store: DeviceStore
    @StateObject private var browser: TVBrowser
    @StateObject private var session: TVSession

    init() {
        let store = DeviceStore()
        _store = StateObject(wrappedValue: store)
        _browser = StateObject(wrappedValue: TVBrowser())
        _session = StateObject(wrappedValue: TVSession(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(browser)
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.brass)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var browser: TVBrowser
    @EnvironmentObject private var session: TVSession

    var body: some View {
        NavigationStack {
            Group {
                switch session.route {
                case .devices:
                    DevicesView()
                case .pairing:
                    PairingView()
                case .remote:
                    RemoteView()
                }
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .onAppear { browser.start() }
    }
}
