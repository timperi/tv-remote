import SwiftUI
import UIKit

struct RemoteView: View {
    @EnvironmentObject private var session: TVSession
    @EnvironmentObject private var store: DeviceStore
    @State private var touchpad = false
    @State private var showKeyboard = false

    var body: some View {
        Group {
            if session.isReady {
                controls
            } else {
                connecting
            }
        }
        .background(Theme.background)
        .navigationTitle(session.deviceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("TVs") { session.closeToList() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Haptics", isOn: $store.hapticsEnabled)
                    Button("Pair again") { session.beginPairing() }
                    Button("Forget this TV", role: .destructive) { session.forget() }
                    Button("Reset pairing certificate", role: .destructive) { session.resetCertificate() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Remote options")
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var connecting: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session.status.isEmpty ? "Connecting…" : session.status)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
            if session.isWorking {
                ProgressView()
                    .tint(Theme.brass)
            }
            if let error = session.errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.isWorking {
                Button("Try again") { session.reconnect() }
                    .buttonStyle(.borderedProminent)
                if session.offerPairing {
                    Button("Pair with this TV") { session.beginPairing() }
                        .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            statusRow
            appRow
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if touchpad {
                        touchSurface
                    } else {
                        dpad
                    }
                }
                .frame(maxWidth: 280, maxHeight: 280)
                .aspectRatio(1, contentMode: .fit)
                volumeRocker
            }
            .frame(maxHeight: .infinity)
            transportRow
            channelRow
            guideRow
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .fullScreenCover(isPresented: $showKeyboard) {
            KeyboardView()
                .environmentObject(session)
                .environmentObject(store)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Button {
                if store.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                session.power()
            } label: {
                Image(systemName: "power")
                    .font(.body.weight(.bold))
                    .foregroundStyle(session.isOn == false ? Theme.secondary : Theme.brass)
                    .frame(width: 44, height: 44)
                    .background(Theme.button, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isOn == false ? "Wake" : "Sleep")

            VStack(alignment: .leading, spacing: 2) {
                Text(powerLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(detailLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(touchpad ? "Buttons" : "Touchpad") {
                touchpad.toggle()
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
        }
    }

    private var powerLabel: String {
        switch session.isOn {
        case .some(true): return "On"
        case .some(false): return "Asleep"
        case .none: return "Connected"
        }
    }

    private var detailLabel: String {
        var parts: [String] = []
        if let app = friendlyApp(session.currentApp) { parts.append(app) }
        if session.isMuted == true {
            parts.append("Muted")
        } else if let level = session.volumeLevel, let max = session.volumeMax {
            parts.append("Volume \(level) of \(max)")
        } else if let level = session.volumeLevel {
            parts.append("Volume \(level)")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    private var appRow: some View {
        HStack(spacing: 10) {
            appButton("YouTube", AppLink.youtube)
            appButton("Netflix", AppLink.netflix)
        }
    }

    private func appButton(_ title: String, _ link: String) -> some View {
        Button(title) { session.launch(link) }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
            .foregroundStyle(Theme.text)
            .buttonStyle(.plain)
    }

    private var dpad: some View {
        ZStack {
            Circle().fill(Theme.surface)
            VStack {
                arrow(.dpadUp, "chevron.up", "Up")
                Spacer()
                arrow(.dpadDown, "chevron.down", "Down")
            }
            .padding(8)
            HStack {
                arrow(.dpadLeft, "chevron.left", "Left")
                Spacer()
                arrow(.dpadRight, "chevron.right", "Right")
            }
            .padding(8)
            Pressable(haptics: store.hapticsEnabled) { direction in
                session.press(.dpadCenter, direction: direction)
            } label: {
                Text("OK")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.1, blue: 0.04))
                    .frame(width: 76, height: 76)
                    .background(Theme.brass, in: Circle())
            }
            .accessibilityLabel("OK")
        }
    }

    private func arrow(_ key: RemoteKey, _ symbol: String, _ name: String) -> some View {
        Pressable(repeats: true, haptics: store.hapticsEnabled) { direction in
            session.press(key, direction: direction)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 52, height: 52)
        }
        .accessibilityLabel(name)
    }

    private var touchSurface: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(Theme.surface)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.title2)
                    Text("Swipe to move\nTap to select")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.secondary)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        let key: RemoteKey
                        if hypot(dx, dy) < 24 {
                            key = .dpadCenter
                        } else if abs(dx) > abs(dy) {
                            key = dx > 0 ? .dpadRight : .dpadLeft
                        } else {
                            key = dy > 0 ? .dpadDown : .dpadUp
                        }
                        if store.hapticsEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        session.press(key, direction: .short)
                    }
            )
            .accessibilityLabel("Touchpad")
            .accessibilityHint("Swipe up, down, left, or right. Tap to select.")
    }

    private var volumeRocker: some View {
        VStack(spacing: 8) {
            rocker(.volumeUp, "plus", "Volume up")
            Pressable(haptics: store.hapticsEnabled) { direction in
                session.press(.mute, direction: direction)
            } label: {
                Image(systemName: session.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 52, height: 52)
                    .background(Theme.button, in: Circle())
            }
            .accessibilityLabel("Mute")
            rocker(.volumeDown, "minus", "Volume down")
        }
    }

    private func rocker(_ key: RemoteKey, _ symbol: String, _ name: String) -> some View {
        Pressable(repeats: true, haptics: store.hapticsEnabled) { direction in
            session.press(key, direction: direction)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.text)
                .frame(width: 52, height: 52)
                .background(Theme.button, in: Circle())
        }
        .accessibilityLabel(name)
    }

    private var transportRow: some View {
        HStack(spacing: 10) {
            bar(.back, "arrow.uturn.backward", "Back")
            bar(.home, "house", "Home")
            bar(.playPause, "playpause", "Play pause")
        }
    }

    private func bar(_ key: RemoteKey, _ symbol: String, _ name: String, repeats: Bool = false) -> some View {
        Pressable(repeats: repeats, haptics: store.hapticsEnabled) { direction in
            session.press(key, direction: direction)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.button, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(name)
    }

    private var channelRow: some View {
        HStack(spacing: 10) {
            bar(.channelUp, "chevron.up", "Channel up", repeats: true)
            bar(.channelDown, "chevron.down", "Channel down", repeats: true)
        }
    }

    private var guideRow: some View {
        HStack(spacing: 10) {
            shortcut("Guide") { session.press(.guide, direction: .short) }
            shortcut("Live TV") { session.press(.tv, direction: .short) }
            shortcut("Keyboard") { showKeyboard = true }
        }
    }

    private func shortcut(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.button, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func friendlyApp(_ package: String?) -> String? {
        switch package {
        case "com.google.android.youtube.tv", "com.google.android.youtube":
            return "YouTube"
        case "com.netflix.ninja":
            return "Netflix"
        case "com.amazon.amazonvideo.livingroom":
            return "Prime Video"
        case "com.google.android.tvlauncher", "com.google.android.apps.tv.launcherx":
            return "Home"
        case let value? where !value.isEmpty:
            return value.split(separator: ".").last.map(String.init)
        default:
            return nil
        }
    }
}
