import SwiftUI
import UIKit

enum Theme {
    static let background = Color(red: 0.063, green: 0.067, blue: 0.078)
    static let surface = Color(red: 0.11, green: 0.118, blue: 0.137)
    static let button = Color(red: 0.165, green: 0.176, blue: 0.204)
    static let pressed = Color(red: 0.24, green: 0.255, blue: 0.29)
    static let brass = Color(red: 0.91, green: 0.64, blue: 0.36)
    static let text = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let secondary = Color(red: 0.62, green: 0.60, blue: 0.56)
    static let danger = Color(red: 0.86, green: 0.42, blue: 0.34)
}

struct Pressable<Label: View>: View {
    var repeats: Bool = false
    var haptics: Bool
    var action: (KeyDirection) -> Void
    @ViewBuilder var label: () -> Label

    @State private var pressed = false
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        label()
            .opacity(pressed ? 0.72 : 1)
            .scaleEffect(pressed ? 0.97 : 1)
            .contentShape(Rectangle())
            .gesture(gesture)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { fire(.short) }
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                guard repeats else { return }
                holdTask = Task {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard !Task.isCancelled else { return }
                    holding = true
                    action(.startLong)
                    bump()
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                if holding {
                    action(.endLong)
                } else {
                    fire(.short)
                }
                holding = false
                pressed = false
            }
    }

    private func fire(_ direction: KeyDirection) {
        bump()
        action(direction)
    }

    private func bump() {
        guard haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
