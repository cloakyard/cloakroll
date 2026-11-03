import MediaModels

enum SidebarDestination: Hashable {
    case library(LibraryFilter)
    case backupHistory
    case backupHealth
    case savedLibrary
}
