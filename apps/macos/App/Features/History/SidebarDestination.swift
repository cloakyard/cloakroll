import MediaModels

enum SidebarDestination: Hashable {
    case library(LibraryFilter)
    case backupHistory
}
