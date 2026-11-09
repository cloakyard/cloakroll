import BackupEngine
import Foundation
import Testing
@testable import CloakRoll

@Suite("Notification permission ordering", .timeLimit(.minutes(1)))
@MainActor
struct BackupNotificationRaceTests {
    @Test func disablingWhileDeliveryChecksPermissionDoesNotSendTheOutcome() async throws {
        let gate = NoticePermissionGate(holdFirstRead: false)
        let notifications = BackupNotifications(client: gate.client)
        await notifications.configure(completion: true, reminderDays: 0)
        await gate.holdNextPermission()
        let outcome = Task { await notifications.backupFinished(.init(phase: .failed)) }
        try await gate.waitUntilPending()
        let disabling = Task { await notifications.configure(completion: false, reminderDays: 0) }
        try await waitForPersistentState { !notifications.completionEnabled }
        await gate.release(.allowed)
        await outcome.value
        await disabling.value
        #expect(await gate.notices.isEmpty)
        #expect(await gate.addRequests == 0)
    }

    @Test func changingOutcomePreferenceDoesNotLoseAnInFlightReminder() async throws {
        let gate = NoticePermissionGate(holdFirstRead: false)
        let notifications = BackupNotifications(client: gate.client)
        await notifications.configure(completion: false, reminderDays: 7)
        await gate.holdNextPermission()
        let outcome = Task { await notifications.backupFinished(.init(phase: .completed)) }
        try await gate.waitUntilPending()
        let enabling = Task { await notifications.configure(completion: true, reminderDays: 7) }
        try await waitForPersistentState { notifications.completionEnabled }
        await gate.release(.allowed)
        await outcome.value
        await enabling.value
        #expect(await gate.notices[BackupNotifications.reminderID] != nil)
    }

    @Test func olderPermissionRefreshCannotReplaceANewerResult() async throws {
        let gate = NoticePermissionGate()
        let notifications = BackupNotifications(client: gate.client)
        let older = Task { await notifications.refreshPermission() }
        try await gate.waitUntilPending()
        await notifications.refreshPermission()
        #expect(notifications.permission == .allowed)
        await gate.release(.denied)
        await older.value
        #expect(notifications.permission == .allowed)
    }

    @Test func supersededEnableDoesNotPromptOrOverwriteDisabledSettings() async throws {
        let gate = NoticePermissionGate()
        let notifications = BackupNotifications(client: gate.client)
        let enabling = Task { await notifications.configure(completion: true, reminderDays: 7) }
        try await gate.waitUntilPending()
        await notifications.configure(completion: false, reminderDays: 0)
        await gate.release(.unknown)
        await enabling.value
        #expect(await gate.authorizationRequests == 0)
        #expect(!notifications.completionEnabled && notifications.reminderDays == 0)
        #expect(notifications.errorMessage == nil && !notifications.isUpdating)
    }

    @Test func obsoleteAuthorizationFailureDoesNotSurfaceAfterDisabling() async throws {
        let gate = NoticePermissionGate(holdAuthorization: true)
        let notifications = BackupNotifications(client: gate.client)
        let enabling = Task { await notifications.configure(completion: true, reminderDays: 7) }
        try await gate.waitUntilPending()
        await notifications.configure(completion: false, reminderDays: 0)
        await gate.release(.denied)
        await enabling.value
        #expect(notifications.errorMessage == nil)
        #expect(!notifications.completionEnabled && !notifications.isUpdating)
    }
}

private actor NoticePermissionGate {
    private let holdAuthorization: Bool
    private var holdsNextRead: Bool
    private var pending: CheckedContinuation<BackupNotificationPermission, Never>?
    private(set) var authorizationRequests = 0
    private(set) var addRequests = 0
    private(set) var notices: [String: BackupNotice] = [:]

    init(holdAuthorization: Bool = false, holdFirstRead: Bool = true) {
        self.holdAuthorization = holdAuthorization
        holdsNextRead = holdFirstRead
    }

    nonisolated var client: BackupNotificationClient {
        BackupNotificationClient(permission: { await self.read() }, authorize: { try await self.authorize() },
                                 add: { await self.add($0) }, remove: { await self.remove($0) })
    }

    private func read() async -> BackupNotificationPermission {
        if holdAuthorization { return .unknown }
        if holdsNextRead {
            holdsNextRead = false
            return await withCheckedContinuation { pending = $0 }
        }
        return .allowed
    }

    func holdNextPermission() { holdsNextRead = true }

    private func add(_ notice: BackupNotice) {
        addRequests += 1
        notices[notice.id] = notice
    }

    private func remove(_ ids: [String]) { for id in ids { notices[id] = nil } }

    private func authorize() async throws -> Bool {
        authorizationRequests += 1
        if holdAuthorization {
            _ = await withCheckedContinuation { pending = $0 }
            throw CocoaError(.userCancelled)
        }
        return true
    }

    func release(_ value: BackupNotificationPermission) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: value)
    }

    func waitUntilPending() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while pending == nil && ContinuousClock.now < deadline { await Task.yield() }
        try #require(pending != nil)
    }
}
