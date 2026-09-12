import SwiftUI

enum SettingsTab: Hashable {
    case general, backup, about
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            backup.tabItem { Label("Backup", systemImage: "externaldrive") }.tag(SettingsTab.backup)
            about.tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 560, height: 430)
    }

    private var general: some View {
        @Bindable var model = model
        return Form {
            Section("Browsing") {
                Slider(value: $model.cellSize, in: 84...200, step: 4) { Text("Thumbnail size") }
                LabeledContent("Selection", value: "Click, ⌘-click, ⇧-click")
                LabeledContent("Preview", value: "Space or ⌘I")
            }
            Section {
                Text("CloakRoll browses photos and videos available over USB. It does not change or delete media on your iPhone.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Your camera roll, safely on your Mac.")
            }
        }
        .formStyle(.grouped)
    }

    private var backup: some View {
        Form {
            Section("Originals") {
                LabeledContent("Media format", value: "Keep originals")
                LabeledContent("Folder structure", value: "Year / Month")
            }
            Section {
                Label("Backup is not available in this development build.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Sample backup states illustrate the interface. They are not records of a completed backup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("AboutAppIcon").resizable().frame(width: 76, height: 76).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("CloakRoll").font(.title.weight(.semibold))
                        Text("Your camera roll, safely on your Mac.").foregroundStyle(.secondary)
                        Text("\(version) · Development preview").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            Section("Part of Cloakyard") {
                Label("Local processing. No accounts. No analytics.", systemImage: "lock.shield")
                Text("Designed for the things you want to keep.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
