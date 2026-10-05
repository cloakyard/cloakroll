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
                Label("Backup History", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarDestination.backupHistory)
            }
            if model.isSample {
                Section("Destination") {
                    Label("Sample library", systemImage: "externaldrive")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Destination") {
                    if let destination = model.backup.destination.selection {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(destination.displayName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(destination.lastKnownPath)
                                if model.backup.recovery.isRunning {
                                    Text("Rebuilding History…").font(.caption).foregroundStyle(.secondary)
                                } else if model.backup.isBackingUp {
                                    Text(BackupProgressPresentation(
                                        snapshot: model.backup.snapshot ?? .init(phase: .preparing),
                                        isStopping: model.backup.isStopping
                                    ).title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                } else {
                                    DestinationReadinessLabel(readiness: model.backup.destination.readiness)
                                        .font(.caption)
                                }
                            }
                        } icon: {
                            Image(systemName: "folder")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityActions { openDestinationAction }
                        .contextMenu { openDestinationAction }
                    }
                    Button {
                        Task { await model.backup.chooseDestination() }
                    } label: {
                        Label(model.backup.destination.selection == nil ? "Choose Folder…" : "Change Folder…",
                              systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.backup.isBusy || model.backup.destination.isChoosing)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CloakRoll")
    }

    private var openDestinationAction: some View {
        Button {
            Task { await model.backup.revealDestination() }
        } label: {
            Label("Open in Finder", systemImage: "arrow.up.forward.square")
        }
        .disabled(model.backup.destination.isChoosing)
    }

    private var selection: Binding<SidebarDestination?> {
        Binding(get: { model.navigation }, set: { value in
            switch value {
            case .library(let filter): model.filter = filter
            case .backupHistory: model.navigation = .backupHistory
            case nil: break
            }
        })
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
        .tag(SidebarDestination.library(filter))
        .accessibilityElement(children: .combine)
    }
}

struct DeviceSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(model.device == nil ? Color.secondary : Design.accent)
                .accessibilityHidden(true)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if model.deviceInventory.devices.count > 1 {
                    ConnectedDevicePicker(inventory: model.deviceInventory, isEnabled: model.canSelectDevice) {
                        model.selectDevice(id: $0)
                    }
                } else {
                    Text(model.device?.displayName ?? "No iPhone Connected")
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                Label(status, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.isSample, let device = model.device, let persistence = model.backup.persistence {
                    DeviceBackupSummary(deviceKey: device.id, persistence: persistence)
                        .padding(.top, 4)
                }
            }
        }
        .accessibilityElement(children: .contain)
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
