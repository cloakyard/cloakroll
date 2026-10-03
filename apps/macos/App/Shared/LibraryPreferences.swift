import Foundation
import MediaModels

/// Small browsing choices stay local. Invalid or missing values fall back independently.
@MainActor
struct LibraryPreferences {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) { self.defaults = defaults }

    static var standard: LibraryPreferences {
        LibraryPreferences(defaults: ProcessInfo.processInfo.environment["CLOAKROLL_TESTING"] == "1" ? nil : .standard)
    }

    var thumbnailSize: ThumbnailSize {
        defaults?.string(forKey: "browsing.thumbnailSize").flatMap(ThumbnailSize.init(rawValue:)) ?? .medium
    }
    var sort: CatalogSort {
        defaults?.string(forKey: "browsing.sort").flatMap(CatalogSort.init(rawValue:)) ?? .newestFirst
    }
    var grouping: CatalogGrouping {
        defaults?.string(forKey: "browsing.grouping").flatMap(CatalogGrouping.init(rawValue:)) ?? .automatic
    }
    var settingsTab: SettingsTab {
        defaults?.string(forKey: "settings.selectedTab").flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    func save(_ size: ThumbnailSize) { defaults?.set(size.rawValue, forKey: "browsing.thumbnailSize") }
    func save(_ sort: CatalogSort) { defaults?.set(sort.rawValue, forKey: "browsing.sort") }
    func save(_ grouping: CatalogGrouping) { defaults?.set(grouping.rawValue, forKey: "browsing.grouping") }
    func save(_ tab: SettingsTab) { defaults?.set(tab.rawValue, forKey: "settings.selectedTab") }
}
