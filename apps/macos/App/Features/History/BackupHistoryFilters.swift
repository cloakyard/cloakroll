import BackupPersistence
import SwiftUI

struct BackupHistoryFilters: View {
    let persistence: LibraryBackupPersistence

    var body: some View {
        Menu {
            Picker("iPhone", selection: deviceSelection) {
                Text("All iPhones").tag(String?.none)
                ForEach(persistence.historyDevices) { device in
                    Text(deviceTitle(device)).tag(Optional(device.id))
                }
            }
            Picker("Result", selection: outcomeSelection) {
                Text("All Results").tag(BackupHistoryFilter.Outcome.all)
                Text("Completed").tag(BackupHistoryFilter.Outcome.completed)
                Text("Unfinished").tag(BackupHistoryFilter.Outcome.unfinished)
            }
            if persistence.sessionFilter != BackupHistoryFilter() {
                Divider()
                Button("Clear Filters") { apply(BackupHistoryFilter()) }
            }
        } label: {
            Label("Filter Backup History", systemImage: persistence.sessionFilter == BackupHistoryFilter()
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Filter backup history by iPhone and result")
        .accessibilityValue(summary)
    }

    var summary: String {
        let device = persistence.historyDevices.first { $0.id == persistence.sessionFilter.deviceKey }
        let name = device.map(deviceTitle) ?? "All iPhones"
        switch persistence.sessionFilter.outcome {
        case .all: return name
        case .completed: return "\(name) · Completed"
        case .unfinished: return "\(name) · Unfinished"
        }
    }

    private func deviceTitle(_ device: BackupHistoryDevice) -> String {
        let matching = persistence.historyDevices.filter { $0.name == device.name }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.id == device.id }) else { return device.name }
        return "\(device.name) (\(index + 1))"
    }

    private var deviceSelection: Binding<String?> {
        Binding(get: { persistence.sessionFilter.deviceKey }, set: { key in
            var filter = persistence.sessionFilter
            filter.deviceKey = key
            apply(filter)
        })
    }

    private var outcomeSelection: Binding<BackupHistoryFilter.Outcome> {
        Binding(get: { persistence.sessionFilter.outcome }, set: { outcome in
            var filter = persistence.sessionFilter
            filter.outcome = outcome
            apply(filter)
        })
    }

    private func apply(_ filter: BackupHistoryFilter) {
        Task { await persistence.applySessionFilter(filter) }
    }
}
