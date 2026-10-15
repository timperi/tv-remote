import SwiftUI
import UIKit

@main
struct RoomRemoteApp: App {
    @UIApplicationDelegateAdaptor(RoomRemoteDelegate.self) private var appDelegate
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

/// The keyboard screen widens this mask. Every other screen stays portrait.
enum InterfaceOrientation {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class RoomRemoteDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        InterfaceOrientation.mask
    }
}
