import Foundation

/// Brackets actual user-requested file work, including asynchronous cleanup. No token
/// is stored on a view or inferred from progress: cancellation must settle before release.
@MainActor
struct BackupActivity {
    var begin: (ProcessInfo.ActivityOptions, String) -> any NSObjectProtocol
    var end: (any NSObjectProtocol) -> Void

    static let system = BackupActivity(
        begin: { ProcessInfo.processInfo.beginActivity(options: $0, reason: $1) },
        end: { ProcessInfo.processInfo.endActivity($0) }
    )

    func perform<Value>(reason: String, operation: () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        // userInitiated prevents App Nap and idle system sleep, but permits display sleep.
        // Explicit sleep, lid closure and power loss still use normal interruption recovery.
        let token = begin(.userInitiated, reason)
        defer { end(token) }
        return try await operation()
    }
}
