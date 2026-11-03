import BackupEngine
import Foundation
import Testing
@testable import CloakRoll

@Suite("Private local backup notifications")
@MainActor
struct BackupNotificationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func defaultsNeverAskOrSendAndUserStopStaysQuiet() async {
        let recorder = NoticeRecorder()
        let notifications = BackupNotifications(client: recorder.client)
        await notifications.backupFinished(.init(phase: .completed))
        await notifications.backupFinished(.init(phase: .failed))
        await notifications.backupFinished(.init(phase: .cancelled))
        #expect(await recorder.authorizationRequests == 0)
        #expect(await recorder.notices.isEmpty)
        #expect(!notifications.completionEnabled && notifications.reminderDays == 0)
    }

    @Test func enablingRequestsPermissionAndSchedulesOnlyPrivateContent() async {
        let recorder = NoticeRecorder()
        let now = now
        let notifications = BackupNotifications(client: recorder.client, now: { now })
        await notifications.configure(completion: true, reminderDays: 7)
        #expect(await recorder.authorizationRequests == 1)
        #expect(notifications.completionEnabled && notifications.reminderDays == 7)
        let scheduled = await recorder.notices[BackupNotifications.reminderID]
        #expect(scheduled?.deliveryDate == now.addingTimeInterval(7 * 86_400))
        await notifications.backupFinished(.init(phase: .failed, message: "/Users/private/iPhone IMG_0001.heic"))
        let notice = await recorder.notices[BackupNotifications.completionID]
        #expect(notice?.title == "Backup needs attention")
        #expect(notice?.body.contains("private") == false)
        #expect(notice?.body.contains("IMG_0001") == false)
        await notifications.configure(completion: false, reminderDays: 0)
        #expect(await recorder.notices.isEmpty)
    }

    @Test func denialAndRevocationDoNotScheduleAndCanStillDisable() async {
        let recorder = NoticeRecorder(grantsPermission: false)
        let notifications = BackupNotifications(client: recorder.client)
        await notifications.configure(completion: true, reminderDays: 14)
        #expect(!notifications.completionEnabled && notifications.reminderDays == 0)
        #expect(notifications.errorMessage != nil)
        #expect(await recorder.notices.isEmpty)
        await recorder.setPermission(.allowed)
        await notifications.configure(completion: true, reminderDays: 14)
        await recorder.setPermission(.denied)
        await notifications.configure(completion: true, reminderDays: 0)
        #expect(notifications.reminderDays == 0)
        #expect(await recorder.notices[BackupNotifications.reminderID] == nil)
        await notifications.backupFinished(.init(phase: .failed))
        #expect(await recorder.notices[BackupNotifications.completionID] == nil)
    }

    @Test func existingBackupSetsDueDateAndSuccessReplacesReminder() async {
        let recorder = NoticeRecorder()
        let now = now
        let notifications = BackupNotifications(client: recorder.client, now: { now })
        await notifications.restoreLastCompleted(now.addingTimeInterval(-3 * 86_400))
        #expect(await recorder.authorizationRequests == 0)
        await notifications.configure(completion: false, reminderDays: 7)
        #expect(await recorder.notices[BackupNotifications.reminderID]?.deliveryDate == now.addingTimeInterval(4 * 86_400))
        await notifications.backupFinished(.init(phase: .completed))
        #expect(await recorder.notices[BackupNotifications.reminderID]?.deliveryDate == now.addingTimeInterval(7 * 86_400))
        #expect(await recorder.notices.count == 1)
        await notifications.restoreLastCompleted(now.addingTimeInterval(-30 * 86_400))
        #expect(await recorder.notices[BackupNotifications.reminderID]?.deliveryDate == now.addingTimeInterval(7 * 86_400))
    }
}

private actor NoticeRecorder {
    var permission = BackupNotificationPermission.unknown
    var authorizationRequests = 0
    var notices: [String: BackupNotice] = [:]
    let grantsPermission: Bool

    init(grantsPermission: Bool = true) { self.grantsPermission = grantsPermission }

    nonisolated var client: BackupNotificationClient {
        BackupNotificationClient(permission: { await self.permission }, authorize: { await self.authorize() },
                                 add: { await self.add($0) }, remove: { await self.remove($0) })
    }

    func authorize() -> Bool {
        authorizationRequests += 1
        permission = grantsPermission ? .allowed : .denied
        return grantsPermission
    }

    func setPermission(_ permission: BackupNotificationPermission) { self.permission = permission }
    func add(_ notice: BackupNotice) { notices[notice.id] = notice }
    func remove(_ ids: [String]) { for id in ids { notices[id] = nil } }
}
