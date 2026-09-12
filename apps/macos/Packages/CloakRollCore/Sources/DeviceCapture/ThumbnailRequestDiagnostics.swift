/// Aggregate transport accounting for one capture context, including retired browser sessions.
/// Cancellation and retirement count waiting callers; neither means the device call has ended.
/// No resource names, identifiers or thumbnail contents are included.
public struct ThumbnailRequestDiagnostics: Equatable, Sendable {
    public internal(set) var startedCount = 0
    public internal(set) var completedCount = 0
    public internal(set) var failedCount = 0
    public internal(set) var cancelledCount = 0
    public internal(set) var retiredCount = 0
    public internal(set) var actualOutstandingCount = 0
    public internal(set) var actualHighWaterMark = 0
    public internal(set) var queuedCount = 0
    public internal(set) var queuedHighWaterMark = 0
}
