import SwiftUI

struct LibraryCommands: Commands {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CloakRoll") {
                model.settingsTab = .about
                openSettings()
            }
        }
        SidebarCommands()
        CommandGroup(after: .textEditing) {
            Button("Find…") { model.searchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!model.isViewingLibrary)
        }
        CommandGroup(after: .toolbar) {
            Divider()
            LibraryViewOptions(model: model)
                .disabled(!model.isViewingLibrary)
        }
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Show Library") { model.navigation = .library(model.filter) }
                .disabled(model.isViewingLibrary)
            Button("Show Backup History") { model.navigation = .backupHistory }
                .disabled(!model.isViewingLibrary)
        }
        CommandMenu("Library") {
            LibraryActionItems(model: model)
        }
        CommandGroup(replacing: .help) {
            Button("CloakRoll Help") { showHelp(.gettingStarted) }
            Button("If a Backup Is Interrupted…") { showHelp(.interruptedBackups) }
            Button("About USB Availability…") { showHelp(.usbAvailability) }
        }
        #if DEBUG
        DevelopmentCommands(model: model)
        #endif
    }

    private func showHelp(_ topic: BackupHelpTopic) {
        openWindow(id: "main")
        model.presentation = .help(topic)
    }
}

private struct LibraryActionItems: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Show Info") { model.showSelectedInfo() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(model.selection.selectedIDs.isEmpty)
            Button(model.selection.selectedIDs.count == 1 ? "Copy Filename" : "Copy Filenames") {
                model.copySelectedFilenames()
            }
            .disabled(model.selection.selectedIDs.isEmpty)
            DateGroupSelectionActions(model: model, target: model.activeDateGroupTarget)
            Button("Deselect All") { model.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.selection.selectedIDs.isEmpty)
            Divider()
            Button(backupTitle) { model.backUpCurrentSelection() }
                .disabled(!model.canBackUp)
        }
        .disabled(!model.isViewingLibrary)
        Button("Stop Backup") { model.backup.cancel() }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!model.backup.isBusy || model.backup.isStopping)
        Divider()
        Button("Check Saved Originals") { model.checkSavedOriginals() }
            .disabled(!model.canCheckSavedOriginals)
        Button("Refresh Backup History") {
            Task { await model.backup.persistence?.loadSessions() }
        }
        .disabled(model.isViewingLibrary || model.backup.persistence == nil
                  || model.backup.persistence?.isLoadingSessions == true)
        Divider()
        Button(model.backup.destination.selection == nil ? "Choose Backup Folder…" : "Change Backup Folder…") {
            Task { await model.backup.chooseDestination() }
        }
        .disabled(model.isSample || model.backup.isBusy || model.backup.destination.isChoosing)
        Button("Show Backup Folder in Finder") {
            Task { await model.backup.revealDestination() }
        }
        .disabled(model.backup.destination.selection == nil)
    }

    private var backupTitle: String {
        switch model.selection.selectedIDs.count {
        case 0: "Back Up New Items"
        case 1: "Back Up Selected Item"
        default: "Back Up Selected Items"
        }
    }
}
