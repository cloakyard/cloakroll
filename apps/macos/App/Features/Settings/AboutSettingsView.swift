import SwiftUI

struct AboutSettingsView: View {
    @State private var showingLicenses = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image("AboutAppIcon")
                        .resizable().interpolation(.high)
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                    VStack(spacing: 3) {
                        Text(wordmark).font(.title2.weight(.semibold))
                            .accessibilityLabel("CloakRoll")
                        Text("Version \(version) · \(releaseChannel)")
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Created by Sumit Sahoo")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if let url = SettingsLinks.author {
                    SettingsLinkRow(title: "github.com/sumitsahoo", symbol: "person.crop.circle", destination: url)
                }
                if let url = SettingsLinks.repository {
                    SettingsLinkRow(
                        title: "github.com/cloakyard/cloakroll", symbol: "chevron.left.forwardslash.chevron.right", destination: url
                    )
                }
                if let url = SettingsLinks.issues {
                    SettingsLinkRow(title: "Report a Bug", symbol: "ladybug", destination: url)
                }
                Button("Open-Source Licenses…") { showingLicenses = true }
            } footer: {
                Text("Part of Cloakyard. Your camera roll, safely on your Mac.")
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showingLicenses) { LicensesView() }
    }

    private var wordmark: AttributedString {
        var text = AttributedString("Cloak")
        var suffix = AttributedString("Roll")
        suffix.foregroundColor = Design.accent
        text.append(suffix)
        return text
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var releaseChannel: String {
        Bundle.main.object(forInfoDictionaryKey: "CloakRollReleaseChannel") as? String ?? "Development preview"
    }
}

private struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Open-Source Licenses").font(.title2.weight(.semibold))
                    Text("CloakRoll").font(.headline)
                    Text(license("LICENSE"))
                    Text("GRDB 7.11.1").font(.headline)
                    Text(license("ThirdPartyNotices/GRDB.txt"))
                }
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(width: 560, height: 460)
        .onExitCommand { dismiss() }
    }

    private func license(_ path: String) -> String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(path),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "This license could not be loaded. It is available in the CloakRoll source repository."
        }
        return text
    }
}
