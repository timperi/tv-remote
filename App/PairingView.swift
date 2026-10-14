import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var session: TVSession
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.deviceName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(session.status)
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.isWorking && !session.awaitingCode {
                ProgressView()
                    .tint(Theme.brass)
            }

            Text("A six-character code appears on the TV, something like 1A2B3C. If the TV asks whether to allow a remote, allow it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("1A2B3C", text: codeBinding)
                .focused($focused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .font(.system(size: 34, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Theme.text)
                .disabled(!session.awaitingCode)
                .onSubmit(submit)

            if let error = session.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                Text("Pair")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count != 6 || !session.awaitingCode)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .navigationTitle("Pair")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("TVs") { session.closeToList() }
            }
        }
        .onAppear { focused = session.awaitingCode }
        .onChange(of: session.awaitingCode) { _, waiting in
            focused = waiting
        }
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { code },
            set: { newValue in
                code = String(newValue.uppercased().filter(\.isHexDigit).prefix(6))
            }
        )
    }

    private func submit() {
        guard code.count == 6 else { return }
        focused = false
        session.submit(code: code)
    }
}
