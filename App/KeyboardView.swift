import SwiftUI
import UIKit

/// Full-screen keyboard. It does not use the iOS system keyboard, so nothing
/// covers a text field on the phone. Each tap is sent to the TV immediately.
struct KeyboardView: View {
    @EnvironmentObject private var session: TVSession
    @EnvironmentObject private var store: DeviceStore
    @Environment(\.dismiss) private var dismiss

    @State private var shift = LetterCase.off
    @State private var layer = KeyboardLayer.letters

    private let top = Array("qwertyuiopå")
    private let home = Array("asdfghjklöä")
    private let bottom = Array("zxcvbnm")

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let keyHeight = keyHeight(in: geo.size, landscape: landscape)
            VStack(spacing: landscape ? 6 : 8) {
                header
                echo
                Spacer(minLength: 0)
                layers(keyHeight: keyHeight)
            }
            .padding(.horizontal, landscape ? 10 : 6)
            .padding(.top, 4)
            .padding(.bottom, landscape ? 4 : 8)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            InterfaceOrientation.set([.portrait, .landscapeLeft, .landscapeRight])
        }
        .onDisappear {
            InterfaceOrientation.set(.portrait)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Close") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Theme.button, in: Capsule())
            Spacer()
            Text("Keyboard")
                .font(.headline)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var echo: some View {
        Text(session.keyboardText.isEmpty ? "Text appears on the TV" : session.keyboardText)
            .font(.body.weight(.medium))
            .foregroundStyle(session.keyboardText.isEmpty ? Theme.secondary : Theme.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .accessibilityLabel(session.keyboardText.isEmpty ? "Text appears on the TV" : session.keyboardText)
    }

    @ViewBuilder
    private func layers(keyHeight: CGFloat) -> some View {
        switch layer {
        case .letters:
            letterKeys(keyHeight: keyHeight)
        case .numbers:
            symbolKeys(rows: numberRows, next: "#+=", nextLayer: .symbols, keyHeight: keyHeight)
        case .symbols:
            symbolKeys(rows: symbolRows, next: "123", nextLayer: .numbers, keyHeight: keyHeight)
        }
    }

    private func letterKeys(keyHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            characterRow(top.map { display($0) }, height: keyHeight, consumesShift: true)
            characterRow(home.map { display($0) }, height: keyHeight, consumesShift: true)
            HStack(spacing: 5) {
                shiftKey(height: keyHeight)
                ForEach(Array(bottom.enumerated()), id: \.offset) { _, character in
                    let label = display(character)
                    keyButton(label, accessibility: label, height: keyHeight) {
                        session.type(label)
                        if shift == .once { shift = .off }
                    }
                }
                backspace(height: keyHeight)
            }
            .frame(height: keyHeight)
            bottomRow(layerTitle: "123", layerAction: { layer = .numbers }, height: keyHeight)
        }
    }

    private func symbolKeys(rows: [[String]], next: String, nextLayer: KeyboardLayer, keyHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            characterRow(rows[0], height: keyHeight, consumesShift: false)
            characterRow(rows[1], height: keyHeight, consumesShift: false)
            HStack(spacing: 5) {
                layerButton(next, height: keyHeight) { layer = nextLayer }
                ForEach(Array(rows[2].enumerated()), id: \.offset) { _, label in
                    keyButton(label, accessibility: label, height: keyHeight) {
                        session.type(label)
                    }
                }
                backspace(height: keyHeight)
            }
            .frame(height: keyHeight)
            bottomRow(layerTitle: "ABC", layerAction: { layer = .letters }, height: keyHeight)
        }
    }

    private func characterRow(_ labels: [String], height: CGFloat, consumesShift: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                keyButton(label, accessibility: label, height: height) {
                    session.type(label)
                    if consumesShift, shift == .once { shift = .off }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func backspace(height: CGFloat) -> some View {
        HoldKey(haptics: store.hapticsEnabled, action: { session.typeBackspace() }) {
            keyFace("⌫", height: height)
        }
        .frame(minWidth: height)
        .accessibilityLabel("Backspace")
    }

    private func bottomRow(layerTitle: String, layerAction: @escaping () -> Void, height: CGFloat) -> some View {
        HStack(spacing: 5) {
            layerButton(layerTitle, height: height, action: layerAction)
            keyButton("space", accessibility: "Space", height: height) {
                session.type(" ")
                if shift == .once { shift = .off }
            }
            keyButton("enter", accessibility: "Enter", height: height) {
                session.typeEnter()
            }
        }
        .frame(height: height)
    }

    private func shiftKey(height: CGFloat) -> some View {
        let title = shift == .locked ? "⇪" : "⇧"
        return keyButton(title, accessibility: shift == .locked ? "Caps lock" : "Shift", height: height, fill: shift == .off ? Theme.button : Theme.brass) {
            switch shift {
            case .off: shift = .once
            case .once: shift = .locked
            case .locked: shift = .off
            }
        }
        .frame(minWidth: height)
    }

    private func layerButton(_ title: String, height: CGFloat, action: @escaping () -> Void) -> some View {
        keyButton(title, accessibility: title, height: height, action: action)
            .frame(minWidth: height * 1.15)
    }

    private func keyButton(_ title: String, accessibility: String, height: CGFloat, fill: Color = Theme.button, action: @escaping () -> Void) -> some View {
        Button {
            tap()
            action()
        } label: {
            keyFace(title, height: height, fill: fill)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private func keyFace(_ title: String, height: CGFloat, fill: Color = Theme.button) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func display(_ character: Character) -> String {
        let text = String(character)
        return shift == .off ? text : text.uppercased()
    }

    private func tap() {
        guard store.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func keyHeight(in size: CGSize, landscape: Bool) -> CGFloat {
        let chrome: CGFloat = landscape ? 96 : 108
        let gaps: CGFloat = 6 * 3
        let available = size.height - chrome - gaps
        let fitted = available / 4
        let cap: CGFloat = landscape ? 72 : 58
        return min(cap, max(40, fitted))
    }

    private var numberRows: [[String]] {
        [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""],
            [".", ",", "?", "!", "'"]
        ]
    }

    private var symbolRows: [[String]] {
        [
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
            ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"],
            [".", ",", "?", "!", "'"]
        ]
    }
}

private enum KeyboardLayer {
    case letters
    case numbers
    case symbols
}

private enum LetterCase {
    case off
    case once
    case locked
}

/// Backspace repeats while the finger stays down.
private struct HoldKey<Label: View>: View {
    var haptics: Bool
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var pressed = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        label()
            .opacity(pressed ? 0.72 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        fire()
                        task = Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            while !Task.isCancelled {
                                fire()
                                try? await Task.sleep(nanoseconds: 80_000_000)
                            }
                        }
                    }
                    .onEnded { _ in
                        task?.cancel()
                        task = nil
                        pressed = false
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { fire() }
    }

    private func fire() {
        if haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        action()
    }
}
