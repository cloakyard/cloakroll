import SwiftUI

enum SettingsTab: String {
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
        @Bindable var model = model
        return Form {
            Section("Destination") {
                if let destination = model.backup.destination.selection {
                    LabeledContent("Folder", value: destination.displayName)
                    Text(destination.lastKnownPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    LabeledContent("Status") {
                        DestinationReadinessLabel(readiness: model.backup.destination.readiness)
                    }
                    if let message = model.backup.destination.readiness.message {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Button(model.backup.destination.selection == nil ? "Choose Folder…" : "Change Folder…") {
                        Task { await model.backup.chooseDestination() }
                    }
                    Spacer()
                    if model.backup.destination.selection != nil {
                        Button(model.backup.destination.readiness.message == nil ? "Check Folder" : "Try Again") {
                            Task { await model.backup.checkDestination() }
                        }
                        .disabled(model.backup.destination.readiness.isChecking)
                    }
                }
                .disabled(model.isSample || model.backup.isBusy || model.backup.destination.isChoosing)
            }
            Section {
                LabeledContent("Media format", value: "Keep originals")
                Picker("Folder structure", selection: $model.backupOrganization) {
                    ForEach(BackupOrganization.allCases, id: \.self) { organization in
                        Text(organization.title).tag(organization)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.backup.isBusy)
            } header: {
                Text("Originals")
            } footer: {
                Text("""
                Each iPhone has its own folder. Photos and videos can be grouped by year and month or kept together.
                This setting applies to new files; existing backups stay in place.
                """)
            }
        }
        .formStyle(.grouped)
        .task {
            guard !model.isSample, !model.backup.isBusy else { return }
            await model.backup.checkDestination()
        }
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
