import SwiftUI

enum BackupHelpTopic: String {
    case gettingStarted, usbAvailability, interruptedBackups

    var title: String {
        switch self {
        case .gettingStarted: "Backing Up Your iPhone"
        case .usbAvailability: "USB Availability"
        case .interruptedBackups: "Interrupted Backups"
        }
    }
}

struct BackupHelpView: View {
    let topic: BackupHelpTopic
    let selectTopic: (BackupHelpTopic) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch topic {
                case .gettingStarted: gettingStarted
                case .usbAvailability: usbAvailability
                case .interruptedBackups: interruptedBackups
                }
            }
            .formStyle(.grouped)
            .navigationTitle(topic.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 520, height: 500)
        .onExitCommand { dismiss() }
    }

    private var gettingStarted: some View {
        Group {
            Section("Connect Your iPhone") {
                Text("Connect your iPhone to this Mac with a USB cable and unlock it. If asked, tap Trust on your iPhone.")
                Text("When more than one iPhone is connected, choose one in the sidebar. Back up one iPhone at a time.")
                    .foregroundStyle(.secondary)
            }
            Section("Choose a Backup Folder") {
                Text("Choose a folder on your Mac or an external drive using Choose Folder in the sidebar.")
                Text("Keep an external drive connected until the backup finishes.")
                    .foregroundStyle(.secondary)
            }
            Section("Back Up Your Originals") {
                Text("""
                Select photos and videos, then choose Back Up Selected Items. With nothing selected, \
                Back Up New Items copies new items in the current view.
                """)
                Text("""
                Original files are saved in separate iPhone folders, organized by year and month, and verified after copying. \
                Your photos and videos stay on your iPhone.
                """)
                    .foregroundStyle(.secondary)
                Text("Each iPhone folder has a stable identifier. Earlier backups in Year / Month folders can still be checked and reused.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("If a Backup Is Interrupted…") { selectTopic(.interruptedBackups) }
                Button("About USB Availability…") { selectTopic(.usbAvailability) }
            }
        }
    }

    private var interruptedBackups: some View {
        Group {
            Section("If Your iPhone Disconnects") {
                Text("Reconnect and unlock your iPhone, then wait for the library and backup checks to finish.")
                Text("Choose the items to back up again. Saved originals are checked and reused when they still match.")
                    .foregroundStyle(.secondary)
            }
            Section("What Was Saved") {
                Text("""
                Originals already saved stay in your backup folder. An item is marked backed up \
                only after all its available originals have been verified.
                """)
                Text("""
                An unfinished original may need to be copied again from the beginning. \
                Backup History shows how many items and originals were verified.
                """)
                    .foregroundStyle(.secondary)
            }
            Section("If the Backup Drive Is Unavailable") {
                Text("Reconnect the drive, then open Backup in Settings and check the folder. Free up space if the drive is full.")
                Text("CloakRoll won’t switch to a different folder automatically.")
                    .foregroundStyle(.secondary)
            }
            Section("Stop or Quit During a Backup") {
                Text("Choose Stop or press Command-period. CloakRoll waits for the current file operation to settle before stopping.")
                Text("""
                Quitting also waits for the backup to stop. Keep the backup drive connected \
                until CloakRoll finishes stopping or quits.
                """)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("How to Back Up Your iPhone…") { selectTopic(.gettingStarted) }
            }
        }
    }

    private var usbAvailability: some View {
        Group {
            Section("Available Over USB") {
                Text("""
                CloakRoll shows the photos and videos your iPhone makes available over USB. \
                This can differ from the library in Photos on your iPhone.
                """)
                Text("""
                A completed backup covers the items in that backup. \
                CloakRoll can’t count items that aren’t available over USB.
                """)
                    .foregroundStyle(.secondary)
            }
            Section("iCloud Photos") {
                Text("With Optimize iPhone Storage, some originals may be stored in iCloud and unavailable for USB import.")
                Text("""
                CloakRoll doesn’t download from iCloud. Apple’s guidance explains other ways \
                to copy photos and videos that aren’t available for import.
                """)
                    .foregroundStyle(.secondary)
                if let url = Self.unavailablePhotosURL {
                    Link("Apple’s guidance for unavailable photos", destination: url)
                }
            }
            Section("Hidden Photos and Videos") {
                Text("On macOS 15.4 or later, photos and videos in a locked Hidden album aren’t imported over USB.")
                if let url = Self.imageCaptureURL {
                    Link("Apple’s guide to importing over USB", destination: url)
                }
            }
            Section {
                Button("How to Back Up Your iPhone…") { selectTopic(.gettingStarted) }
            }
        }
    }

    private static let unavailablePhotosURL = URL(string: "https://support.apple.com/en-us/102302")
    private static let imageCaptureURL = URL(string: "https://support.apple.com/guide/image-capture/image-capture-imgcp1003/mac")
}
