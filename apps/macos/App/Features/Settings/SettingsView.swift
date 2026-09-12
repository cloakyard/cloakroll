import BackupPersistence
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
                Text("Previous backups are remembered for each iPhone and folder. Saved originals are checked before they are reused.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let sessions = model.backup.persistence?.recentSessions, !sessions.isEmpty {
                Section("Recent Backups") {
                    ForEach(sessions.prefix(3), id: \.id) { session in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                                Text(session.deviceName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sessionLabel(session)).foregroundStyle(.secondary)
                        }
                    }
                }
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

    private func sessionLabel(_ session: StoredBackupSession) -> String {
        switch session.status {
        case .completed: "\(session.completedAssets.formatted()) \(session.completedAssets == 1 ? "item" : "items")"
        case .running: "In Progress"
        case .cancelled: "Stopped"
        case .failed: "Incomplete"
        case .interrupted: "Interrupted"
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
