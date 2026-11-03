import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    private var notifications: BackupNotifications { model.backup.notifications }

    var body: some View {
        Form {
            Section {
                Toggle("Backup completion and attention", isOn: Binding(
                    get: { notifications.completionEnabled },
                    set: { enabled in
                        Task { await notifications.configure(completion: enabled, reminderDays: notifications.reminderDays) }
                    }
                ))
            } header: { Text("Backup Results") } footer: {
                Text("Receive a local notification when a backup finishes or needs attention. Stopping a backup does not notify.")
            }
            Section {
                Picker("Remind me after", selection: Binding(
                    get: { notifications.reminderDays },
                    set: { days in
                        Task { await notifications.configure(completion: notifications.completionEnabled, reminderDays: days) }
                    }
                )) {
                    Text("Off").tag(0)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
            } header: { Text("Backup Reminder") } footer: {
                Text("One reminder after your last completed backup, across your iPhones. A successful backup resets it. "
                     + "If you have no completed backup, the interval starts when enabled. Reminders never start a backup.")
            }
            Section("Permission") {
                LabeledContent("Notifications", value: permissionTitle)
                Button("Check Permission") { Task { await notifications.refreshPermission() } }
                if let message = notifications.errorMessage {
                    Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Text("Notifications contain no phone names, filenames, photos or paths. "
                     + "They are scheduled on this Mac without a server. macOS controls their delivery and presentation.")
            }
        }
        .formStyle(.grouped)
        .disabled(notifications.isUpdating)
        .task { await notifications.refreshPermission() }
    }

    private var permissionTitle: String {
        switch notifications.permission {
        case .unknown: "Not requested"
        case .allowed: "Allowed by macOS"
        case .denied: "Not allowed — check System Settings"
        }
    }
}
