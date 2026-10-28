import SwiftUI

/// Native link rows share the hierarchy of the other Cloakyard Settings windows.
struct SettingsLinkRow: View {
    let title: String
    let symbol: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(destination.absoluteString)
    }
}

/// These links open only after a user action.
enum SettingsLinks {
    static let author = URL(string: "https://github.com/sumitsahoo")
    static let repository = URL(string: "https://github.com/cloakyard/cloakroll")
    static let issues = URL(string: "https://github.com/cloakyard/cloakroll/issues/new?template=bug_report.yml")
    static let privacy = URL(string: "https://github.com/cloakyard/cloakroll/blob/main/docs/PRIVACY.md")
}
