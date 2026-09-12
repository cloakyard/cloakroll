import Foundation
import Testing
@testable import ThumbnailPipeline

enum PipelineTestError: Error { case timeout, sourceFailure, unexpectedLoad }

actor ControlledThumbnailSource {
    private var pending: [String: CheckedContinuation<Data, any Error>] = [:]
    private(set) var started: [String] = []

    /// Intentionally ignores cancellation until the test supplies an actual completion.
    func load(_ name: String) async throws -> Data {
        started.append(name)
        return try await withCheckedThrowingContinuation { pending[name] = $0 }
    }

    func finish(_ name: String, data: Data = Data([1, 2, 3])) {
        pending.removeValue(forKey: name)?.resume(returning: data)
    }
}

func key(_ name: String, session: UUID, version: String = "1", pixels: Int = 512) -> ThumbnailKey {
    ThumbnailKey(sessionID: session, resourceID: name, version: version, maximumPixelSize: pixels)
}

func request(
    _ name: String, pipeline: ThumbnailPipeline, source: ControlledThumbnailSource,
    session: UUID, priority: ThumbnailPriority = .visible
) -> Task<Data, any Error> {
    Task { try await pipeline.data(for: key(name, session: session), priority: priority) { try await source.load(name) } }
}

func eventually(_ message: String, _ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record(Comment(rawValue: message))
    throw PipelineTestError.timeout
}

func temporaryCache() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakRollPipelineTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

func diskFile(_ key: ThumbnailKey, directory: URL) throws -> URL {
    directory.appendingPathComponent("CloakRollThumbnails-v1")
        .appendingPathComponent("s-" + key.sessionID.uuidString.lowercased())
        .appendingPathComponent(try #require(ThumbnailDiskCodec.filename(for: key)))
}
