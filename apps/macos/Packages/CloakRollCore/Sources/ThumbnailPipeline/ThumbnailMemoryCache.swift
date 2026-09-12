import Foundation

struct ThumbnailMemoryCache {
    private struct Entry {
        let data: Data
        var access: UInt64
    }

    private let byteLimit: Int
    private let itemLimit: Int
    private var entries: [ThumbnailKey: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var bytes = 0
    var count: Int { entries.count }

    init(configuration: ThumbnailPipelineConfiguration) {
        byteLimit = configuration.memoryByteLimit
        itemLimit = configuration.memoryItemLimit
    }

    mutating func data(for key: ThumbnailKey) -> Data? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.access = clock
        entries[key] = entry
        return entry.data
    }

    mutating func insert(_ data: Data, for key: ThumbnailKey) {
        if let previous = entries.removeValue(forKey: key) { bytes -= previous.data.count }
        guard itemLimit > 0, data.count <= byteLimit else { return }
        while entries.count >= itemLimit || bytes > byteLimit - data.count {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key,
                  let removed = entries.removeValue(forKey: oldest) else { break }
            bytes -= removed.data.count
        }
        clock &+= 1
        entries[key] = Entry(data: data, access: clock)
        bytes += data.count
    }

    mutating func discardSessionScopedEntries() {
        for key in Array(entries.keys) where !key.permitsReuse {
            if let entry = entries.removeValue(forKey: key) { bytes -= entry.data.count }
        }
    }
}
