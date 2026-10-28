import SwiftUI

struct AboutHeaderView: View {
    let version: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    @State private var matrixMode = false
    private static let phosphor = Color(red: 0.62, green: 1, blue: 0.62)

    var body: some View {
        VStack(spacing: 12) {
            Button(action: registerTap) {
                Image("AboutAppIcon").resizable().interpolation(.high)
                    .frame(width: 84, height: 84)
                    .shadow(color: .green.opacity(matrixMode ? 0.7 : 0), radius: 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(matrixMode ? "Stop Matrix animation" : "CloakRoll")
            VStack(spacing: 3) {
                Text(wordmark).font(.title2.weight(.semibold)).accessibilityLabel("CloakRoll")
                Text("Version \(version)")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(matrixMode ? Self.phosphor.opacity(0.85) : .secondary)
                    .textSelection(.enabled)
                Text("Created by Sumit Sahoo")
                    .font(.footnote)
                    .foregroundStyle(matrixMode ? Self.phosphor.opacity(0.7) : .secondary)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background {
            if matrixMode { MatrixRainView().clipShape(.rect(cornerRadius: 8)) }
        }
        .contentShape(.rect)
        .onTapGesture { if matrixMode { stop() } }
        .onDisappear { stop() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: matrixMode)
    }

    private var wordmark: AttributedString {
        var lead = AttributedString("Cloak")
        lead.foregroundColor = matrixMode ? Self.phosphor : .primary
        var suffix = AttributedString("Roll")
        suffix.foregroundColor = matrixMode ? Self.phosphor : Design.accent
        lead.append(suffix)
        return lead
    }

    private func registerTap() {
        if matrixMode { stop(); return }
        taps += 1
        if taps == 5 { matrixMode = true }
    }

    private func stop() {
        matrixMode = false
        taps = 0
    }
}
