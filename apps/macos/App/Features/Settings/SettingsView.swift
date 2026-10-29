import SwiftUI

enum SettingsTab: String {
    case general, backup, privacy, about
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            backup.tabItem { Label("Backup", systemImage: "externaldrive") }.tag(SettingsTab.backup)
            PrivacySettingsView().tabItem { Label("Privacy", systemImage: "lock.shield") }.tag(SettingsTab.privacy)
            AboutSettingsView().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 640, height: 600)
        .onDisappear { model.settingsTab = .general }
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
                Text("Choose how large photos and videos appear in the library.")
            }
            Section("Selection") {
                SettingsShortcutRow("Select individual items", value: "⌘-click")
                SettingsShortcutRow("Select a range", value: "⇧-click")
                SettingsShortcutRow("Move between items", value: "Arrow keys")
                SettingsShortcutRow("Extend the selection", value: "⇧ + Arrow keys")
                SettingsShortcutRow("Deselect all", value: "Esc or ⇧⌘A")
            }
            Section {
                SettingsShortcutRow("Show media info", value: "Space or ⌘I")
                SettingsShortcutRow("Previous or next item in Info", value: "⌘[ or ⌘]")
            } header: {
                Text("Media Info")
            } footer: {
                Text("Right-click a date label to select or deselect its group. Shortcuts apply while browsing the library.")
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
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
                if !model.isSample, let device = model.device {
                    Text("The backup folder is remembered for \(device.displayName). Other iPhones can use different folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                Text(model.backupOrganization.explanation + " This applies to new files; existing backups stay in place.")
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .task {
            guard !model.isSample, !model.backup.isBusy else { return }
            await model.backup.checkDestination()
        }
    }
}

private struct SettingsShortcutRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
    }
}
