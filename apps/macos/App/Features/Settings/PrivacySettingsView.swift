import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section {
                Label("Local processing", systemImage: "internaldrive")
                Label("No accounts, analytics or media uploads", systemImage: "lock.shield")
                Label("Your iPhone originals stay unchanged", systemImage: "photo.on.rectangle")
            } header: {
                Text("Your Privacy")
            } footer: {
                Text("CloakRoll works with a USB-connected iPhone and a backup folder you choose.")
            }
            Section("On This Mac") {
                Text("""
                Backup history, device and folder references, preferences and disposable previews stay in the app’s local storage.
                Camera information is read when you open Media Info. CloakRoll does not extract GPS fields from that request.
                """)
            }
            Section("Your Originals") {
                Text("""
                Photos, videos and companion files are copied without conversion. Embedded metadata, including any location \
                in an original, is preserved. A cloud-managed backup folder may sync through its separate service.
                """)
            }
            Section("Recovery and Removal") {
                Text("""
                Backup folders contain hidden recovery records with file and device metadata, sizes and verification hashes. \
                Keep these records with your originals. Removing the app does not remove your backups. If app data is lost, \
                use Backup History → Rebuild History to verify the folder again.
                """)
            }
            Section {
                if let url = SettingsLinks.privacy {
                    SettingsLinkRow(title: "Read the Full Privacy Policy", symbol: "doc.text", destination: url)
                }
            } footer: {
                Text("External links open in your browser only when you choose them. CloakRoll does not upload diagnostics.")
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
    }
}
