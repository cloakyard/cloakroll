import SwiftUI

struct LibraryEmptyResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(message)
        } actions: {
            if model.captureDateRange != nil {
                Button("Clear Date Filter") { model.captureDateRange = nil }
            }
            if hasSearch { Button("Clear Search") { model.search = "" } }
        }
    }

    private var hasSearch: Bool { !model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isFiltered: Bool { hasSearch || model.captureDateRange != nil }

    private var title: String {
        if isFiltered { return "No Matching Items" }
        return switch model.filter {
        case .notBackedUp: "No New Items"
        case .backedUp, .recentlyBackedUp: "No Backed-Up Items"
        default: "No Items in This Collection"
        }
    }

    private var message: String {
        if model.captureDateRange != nil {
            return "Try a different capture date or clear the date filter. Items without a capture date are hidden."
        }
        if hasSearch { return "Try another filename or clear the search." }
        return switch model.filter {
        case .notBackedUp: "The items available in this library are already backed up to the selected folder."
        case .backedUp: "Verified backups in the selected folder will appear here."
        case .recentlyBackedUp: "Items backed up to the selected folder in the last seven days will appear here."
        default: "Choose another collection in the sidebar."
        }
    }
}
