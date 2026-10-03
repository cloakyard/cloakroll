import SwiftUI

enum BackupHelpTopic: String {
    case gettingStarted, usbAvailability

    var title: String {
        switch self {
        case .gettingStarted: "Backing Up Your iPhone"
        case .usbAvailability: "USB Availability"
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
                Original files are saved in Year / Month folders and verified after copying. \
                Your photos and videos stay on your iPhone.
                """)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("About USB Availability…") { selectTopic(.usbAvailability) }
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
