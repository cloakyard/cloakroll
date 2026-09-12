import MediaModels
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selection) {
            Section {
                DeviceSummary()
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
            }
            Section("Library") {
                ForEach([LibraryFilter.all, .photos, .videos, .livePhotos, .raw], id: \.self) { row($0) }
            }
            Section("Backup") {
                ForEach([LibraryFilter.notBackedUp, .backedUp, .recentlyBackedUp], id: \.self) { row($0) }
            }
            if model.isSample {
                Section("Destination") {
                    Label("Sample library", systemImage: "externaldrive")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CloakRoll")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("Private by nature.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var selection: Binding<LibraryFilter?> {
        Binding(get: { model.filter }, set: { if let value = $0 { model.filter = value } })
    }

    private func row(_ filter: LibraryFilter) -> some View {
        HStack {
            Label(filter == .recentlyBackedUp ? "Recent Backups" : filter.title, systemImage: filter.symbol)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count = model.snapshot.counts[filter], count > 0 {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .tag(filter)
        .accessibilityElement(children: .combine)
    }
}

struct DeviceSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(model.device == nil ? Color.secondary : Design.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.device?.displayName ?? "No iPhone Connected")
                    .fontWeight(.medium)
                    .lineLimit(2)
                Label(status, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        switch model.deviceState {
        case .disconnected: "Connect using USB"
        case .opening: "Connecting…"
        case .restricted: "Unlock and trust this Mac"
        case .ready: model.isSample ? "Connected · Sample" : "Connected"
        case .unavailable: "Unavailable"
        }
    }

    private var symbol: String {
        switch model.deviceState {
        case .ready: "checkmark.circle.fill"
        case .restricted: "lock"
        case .opening: "arrow.triangle.2.circlepath"
        case .disconnected, .unavailable: "cable.connector"
        }
    }
}
