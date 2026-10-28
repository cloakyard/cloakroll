import BackupEngine
import SwiftUI

struct UnavailableOriginalsView: View {
    let originals: [UnavailableBackupOriginal]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unavailable Originals").font(.title2.weight(.semibold))
                Text("""
                These originals could not be found in the iPhone’s current USB library.
                Reconnect and unlock it, then back up the remaining items.
                """)
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(20)
            List(originals) { original in
                Label(original.filename, systemImage: "doc")
                    .textSelection(.enabled)
                    .help(original.filename)
            }
            Divider()
            HStack {
                Text("\(originals.count.formatted()) not copied").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(width: 480, height: 380)
        .onExitCommand { dismiss() }
    }
}
