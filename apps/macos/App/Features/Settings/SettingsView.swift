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
            Section {
                ThumbnailSizePicker(selection: $model.thumbnailSize)
                    .pickerStyle(.menu)
            } header: {
                Text("Browsing")
            } footer: {
                Text("""
                ⌘-click to select individual items. ⇧-click to select a range.
                Press Space or ⌘I to show info for the selected item.
                """)
            }
            Section {
                Text("CloakRoll browses photos and videos available over USB. It does not change or delete media on your iPhone.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
    }

    private var backup: some View {
        Form {
            Section("Destination") {
                if let destination = model.backup.destination.selection {
                    LabeledContent("Folder", value: destination.displayName)
                    Text(destination.lastKnownPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button(model.backup.destination.selection == nil ? "Choose Folder…" : "Change Folder…") {
                    Task { await model.backup.chooseDestination() }
                }
                .disabled(model.backup.isBusy || model.backup.destination.isChoosing)
            }
            Section("Originals") {
                LabeledContent("Media format", value: "Keep originals")
                LabeledContent("Folder structure", value: "Year / Month")
            }
            Section {
                Text("Backup history currently lasts for this connection. Existing files are kept when another copy is made.")
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
