import BackupEngine
import Foundation
import Observation

@MainActor @Observable
final class BackupNotifications {
    static let completionID = "cloakroll.backup.outcome"
    static let reminderID = "cloakroll.backup.reminder"
    static let testID = "cloakroll.backup.test"
    private(set) var completionEnabled: Bool
    private(set) var reminderDays: Int
    private(set) var permission = BackupNotificationPermission.unknown
    private(set) var isUpdating = false
    private(set) var errorMessage: String?
    private(set) var testMessage: String?
    @ObservationIgnored private let client: BackupNotificationClient
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var lastCompleted: Date?
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var permissionGeneration = 0

    init(defaults: UserDefaults? = nil, client: BackupNotificationClient = .disabled,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.defaults = defaults
        self.client = client
        self.now = now
        completionEnabled = defaults?.bool(forKey: "notifications.completion") ?? false
        let days = defaults?.integer(forKey: "notifications.reminderDays") ?? 0
        reminderDays = [0, 7, 14, 30].contains(days) ? days : 0
        lastCompleted = defaults?.object(forKey: "notifications.lastCompleted") as? Date
    }

    static func appDefault() -> BackupNotifications {
        ProcessInfo.processInfo.environment["CLOAKROLL_TESTING"] == "1"
            ? BackupNotifications() : BackupNotifications(defaults: .standard, client: .system)
    }

    func refreshPermission() async { _ = await readPermission() }

    func configure(completion: Bool, reminderDays days: Int) async {
        guard [0, 7, 14, 30].contains(days) else { return }
        generation += 1
        permissionGeneration += 1
        let requested = generation
        isUpdating = true
        errorMessage = nil
        testMessage = nil
        defer { if generation == requested { isUpdating = false } }
        do {
            if (completion && !completionEnabled) || (days > 0 && days != reminderDays) {
                var currentPermission = await readPermission()
                guard requested == generation else { return }
                if currentPermission == .unknown {
                    currentPermission = try await client.authorize() ? .allowed : .denied
                    guard requested == generation else { return }
                    // The authorization result supersedes reads started before it finished.
                    permissionGeneration += 1
                    permission = currentPermission
                }
                guard requested == generation else { return }
                guard currentPermission == .allowed else {
                    errorMessage = "Allow CloakRoll in System Settings → Notifications, then try again."
                    return
                }
            }
            guard requested == generation else { return }
            let reminderChanged = reminderDays != days
            completionEnabled = completion
            reminderDays = days
            defaults?.set(completion, forKey: "notifications.completion")
            defaults?.set(days, forKey: "notifications.reminderDays")
            await enqueue {
                if !self.completionEnabled { await self.client.remove([Self.completionID]) }
                if !self.completionEnabled && self.reminderDays == 0 { await self.client.remove([Self.testID]) }
                if reminderChanged { await self.scheduleReminder() }
            }
        } catch {
            guard requested == generation else { return }
            errorMessage = "Notification permission couldn’t be requested. Try again."
        }
    }

    /// An explicit user action; never requests permission or changes the last-backup date.
    func sendTestNotification() async {
        guard !isUpdating else { return }
        generation += 1
        let requested = generation
        isUpdating = true
        errorMessage = nil
        testMessage = nil
        defer { if generation == requested { isUpdating = false } }
        await enqueue {
            guard requested == self.generation else { return }
            await self.client.remove([Self.testID])
            let sent = await self.send(BackupNotice(
                id: Self.testID, title: "CloakRoll notifications are ready",
                body: "This is a test notification. No backup was started.",
                deliveryDate: self.now().addingTimeInterval(5)
            ))
            guard requested == self.generation else { return }
            if sent {
                self.testMessage = "Test scheduled in 5 seconds. Switch to another app to see it. macOS controls delivery."
            } else if self.errorMessage == nil {
                self.errorMessage = "Allow CloakRoll in System Settings → Notifications, then try again."
            }
        }
    }

    /// Report delivery separately from scheduling; this does not establish that a banner was shown.
    func checkTestDelivery() async {
        guard testMessage != nil, !isUpdating else { return }
        let requested = generation
        let delivered = await client.deliveredIDs()
        guard requested == generation else { return }
        testMessage = delivered.contains(Self.testID)
            ? "macOS reports the test in Notification Centre. Banner presentation depends on your system settings."
            : "macOS hasn’t reported the test in Notification Centre. Wait a few seconds, then check again or review system settings."
    }

    /// Upgrade existing history without inventing a backup time or prompting on launch.
    func restoreLastCompleted(_ date: Date?) async {
        guard let date, date > (lastCompleted ?? .distantPast) else { return }
        lastCompleted = date
        defaults?.set(date, forKey: "notifications.lastCompleted")
        if reminderDays > 0 { await enqueue { await self.scheduleReminder() } }
    }

    func backupFinished(_ result: BackupSnapshot) async {
        guard result.phase == .completed || result.phase == .failed else { return }
        if result.phase == .completed {
            lastCompleted = now()
            defaults?.set(lastCompleted, forKey: "notifications.lastCompleted")
        }
        await enqueue {
            if self.completionEnabled {
                let completed = result.phase == .completed
                await self.send(BackupNotice(
                    id: Self.completionID,
                    title: completed ? "Backup finished" : "Backup needs attention",
                    body: completed ? "Your selected originals were saved. Open CloakRoll to review the result."
                        : "Open CloakRoll to review the unfinished backup. Saved originals have been kept."
                ))
            }
            if result.phase == .completed { await self.scheduleReminder() }
        }
    }

    private func scheduleReminder() async {
        await client.remove([Self.reminderID])
        guard reminderDays > 0 else { return }
        let current = now()
        let due = (lastCompleted ?? current).addingTimeInterval(Double(reminderDays) * 86_400)
        await send(BackupNotice(id: Self.reminderID, title: "Time to back up",
                               body: "Connect your iPhone and open CloakRoll when you’re ready to back up.",
                               deliveryDate: max(due, current.addingTimeInterval(60))))
    }

    @discardableResult
    private func send(_ notice: BackupNotice) async -> Bool {
        let requested = generation
        let currentPermission = await readPermission()
        let enabled = notice.id == Self.testID ? requested == generation
            : notice.id == Self.completionID ? completionEnabled : reminderDays > 0
        guard currentPermission == .allowed, enabled else { return false }
        do { try await client.add(notice); return true } catch {
            guard requested == generation else { return false }
            errorMessage = "A local notification couldn’t be scheduled. Check permission and try again."
            return false
        }
    }

    private func readPermission() async -> BackupNotificationPermission {
        permissionGeneration += 1
        let requested = permissionGeneration
        let result = await client.permission()
        if requested == permissionGeneration { permission = result }
        return result
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task { await previous?.value; await operation() }
        tail = task
        await task.value
    }
}

extension LibraryBackupController {
    func restoreNotificationHistory() async {
        guard let persistence, let entries = try? await persistence.store().backupHealth() else { return }
        await notifications.restoreLastCompleted(entries.compactMap(\.lastCompletedAt).max())
    }
}
